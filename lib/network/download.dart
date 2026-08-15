import 'dart:async';
import 'dart:isolate';

import 'package:flutter/widgets.dart' show ChangeNotifier;
import 'package:flutter_saf/flutter_saf.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_type.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/foundation/res.dart';
import 'package:kong_comic/network/images.dart';
import 'package:kong_comic/utils/ext.dart';
import 'package:kong_comic/utils/file_type.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:archive/archive.dart' hide ZipFile;
import 'package:path/path.dart' as p;
import 'package:zip_flutter/zip_flutter.dart';

import 'package:kong_comic/utils/translations.dart';
import 'file_downloader.dart';
abstract class DownloadTask with ChangeNotifier {
  /// 0-1
  double get progress;

  bool get isError;

  bool get isPaused;

  /// bytes per second
  int get speed;

  void cancel();

  void pause();

  void resume();

  String get title;

  String? get cover;

  String get message;

  /// root path for the comic. If null, the task is not scheduled.
  String? path;

  /// convert current state to json, which can be used to restore the task
  Map<String, dynamic> toJson();

  LocalComic toLocalComic();

  String get id;

  ComicType get comicType;

  static DownloadTask? fromJson(Map<String, dynamic> json) {
    switch (json["type"]) {
      case "ImagesDownloadTask":
        return ImagesDownloadTask.fromJson(json);
      default:
        return null;
    }
  }

  @override
  bool operator ==(Object other) {
    return other is DownloadTask &&
        other.id == id &&
        other.comicType == comicType;
  }

  @override
  int get hashCode => Object.hash(id, comicType);
}

class ImagesDownloadTask extends DownloadTask with _TransferSpeedMixin {
  final ComicSource source;

  final String comicId;

  /// comic details. If null, the comic details will be fetched from the source.
  ComicDetails? comic;

  /// chapters to download. If null, all chapters will be downloaded.
  final List<String>? chapters;

  @override
  String get id => comicId;

  @override
  ComicType get comicType => ComicType(source.key.hashCode);

  String? comicTitle;

  ImagesDownloadTask({
    required this.source,
    required this.comicId,
    this.comic,
    this.chapters,
    this.comicTitle,
  });

  @override
  void cancel() {
    _isRunning = false;
    stopRecorder();
    LocalManager().removeTask(this);
    var local = LocalManager().find(id, comicType);
    if (path != null) {
      if (local == null) {
        Future.sync(() async {
          var tasks = this.tasks.values.toList();
          for (var i = 0; i < tasks.length; i++) {
            if (!tasks[i].isComplete) {
              tasks[i].cancel();
              await tasks[i].wait();
            }
          }
          try {
            await Directory(path!).delete(recursive: true);
          }
          catch(e) {
            Log.error("Download", "Failed to delete directory: $e");
          }
        });
      } else if (chapters != null) {
        Future.sync(() async {
          for (var c in chapters!) {
            var dir = Directory(FilePath.join(path!, c));
            if (await dir.exists()) {
              await dir.delete(recursive: true);
            }
          }
        });
      }
    }
  }

  @override
  String? get cover => _cover ?? comic?.cover;

  @override
  String get message => _message;

  @override
  void pause() {
    if (isPaused) {
      return;
    }
    _isRunning = false;
    _message = "Paused".tl;
    _currentSpeed = 0;
    var shouldMove = <int>[];
    for (var entry in tasks.entries) {
      if (!entry.value.isComplete) {
        entry.value.cancel();
        shouldMove.add(entry.key);
      }
    }
    for (var i in shouldMove) {
      tasks.remove(i);
    }
    stopRecorder();
    notifyListeners();
  }

  @override
  double get progress => _totalCount == 0 ? 0 : _downloadedCount / _totalCount;

  bool _isRunning = false;

  bool _isError = false;

  String _message = "Fetching comic info...".tl;

  String? _cover;

  /// All images to download, key is chapter name
  Map<String, List<String>>? _images;

  /// Downloaded image count
  int _downloadedCount = 0;

  /// Total image count
  int _totalCount = 0;

  /// Current downloading image index
  int _index = 0;

  /// Current downloading chapter, index of [_images]
  int _chapter = 0;

