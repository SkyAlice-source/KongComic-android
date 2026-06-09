part of 'components.dart';

/// iOS 18 风格毛玻璃容器
/// 使用 BackdropFilter + 半透明背景实现毛玻璃效果
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blurStrength;
  final double opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final Color? tintColor;
  final AlignmentGeometry? alignment;
  final Clip clipBehavior;

  const GlassContainer({
    super.key,
    required this.child,
    this.blurStrength = 20,
    this.opacity = 0.15,
    this.borderRadius,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.constraints,
    this.border,
    this.boxShadow,
    this.tintColor,
    this.alignment,
    this.clipBehavior = Clip.antiAlias,
  });

  /// 浅色模式下的玻璃颜色（白玻）
  static Color lightGlassColor(double opacity) =>
      Colors.white.withValues(alpha: opacity);

  /// 深色模式下的玻璃颜色（深灰玻）
  static Color darkGlassColor(double opacity) =>
      Colors.grey.shade900.withValues(alpha: opacity * 0.7);

  /// 根据 brightness 获取玻璃背景色
  static Color glassColor(BuildContext context, double opacity) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.light
        ? lightGlassColor(opacity)
        : darkGlassColor(opacity);
  }

  /// 获取默认的 iOS 风格边框
  static Border iosBorder(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Border.all(
      color: brightness == Brightness.light
          ? Colors.white.withValues(alpha: 0.5)
          : Colors.white.withValues(alpha: 0.08),
      width: 0.5,
    );
  }

  /// 获取默认的玻璃阴影
  static List<BoxShadow> defaultShadow(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return [
      BoxShadow(
        color: brightness == Brightness.light
            ? Colors.black.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.3),
        blurRadius: 12,
        offset: const Offset(0, 2),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(16);
    final effectiveBorder = border ?? iosBorder(context);
    final effectiveShadow = boxShadow ?? defaultShadow(context);
    final effectiveTint = tintColor;

    Widget glassChild = ClipRRect(
      borderRadius: effectiveBorderRadius,
      clipBehavior: clipBehavior,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: blurStrength,
          sigmaY: blurStrength,
          tileMode: ui.TileMode.mirror,
        ),
        child: Container(
          width: width,
          height: height,
          constraints: constraints,
          padding: padding,
          decoration: BoxDecoration(
            color: glassColor(context, opacity),
            borderRadius: effectiveBorderRadius,
            border: effectiveBorder,
            boxShadow: effectiveShadow,
            gradient: effectiveTint != null
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      effectiveTint.withValues(alpha: 0.05),
                      effectiveTint.withValues(alpha: 0.0),
                    ],
                  )
                : null,
          ),
          alignment: alignment,
          child: child,
        ),
      ),
    );

    if (margin != null) {
      glassChild = Padding(padding: margin!, child: glassChild);
    }

    return glassChild;
  }
}

/// iOS 18 风格的毛玻璃导航栏（底部 TabBar）
class GlassBottomBar extends StatelessWidget {
  final List<Widget> children;
  final double height;

  const GlassBottomBar({
    super.key,
    required this.children,
    this.height = 58,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return GlassContainer(
      blurStrength: 25,
      opacity: 0.20,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
      border: Border(
        top: BorderSide(
          color: Theme.of(context).brightness == Brightness.light
              ? Colors.white.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, -2),
        ),
      ],
      padding: EdgeInsets.only(bottom: bottomPadding),
      width: double.infinity,
      height: height + bottomPadding,
      child: Row(
        children: children,
      ),
    );
  }
}

/// iOS 18 风格的毛玻璃侧边栏
class GlassSideBar extends StatelessWidget {
  final Widget child;
  final double width;

  const GlassSideBar({
    super.key,
    required this.child,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      blurStrength: 25,
      opacity: 0.18,
      borderRadius: BorderRadius.zero,
      border: Border(
        right: BorderSide(
          color: Theme.of(context).brightness == Brightness.light
              ? Colors.white.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(1, 0),
        ),
      ],
      width: width,
      height: double.infinity,
      child: child,
    );
  }
}

/// iOS 18 风格毛玻璃卡片
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final double blurStrength;
  final double opacity;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.onTap,
    this.blurStrength = 18,
    this.opacity = 0.12,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(12);

    Widget card = GlassContainer(
      blurStrength: blurStrength,
      opacity: opacity,
      borderRadius: effectiveBorderRadius,
      border: GlassContainer.iosBorder(context),
      boxShadow: GlassContainer.defaultShadow(context),
      padding: padding ?? const EdgeInsets.all(0),
      child: onTap != null
          ? InkWell(
              borderRadius: effectiveBorderRadius,
              onTap: onTap,
              child: child,
            )
          : child,
    );

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }

    return card;
  }
}

/// iOS 18 风格毛玻璃 AppBar 包装器
/// 用于替换原有的 AppBar 背景
class GlassAppBarWrapper extends StatelessWidget {
  final Widget child;
  final double blurStrength;
  final bool scrolledUnder;

  const GlassAppBarWrapper({
    super.key,
    required this.child,
    this.blurStrength = 22,
    this.scrolledUnder = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOpacity = scrolledUnder ? 0.20 : 0.12;
    return GlassContainer(
      blurStrength: blurStrength,
      opacity: effectiveOpacity,
      borderRadius: BorderRadius.zero,
      border: Border(
        bottom: BorderSide(
          color: scrolledUnder
              ? (Theme.of(context).brightness == Brightness.light
                  ? Colors.white.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.08))
              : Colors.transparent,
          width: 0.5,
        ),
      ),
      boxShadow: scrolledUnder
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ]
          : [],
      width: double.infinity,
      child: child,
    );
  }
}
