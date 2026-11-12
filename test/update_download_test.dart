import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kong_comic/network/file_downloader.dart';
import 'package:kong_comic/utils/app_update.dart';

/// A file server that answers the HEAD probe, sends one chunk of a Range
/// request and then goes silent — the exact shape of a throttled GitHub
/// connection: bytes arrive quickly at first, then nothing until the socket
/// times out.
class _SlowServer {
  _SlowServer(this._server, this.size);

  final HttpServer _server;
  final int size;

  final List<HttpResponse> _open = [];

  static Future<_SlowServer> start({int size = 4 * 1024 * 1024}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final slow = _SlowServer(server, size);
    server.listen(slow._handle);
    return slow;
  }

  String url(String name) => 'http://127.0.0.1:${_server.port}/$name';

  Future<void> _handle(HttpRequest req) async {
    if (req.method == 'HEAD') {
      req.response.headers.contentLength = size;
      await req.response.close();
      return;
    }
    final match = RegExp(
      r'bytes=(\d+)-',
    ).firstMatch(req.headers.value('range') ?? '');
    final start = match == null ? 0 : int.parse(match.group(1)!);
    final remaining = size - start;
    req.response.statusCode = 206;
    req.response.headers.set('content-range', 'bytes $start-${size - 1}/$size');
    req.response.headers.contentLength = remaining;
    req.response.add(List<int>.filled(64 * 1024, 7));
    await req.response.flush();
    // Deliberately left open: the client is the one that has to abort.
    _open.add(req.response);
  }

  Future<void> close() async {
    for (final response in _open) {
      try {
        await response.close();
      } catch (_) {
        // The client already tore the connection down; that is expected.
      }
    }
    await _server.close(force: true);
  }
}

void main() {
  group('canResumeAcrossMirror', () {
    test('keeps partial bytes only when the next route serves the same size', () {
      expect(
        canResumeAcrossMirror(
          supportsRange: true,
          remoteSize: 40 * 1024 * 1024,
          localSize: 40 * 1024 * 1024,
        ),
        isTrue,
      );
      // A different size means a different file: never splice the two.
      expect(
        canResumeAcrossMirror(
          supportsRange: true,
          remoteSize: 41 * 1024 * 1024,
          localSize: 40 * 1024 * 1024,
        ),
        isFalse,
      );
      // Without Range the next route would rewrite the file from offset 0.
      expect(
        canResumeAcrossMirror(
          supportsRange: false,
          remoteSize: 40 * 1024 * 1024,
          localSize: 40 * 1024 * 1024,
        ),
        isFalse,
      );
      // Unknown remote size: cannot prove the bytes line up.
      expect(
        canResumeAcrossMirror(
          supportsRange: true,
          remoteSize: null,
          localSize: 40 * 1024 * 1024,
        ),
        isFalse,
      );
      // Nothing downloaded yet.
      expect(
        canResumeAcrossMirror(
          supportsRange: true,
          remoteSize: 40 * 1024 * 1024,
          localSize: 0,
        ),
        isFalse,
      );
    });
  });

  group('FileDownloaderHandle', () {
    test('cancel completes whenCanceled and is idempotent', () async {
      final handle = FileDownloaderHandle();
      var notified = 0;
      handle.whenCanceled.then((_) => notified++);

      handle.cancel();
      handle.cancel();
      await handle.whenCanceled;

      expect(handle.isCanceled, isTrue);
      expect(notified, 1);
      expect(handle.cancelToken.isCancelled, isTrue);
    });

    test('a route switch is not a cancellation, and survives resetStall', () async {
      final handle = FileDownloaderHandle();
      var canceled = false;
      handle.whenCanceled.then((_) => canceled = true);

      handle.requestSwitch();
      handle.resetStall();

      expect(handle.isCanceled, isFalse);
      expect(canceled, isFalse);
      // A switch tapped while a mirror is still being probed must not be wiped
      // by the next route's bookkeeping, otherwise the tap is silently lost.
      expect(handle.switchPending, isTrue);
    });
  });

  group('FileDownloader cancellation', () {
    late _SlowServer server;
    late Directory dir;

    setUp(() async {
      server = await _SlowServer.start();
      dir = Directory.systemTemp.createTempSync('kc_update_cancel');
    });

    tearDown(() async {
      await server.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('stop() ends a download stuck on a silent socket immediately', () async {
      final downloader = FileDownloader(
        server.url('KongComic-test.apk'),
        '${dir.path}/KongComic-test.apk',
        resolveProxy: () async => null,
      );
      final done = Completer<void>();
      var received = 0;
      final sub = downloader.start().listen(
        (status) {
          if (status.downloadedBytes > received) {
            received = status.downloadedBytes;
          }
        },
        onError: (_) {},
        onDone: done.complete,
      );

      // Let the request start and the first chunk land, so the downloader is
      // genuinely parked on a socket that has gone silent.
      await Future.delayed(const Duration(milliseconds: 1500));
      expect(received, greaterThan(0));
      expect(downloader.isCanceled, isFalse);

      final stopwatch = Stopwatch()..start();
      await downloader.stop();
      // Before the CancelToken was wired in, this only flipped a flag that was
      // read between chunks, so the caller waited out the 30 s receive timeout.
      await done.future.timeout(const Duration(seconds: 3));
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
      await sub.cancel();
    });
  });
}
