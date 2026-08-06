import 'package:flutter/material.dart';
import 'package:kong_comic/design_tokens.dart';

/// 全站统一的语义色角标。
/// 用法：AppBadge("New Version", type: AppBadgeType.warning)
enum AppBadgeType { info, warning, success, neutral }

class AppBadge extends StatelessWidget {
  final String text;
  final AppBadgeType type;
  final double fontSize;
  final EdgeInsetsGeometry? padding;

  /// 可选的自定义底色/字色，优先级高于 [type]。
  /// 用于需要按业务维度（如漫画源）区分颜色的场景。
  final Color? backgroundColor;
  final Color? foregroundColor;

  const AppBadge(
    this.text, {
    super.key,
    this.type = AppBadgeType.neutral,
    this.fontSize = 13,
    this.padding,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    late final Color bg;
    late final Color fg;
    if (backgroundColor != null) {
      bg = backgroundColor!;
      fg = foregroundColor ?? kcTagTextColor(bg);
    } else {
      switch (type) {
        case AppBadgeType.info:
          bg = cs.primaryContainer;
          fg = cs.onPrimaryContainer;
        case AppBadgeType.warning:
          bg = cs.errorContainer;
          fg = cs.onErrorContainer;
        case AppBadgeType.success:
          bg = cs.tertiaryContainer;
          fg = cs.onTertiaryContainer;
        case AppBadgeType.neutral:
          bg = cs.surfaceContainer;
          fg = cs.onSurfaceVariant;
      }
    }
    return Container(
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(kcRadius8)),
      child: Text(text, style: TextStyle(fontSize: fontSize, color: fg)),
    );
  }
}