  var tasks = <int, _ImageDownloadWrapper>{};

  int get _maxConcurrentTasks =>
      (appdata.settings["downloadThreads"] as num).toInt();

  void _scheduleTasks() {
    if (_images == null) return;
    var images = _images![_images!.keys.elementAt(_chapter)]!;
    var downloading = 0;
    for (var i = _index; i < images.length; i++) {
      if (downloading >= _maxConcurrentTasks) {
        return;
      }
      if (tasks[i] != null) {
        if (!tasks[i]!.isComplete) {
          downloading++;
        }
        if (tasks[i]!.error == null) {
          continue;
        }
      }
      Directory saveTo;
      if (comic!.chapters != null) {
        saveTo = Directory(FilePath.join(
          path!,
          LocalManager.getChapterDirectoryName(
            _images!.keys.elementAt(_chapter),
          ),
        ));
        if (!saveTo.existsSync()) {
          saveTo.createSync(recursive: true);
        }
      } else {
        saveTo = Directory(path!);
      }
      var task = _ImageDownloadWrapper(
        this,
        _images!.keys.elementAt(_chapter),
        images[i],
        saveTo,
        i,
      );
      tasks[i] = task;
      task.wait().then((task) {
        if (task.isComplete) {
          _scheduleTasks();
        }
      });
      downloading++;
    }
  }

