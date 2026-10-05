part of 'components.dart';

/// 全局「是否正在滚动」状态。
///
/// 背景模糊（BackdropFilter）是滚动时最贵的一笔开销：列表每一帧移动，
/// 底栏/顶栏就要重新采样背后内容并跑一次高斯模糊，中低端机上很容易吃满 16ms 预算。
/// 而**滚动过程中人眼根本分辨不出背后是模糊还是实色**——所以滚动中直接降级成
/// 半透明实色（tint 略加厚保证可读性），停止 150ms 后再恢复真玻璃。
/// 观感几乎无损，滚动帧耗时大幅下降。
class KcGlassActivity {
  KcGlassActivity._();

  static final ValueNotifier<bool> scrolling = ValueNotifier<bool>(false);

  static Timer? _timer;

  /// 由页面容器（NaviPane）在收到滚动通知时调用。
  static void markScrolling() {
    if (!scrolling.value) {
      scrolling.value = true;
    }
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 150), () {
      scrolling.value = false;
    });
  }
}

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
    final effectiveBorderRadius = widget.borderRadius ?? BorderRadius.circular(kcRadius20);
    final effectiveBorder = widget.border ?? GlassContainer.iosBorder(context);
    final effectiveShadow = widget.boxShadow ?? GlassContainer.liquidShadow(context);
    final brightness = Theme.of(context).brightness;

    Widget glassChild = ClipRRect(
      borderRadius: effectiveBorderRadius ,
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
          borderRadius: effectiveBorderRadius ,
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

    // 折射渐变 — 模拟光线经过玻璃的折射感。
    // 无显式 tintColor 时从主题 primary/tertiary 派生，跟随种子色/Material You，
    // 避免固定蓝紫与用户选定的强调色（如红/绿）冲突。
    final cs = Theme.of(context).colorScheme;
    final refractionColors = [
      baseColor,
      if (tintColor != null)
        tintColor!.withValues(alpha: opacity * 0.6)
      else if (isLight)
        cs.primary.withValues(alpha: opacity * 0.3)
      else
        cs.primary.withValues(alpha: opacity * 0.2),
      baseColor,
      if (tintColor != null)
        tintColor!.withValues(alpha: opacity * 0.3)
      else if (isLight)
        cs.tertiary.withValues(alpha: opacity * 0.15)
      else
        cs.tertiary.withValues(alpha: opacity * 0.1),
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

/// Glass bottom navigation bar with frosted glass effect.
/// Floating capsule style — rounded, with margin, extends into system nav area for immersive feel.
class GlassBottomBar extends StatelessWidget {
  final List<Widget> children;
  final double height;
  final bool edgeToEdge;
  final EdgeInsetsGeometry margin;

  /// 可选的「液体选中框」滑动药丸（按底栏内容宽度构建），叠在 item 行之上、不拦截点击。
  final Widget Function(double width)? indicator;

  const GlassBottomBar({
    super.key,
    required this.children,
    this.height = 56,
    this.edgeToEdge = false,
    this.margin = const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
    this.indicator,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = edgeToEdge
        ? MediaQuery.of(context).padding.bottom
        : 0.0;
    final totalHeight = height + bottomPad;
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    // 真·磨砂玻璃（像贴吧 Haze）的关键：不要镜面高光、不要过硬的投影。
    // 之前那道「顶部 white@0.55→0 渐变」是塑料反光感的来源，已移除。
    final tintColor = isDark
        ? Colors.black.withValues(alpha: 0.54)
        : Colors.white.withValues(alpha: 0.66);
    // 模糊半径：40 → 24。Skia 的高斯模糊开销随 sigma 增长，24 在观感上与 40
    // 差别很小（都是「看不清细节」级别的模糊），但每帧耗时明显更低。
    const blurSigma = 24.0;

    // 滚动中降级为实色（不套 BackdropFilter），停止后恢复真玻璃。
    // 见 KcGlassActivity 的说明：滚动时人眼分辨不出背后是否模糊，但省掉每帧采样+模糊。
    final pill = ValueListenableBuilder<bool>(
      valueListenable: KcGlassActivity.scrolling,
      builder: (context, scrolling, _) {
        final effectiveTint = scrolling
            ? (isDark
                ? Colors.black.withValues(alpha: 0.72)
                : Colors.white.withValues(alpha: 0.88))
            : tintColor;

        Widget body = Container(
          decoration: BoxDecoration(
            color: effectiveTint,
            borderRadius: BorderRadius.circular(kcRadius32),
            // 贴吧那种「无描边、无凝光」的干净玻璃片：只留一层柔和漫射投影，
            // 让浮岛从内容轻轻浮起，不靠硬边/高光制造塑料质感。
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.06),
                blurRadius: 28,
                spreadRadius: -4,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SizedBox(
            height: height,
            // 测宽放在这里：indicator 内部的 Positioned 必须直接挂在 Stack 下，
            // 中间不能隔 LayoutBuilder 这类 RenderObjectWidget，否则定位失效。
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                fit: StackFit.expand,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: children,
                  ),
                  if (indicator != null) indicator!(constraints.maxWidth),
                ],
              ),
            ),
          ),
        );

        if (!scrolling) {
          body = BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: body,
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(kcRadius32),
          child: body,
        );
      },
    );

    return Padding(
      padding: margin,
      child: SizedBox(
        height: totalHeight,
        width: double.infinity,
        // 安全区透明（不加背景），内容自然透出
        child: Column(
          children: [
            Expanded(child: pill),
            if (bottomPad > 0) SizedBox(height: bottomPad),
          ],
        ),
      ),
    );
  }
}

/// Card that adapts: dark mode = frosted glass, light mode = blue gradient + white edge
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(kcRadius16);

    Widget card;
    if (isDark) {
      card = ClipRRect(
        borderRadius: effectiveBorderRadius ,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: padding ?? const EdgeInsets.all(kcSpaceLg),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: effectiveBorderRadius ,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
                // ColorOS 17 Contour Glow：卡片四周柔光描边
                ...kcContourGlow(context),
              ],
            ),
            child: onTap != null
                ? InkWell(
                    borderRadius: effectiveBorderRadius ,
                    onTap: onTap,
                    splashColor: Colors.white.withValues(alpha: 0.08),
                    highlightColor: Colors.white.withValues(alpha: 0.04),
                    child: child,
                  )
                : child,
          ),
        ),
      );
    } else {
      card = ClipRRect(
        borderRadius: effectiveBorderRadius ,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: padding ?? const EdgeInsets.all(kcSpaceLg),
            decoration: BoxDecoration(
              borderRadius: effectiveBorderRadius ,
              gradient: LinearGradient(
                colors: [
                  primary.withValues(alpha: 0.12),
                  primary.withValues(alpha: 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: primary.withValues(alpha: 0.2),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
                // ColorOS 17 Contour Glow：卡片四周柔光描边
                ...kcContourGlow(context),
              ],
            ),
            child: onTap != null
                ? InkWell(
                    borderRadius: effectiveBorderRadius ,
                    onTap: onTap,
                    splashColor: Colors.white.withValues(alpha: 0.08),
                    highlightColor: Colors.white.withValues(alpha: 0.04),
                    child: child,
                  )
                : child,
          ),
        ),
      );
    }

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }

    return card;
  }
}

