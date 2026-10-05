import 'dart:async';
import 'dart:io';

import 'package:dio/io.dart';
import 'package:kong_comic/foundation/update_mirror.dart';
import 'package:kong_comic/network/app_dio.dart';
import 'package:kong_comic/network/proxy.dart';
import 'package:kong_comic/utils/ext.dart';

class FileDownloader {
  final String url;
  final String savePath;
  final int maxConcurrent;

  /// Ignore `Range` semantics and pull the file in one stream.
  ///
  /// Some GitHub mirrors do not honor `Range` and answer `200` with the entire
  /// body for every chunk request. Feeding those into parallel blocks writes
  /// several copies of the whole file at different offsets, producing an APK
  /// that passes the structural ZIP check but fails its SHA-256 check. Those
  /// hosts must be downloaded start to finish in a single request.
  final bool singleStream;

  /// How many times a single chunk is retried before the whole download is
  /// abandoned. GitHub resets connections frequently, especially from mainland
  /// China; without retries one dropped chunk fails the whole APK download.
  static const int maxAttemptsPerBlock = 3;

  FileDownloader(
    this.url,
    this.savePath, {
    this.maxConcurrent = 4,
    this.singleStream = false,
  });

  int _currentBytes = 0;

  int _lastBytes = 0;

  late int _fileSize;

  final _dio = Dio()
    ..options.connectTimeout = const Duration(seconds: 30)
    ..options.receiveTimeout = const Duration(seconds: 30)
    ..options.sendTimeout = const Duration(seconds: 30);

  RandomAccessFile? _file;

  bool _isWriting = false;

  int _kChunkSize = 16 * 1024 * 1024;

  bool _canceled = false;

  /// Set by the first chunk that gives up. Blocks any further chunks from
  /// starting and is rethrown once the running ones finish, so no error goes
  /// unawaited (a stray `throw` in a `then` callback used to leak here).
  Object? _failure;

  /// Chunk layout of the file.
  ///
  /// Must be initialized, not `late`: [_createTasks] reads `_blocks.isEmpty` on
  /// a fresh download (no `.download` resume file), and a `late` field throws
  /// LateInitializationError the moment it is read before assignment — which
  /// made *every* first-time APK download fail instantly.
  List<_DownloadBlock> _blocks = [];

  Future<void> _writeStatus() async {
    var file = File("$savePath.download");
    await file.writeAsString(_blocks.map((e) => e.toString()).join("\n"));
  }

  Future<void> _readStatus() async {
    var file = File("$savePath.download");
    if (!await file.exists()) {
      return;
    }

    var lines = await file.readAsLines();
    _blocks = lines.map((e) => _DownloadBlock.fromString(e)).toList();
  }

  /// True if the already-downloaded file contains a ZIP End Of Central
  /// Directory record (signature `PK\x05\x06`) near its tail. A complete
  /// APK/ZIP always has one; a partially-written file does not, so this lets
  /// us distinguish "download truly finished" from "state file claims done
  /// but the file was never fully flushed".
  Future<bool> _eocdPresent() async {
    final f = File(savePath);
    if (!await f.exists()) return false;
    final size = await f.length();
    if (size < 22) return false;
    final raf = await f.open(mode: FileMode.read);
    try {
      final tailLen = size > 128 * 1024 ? 128 * 1024 : size;
      await raf.setPosition(size - tailLen);
      final tail = await raf.read(tailLen);
      for (var i = 0; i + 3 < tail.length; i++) {
        if (tail[i] == 0x50 &&
            tail[i + 1] == 0x4B &&
            tail[i + 2] == 0x05 &&
            tail[i + 3] == 0x06) {
          return true;
        }
      }
      return false;
    } finally {
      await raf.close();
    }
  }

  /// create file and write empty bytes
  Future<void> _prepareFile() async {
    var file = File(savePath);
    if (await file.exists()) {
      if (file.lengthSync() == _fileSize &&
          File("$savePath.download").existsSync()) {
        _file = await file.open(mode: FileMode.append);
        return;
      } else {
        await file.delete();
      }
    }

    await file.create(recursive: true);
    _file = await file.open(mode: FileMode.append);
    await _file!.truncate(_fileSize);
  }

