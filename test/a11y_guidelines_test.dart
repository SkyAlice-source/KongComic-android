// 无障碍回归：用 Flutter 官方 AccessibilityGuideline 在**真实语义树**上量
// 点击区、语义标签和文字对比度。
//
// 为什么需要它：tools/check_*.py 是正则棘轮，只能数「有没有写 kcMinTapTarget」，
// 量不出渲染后的实际尺寸。首次实测抓出 KcSwitch 的 TalkBack 语义节点缺标签
// （已修：新增 semanticLabel 并补齐 6 个使用点），以及孤立节点只有 52×34。
// 后者**有意保留**：它在真实页面里始终嵌在 48dp+ 的列表行 InkWell 中，若把
// 组件放大到 48dp，_KcSettingTile 的 12dp padding 会把每行从 58dp 顶到 72dp，
// 视觉代价大于收益。测试改为直接断言整行真实点击区。
//
// 口径说明：KC 组件按**真实使用组合**测（开关嵌在 KcListTile 里并带标题标签）；
// textContrastGuideline 靠采样语义节点四角像素算对比度，对「半透明胶囊 + 相邻
// 异色控件」会误报（把红底和邻行灰字配成一对），所以只在不透明纯文本场景启用。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/appdata.dart';

void main() {
  // kcIsAmoled() 读的是全局 settings；测试不改盘，只在内存里切，用完还原。
  setUp(() => appdata.settings['theme_mode'] = 'system');
  tearDown(() => appdata.settings['theme_mode'] = 'system');

  Widget host(
    Widget child, {
    Brightness brightness = Brightness.light,
    bool amoled = false,
  }) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        brightness: brightness,
        scaffoldBackgroundColor: amoled ? kcAmoledBackground : null,
      ),
      home: Scaffold(body: Center(child: child)),
    );
  }

  /// 判定对象是整棵语义树，所以只需 tester。
  /// [contrast] 仅在不透明纯文本场景开启，见文件头口径说明。
  /// [tap] 在含 `KcSwitch` 的组合里关闭：开关孤立语义节点不足 48dp，
  /// 真实点击区由整行 InkWell 提供，改用尺寸断言（见「设置行」用例）。
  Future<void> expectAccessible(
    WidgetTester tester, {
    bool tap = true,
    bool contrast = false,
  }) async {
    final handle = tester.ensureSemantics();
    try {
      if (tap) {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      }
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      if (contrast) {
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
    } finally {
      // 必须在 test body 结束前 dispose，addTearDown 太晚（框架会先校验句柄）。
      handle.dispose();
    }
  }

  group('核心组件（亮色）', () {
    testWidgets('筛选胶囊：32dp 视觉 + 48dp 命中区，选中/未选中都达标', (tester) async {
      for (final selected in <bool>[true, false]) {
        await tester.pumpWidget(host(KcPillChip(
          label: 'All',
          selected: selected,
          onTap: () {},
        )));
        await expectAccessible(tester);
      }
    });

    testWidgets('设置行：整行点击区 ≥48dp，开关有语义标签', (tester) async {
      await tester.pumpWidget(host(KcListTile(
        title: const Text('Auto Sync Data'),
        subtitle: const Text('Sync via WebDAV'),
        trailing: KcSwitch(
          value: true,
          semanticLabel: 'Auto Sync Data',
          onChanged: (_) {},
        ),
        onTap: () {},
      )));
      await expectAccessible(tester, tap: false, contrast: true);

      // 官方 guideline 逐节点检查，会判开关的 52×34 不达标；但真实可点区是
      // 整行 InkWell。这里量真实尺寸，既不放宽判定也不把设置行顶高 14dp。
      final rowRect = tester.getRect(find.byType(InkWell).first);
      expect(rowRect.height, greaterThanOrEqualTo(kcMinTapTarget));
      final switchRect = tester.getRect(find.byType(KcSwitch));
      expect(switchRect.width, 52);
      expect(switchRect.height, 34);
    });

    testWidgets('列表行（带箭头）与卡片文字', (tester) async {
      await tester.pumpWidget(host(Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KcListTile(
            title: const Text('Downloads'),
            chevron: true,
            onTap: () {},
          ),
          KcCard(
            child: const Padding(
              padding: EdgeInsets.all(kcSpaceLg),
              child: Text('Chapter 12'),
            ),
          ),
        ],
      )));
      await expectAccessible(tester);
    });

    testWidgets('KcSwitch 孤立渲染：52×34 是已知例外，标签仍可读', (tester) async {
      await tester.pumpWidget(host(KcSwitch(
        value: false,
        semanticLabel: 'Auto Sync Data',
        onChanged: (_) {},
      )));
      final handle = tester.ensureSemantics();
      try {
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      } finally {
        handle.dispose();
      }
      // 钉死视觉尺寸：谁把它放大到 48dp，本用例会红，提醒先评估设置行行高。
      final rect = tester.getRect(find.byType(KcSwitch));
      expect(rect.width, 52);
      expect(rect.height, 34);
    });

    testWidgets('原生 IconButton 作为对照基线（Flutter 默认即 48dp）', (tester) async {
      await tester.pumpWidget(host(IconButton(
        icon: const Icon(Icons.add),
        tooltip: 'Add',
        onPressed: () {},
      )));
      await expectAccessible(tester, contrast: true);
    });
  });

  group('深色 / AMOLED 零彩色', () {
    testWidgets('深色：设置行标签、对比度与整行点击区', (tester) async {
      await tester.pumpWidget(host(
        KcListTile(
          title: const Text('Dark Mode'),
          trailing: KcSwitch(
            value: true,
            semanticLabel: 'Dark Mode',
            onChanged: (_) {},
          ),
        ),
        brightness: Brightness.dark,
      ));
      await expectAccessible(tester, tap: false, contrast: true);
      final rowRect = tester.getRect(find.byType(InkWell).first);
      expect(rowRect.height, greaterThanOrEqualTo(kcMinTapTarget));
    });

    testWidgets('AMOLED：纯黑底白字对比度过 AA，且语义色退化为中性灰', (tester) async {
      appdata.settings['theme_mode'] = 'amoled';
      await tester.pumpWidget(host(
        KcCard(
          color: kcAmoledBackground,
          child: const Padding(
            padding: EdgeInsets.all(kcSpaceLg),
            child: Text(
              'Pure Black',
              style: TextStyle(fontSize: kcBody, color: kcDarkForeground),
            ),
          ),
        ),
        brightness: Brightness.dark,
        amoled: true,
      ));

      // 零彩色铁律：AMOLED 下强调色必须来自中性 surface 层级，不能是品牌红。
      final element = tester.element(find.byType(KcCard));
      expect(kcIsAmoled(), isTrue);
      expect(kcAccentColor(element), isNot(kcBrandColor));

      await expectAccessible(tester, contrast: true);
    });
  });

  group('已知例外（如实记录，不放宽门禁）', () {
    // 翻页胶囊只有 38dp 高，箭头若按 48dp 撑宽，整条胶囊会从约 150dp 胖回
    // 195dp（用户实拍「太长了」）。这里钉死紧凑尺寸：谁去掉 ToolsPillButton
    // 里的 `tapTargetSize: shrinkWrap`，本用例会红。
    testWidgets('翻页胶囊箭头：34dp 紧凑命中区，标签仍可读', (tester) async {
      await tester.pumpWidget(host(ToolsPillButton(
        icon: HugeIcons.strokeRoundedArrowLeft01,
        tooltip: 'Previous page',
        minSize: kcPagerArrowSize,
        onPressed: () {},
      )));
      final handle = tester.ensureSemantics();
      try {
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      } finally {
        handle.dispose();
      }
      final rect = tester.getRect(find.byType(ToolsPillButton));
      expect(rect.width, kcPagerArrowSize);
      expect(rect.height, kcPagerArrowSize);
    });

    // Button.icon 视觉上是 30–36dp 的小图标按钮，用在投票胶囊 / toast 关闭 /
    // Appbar actions 这类紧凑行里；直接放大到 48dp 会改变既有间距节奏。
    // 这里钉死当前尺寸：谁把它修到 48dp，本用例会红，提醒把组件并入上面的
    // 合规组并同步 DESIGN.md §12，避免文档与实现脱节。
    testWidgets('Button.icon 仍是 36dp，但语义标签与对比度合规', (tester) async {
      await tester.pumpWidget(host(Button.icon(
        icon: const Icon(Icons.settings),
        tooltip: 'Settings',
        onPressed: () {},
      )));

      final handle = tester.ensureSemantics();
      try {
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      } finally {
        handle.dispose();
      }

      final rect = tester.getRect(find.byType(GestureDetector).first);
      expect(rect.width, 36);
      expect(rect.height, 36);
    });
  });
}
