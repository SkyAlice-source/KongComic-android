import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/utils/io.dart';

// share_plus v12 talks to the platform through this channel. We mock it so the
// test runs on the host (no device/emulator needed) while still exercising the
// real Share helpers in lib/utils/io.dart.
const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

// share_plus v12 把「只有字节、没有路径」的 XFile 落到临时目录后再交给原生层，
// 落盘目录来自 path_provider。host 测试里这个插件不存在，必须自己给出一个
// 真实可写的目录，否则会抛 MissingPluginException。
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      return tempDir.path;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_shareChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
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
      'shareFile writes bytes to disk then shares the materialised file (the fix)',
      () async {
    final data = Uint8List.fromList([1, 2, 3, 4, 5]);
    const filename = 'cover.png';
    await Share.shareFile(data: data, filename: filename, mime: 'image/png');

    expect(calls, hasLength(1));
    final args = calls.first.arguments as Map<Object?, Object?>;
    // The fix: bytes are written to a real file before reaching the platform
    // share sheet (an in-memory file cannot be opened by the OS). share_plus
    // does the materialising now, so we assert on what actually got handed over.
    final paths = (args['paths'] as List<Object?>).cast<String>();
    expect(paths, hasLength(1));

    final sharedFile = File(paths.single);
    expect(sharedFile.existsSync(), isTrue,
        reason: 'shared bytes should be materialised into a real file');
    expect(sharedFile.path, endsWith(filename),
        reason: 'the original filename should be preserved');
    expect(sharedFile.readAsBytesSync(), data,
        reason: 'the materialised file should contain the exact shared bytes');

    // 图片必须以真正的 image/* 交给接收方，否则会被当成「文件」打开。
    expect((args['mimeTypes'] as List<Object?>).single, 'image/png');
  });

  test('shareFiles shares every provided path', () async {
    final p1 = '${tempDir.path}/page1.jpg';
    final p2 = '${tempDir.path}/page2.jpg';
    File(p1).writeAsBytesSync([9, 9, 9]);
    File(p2).writeAsBytesSync([8, 8, 8]);

    await Share.shareFiles(paths: [p1, p2]);

    expect(calls, hasLength(1));
    final args = calls.first.arguments as Map<Object?, Object?>;
    final paths = (args['paths'] as List<Object?>).cast<String>();
    expect(paths, hasLength(2), reason: 'both files should reach the platform');
    expect(paths.map((p) => p.split('/').last), containsAll(['page1.jpg', 'page2.jpg']));
    expect(File(paths[0]).readAsBytesSync(), [9, 9, 9]);
    expect(File(paths[1]).readAsBytesSync(), [8, 8, 8]);
  });
}