  @override
  void resume() async {
    if (_isRunning) return;
    _isError = false;
    _message = "Resuming...".tl;
    _isRunning = true;
    notifyListeners();
    runRecorder();

    if (comic == null) {
      _message = "Fetching comic info...".tl;
      notifyListeners();
      var res = await _runWithRetry(() async {
        var r = await source.loadComicInfo!(comicId);
        if (r.error) {
          throw r.errorMessage!;
        } else {
          return r.data;
        }
      });
      if (!_isRunning) {
        return;
      }
      if (res.error) {
        _setError("${"Error".tl}: ${friendlyError(res.errorMessage!)}");
        return;
      } else {
        comic = res.data;
      }
    }

    if (path == null) {
      try {
        var dir = await LocalManager().findValidDirectory(
          comicId,
          comicType,
          comic!.title,
        );
        if (!(await dir.exists())) {
          await dir.create();
        }
        path = dir.path;
      } catch (e, s) {
        Log.error("Download", e.toString(), s);
        _setError("${"Error".tl}: $e");
        return;
      }
    }

    await LocalManager().saveCurrentDownloadingTasks();

    if (_cover == null) {
      _message = "Downloading cover...".tl;
      notifyListeners();
      var res = await _runWithRetry(() async {
        Uint8List? data;
        await for (var progress
            in ImageDownloader.loadThumbnail(comic!.cover, source.key)) {
          if (progress.imageBytes != null) {
            data = progress.imageBytes;
          }
        }
        if (data == null) {
          throw "Failed to download cover";
        }
        var fileType = detectFileType(data);
        var file = File(FilePath.join(path!, "cover${fileType.ext}"));
        await file.writeAsBytes(data);
        return "file://${file.path}";
      });
      if (res.error) {
        Log.error("Download", res.errorMessage!);
        _setError("${"Error".tl}: ${friendlyError(res.errorMessage!)}");
        return;
      } else {
        _cover = res.data;
        notifyListeners();
      }
      await LocalManager().saveCurrentDownloadingTasks();
    }

    if (_images == null) {
      if (comic!.chapters == null) {
        _message = "Fetching image list...".tl;
        notifyListeners();
        var res = await _runWithRetry(() async {
          var r = await source.loadComicPages!(comicId, null);
          if (r.error) {
            throw r.errorMessage!;
          } else {
            return r.data;
          }
        });
        if (!_isRunning) {
          return;
        }
        if (res.error) {
          Log.error("Download", res.errorMessage!);
          _setError("${"Error".tl}: ${friendlyError(res.errorMessage!)}");
          return;
        } else {
          _images = {'': res.data};
          _totalCount = _images!['']!.length;
        }
      } else {
        _images = {};
        _totalCount = 0;
        int cpCount = 0;
        int totalCpCount =
            chapters?.length ?? comic!.chapters!.allChapters.length;
        for (var i in comic!.chapters!.allChapters.keys) {
          if (chapters != null && !chapters!.contains(i)) {
            continue;
          }
          if (_images![i] != null) {
            _totalCount += _images![i]!.length;
            continue;
          }
          _message = "${"Fetching image list".tl} ($cpCount/$totalCpCount)...";
          notifyListeners();
          var res = await _runWithRetry(() async {
            var r = await source.loadComicPages!(comicId, i);
            if (r.error) {
              throw r.errorMessage!;
            } else {
              return r.data;
            }
          });
          if (!_isRunning) {
            return;
          }
          if (res.error) {
            Log.error("Download", res.errorMessage!);
            _setError("${"Error".tl}: ${friendlyError(res.errorMessage!)}");
            return;
          } else {
            _images![i] = res.data;
            _totalCount += _images![i]!.length;
          }
        }
      }
      _message = "$_downloadedCount/$_totalCount";
      notifyListeners();
      await LocalManager().saveCurrentDownloadingTasks();
    }

    if (_images == null) return;
    while (_chapter < _images!.length) {
      var images = _images![_images!.keys.elementAt(_chapter)]!;
      tasks.clear();
      while (_index < images.length) {
        _scheduleTasks();
        var task = tasks[_index]!;
        await task.wait();
        if (isPaused) {
          return;
        }
        if (task.error != null) {
          Log.error("Download", task.error.toString());
          _setError("${"Error".tl}: ${task.error}");
          return;
        }
        _index++;
        _downloadedCount++;
        _message = "$_downloadedCount/$_totalCount";
        await LocalManager().saveCurrentDownloadingTasks();
      }
      _index = 0;
      _chapter++;
    }

    // Package downloaded chapters as CBZ if enabled
    if (appdata.settings['saveAsCbz'] == true) {
      // Sanitize the manga title once and use it as the CBZ filename prefix,
      // matching the "漫画名 + 章节名" naming convention so files stay
      // recognizable when copied out of the per-comic folder.
      final mangaName =
          sanitizeFileName(comic?.title ?? comicTitle ?? "Comic");
      if (comic!.chapters != null) {
        // 多章节模式：每个章节文件夹打包为单独的 .cbz
        for (var chapterId in (chapters ?? comic!.chapters!.allChapters.keys)) {
          var chapterDir = Directory(FilePath.join(
            path!,
            LocalManager.getChapterDirectoryName(chapterId),
          ));
          if (!await chapterDir.exists()) continue;
          // allChapters: Map<chapterId, chapterTitle>
          // 用 .keys 拿到的是 ID（如 1221144），CBZ 名要用人能看懂的章节标题
          final chapterTitle = comic!.chapters!.allChapters[chapterId] ?? chapterId;
          final chapterName =
              LocalManager.getChapterDirectoryName(chapterTitle);
          final cbzFileName = '$mangaName - $chapterName.cbz';
          var cbzPath =
              FilePath.join(p.dirname(chapterDir.path), cbzFileName);
          try {
            final bytes = await _buildCbzFromDir(chapterDir);
            await _writeCbzBytes(cbzPath, bytes);
            if (appdata.settings['deleteFolderAfterCbz'] == true) {
              await chapterDir.delete(recursive: true);
            }
          } catch (e, s) {
            Log.error("Download", "Failed to package chapter as CBZ: $e\n$s");
          }
        }
      } else {
        // 单章节模式（单行本）：整个下载目录打包为一个 .cbz
        var dir = Directory(path!);
        if (await dir.exists()) {
          final cbzFileName = '$mangaName.cbz';
          var cbzPath = FilePath.join(p.dirname(dir.path), cbzFileName);
          try {
            final bytes = await _buildCbzFromDir(dir);
            await _writeCbzBytes(cbzPath, bytes);
            if (appdata.settings['deleteFolderAfterCbz'] == true) {
              await dir.delete(recursive: true);
            }
          } catch (e, s) {
            Log.error("Download", "Failed to package single chapter as CBZ: $e\n$s");
          }
        }
      }
    }

    LocalManager().completeTask(this);
    stopRecorder();
  }

  @override
  void onNextSecond(Timer t) {
    notifyListeners();
    super.onNextSecond(t);
  }

