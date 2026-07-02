import 'dart:convert';
import 'dart:isolate';
import 'dart:async';

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

class LocalComic with HistoryMixin implements Comic {
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
        tags = List.from(jsonDecode(row[3] as String)),
        directory = row[4] as String,
        chapters = ComicChapters.fromJsonOrNull(jsonDecode(row[5] as String)),
        cover = row[6] as String,
        comicType = ComicType(row[7] as int),
        downloadedChapters = List.from(jsonDecode(row[8] as String)),
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
    App.rootContext.to(
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

  void _checkNoMedia() {
    if (App.isAndroid) {
      var file = File(FilePath.join(path, '.nomedia'));
      if (!file.existsSync()) {
        file.createSync();
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
    try {
      await _copyWithStrategy(directory, newDir, overwrite: overwrite);
      await directory.deleteContents(recursive: true);
      await File(FilePath.join(App.dataPath, 'local_path'))
          .writeAsString(newPath);
    } catch (e, s) {
      Log.error("IO", e, s);
      return e.toString();
    }
    path = newPath;
    _checkNoMedia();
    return null;
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

  Future<String> findDefaultPath() async {
    if (App.isAndroid) {
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

  Future<void> _checkPathValidation() async {
    var testFile = File(FilePath.join(path, 'kongcomic_test'));
    try {
      testFile.createSync();
      testFile.deleteSync();
    } catch (e) {
      Log.error("IO",
          "Failed to create test file in local path: $e\nUsing default path instead.");
      path = await findDefaultPath();
    }
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
    if (File(FilePath.join(App.dataPath, 'local_path')).existsSync()) {
      path = File(FilePath.join(App.dataPath, 'local_path')).readAsStringSync();
      if (!directory.existsSync()) {
        path = await findDefaultPath();
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
    _checkPathValidation();
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
    _db.dispose();
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
      throw "Invalid ep";
    }
    var comic = find(id, type) ?? (throw "Comic Not Found");
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
    files.sort((a, b) {
      var ai = int.tryParse(a.name.split('.').first);
      var bi = int.tryParse(b.name.split('.').first);
      if (ai != null && bi != null) {
        return ai.compareTo(bi);
      }
      return a.name.compareTo(b.name);
    });
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

  void completeTask(DownloadTask task) {
    add(task.toLocalComic());
    downloadingTasks.remove(task);
    notifyListeners();
    saveCurrentDownloadingTasks();
    downloadingTasks.firstOrNull?.resume();
  }

  void removeTask(DownloadTask task) {
    downloadingTasks.remove(task);
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
      if (shouldResume) {
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
    downloadingTasks.first.resume();
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
