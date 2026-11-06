import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'foundation/appdata.dart';

/// KongComic 设计令牌 —— 统一卡片圆角 / 描边 / 阴影 / 字号阶梯，消灭魔法数字。
///
/// **本文件是设计令牌的唯一事实来源（single source of truth）。**
/// 历史上曾存在 `lib/foundation/design_tokens.dart`（`AppRadii` / `AppSpacing`
/// 体系），与本文档语义重叠且全库 0 引用，已于 v1.5.2 删除。任何新增令牌
/// 必须放在这里；不要再引入第二套命名体系。CI（`tools/check_tokens.py`）会断言
/// `AppRadii|AppSpacing` 不得再次出现。
///
/// 约束：主页英雄卡片外观保持不变，这里只把散落的硬编码值收口到令牌。

// ── 品牌色 ───────────────────────────────────────────────
/// 品牌主色 Kong Coral，用于收藏红心、收藏角标等强调色。
const Color kcBrandColor = Color(0xFFD4381B);

/// 三套外观的实际底色 / 前景色（唯一事实来源）。
///
/// `main.dart` 的 getTheme 与设置页的外观预览卡曾各自硬抄一份，改主题时
/// 「预览卡是 A 色、真实界面是 B 色」；现在两处都只引用这三个常量。
const Color kcDarkBackground = Color(0xFF100D0F);
const Color kcAmoledBackground = Color(0xFF0A0A0A);
const Color kcDarkForeground = Color(0xFFEDEAEB);

/// 可选主题色板：key 与 `settings['color']` 一一对应，值为 (primary, secondary)。
///
/// **唯一事实来源**：`main.dart` 用它生成 ColorScheme，设置页用它画色点。
/// 以前色值只写在 `translateColorSetting()` 里，设置页要显示色点就得再抄一份，
/// 抄错一个色值就会出现「点的是紫、界面是蓝」。
///
/// 顺序即设置页的展示顺序；`system`（= 品牌红）放在首位当默认项。
const Map<String, (Color, Color)> kcThemePalettes = {
  // 默认项不跟壁纸动态取色，直接落品牌红 + 同族珊瑚红。
  'system': (kcBrandColor, kcBrandColorOnDark),
  // 高饱和珊瑚红 + 鲜天蓝
  'red': (Color(0xFFFF453A), Color(0xFF0EA5E9)),
  // 高饱和玫红 + 电光紫
  'pink': (Color(0xFFFF2D55), Color(0xFF8B5CF6)),
  // 高饱和紫 + 鲜橙
  'purple': (Color(0xFFBF5AF2), Color(0xFFFF9F0A)),
  // 高饱和草绿 + 鲜橙
  'green': (Color(0xFF30D158), Color(0xFFFF9F0A)),
  // 高饱和蓝 + 鲜橙
  'blue': (Color(0xFF0A84FF), Color(0xFFFF9F0A)),
  // 高饱和黄 + 鲜天蓝
  'yellow': (Color(0xFFFFD60A), Color(0xFF0EA5E9)),
  // 高饱和青 + 电光紫
  'cyan': (Color(0xFF5AC8FA), Color(0xFF8B5CF6)),
};

/// 当前是否为 **AMOLED 纯黑外观**。
///
/// 只有 `theme_mode == 'amoled'` 才算；「深色」与「跟随系统（系统为暗色）」都走
/// 带品牌红的深色方案。AMOLED 是唯一「零彩色、只用灰阶」的外观。
bool kcIsAmoled() => appdata.isAmoledMode;

/// 「主 CTA / 当前项 / 开关 ON」的强调色。
///
/// - **浅色 / 深色**：品牌红 [kcBrandColor]，与收藏红心同源，是全站唯一强调色。
///   深色下红压在暖近黑底上更「沉」，不需要另一套色值。
/// - **AMOLED**：退化为中性灰 [ColorScheme.surfaceContainerHigh]。纯黑外观要求
///   「零彩色」——纯灰底上不能冒出一颗红，用「深灰浮起 + 白字」表达选中 / 激活。
///
/// ⚠️ 只用于**面与线**（实心按钮底、选中项描边、开关轨道、进度填充）。
///   图标 / 文字类品牌标记（收藏心、选中勾、动作栏图标）请用 [kcBrandAdaptive]，
///   AMOLED 下会同步走中性灰而不破坏「零彩色」。
Color kcAccentColor(BuildContext context) {
  if (kcIsAmoled()) return Theme.of(context).colorScheme.surfaceContainerHigh;
  return kcBrandColor;
}