  void _setError(String message) {
    _isRunning = false;
    _isError = true;
    _message = message;
    notifyListeners();
    stopRecorder();
  }

  @override
  int get speed => currentSpeed;

  @override
  String get title => comic?.title ?? comicTitle ?? "Loading...";

  @override
  Map<String, dynamic> toJson() {
    return {
      "type": "ImagesDownloadTask",
      "source": source.key,
      "comicId": comicId,
      "comic": comic?.toJson(),
      "chapters": chapters,
      "path": path,
      "cover": _cover,
      "images": _images,
      "downloadedCount": _downloadedCount,
      "totalCount": _totalCount,
      "index": _index,
      "chapter": _chapter,
    };
  }

  static ImagesDownloadTask? fromJson(Map<String, dynamic> json) {
    if (json["type"] != "ImagesDownloadTask") {
      return null;
    }

    Map<String, List<String>>? images;
    if (json["images"] != null) {
      images = {};
      for (var entry in json["images"].entries) {
        images[entry.key] = List<String>.from(entry.value);
      }
    }

    return ImagesDownloadTask(
      source: ComicSource.find(json["source"])!,
      comicId: json["comicId"],
      comic:
          json["comic"] == null ? null : ComicDetails.fromJson(json["comic"]),
      chapters: ListOrNull.from(json["chapters"]),
    )
      ..path = json["path"]
      .._cover = json["cover"]
      .._images = images
      .._downloadedCount = json["downloadedCount"]
      .._totalCount = json["totalCount"]
      .._index = json["index"]
      .._chapter = json["chapter"];
  }

  @override
  bool get isError => _isError;

  @override
  bool get isPaused => !_isRunning;

