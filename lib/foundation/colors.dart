import 'package:flutter/material.dart';
import 'package:kong_comic/utils/tags_translation.dart';

/// 搜索页/标签翻译中各 [TranslationType] 的稳定配色。
///
/// 抽自原 `search_page.dart` 与 `settings/search_page.dart` 中重复定义的两份映射，
/// 统一在此维护，避免“改一处漏一处”。
const Map<TranslationType, Color> translationTypeColors = {
  TranslationType.female: Color(0xFFE91E63),
  TranslationType.male: Color(0xFF2196F3),
  TranslationType.parody: Color(0xFF9C27B0),
  TranslationType.character: Color(0xFFFF9800),
  TranslationType.artist: Color(0xFF4CAF50),
  TranslationType.group: Color(0xFF00BCD4),
  TranslationType.cosplayer: Color(0xFFFF5722),
  TranslationType.language: Color(0xFF607D8B),
  TranslationType.mixed: Color(0xFF795548),
};

/// 返回翻译类型对应的配色；未命中（如 [TranslationType.other] / [TranslationType.reclass]）
/// 时回退到主题感知的 [ColorScheme.onSurfaceVariant]。
///
/// 固定配色会按 [ColorScheme.brightness] 自适应（暗色模式下提亮），
/// 避免中等明度的固定色在暗色表面上作为前景时对比度不足。
Color translationTypeColor(TranslationType type, ColorScheme cs) {
  final fixed = translationTypeColors[type];
  return fixed == null ? cs.onSurfaceVariant : adaptAccent(fixed, cs.brightness);
}

/// 多来源匹配时为各漫画源分配的稳定强调色。
///
/// 抽自原 `search_page.dart` 内重复定义的两处列表。
const List<Color> sourceColors = [
  Color(0xFF534AB7),
  Color(0xFF0F6E56),
  Color(0xFFD85A30),
  Color(0xFF185FA5),
  Color(0xFF993556),
];

/// 将固定强调色适配到指定亮度。
///
/// 这些调色板颜色是为亮色表面设计的；在暗色模式下作为前景（文字/图标）时，
/// 深色基调（如深绿 [0xFF0F6E56]、深蓝 [0xFF185FA5]）会远低于 WCAG AA 对比度。
/// 暗色模式下向白色混合提亮，保证在暗色表面上可读；亮色模式原样返回。
Color adaptAccent(Color color, Brightness brightness) =>
    brightness == Brightness.dark
        ? Color.lerp(color, Colors.white, 0.45)!
        : color;

/// 多来源强调色（亮度感知）。用作前景色时使用此函数而非直接取 [sourceColors]。
Color sourceColor(int index, Brightness brightness) =>
    adaptAccent(sourceColors[index % sourceColors.length], brightness);
