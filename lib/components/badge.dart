import 'package:flutter/material.dart';
import 'package:kong_comic/design_tokens.dart';

/// 全站统一的语义色角标。
/// 用法：AppBadge("New Version", type: AppBadgeType.warning)
enum AppBadgeType { info, warning, success, neutral }

/// 紧凑徽章：padding 只有 `vertical: 2`，高度几乎被字号决定。
///
/// 因此它是 design_tokens 里「kcFont13 例外」的**合规使用点** —— 换成 kcBody(14)
/// 会让每个徽章整体长高，与旁边的 chip / 图标基线错位。默认与调用处统一取
/// [kcFont13]，不要再往下调（≤12 在 3x 屏上偏小）。
class AppBadge extends StatelessWidget {
  final String text;
  final AppBadgeType type;
  final double fontSize;
  final EdgeInsetsGeometry? padding;

  /// 可选的自定义底色/字色，优先级高于 [type]。
  /// 用于需要按业务维度（如漫画源）区分颜色的场景。
  final Color? backgroundColor;
  final Color? foregroundColor;

  /// 圆角。默认小圆角（8）用于「标签」；需要和胶囊按钮并排时传
  /// [kcPillRadius]，避免同一行里既有方角标签又有圆角胶囊。
  final double radius;

  const AppBadge(
    this.text, {
    super.key,
    this.type = AppBadgeType.neutral,
    this.fontSize = 13,
    this.padding,
    this.backgroundColor,
    this.foregroundColor,
    this.radius = kcRadius8,
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
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: fontSize, color: fg),
      ),
    );
  }
}
