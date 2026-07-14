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
Color translationTypeColor(TranslationType type, ColorScheme cs) =>
    translationTypeColors[type] ?? cs.onSurfaceVariant;

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
