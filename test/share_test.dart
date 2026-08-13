import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/utils/io.dart';

// share_plus v12 talks to the platform through this channel. We mock it so the
// test runs on the host (no device/emulator needed) while still exercising the
// real Share helpers in lib/utils/io.dart.
const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

void main() {
  // Required so we can register a mock method-call handler on the share channel.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<MethodCall> calls;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kong_share_');
    // The share fix materialises shared files under App.cachePath first, so
    // point it at a writable temp dir for the test.
    App.cachePath = tempDir.path;
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_shareChannel, (call) async {
      calls.add(call);
      // share_plus expects a status string back, which it wraps in ShareResult.
      return 'success';
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_shareChannel, null);
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // best effort cleanup
    }
  });

  test('shareText invokes the share channel with the given text', () async {
    await Share.shareText('hello kong');

    expect(calls, hasLength(1));
    expect(calls.first.method, 'share');
    final args = calls.first.arguments as Map<Object?, Object?>;
    expect(args['text'], 'hello kong');
  });

  test(
      'shareFile writes bytes to cache then shares the cached file (the fix)',
      () async {
    final data = Uint8List.fromList([1, 2, 3, 4, 5]);
    const filename = 'cover.png';
    await Share.shareFile(data: data, filename: filename, mime: 'image/png');

    // The fix: bytes are written to a real file under App.cachePath so the
    // platform share sheet can read them reliably (instead of an in-memory
    // file the OS cannot open).
    final cacheFile = File('${tempDir.path}/$filename');
    expect(cacheFile.existsSync(), isTrue,
        reason: 'shared bytes should be materialised into the cache');
    expect(cacheFile.readAsBytesSync(), data,
        reason: 'cached file should contain the exact shared bytes');

    expect(calls, hasLength(1));
    final args = calls.first.arguments as Map<Object?, Object?>;
    expect(args['paths'], contains(cacheFile.path),
        reason: 'share channel should receive the cached file path');
  });

  test('shareFiles shares every provided path', () async {
    final p1 = '${tempDir.path}/page1.jpg';
    final p2 = '${tempDir.path}/page2.jpg';
    File(p1).writeAsBytesSync([9, 9, 9]);
    File(p2).writeAsBytesSync([8, 8, 8]);

    await Share.shareFiles(paths: [p1, p2]);

    expect(calls, hasLength(1));
    final args = calls.first.arguments as Map<Object?, Object?>;
    expect(args['paths'], containsAll([p1, p2]),
        reason: 'share channel should receive all requested paths');
  });
}