  @override
  LocalComic toLocalComic() {
    return LocalComic(
      id: comic!.id,
      title: title,
      subtitle: comic!.subTitle ?? '',
      tags: comic!.tags.entries.expand((e) {
        return e.value.map((v) => "${e.key}:$v");
      }).toList(),
      directory: Directory(path!).name,
      chapters: comic!.chapters,
      cover: File(_cover!.split("file://").last).name,
      comicType: ComicType(source.key.hashCode),
      downloadedChapters: chapters ?? comic?.chapters?.ids.toList() ?? [],
      createdAt: DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is ImagesDownloadTask) {
      return other.comicId == comicId && other.source.key == source.key;
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(comicId, source.key);
}

Future<Res<T>> _runWithRetry<T>(Future<T> Function() task,
    {int retry = 3}) async {
  for (var i = 0; i < retry; i++) {
    try {
      return Res(await task());
    } catch (e) {
      if (i == retry - 1) {
        return Res.error(e.toString());
      }
      await Future.delayed(Duration(seconds: i + 1));
    }
  }
  throw UnimplementedError();
}

class _ImageDownloadWrapper {
  final ImagesDownloadTask task;

  final String chapter;

  final int index;

  final String image;

  final Directory saveTo;

  _ImageDownloadWrapper(
    this.task,
    this.chapter,
    this.image,
    this.saveTo,
    this.index,
  ) {
    start();
  }

  bool isComplete = false;

  String? error;

  bool isCancelled = false;

  void cancel() {
    isCancelled = true;
  }

  var completers = <Completer<_ImageDownloadWrapper>>[];

  var retry = 3;

  void start() async {
    int lastBytes = 0;
    try {
      await for (var p in ImageDownloader.loadComicImageUnwrapped(
          image, task.source.key, task.comicId, chapter)) {
        if (isCancelled) {
          return;
        }
        task.onData(p.currentBytes - lastBytes);
        lastBytes = p.currentBytes;
        if (p.imageBytes != null) {
          var fileType = detectFileType(p.imageBytes!);
          var file = saveTo.joinFile("$index${fileType.ext}");
          await file.writeAsBytes(p.imageBytes!);
          isComplete = true;
          for (var c in completers) {
            c.complete(this);
          }
          completers.clear();
        }
      }
    } catch (e, s) {
      if (isCancelled) {
        return;
      }
      Log.error("Download", e.toString(), s);
      retry--;
      if (retry > 0) {
        start();
        return;
      }
      error = e.toString();
      for (var c in completers) {
        if (!c.isCompleted) {
          c.complete(this);
        }
      }
    }
  }

  Future<_ImageDownloadWrapper> wait() {
    if (isComplete) {
      return Future.value(this);
    }
    var c = Completer<_ImageDownloadWrapper>();
    completers.add(c);
    return c.future;
  }
}

abstract mixin class _TransferSpeedMixin {
  int _bytesSinceLastSecond = 0;

  int _currentSpeed = 0;

  int get currentSpeed => _currentSpeed;

  Timer? timer;

  void onData(int length) {
    if (timer == null) return;
    if (length < 0) {
      return;
    }
    _bytesSinceLastSecond += length;
  }

  void onNextSecond(Timer t) {
    _currentSpeed = _bytesSinceLastSecond;
    _bytesSinceLastSecond = 0;
  }

  void runRecorder() {
    if (timer != null) {
      timer!.cancel();
    }
    _bytesSinceLastSecond = 0;
    timer = Timer.periodic(const Duration(seconds: 1), onNextSecond);
  }

  void stopRecorder() {
    timer?.cancel();
    timer = null;
    _currentSpeed = 0;
    _bytesSinceLastSecond = 0;
  }
}

class ArchiveDownloadTask extends DownloadTask {
  final String archiveUrl;

  final ComicDetails comic;

  late ComicSource source;

  /// Download comic by archive url
  ///
  /// Currently only support zip file and comics without chapters
  ArchiveDownloadTask(this.archiveUrl, this.comic) {
    source = ComicSource.find(comic.sourceKey)!;
  }

  FileDownloader? _downloader;

  String _message = "Fetching comic info...".tl;

  bool _isRunning = false;

  bool _isError = false;

  void _setError(String message) {
    _isRunning = false;
    _isError = true;
    _message = message;
    notifyListeners();
    Log.error("Download", message);
  }

  @override
  void cancel() async {
    _isRunning = false;
    await _downloader?.stop();
    if (path != null) {
      Directory(path!).deleteIgnoreError(recursive: true);
    }
    path = null;
    LocalManager().removeTask(this);
  }

  @override
  ComicType get comicType => ComicType(source.key.hashCode);

  @override
  String? get cover => comic.cover;

  @override
  String get id => comic.id;

  @override
  bool get isError => _isError;

  @override
  bool get isPaused => !_isRunning;

  @override
  String get message => _message;

  int _currentBytes = 0;

  int _expectedBytes = 0;

  int _speed = 0;

  @override
  void pause() {
    _isRunning = false;
    _message = "Paused".tl;
    _downloader?.stop();
    notifyListeners();
  }

  @override
  double get progress =>
      _expectedBytes == 0 ? 0 : _currentBytes / _expectedBytes;

  @override
  void resume() async {
    if (_isRunning) {
      return;
    }
    _isError = false;
    _isRunning = true;
    notifyListeners();
    _message = "Downloading...".tl;

    if (path == null) {
      var dir = await LocalManager().findValidDirectory(
        comic.id,
        comicType,
        comic.title,
      );
      if (!(await dir.exists())) {
        try {
          await dir.create();
        } catch (e) {
          _setError("${"Error".tl}: $e");
          return;
        }
      }
      path = dir.path;
    }

    var archiveFile =
        File(FilePath.join(App.dataPath, "archive_downloading.zip"));

    Log.info("Download", "Downloading $archiveUrl");

    _downloader = FileDownloader(archiveUrl, archiveFile.path);

    bool isDownloaded = false;

    try {
      await for (var status in _downloader!.start()) {
        _currentBytes = status.downloadedBytes;
        _expectedBytes = status.totalBytes;
        _message =
            "${bytesToReadableString(_currentBytes)}/${bytesToReadableString(_expectedBytes)}";
        _speed = status.bytesPerSecond;
        isDownloaded = status.isFinished;
        notifyListeners();
      }
    } catch (e) {
      _setError("${"Error".tl}: $e");
      return;
    }

    if (!_isRunning) {
      return;
    }

    if (!isDownloaded) {
      _setError("${"Error".tl}: ${"Download failed".tl}");
      return;
    }

    try {
      await _extractArchive(archiveFile.path, path!);
    } catch (e) {
      _setError("${"Failed to extract archive".tl}: $e");
      return;
    }

    await archiveFile.deleteIgnoreError();

    LocalManager().completeTask(this);
  }

  static Future<void> _extractArchive(String archive, String outDir) async {
    var out = Directory(outDir);
    if (out is AndroidDirectory) {
      // Saf directory can't be accessed by native code.
      var cacheDir = FilePath.join(App.cachePath, "archive_downloading");
      Directory(cacheDir).forceCreateSync();
      await Isolate.run(() {
        ZipFile.openAndExtract(archive, cacheDir);
      });
      await copyDirectoryIsolate(Directory(cacheDir), Directory(outDir));
      await Directory(cacheDir).deleteIgnoreError(recursive: true);
    } else {
      await Isolate.run(() {
        ZipFile.openAndExtract(archive, outDir);
      });
    }
  }

  @override
  int get speed => _speed;

  @override
  String get title => comic.title;

  @override
  Map<String, dynamic> toJson() {
    return {
      "type": "ArchiveDownloadTask",
      "archiveUrl": archiveUrl,
      "comic": comic.toJson(),
      "path": path,
    };
  }

  static ArchiveDownloadTask? fromJson(Map<String, dynamic> json) {
    if (json["type"] != "ArchiveDownloadTask") {
      return null;
    }
    return ArchiveDownloadTask(
      json["archiveUrl"],
      ComicDetails.fromJson(json["comic"]),
    )..path = json["path"];
  }

  String _findCover() {
    var files = Directory(path!).listSync();
    for (var f in files) {
      if (f.name.startsWith('cover')) {
        return f.name;
      }
    }
    if (files.isEmpty) return '';
    files.sort((a, b) {
      return a.name.compareTo(b.name);
    });
    return files.first.name;
  }

  @override
  LocalComic toLocalComic() {
    return LocalComic(
      id: comic.id,
      title: title,
      subtitle: comic.subTitle ?? '',
      tags: comic.tags.entries.expand((e) {
        return e.value.map((v) => "${e.key}:$v");
      }).toList(),
      directory: Directory(path!).name,
      chapters: null,
      cover: _findCover(),
      comicType: ComicType(source.key.hashCode),
      downloadedChapters: [],
      createdAt: DateTime.now(),
    );
  }
}

/// Build a CBZ (zip) archive in memory from a directory's contents.
///
/// Replaces `ZipFile.compressFolderAsync` which is backed by `dart:io` and
/// cannot write to SAF tree URIs (e.g. `android://primary:Download/...`).
/// `archive` is pure Dart, so we can stream bytes in memory and then hand
/// the result to `AndroidFile.writeAsBytesSync` which knows how to write
/// into a SAF tree.
Future<Uint8List> _buildCbzFromDir(Directory dir) async {
  final archive = Archive();

  Future<void> addEntries(Directory d, String prefix) async {
    await for (final entity in d.list(recursive: false, followLinks: false)) {
      final name = p.basename(entity.path);
      final entryPath = prefix.isEmpty ? name : '$prefix/$name';
      if (entity is File) {
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(entryPath, bytes.length, bytes));
      } else if (entity is Directory) {
        await addEntries(entity, entryPath);
      }
    }
  }

  await addEntries(dir, '');
  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded);
}

/// Write a CBZ byte buffer to [cbzPath], routing through AndroidFile so SAF
/// tree URIs work the same as plain paths.
Future<void> _writeCbzBytes(String cbzPath, Uint8List bytes) async {
  final isSaf = cbzPath.startsWith('content://') ||
      cbzPath.startsWith('android://');
  if (isSaf) {
    var safFile = AndroidFile.fromPathSync(cbzPath);
    if (safFile == null) {
      // File doesn't exist yet: ensure the parent directory exists in the
      // SAF tree, then re-resolve so writeAsBytesSync has a valid descriptor.
      final parent = AndroidDirectory.fromPathSync(p.dirname(cbzPath));
      parent?.createSync(recursive: true);
      safFile = AndroidFile.fromPathSync(cbzPath);
    }
    safFile?.writeAsBytesSync(bytes);
  } else {
    File(cbzPath).writeAsBytesSync(bytes, flush: true);
  }
}