  Future<void> _createTasks() async {
    var res = await _dio.head(
      url,
      options: Options(headers: updateRequestHeaders()),
    );
    var length = res.headers["content-length"]?.first;
    if (length == null) {
      throw Exception(
          "Download failed: server did not provide Content-Length for $url");
    }
    _fileSize = int.parse(length);

    await _prepareFile();

    if (File("$savePath.download").existsSync()) {
      await _readStatus();
      _currentBytes = _blocks.fold<int>(0,
          (previousValue, element) => previousValue + element.downloadedBytes);
      // The .download state claims the file is already complete, but a prior
      // run may have been killed before the OS flushed every block to disk.
      // Verify the End Of Central Directory record really exists; if not,
      // discard the stale state and re-download from scratch instead of
      // resuming a half-written file.
      if (_currentBytes >= _fileSize && !await _eocdPresent()) {
        await File("$savePath.download").delete();
        _currentBytes = 0;
        _blocks = [];
      }
    }
    if (_blocks.isEmpty) {
      if (_fileSize > 1024 * 1024 * 1024) {
        _kChunkSize = 64 * 1024 * 1024;
      } else if (_fileSize > 512 * 1024 * 1024) {
        _kChunkSize = 32 * 1024 * 1024;
      }

      _blocks = [];
      if (singleStream) {
        // One block covering everything: no Range arithmetic to go wrong when
        // the server answers every request with the full body.
        _blocks.add(_DownloadBlock(0, _fileSize, 0, false));
        return;
      }
      for (var i = 0; i < _fileSize; i += _kChunkSize) {
        var end = i + _kChunkSize;
        if (end > _fileSize) {
          _blocks.add(_DownloadBlock(i, _fileSize, 0, false));
        } else {
          _blocks.add(_DownloadBlock(i, i + _kChunkSize, 0, false));
        }
      }
    }
  }

  Stream<DownloadingStatus> start() {
    var stream = StreamController<DownloadingStatus>();
    _download(stream);
    return stream.stream;
  }

  void _reportStatus(StreamController<DownloadingStatus> stream) {
    stream.add(DownloadingStatus(_currentBytes, _fileSize, 0));
  }

  void _download(StreamController<DownloadingStatus> resultStream) async {
    try {
      var proxy = await getProxy();
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          configureProxy(client, proxy);
          return client;
        },
      );

      // get file size
      await _createTasks();

      if (_canceled) {
        // Must close the stream: no status timer is running yet, so nothing
        // else would ever emit again and the caller's `await completer.future`
        // would wait forever. Kicking this in is exactly what a stalled mirror
        // does, so leaving it would hang the whole update instead of letting it
        // fall through to the next download route.
        if (!resultStream.isClosed) await resultStream.close();
        return;
      }

      // check if file is downloaded
      if (_currentBytes >= _fileSize) {
        await _file!.close();
        _file = null;
        _reportStatus(resultStream);
        resultStream.close();
        return;
      }

      _reportStatus(resultStream);

