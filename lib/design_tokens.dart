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
const List<Color> kcTagPaletteDark = [
  Color(0xFF1E40AF), // 深蓝
  Color(0xFF9D174D), // 深粉
  Color(0xFF166534), // 深绿
  Color(0xFF9A3412), // 深橙
  Color(0xFF7E22CE), // 深紫
  Color(0xFF0E7490), // 深青
  Color(0xFF9F1239), // 深玫瑰
  Color(0xFF3F6212), // 深橄榄
  Color(0xFFA16207), // 深金黄
  Color(0xFF581C87), // 暗紫
  Color(0xFF115E59), // 深青绿
  Color(0xFF991B1B), // 深暖红
];

/// AMOLED/纯黑模式下所有标签统一的单一中性灰底。
///
/// 用单一灰而非多档灰阶，呼应「纯黑外观统一灰暗度、去掉所有主题色」的要求，
/// 避免按哈希取色导致的深浅不一。
const Color kcTagAmoledGray = Color(0xFF242424);

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

/// 根据 chip 背景亮度自动选黑/白文字，保证 WCAG 对比度。
Color kcTagTextColor(Color background) {
  return background.computeLuminance() > 0.5
      ? Colors.black.withValues(alpha: 0.87)
      : Colors.white.withValues(alpha: 0.95);
}
