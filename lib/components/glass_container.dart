part of 'components.dart';

/// iOS 26 Liquid Glass 风格容器
/// 更高透明度 + 光线折射感 + 流动动态
class GlassContainer extends StatefulWidget {
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
  final bool enableLiquidEffect;

  const GlassContainer({
    super.key,
    required this.child,
    this.blurStrength = 35,
    this.opacity = 0.06,
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
    this.enableLiquidEffect = true,
  });

  /// 浅色 Liquid Glass 颜色
  static Color lightGlassColor(double opacity) =>
      Colors.white.withValues(alpha: opacity);

  /// 深色 Liquid Glass 颜色
  static Color darkGlassColor(double opacity) =>
      Colors.white.withValues(alpha: opacity * 0.4);

  /// 根据 brightness 获取玻璃背景色
  static Color glassColor(BuildContext context, double opacity) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.light
        ? lightGlassColor(opacity)
        : darkGlassColor(opacity);
  }

  /// iOS 26 Liquid Glass 边框 — 极细、半透明
  static Border iosBorder(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Border.all(
      color: brightness == Brightness.light
          ? Colors.white.withValues(alpha: 0.6)
          : Colors.white.withValues(alpha: 0.12),
      width: 0.4,
    );
  }

  /// Liquid Glass 阴影 — 更柔和扩散
  static List<BoxShadow> liquidShadow(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return [
      BoxShadow(
        color: brightness == Brightness.light
            ? Colors.black.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.25),
        blurRadius: 20,
        spreadRadius: -2,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: brightness == Brightness.light
            ? Colors.white.withValues(alpha: 0.3)
            : Colors.transparent,
        blurRadius: 30,
        spreadRadius: -5,
        offset: const Offset(0, -2),
      ),
    ];
  }

  @override
  State<GlassContainer> createState() => _GlassContainerState();
}

class _GlassContainerState extends State<GlassContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _liquidController;

  @override
  void initState() {
    super.initState();
    _liquidController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _liquidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = widget.borderRadius ?? BorderRadius.circular(20);
    final effectiveBorder = widget.border ?? GlassContainer.iosBorder(context);
    final effectiveShadow = widget.boxShadow ?? GlassContainer.liquidShadow(context);
    final brightness = Theme.of(context).brightness;

    Widget glassChild = ClipRRect(
      borderRadius: effectiveBorderRadius,
      clipBehavior: widget.clipBehavior,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: widget.blurStrength,
          sigmaY: widget.blurStrength,
          tileMode: ui.TileMode.mirror,
        ),
        child: _LiquidGlassSurface(
          animation: widget.enableLiquidEffect ? _liquidController : null,
          brightness: brightness,
          opacity: widget.opacity,
          tintColor: widget.tintColor,
          borderRadius: effectiveBorderRadius,
          border: effectiveBorder,
          boxShadow: effectiveShadow,
          width: widget.width,
          height: widget.height,
          constraints: widget.constraints,
          padding: widget.padding,
          alignment: widget.alignment,
          child: widget.child,
        ),
      ),
    );

    if (widget.margin != null) {
      glassChild = Padding(padding: widget.margin!, child: glassChild);
    }

    return glassChild;
  }
}

/// Liquid Glass 表面 — 包含微渐变、折射感、动画
class _LiquidGlassSurface extends AnimatedWidget {
  final Animation<double>? animation;
  final Brightness brightness;
  final double opacity;
  final Color? tintColor;
  final BorderRadius borderRadius;
  final Border border;
  final List<BoxShadow> boxShadow;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry? alignment;
  final Widget child;

  const _LiquidGlassSurface({
    required this.animation,
    required this.brightness,
    required this.opacity,
    this.tintColor,
    required this.borderRadius,
    required this.border,
    required this.boxShadow,
    this.width,
    this.height,
    this.constraints,
    this.padding,
    this.alignment,
    required this.child,
  }) : super(listenable: animation ?? const AlwaysStoppedAnimation(0.0));