/// 品牌色标记（收藏心、选中勾、动作栏图标这类图标 / 小色块）。
///
/// 浅色与深色恒为品牌红；AMOLED 下取主题 `primary`（亮灰），让标记在纯灰底上
/// 以「高亮灰」呈现，而不是冒出一颗红。面与线请走 [kcAccentColor]。
Color kcBrandAdaptive(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return kcIsAmoled() ? cs.primary : kcBrandColor;
}

/// 状态语义色（可达绿 / 超时黄）：集中到这里，AMOLED「零彩色」下退化为
/// 中性灰，靠文案与底色深浅区分；深色主题再向白提亮一档保证小字对比度。
/// 组件层不要自己写 `Color(0xFF2FA45A)` / `Color(0xFFD9A005)`。
Color kcStatusColor(BuildContext context, {required bool ok}) {
  final cs = Theme.of(context).colorScheme;
  if (kcIsAmoled()) return cs.onSurfaceVariant;
  final base = ok ? const Color(0xFF2FA45A) : const Color(0xFFD9A005);
  return cs.brightness == Brightness.dark
      ? Color.lerp(base, Colors.white, 0.18)!
      : base;
}

/// 品牌红之上的前景色（按钮文字 / 图标 / 选中态文字）。
///
/// 不能复用 `cs.onPrimary`：AMOLED 下 `primary` 是浅灰、`onPrimary` 是黑，
/// 配红底只有 4.3:1 且观感发脏。红底上的白字对比度 4.8:1，是唯一正确解。
const Color kcOnAccentColor = Colors.white;

/// 暗底上的品牌色**前景**（小字号文字 / 小图标）。
///
/// 比 [kcBrandColor] 提亮一档（#E4553A），纯黑底上对比度 5.3:1，过 AA；
/// 直接拿 #D4381B 写 12–13sp 小字在 AMOLED 下会发闷。
const Color kcBrandColorOnDark = Color(0xFFE4553A);

/// 强调色的「柔光底」：极低透明度叠在低对比容器上，用于「当前章节 / 上次阅读」
/// 这类需要点出焦点、又不能整块高饱和的卡片。
///
/// - 浅色 / 深色：品牌红薄染（深色底更暗，同透明度就够用）。
/// - AMOLED：中性灰（[ColorScheme.onSurface]）薄染，保持零彩色。
Color kcAccentSurface(BuildContext context, {double alpha = 0.10}) {
  final cs = Theme.of(context).colorScheme;
  final gray = kcIsAmoled();
  final tint = gray ? cs.onSurface : kcBrandColor;
  return Color.alphaBlend(
    tint.withValues(alpha: gray ? alpha * 0.5 : alpha),
    cs.surfaceContainerLow,
  );
}

// ── 圆角 ───────────────────────────────────────────────
const double kcCardRadius = 12; // 漫画卡 / 英雄卡 外圆角
const double kcCardInnerRadius = 10; // 卡内裁剪圆角
const double kcPillRadius = 999; // 胶囊 / 底栏激活态

/// 输入框圆角（唯一的输入框圆角来源）。
///
/// 比卡片（[kcCardRadius] 12）再圆 4dp：输入框高度只有 48dp 左右，同样的
/// 圆角值在小控件上看起来会更「方」；16 让它在视觉圆润度和卡片的 12 对齐，
/// 同时贴近 Material 3 Expressive 的「大圆角」手感，但还没到胶囊（999）。
/// 设置页、漫画源、仓库页、各类输入弹窗全部走这一个值。
const double kcFieldRadius = 16;

// ── 字号阶梯（对齐用户习惯，杜绝 18/20 混用）─────────────
const double kcTitleMain = 20; // 全局根页主标题（粗体）
/// 顶栏标题（自绘 Appbar / SliverAppbar / 阅读器里的系统 AppBar）。
///
/// 与根页主标题同为 20：内页顶栏若沿用 [kcTitleLarge](22)，进二级页时标题
/// 反而比根页「收藏 / 历史」更大，层级倒挂。两者取同一档，进出页面只变位置
/// 不变字号，视觉更稳。
const double kcAppbarTitle = 20;
const double kcTitleLarge = 22; // 内容区大标题（分区标题、详情页漫画名等）
/// 二级 / 分组标题（收藏页的文件夹选择器「全部」、分组名等）。
///
/// 必须显式指定：`Appbar`/`SliverAppbar` 会把 title 包进
/// `fontSize: kcAppbarTitle(20)` 的 DefaultTextStyle，二级标题若不覆盖就会
/// 与根页主标题（kcTitleMain 20）同大甚至更大，层级倒挂。
const double kcSectionTitle = 17;
const double kcSubtitle = 16;
const double kcBody = 14;
const double kcCaption = 12;

