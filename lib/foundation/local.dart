import 'dart:convert';
import 'dart:isolate';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show ChangeNotifier;
import 'package:flutter_saf/flutter_saf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_type.dart';
import 'package:kong_comic/foundation/favorites.dart';

import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/network/download.dart';
import 'package:kong_comic/pages/reader/reader.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:kong_comic/utils/translations.dart';
import 'package:path/path.dart' as p;

import 'app.dart';
import 'appdata.dart';
import 'history.dart';

/// 一次「存储目录失效 → 自动回退」的记录。
///
/// 存储目录失效（SAF 授权被系统收回、用户删掉了自建目录、SD 卡卸载等）时 App
/// 会静默切回默认目录，界面上所有已下载的漫画随之消失，而文件其实还在原处。
/// 这里把原路径持久化下来，设置页据此提示用户「可以切回去」，而不是让用户以为
/// 数据丢了。
class LocalPathFallback {
  final String originalPath;

  final String fallbackPath;

  /// 失效原因，仅用于日志/排障：`not-writable` / `missing`。
  final String reason;

  final DateTime time;

  const LocalPathFallback({
    required this.originalPath,
    required this.fallbackPath,
    required this.reason,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
        'originalPath': originalPath,
        'fallbackPath': fallbackPath,
        'reason': reason,
        'time': time.millisecondsSinceEpoch,
      };

  static LocalPathFallback? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      return LocalPathFallback(
        originalPath: raw['originalPath'] as String,
        fallbackPath: raw['fallbackPath'] as String,
        reason: (raw['reason'] as String?) ?? 'unknown',
        time: DateTime.fromMillisecondsSinceEpoch(raw['time'] as int),
      );
    } catch (_) {
      return null;
    }
  }
}

class LocalComic with HistoryMixin implements Comic {
  static List<String> _safeDecodeList(dynamic value) {
    try {
      return List.from(jsonDecode(value as String));
    } catch (_) {
      Log.error("LocalComic",
          "Failed to decode list: ${value.toString().length > 200 ? value.toString().substring(0, 200) : value}");
      return [];
    }
  }

  static ComicChapters? _safeDecodeChapters(dynamic value) {
    try {
      return ComicChapters.fromJsonOrNull(jsonDecode(value as String));
    } catch (_) {
      return null;
    }
  }

  @override
  final String id;

  @override
  final String title;

  @override
  final String subtitle;

  @override
  final List<String> tags;

  /// The name of the directory where the comic is stored
  final String directory;

  /// key: chapter id, value: chapter title
  ///
  /// chapter id is the name of the directory in `LocalManager.path/$directory`
  final ComicChapters? chapters;

  bool get hasChapters => chapters != null;

  /// relative path to the cover image
  @override
  final String cover;

  final ComicType comicType;

  final List<String> downloadedChapters;

  final DateTime createdAt;

  const LocalComic({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.directory,
    required this.chapters,
    required this.cover,
    required this.comicType,
    required this.downloadedChapters,
    required this.createdAt,
  });

  LocalComic copyWith({
    String? id,
    String? title,
    String? subtitle,
    List<String>? tags,
    String? directory,
    ComicChapters? chapters,
    String? cover,
    ComicType? comicType,
    List<String>? downloadedChapters,
    DateTime? createdAt,
  }) =>
      LocalComic(
        id: id ?? this.id,
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        tags: tags ?? this.tags,
        directory: directory ?? this.directory,
        chapters: chapters ?? this.chapters,
        cover: cover ?? this.cover,
        comicType: comicType ?? this.comicType,
        downloadedChapters: downloadedChapters ?? this.downloadedChapters,
        createdAt: createdAt ?? this.createdAt,
      );

  LocalComic.fromRow(Row row)
      : id = row[0] as String,
        title = row[1] as String,
        subtitle = row[2] as String,
        tags = _safeDecodeList(row[3]),
        directory = row[4] as String,
        chapters = _safeDecodeChapters(row[5]),
        cover = row[6] as String,
        comicType = ComicType(row[7] as int),
        downloadedChapters = _safeDecodeList(row[8]),
        createdAt = DateTime.fromMillisecondsSinceEpoch(row[9] as int);

  File get coverFile => File(FilePath.join(
        baseDir,
        cover,
      ));

  String get baseDir => (directory.contains('/') || directory.contains('\\'))
      ? directory
      : FilePath.join(LocalManager().path, directory);

  @override
  String get description => "";

  @override
  String get sourceKey =>
      comicType == ComicType.local ? "local" : comicType.sourceKey;

  @override
  Map<String, dynamic> toJson() {
    return {
      "title": title,
      "cover": cover,
      "id": id,
      "subTitle": subtitle,
      "tags": tags,
      "description": description,
      "sourceKey": sourceKey,
      "chapters": chapters?.toJson(),
    };
  }

  @override
  int? get maxPage => null;

  void read() {
    var history = HistoryManager().find(id, comicType);
    int? firstDownloadedChapter;
    int? firstDownloadedChapterGroup;
    if (downloadedChapters.isNotEmpty && chapters != null) {
      final chapters = this.chapters!;
      if (chapters.isGrouped) {
        for (int i=0; i<chapters.groupCount; i++) {
          var group = chapters.getGroupByIndex(i);
          var keys = group.keys.toList();
          for (int j=0; j<keys.length; j++) {
            var chapterId = keys[j];
            if (downloadedChapters.contains(chapterId)) {
              firstDownloadedChapter = j + 1;
              firstDownloadedChapterGroup = i + 1;
              break;
            }
          }
        }
      } else {
        var keys = chapters.allChapters.keys;
        for (int i = 0; i < keys.length; i++) {
          if (downloadedChapters.contains(keys.elementAt(i))) {
            firstDownloadedChapter = i + 1;
            break;
          }
        }
      }
    }
    App.mainNavigatorKey?.currentContext?.to(
      () => Reader(
        type: comicType,
        cid: id,
        name: title,
        chapters: chapters,
        initialChapter: history?.ep ?? firstDownloadedChapter,
        initialPage: history?.page,
        initialChapterGroup: history?.group ?? firstDownloadedChapterGroup,
        history: history ??
            History.fromModel(
              model: this,
              ep: 0,
              page: 0,
            ),
        author: subtitle,
        tags: tags,
      )
    );
  }

