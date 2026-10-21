import 'package:flutter/material.dart';

import 'package:kong_comic/design_tokens.dart';

/// 统一卡片：M3 `Card` 的 token 化封装。
///
/// 目标（P2-5）：全站散落的 M3 `Card` 各自吃主题默认值（radius / elevation /
/// color 随主题漂移），与「kcCardRadius + kcCardShadow」的卡片语言不统一。
/// 本件把所有卡片路由到同一入口，半径恒走 [kcCardRadius]，并让描边 / 阴影成为
/// 显式开关，消灭「两套卡片语言」。
///
/// 默认参数刻意与 M3 `Card` 等价（surfaceContainerLow + 主题默认 elevation +
/// 半径 12），所以 `Card` → `KcCard` 是**视觉零落差**的 drop-in；
/// 后续要统一描边/阴影时，只改本件一处即可全站生效，不必回扫每个调用点。
class KcCard extends StatelessWidget {
  const KcCard({
    super.key,
    this.child,
    this.margin,
    this.padding,
    this.radius = kcCardRadius,
    this.color,
    this.elevation,
    this.shadowColor,
    this.shape,
    this.clipBehavior = Clip.none,
    this.border = false,
  });

  final Widget? child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color? color;
  final double? elevation;
  final Color? shadowColor;
  final ShapeBorder? shape;
  final Clip clipBehavior;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveShape =
        shape ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: border ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
        );
    final card = Card(
      margin: margin,
      elevation: elevation,
      color: color,
      shadowColor: shadowColor,
      shape: effectiveShape,
      clipBehavior: clipBehavior,
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    return card;
  }
}