/// 排版令牌补充说明（**旧字号表已冻结，见下**）：
/// - 项目里另有 `AppFontSizes.sNN`（foundation/text_styles.dart）与 `ts.sNN` 简写，
///   是更早的一套字号表，值与上面阶梯大量重叠（s14=kcBody、s12=kcCaption、
///   s22=kcTitleLarge …）。
/// - **冻结规则（2026-10-18 起执行）**：新增或修改样式只能用上面的 kc* 语义阶梯；
///   `ts.sNN` / `AppFontSizes.sNN` / 裸数字 `fontSize:` 只减不增。
///   门禁脚本：`python3 tools/check_font_sizes.py`（超基线即失败，发版前跑一遍）。
///   迁移顺序：comic.dart → reader → settings，一页一改、改完截图回归；
///   调用点归零后再删 `widget_utils.dart` 里的 `ts` 简写表。
/// - `kcFont13`(13) 是历史遗留的「正文紧凑档」，夹在 kcBody(14) 与 kcCaption(12)
///   之间。**除下列固定高度 / 等宽容器外不得再使用**：
///   · 等宽文本（代码行号、monospace 展示的 ID）—— 14 会让等宽行宽溢出；
///   · 紧凑徽章 `AppBadge`（padding vertical: 2，14 会把徽章撑高）；
///   · 桌面端固定高度标题栏（window_frame）。
///   上述例外处已在代码内就地注明原因。新样式一律用 kcBody(14) / kcCaption(12)。

// ── 行高估算 ───────────────────────────────────────────
/// 未显式指定 `TextStyle.height` 时，中文字体（Noto Sans CJK）的实际行高倍率。
///
/// 用于「按系统字号估算固定高度容器该多高」的场景（阅读器顶栏、详情页
/// 「继续阅读」/「下载中」进度条等）：`行高 ≈ fontSize * kcLineHeightFactor`。
/// 系数由 fs2.0 实测反推（kcCaption+kcFont10 两行内容 70px ÷ 基线 44px 等），
/// 取值比实测 1.545 略高，用于覆盖不同 ROM 的字体度量差异。
const double kcLineHeightFactor = 1.55;

// ── 层级阴影（取代各处长硬编码 black α）─────────────────
/// 统一卡片阴影：亮色用浅黑、暗色用浅白，保证暗色下投影逻辑一致。
BoxShadow kcCardShadow(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxShadow(
    color: (isDark ? Colors.white : Colors.black).withValues(
      alpha: isDark ? 0.16 : 0.10,
    ),
    blurRadius: 8,
    offset: const Offset(0, 2),
  );
}

// ── 减弱动效 ───────────────────────────────────────────
/// 系统“减弱动效”开启时返回 true，调用方应将 >150ms 的转场降级为瞬切。
bool kcReduceMotion(BuildContext context) =>
    MediaQuery.of(context).disableAnimations;

// ── ColorOS 17 Contour Glow（凝光描边）─────────────────
/// 在卡片 / 选中项 / 悬浮底栏四周加一圈柔和辉光，把内容从背景轻轻托起
/// （ColorOS 17 的「Contour Glow」效果）。亮色用浅黑微光、暗色用白色微光，
/// 保证可读且省电（不做重折射）。调用方把它追加进自身 boxShadow 列表即可。
List<BoxShadow> kcContourGlow(BuildContext context, {Color? color}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final glow = color ?? (isDark ? Colors.white : Colors.black);
  // 更柔、更扩散的辉光：原来 spreadRadius:-8 把光勒成一圈贴边硬边，
  // 在卡片四周长得像塑料描边。改为更大模糊 + 较小收缩，让内容像被「轻轻托起」
  // 而非裹了一圈反光边（更贴近真实磨砂玻璃的漫射感，少塑料感）。
  return [
    BoxShadow(
      color: glow.withValues(alpha: isDark ? 0.10 : 0.04),
      blurRadius: 26,
      spreadRadius: -4,
      offset: Offset.zero,
    ),
  ];
}