      Timer? statusTimer;
      statusTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_canceled || _currentBytes >= _fileSize) {
          timer.cancel();
          statusTimer = null;
          return;
        }
        resultStream.add(DownloadingStatus(
            _currentBytes, _fileSize, _currentBytes - _lastBytes));
        _lastBytes = _currentBytes;
      });

      // start downloading
      await _scheduleDownload();
      statusTimer?.cancel();
      if (_canceled) {
        resultStream.close();
        return;
      }
      await _file!.close();
      _file = null;
      await File("$savePath.download").delete();

      // check if download is finished
      if (_currentBytes < _fileSize) {
        resultStream.addError(Exception("Download failed: Expected $_fileSize bytes, "
            "but only $_currentBytes bytes downloaded."));
        resultStream.close();
        return;
      }

      resultStream.add(DownloadingStatus(_currentBytes, _fileSize, 0, true));
      resultStream.close();
    } catch (e, s) {
      await _file?.close();
      _file = null;
      resultStream.addError(e, s);
      resultStream.close();
    }
  }

  Future<void> _scheduleDownload() async {
    final running = <Future<void>>{};
    while (true) {
      if (_canceled) return;
      // Stop feeding new chunks once one has failed for good.
      if (_failure != null) break;
      if (running.length >= maxConcurrent) {
        await Future.any(running);
        continue;
      }
      final block = _blocks.firstWhereOrNull((element) =>
          !element.downloading &&
          element.end - element.start > element.downloadedBytes);
      if (block == null) {
        break;
      }
      block.downloading = true;
      final task = _fetchBlock(block);
      running.add(task);
      // `_fetchBlock` never throws, so this detached listener cannot produce
      // an unhandled error.
      unawaited(task.whenComplete(() => running.remove(task)));
    }
    await Future.wait(running.toList());
    if (_failure != null) {
      throw _failure!;
    }
  }

  /// Fetch [block], retrying transient failures. Never throws: a permanent
  /// failure is recorded in [_failure] and rethrown by [_scheduleDownload].
  ///
  /// The Range header is rebuilt from `block.downloadedBytes` on every
  /// attempt, so a retry resumes the chunk instead of restarting it.
  Future<void> _fetchBlock(_DownloadBlock block) async {
    for (var attempt = 0; attempt < maxAttemptsPerBlock; attempt++) {
      try {
        await _fetchBlockOnce(block);
        block.downloading = false;
        return;
      } catch (e) {
        if (_canceled) {
          block.downloading = false;
          return;
        }
        if (attempt == maxAttemptsPerBlock - 1) {
          block.downloading = false;
          _failure ??= e;
          return;
        }
        // Brief backoff so a brief network hiccup has time to clear.
        await Future.delayed(Duration(milliseconds: 400 << attempt));
      }
    }
  }

  Future<void> _fetchBlockOnce(_DownloadBlock block) async {
    final start = block.start;
    final end = block.end;

    if (start > _fileSize) {
      return;
    }

    var options = Options(
      responseType: ResponseType.stream,
      headers: updateRequestHeaders(
        range: 'bytes=${start + block.downloadedBytes}-${end - 1}',
      ),
      preserveHeaderCase: true,
    );
    var res = await _dio.get<ResponseBody>(url, options: options);
    if (_canceled) return;
    if (res.data == null) {
      throw Exception("Failed to block $start-$end");
    }

    var buffer = <int>[];
    await for (var data in res.data!.stream) {
      if (_canceled) return;
      buffer.addAll(data);
      if (buffer.length > 16 * 1024) {
        if (_isWriting) continue;
        // `_isWriting` guards the file handle, which is shared by every chunk.
        // Writing throws for reasons beyond our control (disk full, the file
        // being closed by [stop] mid-write), and without a `finally` the flag
        // would stay set forever — every other chunk then spins in the
        // `while (_isWriting)` loop below and the download hangs silently
        // instead of failing.
        _isWriting = true;
        try {
          _currentBytes += buffer.length;
          final sink = _requireFile();
          await sink.setPosition(start + block.downloadedBytes);
          await sink.writeFrom(buffer);
          block.downloadedBytes += buffer.length;
          buffer.clear();
          await _writeStatus();
        } finally {
          _isWriting = false;
        }
      }
    }

    if (buffer.isNotEmpty) {
      while (_isWriting) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      _isWriting = true;
      try {
        _currentBytes += buffer.length;
        final sink = _requireFile();
        await sink.setPosition(start + block.downloadedBytes);
        await sink.writeFrom(buffer);
        block.downloadedBytes += buffer.length;
        await _writeStatus();
      } finally {
        _isWriting = false;
      }
    }

    block.downloading = false;
  }

  /// The shared sink every chunk writes through, or a clear error when the
  /// download was stopped and the handle is already gone.
  RandomAccessFile _requireFile() {
    final file = _file;
    if (file == null) {
      throw StateError("Download was stopped");
    }
    return file;
  }

  Future<void> stop() async {
    _canceled = true;
    await _file?.close();
    _file = null;
  }
}

class DownloadingStatus {
  /// The current downloaded bytes
  final int downloadedBytes;

  /// The total bytes of the file
  final int totalBytes;

  /// Whether the download is finished
  final bool isFinished;

  /// The download speed in bytes per second
  final int bytesPerSecond;

  const DownloadingStatus(
      this.downloadedBytes, this.totalBytes, this.bytesPerSecond,
      [this.isFinished = false]);

  @override
  String toString() {
    return "Downloaded: $downloadedBytes/$totalBytes ${isFinished ? "Finished" : ""}";
  }
}

class _DownloadBlock {
  final int start;
  final int end;
  int downloadedBytes;
  bool downloading;

  _DownloadBlock(this.start, this.end, this.downloadedBytes, this.downloading);

  @override
  String toString() {
    return "$start-$end-$downloadedBytes";
  }

  _DownloadBlock.fromString(String str)
      : start = int.parse(str.split("-")[0]),
        end = int.parse(str.split("-")[1]),
        downloadedBytes = int.parse(str.split("-")[2]),
        downloading = false;
}
