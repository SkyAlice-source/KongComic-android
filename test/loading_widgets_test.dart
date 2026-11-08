import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kong_comic/components/components.dart';

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
}