  @override
  HistoryType get historyType => comicType;

  @override
  String? get subTitle => subtitle;

  @override
  String? get language => null;

  @override
  String? get favoriteId => null;

  @override
  double? get stars => null;
}

class LocalManager with ChangeNotifier {
  static LocalManager? _instance;

  LocalManager._();

  factory LocalManager() {
    return _instance ??= LocalManager._();
  }

  /// Mutex lock for saveCurrentDownloadingTasks to prevent concurrent writes
  Completer? _saveTasksLock;

  late Database _db;

  /// path to the directory where all the comics are stored
  late String path;

  Directory get directory => Directory(path);

  /// True while a storage migration ([setNewPath]) is running.
  ///
  /// The migration is "copy to new path -> wipe old path -> switch path", so
  /// anything written into the storage directory in between can be silently
  /// lost. Downloads (which run in the background) and imports must not touch
  /// the directory while this is true.
  bool _isMigrating = false;

  bool get isMigrating => _isMigrating;

  /// 上次启动检测到「存储目录不可用、已临时切换」的记录；正常启动为 null。
  ///
  /// 只在用户明确处理（切回原目录 / 另选目录 / 忽略）后清除，**不会**因为
  /// 重启后新目录可用就自动消失 —— 否则用户永远看不到这条提示，也就无从找回
  /// 留在原目录里的文件。
  LocalPathFallback? _pendingFallback;

  LocalPathFallback? get pendingPathFallback => _pendingFallback;

  /// 标记文件名，存放在 App.dataPath（随 App 数据一起消失，不参与 WebDAV 同步）。
  static const _pathFallbackFile = 'local_path_invalid';

  void _checkNoMedia() {
    if (App.isAndroid) {
      try {
        var file = File(FilePath.join(path, '.nomedia'));
        if (!file.existsSync()) {
          file.createSync();
        }
      } catch (e, s) {
        // 防御：路径异常（如权限中途被收回）时不能让 init 直接崩掉。
        Log.error("IO", "Failed to write .nomedia: $e", s);
      }
    }
  }

  /// Returns the number of conflicting files in [newPath] that already exist
  /// when copying from the current [directory]. Used to prompt the user with
  /// merge/overwrite/cancel choices before moving.
  Future<int> countConflicts(String newPath) async {
    final newDir = Directory(newPath);
    if (!await newDir.exists()) return 0;
    int count = 0;
    try {
      await Isolate.run(() {
        overrideIO(() {
          int walk(Directory d) {
            int n = 0;
            for (final entity in d.listSync(recursive: false)) {
              if (entity is File) {
                n++;
              } else if (entity is Directory) {
                n += walk(entity);
              }
            }
            return n;
          }
          count = walk(directory);
        });
      });
    } catch (_) {
      return 0;
    }
    return count;
  }