  @override
  Widget build(BuildContext context) {
    final liquidValue = animation?.value ?? 0.5;
    final isLight = brightness == Brightness.light;

    // Liquid Glass 基础色
    final baseColor = isLight
        ? Colors.white.withValues(alpha: opacity)
        : Colors.white.withValues(alpha: opacity * 0.5);

    // 折射渐变 — 模拟光线经过玻璃的折射感
    final refractionColors = [
      baseColor,
      if (tintColor != null)
        tintColor!.withValues(alpha: opacity * 0.6)
      else if (isLight)
        Colors.blue.withValues(alpha: opacity * 0.3)
      else
        Colors.purple.withValues(alpha: opacity * 0.2),
      baseColor,
      if (tintColor != null)
        tintColor!.withValues(alpha: opacity * 0.3)
      else if (isLight)
        Colors.amber.withValues(alpha: opacity * 0.15)
      else
        Colors.cyan.withValues(alpha: opacity * 0.1),
      baseColor,
    ];

    // 流动偏移 — 让折射点缓慢移动，模拟液体流动
    final flowOffset = liquidValue * 0.15;

    return Container(
      width: width,
      height: height,
      constraints: constraints,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.5 + flowOffset, -0.5 + flowOffset),
          end: Alignment(0.5 + flowOffset, 0.5 + flowOffset),
          colors: refractionColors,
          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        ),
        borderRadius: borderRadius,
        border: border,
        boxShadow: boxShadow,
      ),
      alignment: alignment,
      child: child,
    );
  }
}


/// M3 Expressive 悬浮底部导航栏（pill 造型，独立浮动）
class GlassBottomBar extends StatelessWidget {
  final List<Widget> children;
  final double height;

  const GlassBottomBar({
    super.key,
    required this.children,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      blurStrength: 40,
      opacity: 0.10,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(
        color: Theme.of(context).brightness == Brightness.light
            ? Colors.white.withValues(alpha: 0.7)
            : Colors.white.withValues(alpha: 0.12),
        width: 0.3,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 16,
          spreadRadius: -1,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 6,
          spreadRadius: -2,
          offset: const Offset(0, 2),
        ),
      ],
      width: double.infinity,
      height: height,
      child: Row(
        children: children,
      ),
    );
  }
}


/// iOS 26 Liquid Glass 侧边栏
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
      blurStrength: 40,
      opacity: 0.08,
      borderRadius: BorderRadius.zero,
      border: Border(
        right: BorderSide(
          color: Theme.of(context).brightness == Brightness.light
              ? Colors.white.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.08),
          width: 0.3,
        ),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 10,
          offset: const Offset(1, 0),
        ),
      ],
      width: width,
      height: double.infinity,
      child: child,
    );
  }
}


/// iOS 26 Liquid Glass 卡片
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
    this.blurStrength = 30,
    this.opacity = 0.05,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(16);

    Widget card = GlassContainer(
      blurStrength: blurStrength,
      opacity: opacity,
      borderRadius: effectiveBorderRadius,
      border: GlassContainer.iosBorder(context),
      boxShadow: GlassContainer.liquidShadow(context),
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


/// iOS 26 Liquid Glass AppBar 包装器
class GlassAppBarWrapper extends StatelessWidget {
  final Widget child;
  final double blurStrength;
  final bool scrolledUnder;

  const GlassAppBarWrapper({
    super.key,
    required this.child,
    this.blurStrength = 35,
    this.scrolledUnder = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOpacity = scrolledUnder ? 0.10 : 0.05;
    return GlassContainer(
      blurStrength: blurStrength,
      opacity: effectiveOpacity,
      borderRadius: BorderRadius.zero,
      border: Border(
        bottom: BorderSide(
          color: scrolledUnder
              ? (Theme.of(context).brightness == Brightness.light
                  ? Colors.white.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.10))
              : Colors.transparent,
          width: 0.3,
        ),
      ),
      boxShadow: scrolledUnder
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ]
          : [],
      width: double.infinity,
      child: child,
    );
  }
}