/// ColorOS 17 风格：对话框 / 底部弹窗 / 悬浮容器的统一大圆角。
const double kcSurfaceRadius = 24;

/// 发丝描边宽度：全站胶囊 / 卡片细描边的事实标准（0.8）。
/// 收口为 token，取代散落各处的 `width: 0.8` 魔数。
const double kcHairline = 0.8;

/// 发丝描边**颜色**：明暗两端都要看得见，全站唯一来源。
///
/// 历史上深浅两套写法正好相反：深色用 `outline@0.45`（#4A4244 半透明叠在
/// #100D0F 上，有效亮度差约 2:1，边界几乎消失，深色实拍已证实），浅色反而
/// 用较淡的 `outlineVariant@0.9`。这里统一：深色改用 `onSurface` 的低透明度
/// 叠色（约 3:1，过 WCAG 1.4.11 非文本对比），浅色沿用品牌中性淡灰。
/// 注意不要直接取 `outlineVariant` —— 它从主色种子派生，选绿/蓝主题时描边
/// 会泛色；`onSurface` 是中性色，任何主题下都是纯灰。
Color kcHairlineColor(BuildContext context) =>
    kcHairlineColorFromScheme(Theme.of(context).colorScheme);

/// 同上，但直接吃构造中的 [ColorScheme]。
///
/// `main.dart` 里 PopupMenuThemeData 是在 `ThemeData(...)` 构造过程中配置，
/// 那时 `Theme.of(context)` 拿到的还是**外层**主题，不能用来判明暗；此重载
/// 让主题构造期也能复用同一份描边逻辑，避免明暗判断分叉。
Color kcHairlineColorFromScheme(ColorScheme cs) {
  if (cs.brightness == Brightness.dark) {
    return cs.onSurface.withValues(alpha: 0.38);
  }
  return cs.outline.withValues(alpha: 0.45);
}

/// 可点击目标的最小高度 / 宽度（M3 & WCAG 无障碍下限 48dp）。
///
/// 列表行按 `kcBody(14) × 1.35 + 12 × 2` 算出来只有 42.9dp，指腹落在两行
/// 交界处容易点进邻行，所以 `KcListTile` 用 `ConstrainedBox` 兜到这个下限。
const double kcMinTapTarget = 48;

// ── 间距（精确值令牌，覆盖散落字面量，零视觉改动）──────
// 命名遵循「值即名」：kcSpaceXs(4) 是最小语义档，其余用精确 dp 值命名，
// 避免早年 kcSpaceXxs=6 竟比 kcSpaceXs=4 大的反直觉坑（写新代码必点错一次）。
const double kcSpaceXs = 4;
const double kcSpace6 = 6;
const double kcSpaceSm = 8;
const double kcSpaceMd = 12;
const double kcSpaceLg = 16;
const double kcSpace18 = 18;

