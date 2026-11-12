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

  /// 当前 Timer 的到期时间戳（ms）。只有需要把截止时间顺延超过 50ms 时
  /// 才重建 Timer：滚动通知是每帧到达的，原来 60fps 下每秒要 cancel + new
  /// 60 次 Timer，纯属无谓分配。
  static int _deadline = 0;

  /// 由页面容器（NaviPane）在收到滚动通知时调用。
  static void markScrolling() {
    if (!scrolling.value) {
      scrolling.value = true;
    }
    const idle = 150;
    final now = DateTime.now().millisecondsSinceEpoch;
    final desired = now + idle;
    if (desired - _deadline < 50) return;
    _deadline = desired;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: idle), () {
      if (DateTime.now().millisecondsSinceEpoch >= _deadline) {
        scrolling.value = false;
      }
    });
  }
}

/// 带「滚动降级 + 恢复渐入」的模糊层。
///
/// [GlassContainer] 早就接入了 KcGlassActivity，[GlassCard] 却一直每帧跑
/// 高斯模糊；同时降级是二值硬切，停止滚动瞬间模糊度跳变会闪一下。
/// 这里让 sigma 在滚动中降到 0、停止后 150ms 平滑回到目标值；减少动效时
/// 直接切换，不给前庭敏感用户额外补间。
class _KcAdaptiveBlur extends StatelessWidget {
  const _KcAdaptiveBlur({required this.sigma, required this.child});

  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: KcGlassActivity.scrolling,
      builder: (context, scrolling, _) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: scrolling ? 0.0 : sigma),
          duration: kcReduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          builder: (context, value, blurChild) => BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: value, sigmaY: value),
            child: blurChild,
          ),
          child: child,
        );
      },
    );
  }
}

/// 贴着内容浮起的小控件（回顶 FAB / 翻页胶囊）共用的玻璃配色。
///
/// 浅色：半透明 surface + 发丝描边 —— 能透出背后的封面，又不会像实心白块
/// 那样在列表上糊出一条硬边；深色：`surfaceContainerHighest` 实心，纯 surface
/// 在近黑底上几乎看不见。
///
/// 收在一处是因为这两个控件同处屏幕右侧/底部尾排，配色一旦分叉（一个半透明
/// 带描边、一个实心带投影）并排看就是两种材质。
({Color background, Color foreground, BorderSide? side}) kcFloatingGlassColors(
  BuildContext context,
) {
  final cs = Theme.of(context).colorScheme;
  if (cs.brightness == Brightness.dark) {
    return (
      background: cs.surfaceContainerHighest,
      foreground: cs.onSurface,
      side: null,
    );
  }
  return (
    background: cs.surface.withValues(alpha: 0.82),
    foreground: cs.onSurface.withValues(alpha: 0.92),
    side: BorderSide(color: cs.outline.withValues(alpha: 0.16), width: 1),
  );
}

/// 悬浮小控件的玻璃外框：同一套底色 + 描边，圆角由调用方按形状给。
///
/// 底色本身是半透明的，压在封面上时调用方要自己配一层
/// `BackdropFilter`（见翻页胶囊），否则底下的书名会透进控件。
BoxDecoration kcFloatingGlassDecoration(
  BuildContext context, {
  required BorderRadius borderRadius,
}) {
  final colors = kcFloatingGlassColors(context);
  return BoxDecoration(
    color: colors.background,
    borderRadius: borderRadius,
    border: colors.side == null ? null : Border.fromBorderSide(colors.side!),
  );
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
    // 纯装饰的 6s 无限渐变默认关闭：弹窗常驻时它每帧重建渐变 + 跑一次
    // sigma=35 的高斯模糊，耗电掉帧却没有信息量。想要流动光泽的调用方显式
    // 传 true；系统开启「移除动画」时无论传什么都会停摆（见 State）。
    this.enableLiquidEffect = false,
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
    // 深色白 @0.12 在近黑底上几乎看不见；与全站共用同一套发丝线
    // 色阶（深色 onSurface@0.38 ≈ 3:1）与线宽（kcHairline）。
    return Border.all(
      color: kcHairlineColor(context),
      width: kcHairline,
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
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _liquidController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
      // 定格在中点：静态表面也留一层柔和光泽，而不是纯平的色块。
      value: 0.5,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery 变化（系统「移除动画」开关）会重新触发这里，运行中即可停摆。
    _syncLiquidAnimation();
  }

  @override
  void didUpdateWidget(covariant GlassContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncLiquidAnimation();
  }

  void _syncLiquidAnimation() {
    final shouldAnimate =
        widget.enableLiquidEffect && !MediaQuery.of(context).disableAnimations;
    if (shouldAnimate == _animating) return;
    _animating = shouldAnimate;
    if (shouldAnimate) {
      _liquidController.repeat(reverse: true);
    } else {
      _liquidController.stop();
      _liquidController.value = 0.5;
    }
  }

  @override
  void dispose() {
    _liquidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius =
        widget.borderRadius ?? BorderRadius.circular(kcRadius20);
    final effectiveBorder = widget.border ?? GlassContainer.iosBorder(context);
    final effectiveShadow =
        widget.boxShadow ?? GlassContainer.liquidShadow(context);
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
          animation: _animating ? _liquidController : null,
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
    final bottomPad = edgeToEdge ? MediaQuery.of(context).padding.bottom : 0.0;
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
    final effectiveBorderRadius =
        borderRadius ?? BorderRadius.circular(kcRadius16);

    Widget card;
    if (isDark) {
      card = ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: _KcAdaptiveBlur(
          sigma: 20,
          child: Container(
            padding: padding ?? const EdgeInsets.all(kcSpaceLg),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: effectiveBorderRadius,
              border: Border.all(
                color: kcHairlineColor(context),
                width: kcHairline,
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
                    borderRadius: effectiveBorderRadius,
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
        borderRadius: effectiveBorderRadius,
        child: _KcAdaptiveBlur(
          sigma: 10,
          child: Container(
            padding: padding ?? const EdgeInsets.all(kcSpaceLg),
            decoration: BoxDecoration(
              borderRadius: effectiveBorderRadius,
              gradient: LinearGradient(
                colors: [
                  primary.withValues(alpha: 0.12),
                  primary.withValues(alpha: 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: kcHairlineColor(context),
                width: kcHairline,
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
                    borderRadius: effectiveBorderRadius,
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
