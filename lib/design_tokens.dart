import 'package:flutter/material.dart';

/// KongComic 设计令牌 —— 统一卡片圆角 / 描边 / 阴影 / 字号阶梯，消灭魔法数字。
///
/// 配套文档：design/kongcomic-design/kongcomic-ui-improvement-proposal.md
/// 约束：主页英雄卡片外观保持不变，这里只把散落的硬编码值收口到令牌。

// ── 圆角 ───────────────────────────────────────────────
const double kcCardRadius = 12; // 漫画卡 / 英雄卡 外圆角
const double kcCardInnerRadius = 10; // 卡内裁剪圆角
const double kcPillRadius = 999; // 胶囊 / 底栏激活态
const double kcChipRadius = 10; // 文件夹 chip / 标签

// ── 字号阶梯（对齐用户习惯，杜绝 18/20 混用）─────────────
const double kcTitleMain = 18; // 全局根页主标题（粗体）
const double kcTitleLarge = 20; // 页面级标题（如内部栏）
const double kcSubtitle = 16;
const double kcBody = 14;
const double kcCaption = 12;

// ── 层级阴影（取代各处长硬编码 black α）─────────────────
/// 统一卡片阴影：亮色用浅黑、暗色用浅白，保证暗色下投影逻辑一致。
BoxShadow kcCardShadow(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxShadow(
    color: (isDark ? Colors.white : Colors.black)
        .withValues(alpha: isDark ? 0.16 : 0.10),
    blurRadius: 8,
    offset: const Offset(0, 2),
  );
}

// ── 减弱动效 ───────────────────────────────────────────
/// 系统“减弱动效”开启时返回 true，调用方应将 >150ms 的转场降级为瞬切。
bool kcReduceMotion(BuildContext context) =>
    MediaQuery.of(context).disableAnimations;

// ── 间距（精确值令牌，覆盖散落字面量，零视觉改动）──────
const double kcSpaceXs = 4;
const double kcSpaceXxs = 6;
const double kcSpaceSm = 8;
const double kcSpaceMd = 12;
const double kcSpaceLg = 16;

// ── 圆角（精确值令牌，覆盖散落字面量，零视觉改动）──────
const double kcRadius3 = 3;
const double kcRadius4 = 4;
const double kcRadius6 = 6;
const double kcRadius8 = 8;
const double kcRadius10 = 10;
const double kcRadius11 = 11;
const double kcRadius16 = 16;
const double kcRadius18 = 18;
const double kcRadius20 = 20;
const double kcRadius22 = 22;
const double kcRadius24 = 24;
const double kcRadius32 = 32;

// ── 字号（精确值令牌，覆盖散落字面量，零视觉改动）──────
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

/// 根据主题亮度与 AMOLED 开关返回对应 palette 中的颜色。
///
/// AMOLED 模式下强制使用单一中性灰，呼应「纯黑外观去掉所有主题色、统一灰暗度」的要求。
Color kcTagColor(int index, Brightness brightness, {bool amoled = false}) {
  if (amoled && brightness == Brightness.dark) {
    return kcTagAmoledGray;
  }
  final palette = brightness == Brightness.dark ? kcTagPaletteDark : kcTagPaletteLight;
  return palette[index % palette.length];
}

/// 把任意颜色柔化成暗色主题用的低饱和版本。
///
/// 用于默认暗色模式下降低主题色亮度/饱和度，使其不那么刺眼。
Color kcSoftenColorForDark(Color color, {double saturationFactor = 0.85, double lightnessFactor = 0.96}) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withSaturation((hsl.saturation * saturationFactor).clamp(0.0, 1.0))
      .withLightness((hsl.lightness * lightnessFactor).clamp(0.0, 1.0))
      .toColor();
}

/// 把任意颜色转为「暗彩」风格：大幅提高饱和度、明显压低亮度，
/// 让暗色模式下的主题色比浅色更深、更艳，避免发灰发浅。
/// 按钮/标签等 accent 在深色底上保持足够对比，但不再像浅色那样泛白。
Color kcDarkColorful(Color color,
    {double saturationFactor = 1.45, double lightnessFactor = 0.62}) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withSaturation((hsl.saturation * saturationFactor).clamp(0.0, 1.0))
      .withLightness((hsl.lightness * lightnessFactor).clamp(0.0, 1.0))
      .toColor();
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

/// 基于「浅色 vivid 配色」生成「暗彩」配色。
///
/// 这是修正暗彩饱和度问题的核心：FlexTones.vivid 在暗色下会把 primary 映射到
/// tone 80（浅色），导致暗彩 accent 与浅色饱和度几乎一致、且偏浅（截图里按钮
/// 仍是浅蓝）。这里先拿到同一套种子在浅色下的 vivid 结果，再把它逐个 accent
/// 经 [kcDarkColorful] 加深、加饱和后覆盖到暗色彩色方案上，从而确保暗彩明显比
/// 浅色更深、更艳，而文字色按亮度自动取黑/白，对比可读。
///
/// [light] 为同一套种子在浅色下的 vivid ColorScheme；[darkBase] 为暗色 vivid
/// ColorScheme（仅取它的表面/中性色与容器色，accent 被覆盖）。
ColorScheme kcDarkColorfulFromLight(
  ColorScheme light,
  ColorScheme darkBase, {
  double saturationFactor = 1.25,
  double lightnessFactor = 0.8,
}) {
  Color dc(Color c) => kcDarkColorful(
        c,
        saturationFactor: saturationFactor,
        lightnessFactor: lightnessFactor,
      );
  final p = dc(light.primary);
  final s = dc(light.secondary);
  final t = dc(light.tertiary);
  return darkBase.copyWith(
    primary: p,
    onPrimary: kcOnColor(p),
    secondary: s,
    onSecondary: kcOnColor(s),
    tertiary: t,
    onTertiary: kcOnColor(t),
  );
}