/// 分区头与上一块内容的竖向间距。
///
/// [kcSectionGapWide] 是既有值（收藏页两个分区头原先写死的 28dp），宽屏 /
/// 平板保持不变；手机（短边 < 600dp）收紧到 [kcSectionGapCompact]，避免
/// 360dp 竖屏里「84dp 入口卡 → 28dp 空档 → 32dp 胶囊」把首屏拉得过于松散。
/// 只改间距，不动任何卡片的形状、圆角、面色与字号。
const double kcSectionGapWide = 28;
const double kcSectionGapCompact = 20;
double kcSectionGap(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide < 600
        ? kcSectionGapCompact
        : kcSectionGapWide;

/// 根页共享顶栏（`NaviPane.buildTop`）的栏体高度，不含状态栏内边距。
///
/// 56 是 M3 / Android 标准 AppBar 高度，也是让 [kcMinTapTarget] 的 48dp
/// 工具胶囊上下各留 4dp 呼吸空间的最小值。自绘顶栏的根 tab（收藏 / 历史）
/// 必须用同一个值，否则切 tab 时标题会上下跳一下（旧值 48 时胶囊贴满栏体、
/// 圆角被挤到边缘，且按钮命中区只剩 36dp）。
const double kcRootTopBarHeight = 56;

// ── 页面外壳编排（方案 E/F：主页之外所有页面共用同一副骨架）──────
/// 内容列的最大宽度。主页早先已按 900 收敛，其余页面没有上限，
/// 平板 2560dp 时网格会被拉成 7 列、右侧留出大片空白。
/// Compact（短边 < 600dp）下由 `kcPageContentWidth` 自动退化为全宽。
const double kcContentMaxWidth = 900;

/// 按可用宽度求统一内容列宽：全宽与 [kcContentMaxWidth] 取小。
double kcPageContentWidth(double availableWidth) =>
    availableWidth < kcContentMaxWidth ? availableWidth : kcContentMaxWidth;

/// 二级页返回键图标大小。此前搜索页 / 设置页是 22、标准 Appbar 是 18、
/// 还有一处原生 `BackButton()`，三套并存。全库统一到这一档。
const double kcBackIconSize = 18;

/// 页面底部统一让位：悬浮玻璃 dock 高度 + 一段呼吸空间。
/// 原先有 `bottomBarHeight` / `padding.bottom + 80` / 仅 kcSpaceSm /
/// 仅 context.padding.bottom 四套写法，主页大字号下模块因此被压住。
const double kcPageBottomGap = 16;

// ── 圆角（精确值令牌，覆盖散落字面量，零视觉改动）──────
const double kcRadius3 = 3;
const double kcRadius4 = 4;
const double kcRadius6 = 6;
const double kcRadius8 = 8;
const double kcRadius10 = 10;
const double kcRadius16 = 16;
const double kcRadius18 = 18;
const double kcRadius20 = 20;
const double kcRadius22 = 22;
const double kcRadius24 = 24;
const double kcRadius32 = 32;

// ── 字号（精确值令牌，覆盖散落字面量，零视觉改动）──────
// 排版阶梯见上方 kcTitleMain / kcTitleLarge / kcSectionTitle / kcSubtitle /
// kcBody / kcCaption；这里是阶梯之外的历史精确值，新增样式请优先用阶梯。
// 可读性下限：正文 / 辅助信息 ≥ kcCaption(12)；图片上的徽标 ≥ kcFont11(11)。
// kcFont10(10) 已全面停用（中文在 3x 屏上仅约 3mm 高，读不清），仅保留常量防误引。
// kcFont13(13) 仅限「固定高度 / 等宽容器」例外（规则见上方排版令牌说明）。
const double kcFont10 = 10;
const double kcFont11 = 11;
const double kcFont13 = 13;
const double kcFont15 = 15;
const double kcFont22 = 22;
const double kcFont24 = 24;

// ── 标签/分类 chip 配色（亮色/暗色两套，保证对比度）────────
/// 亮色模式：提高饱和度的鲜艳糖果色底 + 深色字，彩色区分更鲜明。
const List<Color> kcTagPaletteLight = [
  Color(0xFF82B1FF), // 蓝
  Color(0xFFF06292), // 粉
  Color(0xFF81C784), // 绿
  Color(0xFFFFB74D), // 橙
  Color(0xFFBA68C8), // 紫
  Color(0xFF4DD0E1), // 青
  Color(0xFFFF8A65), // 珊瑚
  Color(0xFFAED581), // 浅绿
  Color(0xFFFFD54F), // 黄
  Color(0xFF9575CD), // 深紫
  Color(0xFF4DB6AC), // 蓝灰
  Color(0xFFE57373), // 暖红
];

/// 暗色模式：深色高饱和底 + 白色字，避免浅色 chip 在暗底上刺眼且看不清。
/// 亮度适度提高，确保「暗彩」模式下标签仍鲜艳不发灰。
const List<Color> kcTagPaletteDark = [
  Color(0xFF2563EB), // 鲜蓝
  Color(0xFFDB2777), // 鲜粉
  Color(0xFF16A34A), // 鲜绿
  Color(0xFFEA580C), // 鲜橙
  Color(0xFF9333EA), // 鲜紫
  Color(0xFF0891B2), // 鲜青
  Color(0xFFE11D48), // 鲜玫瑰
  Color(0xFF65A30D), // 鲜橄榄
  Color(0xFFD97706), // 鲜金黄
  Color(0xFF7C3AED), // 亮紫
  Color(0xFF0D9488), // 鲜青绿
  Color(0xFFDC2626), // 鲜暖红
];

/// AMOLED/纯黑模式下所有标签统一的「黑色透明感」底色。
///
/// 用半透明白叠加在纯黑底上（≈#282828），比上一版 0x1A 更深一度，
/// 让玻璃质感更明显、更有层次，同时仍保持纯黑外观统一灰暗度、去掉主题色。
/// 注意：文字色需配合 kcTagTextColor 的 alpha 感知逻辑。
const Color kcTagAmoledGray = Color(0x28FFFFFF);

/// 稳定字符串哈希（FNV-1a，跨进程/跨启动恒定）。
///
/// ⚠️ 切勿用 Dart 的 `String.hashCode` 给标签取色——它带随机种子，
/// App 每次冷启动都会变，导致同一标签（如「韩漫」）今天蓝、明天粉，
/// 各页面之间也对不上，观感混乱。这里用纯整数哈希保证任何运行都
/// 映射到同一颜色，从而让「同一标签 = 同一颜色」在全站成立。
int kcStableHash(String text) {
  var hash = 0x811c9dc5;
  for (var i = 0; i < text.length; i++) {
    hash ^= text.codeUnitAt(i);
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

/// 根据主题亮度与 AMOLED 开关返回对应 palette 中的颜色。
///
/// AMOLED 模式下强制使用单一中性灰，呼应「纯黑外观去掉所有主题色、统一灰暗度」的要求。
Color kcTagColor(int index, Brightness brightness, {bool amoled = false}) {
  if (amoled && brightness == Brightness.dark) {
    return kcTagAmoledGray;
  }
  final palette = brightness == Brightness.dark
      ? kcTagPaletteDark
      : kcTagPaletteLight;
  return palette[index % palette.length];
}

/// 根据 chip 背景亮度自动选黑/白文字，保证 WCAG 对比度。
///
/// 注意：Color.computeLuminance 会忽略 alpha，而 AMOLED 下 kcTagAmoledGray
/// 已是半透明白叠加（实际在黑底上呈暗灰）。若直接算 luminance 会误判为「白底→黑字」，
/// 导致透明白底上用黑字看不清。因此先与黑底混合得到真实呈现色，再判断。
Color kcTagTextColor(Color background) {
  final effective = Color.alphaBlend(background, Colors.black);
  return effective.computeLuminance() > 0.5
      ? Colors.black.withValues(alpha: 0.87)
      : Colors.white.withValues(alpha: 0.95);
}

/// 根据背景亮度返回可读的文字色（不透明），用于按钮等实心组件。
Color kcOnColor(Color background) {
  return background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}

// ── 弹性动效（Material 3 Expressive）─────────────────────
/// 物理弹簧曲线：把「选中 / 切换 / 进入」等过渡从线性缓动换成欠阻尼弹簧，
/// 带来轻微的回弹与活力，贴合 Material 3 Expressive 的「灵动」观感。
///
/// 通过 [transform] 把归一化进度 t∈[0,1] 映射到约 0.5s 的物理时间，
/// 用 [SpringSimulation] 解出位置（允许轻微过冲，框架会把越界值夹到可用范围）。
/// 系统开启「减弱动效」时不建议使用本曲线（由调用方改用 Duration.zero）。
class KcSpring extends Curve {
  const KcSpring({this.stiffness = 180, this.damping = 20, this.settle = 0.5});

  /// 刚度，越大回弹越快越「脆」。
  final double stiffness;

  /// 阻尼，越小回弹越明显。0.746 为欠阻尼（轻微过冲）。
  final double damping;

  /// 物理收敛时长（秒），决定曲线在 t=1 时是否已基本落定。
  final double settle;

  @override
  double transform(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    final sim = SpringSimulation(
      SpringDescription(mass: 1, stiffness: stiffness, damping: damping),
      0,
      1,
      0,
    );
    // 允许轻微过冲（负向/略大于 1），让回弹可见但不夸张。
    return sim.x(t * settle).clamp(-0.15, 1.1);
  }
}

/// 统一弹簧曲线实例：选中态 / 页面切换复用，避免各处重复构造。
const kcSpring = KcSpring();

// ── 输入框外观 ──────────────────────────────────────────
/// 输入框常态描边的「发丝线」：浅色 90%、深色 55% 的 outlineVariant。
///
/// 必须留这一条线：输入框既出现在页面底色上，也出现在对话框里，而对话框
/// 底色（surfaceContainerHigh）与填充色只差一档，没描边时整块框会「消失」，
/// 只剩一行飘着的标签。
BorderSide kcInputHairline(ColorScheme scheme, bool isDark) => BorderSide(
  color: scheme.outlineVariant.withValues(alpha: isDark ? 0.55 : 0.9),
  width: 0.8,
);

/// [kcFieldRadius] 圆角的输入框边框。
OutlineInputBorder kcInputBorder(BorderSide side) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(kcFieldRadius),
  borderSide: side,
);

/// 输入框四态边框（圆角 + 描边）的**唯一来源**。
///
/// [kcInputDecoration] 从这里取四态，所以改圆润度只需要改 [kcFieldRadius]
/// 一个值 —— 不会再出现「设置页 10dp、漫画源 10dp、登录页 4dp 直角」这种
/// 一屏三套圆角的情况。
///
/// ⚠️ 不要把它整个挂到 `ThemeData.inputDecorationTheme` 上：行内输入
/// （搜索框、评论区、代理 Host/Port、DNS 覆盖…）靠显式写
/// `border: InputBorder.none` 表示「不要边框」，而 `InputDecorator` 在
/// `enabledBorder` 为空时会回落到 **theme** 的 `enabledBorder` —— 一旦全局
/// 给了它，这些输入框会平白多出一圈圆角描边、聚焦时还冒出强调色边。
/// 全局主题只给 [kcInputDefaultBorder]（仅 `border` 一项），见 `main.dart`。
InputDecorationTheme kcInputThemeData({
  required ColorScheme scheme,
  required bool isDark,
  required Color accent,
}) {
  final hairline = kcInputHairline(scheme, isDark);
  return InputDecorationTheme(
    border: kcInputBorder(hairline),
    enabledBorder: kcInputBorder(hairline),
    focusedBorder: kcInputBorder(BorderSide(color: accent, width: 1.2)),
    errorBorder: kcInputBorder(BorderSide(color: scheme.error, width: 1)),
    focusedErrorBorder: kcInputBorder(
      BorderSide(color: scheme.error, width: 1.2),
    ),
  );
}

/// 挂在全局 `inputDecorationTheme` 上的**最小**默认：只有一条圆角发丝边框。
///
/// 只设 `border`、不设 `enabledBorder` / `focusedBorder`，原因见
/// [kcInputThemeData] 的警告。它的作用只是兜底：将来有人写了不指定边框的
/// 输入框，也自动是圆角而不是 Material 下划线。
InputDecorationTheme kcInputDefaultBorder({
  required ColorScheme scheme,
  required bool isDark,
}) {
  return InputDecorationTheme(
    border: kcInputBorder(kcInputHairline(scheme, isDark)),
  );
}

/// 全站统一的输入框装饰：**实心淡面 + [kcFieldRadius] 圆角 + 一圈发丝描边**，
/// 聚焦时描边换成强调色。
///
/// 设置页（WebDAV、关键词屏蔽弹窗）、漫画源登录、源仓库、新建收藏夹等「看得见
/// 边框」的输入框统一走这里；行内输入（设置行里铺满一行、刻意不要边框的那种，
/// 例如代理 Host / Port、DNS 覆盖）仍显式写 `border: InputBorder.none`，
/// 不要套这个装饰，否则会在行里多出一块灰色浮岛。
InputDecoration kcInputDecoration(
  BuildContext context, {
  String? labelText,
  String? hintText,
  Widget? suffixIcon,
  BoxConstraints? suffixIconConstraints,
  String? errorText,
  bool isDense = true,
  EdgeInsetsGeometry? contentPadding,
}) {
  final cs = Theme.of(context).colorScheme;
  final theme = kcInputThemeData(
    scheme: cs,
    isDark: Theme.of(context).brightness == Brightness.dark,
    accent: kcAccentColor(context),
  );

  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    hintStyle: TextStyle(
      fontSize: kcBody,
      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
    ),
    suffixIcon: suffixIcon,
    suffixIconConstraints: suffixIconConstraints,
    errorText: errorText,
    isDense: isDense,
    filled: true,
    fillColor: cs.surfaceContainerHighest,
    contentPadding:
        contentPadding ??
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: theme.border,
    enabledBorder: theme.enabledBorder,
    focusedBorder: theme.focusedBorder,
    errorBorder: theme.errorBorder,
    focusedErrorBorder: theme.focusedErrorBorder,
  );
}