  // [overwrite] controls behaviour when [newPath] already contains files:
  //   true  -> copy all files from current [directory] to [newPath],
  //            overwriting collisions and then wipe the source.
  //   false -> only copy files that do not yet exist in [newPath] (merge),
  //            skip collisions, and then wipe the source.
  // Returns null on success, error message string on failure.
  Future<String?> setNewPath(String newPath, {bool overwrite = true}) async {
    if (_isMigrating) {
      return "A storage migration is already in progress".tl;
    }
    // Reject empty path. Some Android directory pickers return a non-null
    // entry whose `.path` is `""` when the user backs out without granting
    // permission; feeding that into `Directory('')` throws
    // `FileSystemException: Invalid directory., path = ''`.
    if (newPath.isEmpty) {
      return "Directory does not exist".tl;
    }
    // Reject SAF / content URIs: dart:io Directory cannot operate on URIs.
    if (newPath.startsWith('content://') || newPath.startsWith('file://')) {
      return "Please pick a regular file system directory, not a document tree".tl;
    }
    var newDir = Directory(newPath);
    bool exists;
    try {
      exists = await newDir.exists();
    } catch (e, s) {
      Log.error("IO", "Failed to stat new path: $e", s);
      return "Directory does not exist".tl;
    }
    if (!exists) {
      return "Directory does not exist".tl;
    }
    if (p.equals(directory.path, newDir.path)) {
      return null;
    }
    // 迁移前必须让存储目录「静默」：流程是复制到新目录 → 删除旧目录 → 切换
    // 路径，若此时下载任务仍在往旧目录写文件，复制可能漏掉或只复制一半，
    // 随后旧目录被清空 → 这一话直接丢失。
    _isMigrating = true;
    notifyListeners();
    final paused = <DownloadTask>[];
    for (final task in downloadingTasks) {
      if (!task.isPaused) {
        task.pause();
        paused.add(task);
      }
    }
    // 被取消的图片下载可能正卡在 writeAsBytes 的 await 中无法中断，
    // 给一点时间让它落盘，避免复制过程中文件被改写/截断。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      return await _moveTo(newDir, overwrite: overwrite, paused: paused);
    } finally {
      _isMigrating = false;
      notifyListeners();
    }
  }

  /// Performs the actual copy -> wipe -> switch. Extracted from [setNewPath]
  /// so the paused download tasks can always be resumed (or redirected) no
  /// matter which step fails.
  Future<String?> _moveTo(
    Directory newDir, {
    required bool overwrite,
    required List<DownloadTask> paused,
  }) async {
    final oldRoot = directory.path;
    try {
      await _copyWithStrategy(directory, newDir, overwrite: overwrite);
    } catch (e, s) {
      Log.error("IO", "Failed to move comics: $e", s);
      // 复制失败：旧目录数据完好，恢复下载任务继续写旧目录。
      _resumePausedTasks(paused, null, oldRoot);
      return "Failed to move comics. Check storage permission and try again."
          .tl;
    }
    try {
      await directory.deleteContents(recursive: true);
    } catch (e, s) {
      // 复制已成功，旧目录清理失败不致命：仍切换到新路径，残留可手动清理。
      Log.error("IO", "Failed to clean old directory: $e", s);
    }
    try {
      await File(FilePath.join(App.dataPath, 'local_path'))
          .writeAsString(newDir.path);
    } catch (e, s) {
      Log.error("IO", "Failed to persist local_path: $e", s);
      _resumePausedTasks(paused, null, oldRoot);
      return "Failed to save storage path. Please try again.".tl;
    }
    path = newDir.path;
    _checkNoMedia();
    // 成功迁移：把进行中的下载任务重定向到新目录，否则恢复后它们会继续写
    // 已被清空的旧目录，导致同一部漫画的文件分裂在两处。
    _resumePausedTasks(paused, newDir.path, oldRoot);
    return null;
  }

  void _resumePausedTasks(
      List<DownloadTask> tasks, String? newRoot, String oldRoot) {
    for (final task in tasks) {
      if (newRoot != null && task.path != null) {
        task.path = _remapRoot(task.path!, oldRoot, newRoot);
      }
      try {
        task.resume();
      } catch (e, s) {
        Log.error("IO", "Failed to resume download task: $e", s);
      }
    }
  }

  /// Rewrites [taskPath] so it points into [newRoot] instead of [oldRoot].
  String _remapRoot(String taskPath, String oldRoot, String newRoot) {
    if (p.equals(taskPath, oldRoot)) return newRoot;
    try {
      final rel = p.relative(taskPath, from: oldRoot);
      // 以 '..' 开头说明 taskPath 不在旧目录下（异常数据），保持原样。
      if (rel.startsWith('..')) return taskPath;
      return p.join(newRoot, rel);
    } catch (e) {
      // p.relative 在跨盘符等情况下会抛异常，保持原路径即可。
      Log.error("IO", "Failed to remap download path: $e", null);
      return taskPath;
    }
  }

  Future<void> _copyWithStrategy(
    Directory source,
    Directory destination, {
    required bool overwrite,
  }) async {
    await Isolate.run(() {
      overrideIO(() {
        void walk(Directory src, Directory dst) {
          for (final entity in src.listSync(recursive: false)) {
            final name = p.basename(entity.path);
            final target = Directory(FilePath.join(dst.path, name));
            if (entity is File) {
              if (target.existsSync() && !overwrite) {
                continue;
              }
              try {
                if (target.existsSync()) target.deleteSync();
              } catch (_) {}
              if (target.path.startsWith('content://') ||
                  target.path.startsWith('android://')) {
                // SAF destination: dart:io's File.copySync does not understand
                // SAF tree URIs and throws PathNotFoundException. Route the
                // copy through AndroidFile (which is backed by native
                // DocumentsContract) so the file is written into the tree.
                var safFile = AndroidFile.fromPathSync(target.path);
                safFile ??= (() {
                  // File does not exist yet. Ensure its parent directory
                  // exists in the SAF tree, then resolve the file again so
                  // writeAsBytesSync has a valid descriptor to write to.
                  final parent = AndroidDirectory.fromPathSync(
                      p.dirname(target.path));
                  parent?.createSync(recursive: true);
                  return AndroidFile.fromPathSync(target.path);
                })();
                safFile?.writeAsBytesSync(entity.readAsBytesSync());
              } else {
                entity.copySync(target.path);
              }
            } else if (entity is Directory) {
              if (!target.existsSync()) {
                target.createSync(recursive: true);
              }
              walk(entity, target);
            }
          }
        }
        walk(source, destination);
      });
    });
  }

  /// [dir] 是否位于当前存储目录 [path] 之下。
  ///
  /// 用规范化后的前缀比较而不是 `contains`：后者会把 `/data/ComicBackup`
  /// 误判成在 `/data/Comic` 之下。SAF 路径（`android://...`）分隔符同样是 `/`，
  /// 因此这里同时接受平台分隔符和 `/`。
  bool _isUnderStorageRoot(String dir) {
    if (dir.isEmpty) return true;
    var root = p.normalize(path);
    var target = p.normalize(dir);
    if (p.equals(root, target)) return true;
    for (var sep in [p.separator, '/']) {
      if (sep.isEmpty) continue;
      if (target.startsWith('$root$sep')) return true;
    }
    return false;
  }

  /// 文件不在当前存储目录下的本地漫画。
  ///
  /// 导入本地漫画时 `directory` 可能被写成绝对路径（见 import_comic.dart），
  /// 这些漫画的文件散落在 [path] 之外 —— 正是「Move to Current Storage Path」
  /// 要归拢的对象。因此判据必须是每部漫画的 baseDir，而不是拿存储根目录和它
  /// 自己相比（那样恒等，功能永远是死的）。
  List<LocalComic> get externalComics {
    var result = <LocalComic>[];
    var res = _db.select('SELECT * FROM comics;');
    for (var row in res) {
      LocalComic comic;
      try {
        comic = LocalComic.fromRow(row);
      } catch (e) {
        // 单行损坏不该让整个设置页的功能失效。
        Log.error("Local", "Failed to read a local comic row: $e", null);
        continue;
      }
      if (!_isUnderStorageRoot(comic.baseDir)) {
        result.add(comic);
      }
    }
    return result;
  }

  /// 在 [root] 下挑一个不冲突的目录名。
  String _uniqueDirName(String root, String name, Set<String> used) {
    var base = name.trim();
    if (base.isEmpty) base = 'comic';
    if (!used.contains(base)) return base;
    for (var i = 1; i < 10000; i++) {
      var candidate = '${base}_$i';
      if (!used.contains(candidate)) return candidate;
    }
    return '${base}_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// 把 [externalComics] 的文件夹搬进当前存储目录，并把数据库里的 `directory`
  /// 改写为相对目录名（之后 baseDir 就会解析到新位置）。
  ///
  /// 与 [setNewPath] 的区别：[setNewPath] 是「整个存储目录搬家」，这里是
  /// 「把散落的单部漫画收进来」，存储路径设置本身不变。
  /// 返回 null 表示成功，否则返回错误信息。
  Future<String?> gatherExternalComics() async {
    if (_isMigrating) {
      return "A storage migration is already in progress".tl;
    }
    var comics = externalComics;
    if (comics.isEmpty) return null;
    var root = path;
    _isMigrating = true;
    notifyListeners();
    var paused = <DownloadTask>[];
    for (var task in downloadingTasks) {
      if (!task.isPaused) {
        task.pause();
        paused.add(task);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    var moved = 0;
    var failed = 0;
    try {
      var rootDir = Directory(root);
      if (!await rootDir.exists()) {
        await rootDir.create(recursive: true);
      }
      var used = <String>{};
      try {
        for (var entity in rootDir.listSync(recursive: false)) {
          used.add(p.basename(entity.path));
        }
      } catch (_) {}
      for (var comic in comics) {
        var source = Directory(comic.baseDir);
        bool exists;
        try {
          exists = await source.exists();
        } catch (_) {
          exists = false;
        }
        if (!exists) {
          // 源目录已被外部删除，没什么可搬的，跳过而不是报错中断整批。
          failed++;
          continue;
        }
        var name = _uniqueDirName(root, p.basename(comic.baseDir), used);
        used.add(name);
        var destination = Directory(FilePath.join(root, name));
        try {
          await _copyWithStrategy(source, destination, overwrite: false);
          // 只有复制成功才删源，避免两头都不完整。
          await source.delete(recursive: true);
        } catch (e, s) {
          Log.error("IO", "Failed to move comic '${comic.title}': $e", s);
          // 清掉可能残留的半成品，防止下次导入出现半套文件。
          try {
            if (await destination.exists()) {
              await destination.delete(recursive: true);
            }
          } catch (_) {}
          failed++;
          continue;
        }
        _db.execute(
          'UPDATE comics SET directory = ? WHERE id = ? AND comic_type = ?;',
          [name, comic.id, comic.comicType.value],
        );
        moved++;
      }
      notifyListeners();
      if (moved == 0) {
        return "Failed to move comics. Check storage permission and try again."
            .tl;
      }
      if (failed > 0) {
        Log.warning(
            "Local", "Moved $moved comic(s) into storage path, $failed failed.");
      }
      return null;
    } finally {
      _isMigrating = false;
      // 存储根目录没变，下载任务原地恢复即可。
      _resumePausedTasks(paused, null, root);
      notifyListeners();
    }
  }

  /// 探测公共 Download/Comic 目录是否可用（Android）。
  /// 用 getExternalStorageDirectory() 拿当前用户的外部存储根，避免硬编码
  /// /storage/emulated/0 在多用户 / 应用分身场景下写错目录。可用返回完整路径，
  /// 不可用（未授予"所有文件访问"等）返回 null，由调用方自行回退。
  Future<String?> detectDownloadComicPath() async {
    if (!App.isAndroid) return null;
    // 必须是真正的公共 Download 目录（/storage/emulated/0/Download/Comic）。
    // 注意 path_provider 的 getExternalStorageDirectory() 返回的是 **app 专属**
    // 目录（/storage/emulated/0/Android/data/<pkg>/files），用它拼出来的
    // "Download/Comic" 仍然藏在私有目录里：文件管理器里根本不是用户认知的
    // Download，卸载 app 还会被一起删掉。
    var root = await publicStorageRoot();
    root ??= (await getExternalStorageDirectory())?.path;
    if (root == null) return null;
    try {
      var comicDir = Directory(FilePath.join(root, 'Download', 'Comic'));
      if (!comicDir.existsSync()) {
        comicDir.createSync(recursive: true);
      }
      var probe = File(FilePath.join(comicDir.path, 'kongcomic_probe'));
      probe.createSync();
      probe.deleteSync();
      return comicDir.path;
    } catch (e) {
      Log.warning("IO", "Cannot use Download/Comic: $e");
      return null;
    }
  }

  /// 公共（共享）外部存储根，例如 `/storage/emulated/0`。
  ///
  /// 由原生 `Environment.getExternalStorageDirectory()` 提供；不可用时返回
  /// null，调用方自行回退到 app 专属目录。
  static Future<String?> publicStorageRoot() async {
    if (!App.isAndroid) return null;
    try {
      final path = await const MethodChannel('kong_comic/method_channel')
          .invokeMethod<String?>('getPublicStorageRoot');
      if (path != null && path.isNotEmpty) return path;
    } catch (e) {
      Log.warning("IO", "Failed to read public storage root: $e");
    }
    return null;
  }

  Future<String> findDefaultPath() async {
    if (App.isAndroid) {
      // 优先使用公共 Download/Comic 目录（用户可见、方便用文件管理器管理/拷出）。
      // 依赖 MANAGE_EXTERNAL_STORAGE「所有文件访问」权限（Manifest 已声明）；
      // 未授予时写测试文件失败，自动回退到应用专属外部目录，不影响使用。
      var comic = await detectDownloadComicPath();
      if (comic != null) {
        return comic;
      }
      var external = await getExternalStorageDirectories();
      if (external != null && external.isNotEmpty) {
        return FilePath.join(external.first.path, 'local');
      } else {
        return FilePath.join(App.dataPath, 'local');
      }
    } else if (App.isIOS) {
      var oldPath = FilePath.join(App.dataPath, 'local');
      if (Directory(oldPath).existsSync() &&
          Directory(oldPath).listSync().isNotEmpty) {
        return oldPath;
      } else {
        var directory = await getApplicationDocumentsDirectory();
        return FilePath.join(directory.path, 'local');
      }
    } else {
      return FilePath.join(App.dataPath, 'local');
    }
  }

  /// 目录是否真的可写：能创建且能删除一个测试文件才算数。
  ///
  /// 只 [exists] 是不够的 —— SAF 授权被收回的目录仍然"存在"，但一写就抛异常。
  Future<bool> canWrite(String dir) async {
    try {
      var directory = Directory(dir);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      var testFile = File(FilePath.join(dir, 'kongcomic_test'));
      testFile.createSync();
      testFile.deleteSync();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 切回默认目录，并记下这次失效（供设置页提示找回）。
  ///
  /// 之前这里是静默 `path = await findDefaultPath()`：文件还在原目录，界面却
  /// 什么都不剩，用户只会以为数据被 App 弄丢了。现在至少留一条可追踪的记录。
  Future<void> _fallbackToDefaultPath(String previousPath, String reason) async {
    var fallback = await findDefaultPath();
    if (!await canWrite(fallback)) {
      // 兜底中的兜底：App 私有目录几乎不可能写不进去。
      fallback = FilePath.join(App.dataPath, 'local');
      try {
        Directory(fallback).createSync(recursive: true);
      } catch (_) {}
    }
    if (p.equals(previousPath, fallback)) {
      // 默认目录就是当前目录，切换毫无意义，也不必打扰用户。
      path = fallback;
      return;
    }
    var record = LocalPathFallback(
      originalPath: previousPath,
      fallbackPath: fallback,
      reason: reason,
      time: DateTime.now(),
    );
    _pendingFallback = record;
    try {
      File(FilePath.join(App.dataPath, _pathFallbackFile))
          .writeAsString(jsonEncode(record.toJson()));
    } catch (e, s) {
      Log.error("IO", "Failed to persist invalid path flag: $e", s);
    }
    Log.warning(
        "Local",
        "Storage path is unavailable ($reason): '$previousPath'. "
            "Falling back to '$fallback'. Files are still in the original folder.");
    path = fallback;
  }

  Future<void> _loadPathFallback() async {
    try {
      var file = File(FilePath.join(App.dataPath, _pathFallbackFile));
      if (!file.existsSync()) {
        _pendingFallback = null;
        return;
      }
      _pendingFallback = LocalPathFallback.fromJson(jsonDecode(file.readAsStringSync()));
      if (_pendingFallback == null) {
        // 内容损坏：宁可不提示，也不要拿半截路径去误导用户。
        file.deleteIgnoreError();
      }
    } catch (e, s) {
      Log.error("IO", "Failed to read invalid path flag: $e", s);
      _pendingFallback = null;
    }
  }

  /// 用户已处理（切回原目录 / 另选目录 / 主动忽略），丢弃提示。
  Future<void> clearPathFallback() async {
    _pendingFallback = null;
    try {
      File(FilePath.join(App.dataPath, _pathFallbackFile)).deleteIgnoreError();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _checkPathValidation() async {
    var previous = path;
    if (await canWrite(path)) {
      // 注意：这里**不**清除失效提示。local_path 已经被写成回退后的目录，
      // 下次启动校验必然通过，若在此清除，用户永远看不到「文件还在原处」的提示。
      return;
    }
    await _fallbackToDefaultPath(previous, 'not-writable');
  }

  /// 只把存储目录切换到 [newPath]，**不搬运任何文件**。
  ///
  /// 用于「目录失效后找回原目录」：文件本来就在 [newPath] 里。若走
  /// [setNewPath]，它会把当前（空的临时）目录复制过去并清空目标 ——
  /// 恰好把用户的数据抹掉，所以这里必须是纯切换。
  /// 返回 null 表示成功，否则返回错误信息。
  Future<String?> switchPathWithoutMoving(String newPath) async {
    if (newPath.isEmpty) {
      return "Directory does not exist".tl;
    }
    if (newPath.startsWith('content://') || newPath.startsWith('file://')) {
      return "Please pick a regular file system directory, not a document tree"
          .tl;
    }
    var dir = Directory(newPath);
    bool exists;
    try {
      exists = await dir.exists();
    } catch (e, s) {
      Log.error("IO", "Failed to stat path: $e", s);
      return "Directory does not exist".tl;
    }
    if (!exists) {
      return "Directory does not exist".tl;
    }
    if (!await canWrite(newPath)) {
      return "Cannot write to this directory".tl;
    }
    try {
      await File(FilePath.join(App.dataPath, 'local_path'))
          .writeAsString(newPath);
    } catch (e, s) {
      Log.error("IO", "Failed to persist local_path: $e", s);
      return "Failed to save storage path. Please try again.".tl;
    }
    path = newPath;
    // 这里刻意不写 .nomedia：目录由用户选定且可能还在被其它应用使用，
    // 写进去会让其中的图片/视频对系统相册整体隐藏。
    await clearPathFallback();
    notifyListeners();
    return null;
  }

  Future<void> init() async {
    _db = sqlite3.open(
      '${App.dataPath}/local.db',
    );
    _db.execute('''
      CREATE TABLE IF NOT EXISTS comics (
        id TEXT NOT NULL,
        title TEXT NOT NULL,
        subtitle TEXT NOT NULL,
        tags TEXT NOT NULL,
        directory TEXT NOT NULL,
        chapters TEXT NOT NULL,
        cover TEXT NOT NULL,
        comic_type INTEGER NOT NULL,
        downloadedChapters TEXT NOT NULL,
        created_at INTEGER,
        PRIMARY KEY (id, comic_type)
      );
    ''');
    // Performance: add indexes for high-frequency query columns
    _db.execute('CREATE INDEX IF NOT EXISTS idx_comics_type ON comics(comic_type);');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_comics_directory ON comics(directory);');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_comics_title ON comics(title);');
    await _loadPathFallback();
    if (File(FilePath.join(App.dataPath, 'local_path')).existsSync()) {
      path = File(FilePath.join(App.dataPath, 'local_path')).readAsStringSync();
      if (!directory.existsSync()) {
        // 目录被外部删除 / SAF 授权失效：记录下来，让设置页能提示用户找回。
        await _fallbackToDefaultPath(path, 'missing');
      }
    } else {
      path = await findDefaultPath();
    }
    try {
      if (!directory.existsSync()) {
        await directory.create();
      }
    } catch (e, s) {
      Log.error("IO", "Failed to create local folder: $e", s);
    }
    // 必须 await：校验失败时会把 path 改回默认路径，若不等待就往下走，
    // 落盘的会是被覆盖前的旧路径 —— 表现为「迁移成功后重启又变回原路径」。
    await _checkPathValidation();
    _checkNoMedia();
    // 保存有效路径，避免下次启动路径错误
    try {
      File(FilePath.join(App.dataPath, 'local_path')).writeAsString(path);
    } catch (_) {}
    await ComicSourceManager().ensureInit();
    restoreDownloadingTasks();
  }

  String findValidId(ComicType type) {
    final res = _db.select(
      '''
      SELECT id FROM comics WHERE comic_type = ?
      ORDER BY CAST(id AS INTEGER) DESC
      LIMIT 1;
      ''',
      [type.value],
    );
    if (res.isEmpty) {
      return '1';
    }
    return (int.parse((res.first[0])) + 1).toString();
  }

  Future<void> add(LocalComic comic, [String? id]) async {
    var old = find(id ?? comic.id, comic.comicType);
    var downloaded = comic.downloadedChapters;
    if (old != null) {
      downloaded.addAll(old.downloadedChapters);
    }
    _db.execute(
      'INSERT OR REPLACE INTO comics VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        id ?? comic.id,
        comic.title,
        comic.subtitle,
        jsonEncode(comic.tags),
        comic.directory,
        jsonEncode(comic.chapters),
        comic.cover,
        comic.comicType.value,
        jsonEncode(downloaded),
        comic.createdAt.millisecondsSinceEpoch,
      ],
    );
    notifyListeners();
  }

  void remove(String id, ComicType comicType) {
    _db.execute(
      'DELETE FROM comics WHERE id = ? AND comic_type = ?;',
      [id, comicType.value],
    );
    notifyListeners();
  }

  void removeComic(LocalComic comic) {
    remove(comic.id, comic.comicType);
    notifyListeners();
  }

  List<LocalComic> getComics(LocalSortType sortType) {
    final orderBy = switch (sortType) {
      LocalSortType.name => 'title ASC',
      LocalSortType.timeAsc => 'created_at ASC',
      LocalSortType.timeDesc => 'created_at DESC',
    };
    var res = _db.select('''
      SELECT * FROM comics
      ORDER BY $orderBy;
    ''');
    return res.map((row) => LocalComic.fromRow(row)).toList();
  }

  /// Paginated version of [getComics].
  /// Returns at most [limit] comics starting from [offset].
  List<LocalComic> getComicsPaginated(LocalSortType sortType,
      {required int limit, required int offset}) {
    final orderBy = switch (sortType) {
      LocalSortType.name => 'title ASC',
      LocalSortType.timeAsc => 'created_at ASC',
      LocalSortType.timeDesc => 'created_at DESC',
    };
    var res = _db.select('''
      SELECT * FROM comics
      ORDER BY $orderBy
      LIMIT ? OFFSET ?;
    ''', [limit, offset]);
    return res.map((row) => LocalComic.fromRow(row)).toList();
  }

  /// Total number of local comics.
  int getComicCount() {
    var res = _db.select('SELECT COUNT(*) as cnt FROM comics;');
    return res.first['cnt'] as int;
  }

  LocalComic? find(String id, ComicType comicType) {
    final res = _db.select(
      'SELECT * FROM comics WHERE id = ? AND comic_type = ?;',
      [id, comicType.value],
    );
    if (res.isEmpty) {
      return null;
    }
    return LocalComic.fromRow(res.first);
  }

  /// Look up a local comic by its `directory` field. Used to deduplicate
  /// imports — re-importing a file at the same path should not produce a
  /// second row in the database.
  LocalComic? findByDirectory(String directory) {
    if (directory.isEmpty) return null;
    final res = _db.select(
      'SELECT * FROM comics WHERE directory = ? AND comic_type = ? LIMIT 1;',
      [directory, ComicType.local.value],
    );
    if (res.isEmpty) {
      return null;
    }
    return LocalComic.fromRow(res.first);
  }

  @override
  void dispose() {
    super.dispose();
    _db.close();
  }

  List<LocalComic> getRecent() {
    final res = _db.select('''
      SELECT * FROM comics
      ORDER BY created_at DESC
      LIMIT 20;
    ''');
    return res.map((row) => LocalComic.fromRow(row)).toList();
  }

  int get count {
    final res = _db.select('''
      SELECT COUNT(*) FROM comics;
    ''');
    return res.first[0] as int;
  }

  LocalComic? findByName(String name) {
    final res = _db.select('''
      SELECT * FROM comics
      WHERE title = ? OR directory = ?
      LIMIT 1;
    ''', [name, name]);
    if (res.isEmpty) {
      return null;
    }
    return LocalComic.fromRow(res.first);
  }

  List<LocalComic> search(String keyword) {
    // Support search prefixes: src:xxx, id:xxx
    if (keyword.startsWith('src:')) {
      var sourceKey = keyword.substring(4);
      final res = _db.select('''
        SELECT * FROM comics
        WHERE comic_type = ?
        ORDER BY created_at DESC;
      ''', [sourceKey.hashCode]);
      return res.map((row) => LocalComic.fromRow(row)).toList();
    }
    if (keyword.startsWith('id:')) {
      var comicId = keyword.substring(3);
      final res = _db.select('''
        SELECT * FROM comics
        WHERE id = ?
        ORDER BY created_at DESC;
      ''', [comicId]);
      return res.map((row) => LocalComic.fromRow(row)).toList();
    }
    final res = _db.select('''
      SELECT * FROM comics
      WHERE title LIKE ? OR tags LIKE ? OR subtitle LIKE ?
      ORDER BY created_at DESC;
    ''', ['%$keyword%', '%$keyword%', '%$keyword%']);
    return res.map((row) => LocalComic.fromRow(row)).toList();
  }

  /// Paginated version of [search].
  List<LocalComic> searchPaginated(String keyword,
      {required int limit, required int offset}) {
    final res = _db.select('''
      SELECT * FROM comics
      WHERE title LIKE ? OR tags LIKE ? OR subtitle LIKE ?
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?;
    ''', ['%$keyword%', '%$keyword%', '%$keyword%', limit, offset]);
    return res.map((row) => LocalComic.fromRow(row)).toList();
  }

  /// Count of comics matching the search keyword.
  int searchCount(String keyword) {
    final res = _db.select('''
      SELECT COUNT(*) as cnt FROM comics
      WHERE title LIKE ? OR tags LIKE ? OR subtitle LIKE ?;
    ''', ['%$keyword%', '%$keyword%', '%$keyword%']);
    return res.first['cnt'] as int;
  }

  Future<List<String>> getImages(String id, ComicType type, Object ep) async {
    if (ep is! String && ep is! int) {
      throw "Invalid page".tl;
    }
    var comic = find(id, type) ?? (throw "Local comic not found".tl);
    var directory = Directory(comic.baseDir);
    if (comic.hasChapters) {
      var cid =
          ep is int ? comic.chapters!.ids.elementAt(ep - 1) : (ep as String);
      cid = getChapterDirectoryName(cid);
      directory = Directory(FilePath.join(directory.path, cid));
    }
    var files = <File>[];
    await for (var entity in directory.list()) {
      if (entity is File) {
        // Do not exclude comic.cover, since it may be the first page of the chapter.
        // A file with name starting with 'cover.' is not a comic page.
        if (entity.name.startsWith('cover.')) {
          continue;
        }
        //Hidden file in some file system
        if (entity.name.startsWith('.')) {
          continue;
        }
        files.add(entity);
      }
    }
    // 自然排序：文件名里的数字按数值比较，否则 "图_10" 会排在 "图_2" 前面，
    // 导致阅读顺序错乱（旧实现仅在文件名为纯数字时才按数值排）。
    files.sort((a, b) => compareNatural(a.name, b.name));
    return files.map((e) => "file://${e.path}").toList();
  }

  bool isDownloaded(String id, ComicType type,
      [int? ep, ComicChapters? chapters]) {
    var comic = find(id, type);
    if (comic == null) return false;
    if (comic.chapters == null || ep == null) return true;
    if (chapters != null) {
      if (comic.chapters?.length != chapters.length) {
        // update
        add(LocalComic(
          id: comic.id,
          title: comic.title,
          subtitle: comic.subtitle,
          tags: comic.tags,
          directory: comic.directory,
          chapters: chapters,
          cover: comic.cover,
          comicType: comic.comicType,
          downloadedChapters: comic.downloadedChapters,
          createdAt: comic.createdAt,
        ));
      }
    }
    return comic.downloadedChapters
        .contains((chapters ?? comic.chapters)!.ids.elementAtOrNull(ep - 1));
  }

  List<DownloadTask> downloadingTasks = [];

  bool isDownloading(String id, ComicType type) {
    return downloadingTasks
        .any((element) => element.id == id && element.comicType == type);
  }

  Future<Directory> findValidDirectory(
      String id, ComicType type, String name) async {
    var comic = find(id, type);
    if (comic != null) {
      return Directory(FilePath.join(path, comic.directory));
    }
    const comicDirectoryMaxLength = 80;
    if (name.length > comicDirectoryMaxLength) {
      name = name.substring(0, comicDirectoryMaxLength);
    }
    var dir = findValidDirectoryName(path, name);
    return Directory(FilePath.join(path, dir)).create().then((value) => value);
  }

  /// True right after [completeTask] ran, cleared by [removeTask].
  ///
  /// Lets the download notification tell "the queue finished" apart from
  /// "the user cancelled", since both end with an empty queue.
  bool lastTaskCompleted = false;

  /// Resume the head of the queue.
  ///
  /// A task that failed keeps `isError == true` and stays at the head.
  /// Resuming it blindly would retry it forever and starve every task added
  /// after it — the queue would look alive while nothing progresses. So push
  /// a failed head task to the tail (the user can still retry it manually)
  /// before starting the next one.
  void _resumeHead() {
    if (_isMigrating) return;
    if (downloadingTasks.isEmpty) return;
    if (downloadingTasks.first.isError && downloadingTasks.length > 1) {
      final failed = downloadingTasks.removeAt(0);
      downloadingTasks.add(failed);
      notifyListeners();
      saveCurrentDownloadingTasks();
    }
    // Never resume a task the user paused themselves: adding a new download
    // (or finishing one) would otherwise silently undo that pause.
    final head = downloadingTasks.firstOrNull;
    if (head != null && !head.isPaused) {
      head.resume();
    }
  }

  void completeTask(DownloadTask task) {
    add(task.toLocalComic());
    downloadingTasks.remove(task);
    lastTaskCompleted = true;
    notifyListeners();
    saveCurrentDownloadingTasks();
    // 迁移期间不允许自动放行下一个任务（否则它会往正在被清空的旧目录写）。
    _resumeHead();
  }

  void removeTask(DownloadTask task) {
    downloadingTasks.remove(task);
    lastTaskCompleted = false;
    notifyListeners();
    saveCurrentDownloadingTasks();
  }

  void moveToFirst(DownloadTask task) {
    if (downloadingTasks.first != task) {
      var shouldResume = !downloadingTasks.first.isPaused;
      downloadingTasks.first.pause();
      downloadingTasks.remove(task);
      downloadingTasks.insert(0, task);
      notifyListeners();
      saveCurrentDownloadingTasks();
      if (shouldResume && !_isMigrating) {
        // The task was explicitly moved to the front, so start it even if it
        // previously failed.
        downloadingTasks.first.resume();
      }
    }
  }

  Future<void> saveCurrentDownloadingTasks() async {
    // Implement mutex lock to prevent concurrent writes
    while (_saveTasksLock != null) {
      await _saveTasksLock!.future;
    }
    _saveTasksLock = Completer();
    
    try {
      var tasks = downloadingTasks.map((e) => e.toJson()).toList();
      await File(FilePath.join(App.dataPath, 'downloading_tasks.json'))
          .writeAsString(jsonEncode(tasks));
    } finally {
      _saveTasksLock!.complete();
      _saveTasksLock = null;
    }
  }

  void restoreDownloadingTasks() {
    var file = File(FilePath.join(App.dataPath, 'downloading_tasks.json'));
    if (file.existsSync()) {
      try {
        var tasks = jsonDecode(file.readAsStringSync());
        for (var e in tasks) {
          var task = DownloadTask.fromJson(e);
          if (task != null) {
            downloadingTasks.add(task);
          }
        }
      } catch (e) {
        file.delete();
        Log.error("LocalManager", "Failed to restore downloading tasks: $e");
      }
    }
  }

  /// Get all comics in a category
  List<LocalComic> getComicsByCategory(String category, LocalSortType sort) {
    var allComics = getComics(sort);
    var categories = appdata.settings['comicCategories'] as Map? ?? {};
    var comicIds = (categories[category] as List? ?? [])
        .map((e) => e.toString()).toSet();
    return allComics.where((c) => comicIds.contains(c.id)).toList();
  }

  /// Add a comic to a category
  void addToCategory(String comicId, String category) {
    var categories = Map<String, dynamic>.from(
        appdata.settings['comicCategories'] as Map? ?? {});
    var list = List<String>.from(categories[category] as List? ?? []);
    if (!list.contains(comicId)) {
      list.add(comicId);
    }
    categories[category] = list;
    appdata.settings['comicCategories'] = categories;
    appdata.saveData();
    notifyListeners();
  }

  /// Remove a comic from a category
  void removeFromCategory(String comicId, String category) {
    var categories = Map<String, dynamic>.from(
        appdata.settings['comicCategories'] as Map? ?? {});
    var list = List<String>.from(categories[category] as List? ?? []);
    list.remove(comicId);
    if (list.isEmpty) {
      categories.remove(category);
    } else {
      categories[category] = list;
    }
    appdata.settings['comicCategories'] = categories;
    appdata.saveData();
    notifyListeners();
  }

  /// Get all category names
  List<String> getCategories() {
    var categories = appdata.settings['comicCategories'] as Map? ?? {};
    return categories.keys.cast<String>().toList();
  }

  /// Rename a category
  void renameCategory(String oldName, String newName) {
    var categories = Map<String, dynamic>.from(
        appdata.settings['comicCategories'] as Map? ?? {});
    categories[newName] = categories[oldName];
    categories.remove(oldName);
    appdata.settings['comicCategories'] = categories;
    appdata.saveData();
    notifyListeners();
  }

  /// Delete a category
  void deleteCategory(String name) {
    var categories = Map<String, dynamic>.from(
        appdata.settings['comicCategories'] as Map? ?? {});
    categories.remove(name);
    appdata.settings['comicCategories'] = categories;
    appdata.saveData();
    notifyListeners();
  }

  /// Get categories for a specific comic
  List<String> getComicCategories(String comicId) {
    var categories = appdata.settings['comicCategories'] as Map? ?? {};
    var result = <String>[];
    for (var entry in categories.entries) {
      if ((entry.value as List).contains(comicId)) {
        result.add(entry.key);
      }
    }
    return result;
  }

  void addTask(DownloadTask task) {
    downloadingTasks.add(task);
    notifyListeners();
    saveCurrentDownloadingTasks();
    // 迁移期间新任务保持暂停，等迁移结束后由 _resumePausedTasks 统一放行。
    _resumeHead();
  }

  void deleteComic(LocalComic c, [bool removeFileOnDisk = true]) {
    if (removeFileOnDisk) {
      var dir = Directory(FilePath.join(path, c.directory));
      dir.deleteIgnoreError(recursive: true);
    }
    // Deleting a local comic means that it's no longer available, thus both favorite and history should be deleted.
    if (c.comicType == ComicType.local) {
      if (HistoryManager().find(c.id, c.comicType) != null) {
        HistoryManager().remove(c.id, c.comicType);
      }
      var folders = LocalFavoritesManager().find(c.id, c.comicType);
      for (var f in folders) {
        LocalFavoritesManager().deleteComicWithId(f, c.id, c.comicType);
      }
    }
    remove(c.id, c.comicType);
    notifyListeners();
  }

  void deleteComicChapters(LocalComic c, List<String> chapters) {
    if (chapters.isEmpty) {
      return;
    }
    var newDownloadedChapters = c.downloadedChapters
        .where((e) => !chapters.contains(e))
        .toList();
    if (newDownloadedChapters.isNotEmpty) {
      _db.execute(
        'UPDATE comics SET downloadedChapters = ? WHERE id = ? AND comic_type = ?;',
        [
          jsonEncode(newDownloadedChapters),
          c.id,
          c.comicType.value,
        ],
      );
    } else {
      _db.execute(
        'DELETE FROM comics WHERE id = ? AND comic_type = ?;',
        [c.id, c.comicType.value],
      );
    }
    var shouldRemovedDirs = <Directory>[];
    for (var chapter in chapters) {
      var dir = Directory(FilePath.join(
        c.baseDir,
        getChapterDirectoryName(chapter),
      ));
      if (dir.existsSync()) {
        shouldRemovedDirs.add(dir);
      }
    }
    if (shouldRemovedDirs.isNotEmpty) {
      _deleteDirectories(shouldRemovedDirs);
    }
    notifyListeners();
  }

  void batchDeleteComics(List<LocalComic> comics, [bool removeFileOnDisk = true, bool removeFavoriteAndHistory = true]) {
    if (comics.isEmpty) {
      return;
    }

    var shouldRemovedDirs = <Directory>[];
    _db.execute('BEGIN TRANSACTION;');
    try {
      for (var c in comics) {
        if (removeFileOnDisk) {
          var dir = Directory(FilePath.join(path, c.directory));
          if (dir.existsSync()) {
            shouldRemovedDirs.add(dir);
          }
        }
        _db.execute(
          'DELETE FROM comics WHERE id = ? AND comic_type = ?;',
          [c.id, c.comicType.value],
        );
      }
    }
    catch(e, s) {
      Log.error("LocalManager", "Failed to batch delete comics: $e", s);
      _db.execute('ROLLBACK;');
      return;
    }
    _db.execute('COMMIT;');

    var comicIDs = comics.map((e) => ComicID(e.comicType, e.id)).toList();

    if (removeFavoriteAndHistory) {
      LocalFavoritesManager().batchDeleteComicsInAllFolders(comicIDs);
      HistoryManager().batchDeleteHistories(comicIDs);
    }

    notifyListeners();

    if (removeFileOnDisk) {
      _deleteDirectories(shouldRemovedDirs);
    }
  }

  /// Deletes the directories in a separate isolate to avoid blocking the UI thread.
  static void _deleteDirectories(List<Directory> directories) {
    Isolate.run(() async {
      await SAFTaskWorker().init();
      for (var dir in directories) {
        try {
          if (dir.existsSync()) {
            await dir.delete(recursive: true);
          }
        } catch (e) {
          continue;
        }
      }
    });
  }

  static String getChapterDirectoryName(String name) {
    var builder = StringBuffer();
    for (var i = 0; i < name.length; i++) {
      var char = name[i];
      if (char == '/' || char == '\\' || char == ':' || char == '*' ||
          char == '?'
          || char == '"' || char == '<' || char == '>' || char == '|') {
        builder.write('_');
      } else {
        builder.write(char);
      }
    }
    return builder.toString();
  }
}

enum LocalSortType {
  name("name"),
  timeAsc("time_asc"),
  timeDesc("time_desc");

  final String value;

  const LocalSortType(this.value);

  static LocalSortType fromString(String value) {
    for (var type in values) {
      if (type.value == value) {
        return type;
      }
    }
    return name;
  }
}
