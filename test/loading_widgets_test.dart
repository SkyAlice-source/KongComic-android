import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/utils/translations.dart';

// 加载态组件的「数据诚实性」测试。
//
// 这里关心的不是像素细节，而是两件容易在重构中丢掉的事：
// 1. 有真实字节进度时，百分比必须和 value 一致（0.42 → 42%），
//    且 100% 不能把三位数挤出横条宽度；
// 2. 拿不到总字节时**不能编一个数字**（曾经的做法是显示 0%），
//    必须退回不确定态。
void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('有进度时百分比跟着 value 走', (tester) async {
    await tester.pumpWidget(host(const KcTrackProgress(value: 0.42)));
    expect(find.text('42%'), findsOneWidget);

    await tester.pumpWidget(host(const KcTrackProgress(value: 0.07)));
    expect(find.text('7%'), findsOneWidget);

    await tester.pumpWidget(host(const KcTrackProgress(value: 1)));
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('没有总字节时不显示任何百分比', (tester) async {
    await tester.pumpWidget(host(const KcTrackProgress()));
    await tester.pump();
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('value 越界会夹到 0..1，不会画到条外面', (tester) async {
    await tester.pumpWidget(host(const KcTrackProgress(value: 1.8)));
    expect(find.text('100%'), findsOneWidget);

    await tester.pumpWidget(host(const KcTrackProgress(value: -0.4)));
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('可以关掉数字，只留横条', (tester) async {
    await tester.pumpWidget(
      host(const KcTrackProgress(value: 0.5, showPercent: false)),
    );
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('行内 spinner 的尺寸就是传进去的直径', (tester) async {
    for (final size in <double>[12, 16, 20]) {
      await tester.pumpWidget(host(KcInlineSpinner(size: size)));
      expect(tester.getSize(find.byType(KcInlineSpinner)), Size.square(size));
    }
  });

  // 详情页这类「带着作品名进来」的页面，加载失败后顶栏不能只剩一颗返回箭头：
  // 用户会以为自己被丢到了另一个页面，也读不出「哪一部失败了」。
  testWidgets('错误页把传入的标题渲染到顶栏', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkError(
          message: 'Network Error',
          retry: () {},
          title: 'Sousou no Frieren',
        ),
      ),
    );
    expect(find.text('Sousou no Frieren'), findsOneWidget);
  });

  testWidgets('不传标题时顶栏仍是空串，不显示占位文案', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: NetworkError(message: 'Network Error')),
    );
    expect(find.text(''), findsOneWidget);
    expect(find.text('Network Error'), findsOneWidget);
  });

  // 分类是「友好错误页」的地基：判错了，给出的下一步建议就会南辕北辙。
  test('错误分类覆盖离线 / 拦截 / 验证 / 脚本 / 登录 / 未知', () {
    expect(
      classifyErrorMessage('DioException [unknown]: null', 'Network Error'),
      KcErrorKind.network,
    );
    expect(
      classifyErrorMessage('403 Forbidden', '请求被源站拦截：可能是 Cloudflare 验证'),
      KcErrorKind.blocked,
    );
    expect(
      classifyErrorMessage('CloudflareException: challenge', '需要验证'),
      KcErrorKind.verification,
    );
    expect(
      classifyErrorMessage('ReferenceError: x is not defined', '该源的脚本出错了'),
      KcErrorKind.source,
    );
    expect(classifyErrorMessage('Not login', '需登录'), KcErrorKind.auth);
    expect(classifyErrorMessage('HTTP 502', '这是服务器端错误，请稍后重试'), KcErrorKind.server);
    expect(classifyErrorMessage('404 Not found', '未找到。'), KcErrorKind.notFound);
    expect(classifyErrorMessage('', '未知错误'), KcErrorKind.unknown);
  });

  // 断网时不再落「未知错误」：原文要能被归一化成网络类文案。
  test('DioException [unknown]: null 归一化为网络错误', () {
    expect(friendlyErrorMessage('DioException [unknown]: null'), 'Network Error');
    expect(
      friendlyErrorMessage('SocketException: Network is unreachable, errno = 101'),
      'Network Error',
    );
  });

  testWidgets('错误页默认收起技术细节，展开后才出现日志入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkError(message: 'DioException [unknown]: null', retry: () {}),
      ),
    );
    // 分类标题与「下一步」建议都在；开发者向的原文 / 导出日志先藏起来。
    expect(find.text("Can't connect to the network"), findsOneWidget);
    expect(
      find.text('Check Wi-Fi or mobile data, or try another line, then retry.'),
      findsOneWidget,
    );
    expect(find.byType(SelectableText), findsNothing);
    expect(find.text('Export logs'), findsNothing);

    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('Technical details'), findsOneWidget);
    expect(find.text('Export logs'), findsOneWidget);

    await tester.tap(find.text('Hide details'));
    await tester.pumpAndSettle();
    expect(find.text('Export logs'), findsNothing);
  });

  // 分类标题/建议必须真的画到界面上，而不只是分类函数返回正确值。
  testWidgets('不同类别显示各自的标题与下一步建议', (tester) async {
    const cases = <(String, String, String)>[
      (
        '403 Forbidden',
        'Access blocked by the source',
        'Switch networks or lines, or wait a while before retrying.',
      ),
      (
        'ReferenceError: x is not defined',
        'This source needs an update',
        'Update this source in Comic Sources; if the site has changed, remove it.',
      ),
      ('Not login', 'Sign-in needed', 'Log in to this source, then try again.'),
    ];
    for (final (message, title, suggestion) in cases) {
      await tester.pumpWidget(
        MaterialApp(home: NetworkError(message: message, retry: () {})),
      );
      expect(find.text(title), findsOneWidget, reason: message);
      expect(find.textContaining(suggestion), findsWidgets, reason: message);
    }
  });

  testWidgets('Cloudflare 挑战给出验证按钮而不是普通重试', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkError(
          message: 'CloudflareException: https://example.com/chapter',
          retry: () {},
        ),
      ),
    );
    expect(find.text('Verification needed'), findsOneWidget);
    expect(find.text('Verify'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  // 有些调用点把错误页塞在 Column / ScrollView 里，maxHeight 是 infinity；
  // 拿它直接当 minHeight 会触发 BoxConstraints 断言。
  testWidgets('嵌在无界高度的滚动容器里不崩', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NetworkError(message: 'Network Error', withAppbar: false),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(NetworkError), findsOneWidget);
  });
}
