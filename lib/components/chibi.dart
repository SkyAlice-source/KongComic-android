part of 'components.dart';

/// 空状态里的角色 —— 和加载态是同一只 Q 版小人，只是「停下来了」。
///
/// 为什么要有它：加载态已经由 [KcChibiCrawlLoading] 统一成「小人沿轨道爬」，
/// 但「这里没有内容」仍然是二十多处各写一个 56px 的灰图标（时钟 / 收件箱 /
/// 搜不到的放大镜）。同一只小人在一处爬、另一处消失，页面之间就没有共同的
/// 角色记忆。空状态改用同一只小人之后，三种状态读起来是一句话：
///
/// - **加载中**：小人沿轨道从左爬到右，位置即进度；
/// - **没有内容**：小人停在原地，缓慢呼吸，脚下不画轨道（没有进度的暗示）；
/// - **出错**：保留红色警告图标 —— 那不是「还没有内容」，是「出事了」，
///   语义不同就不该共用同一张脸。
///
/// 动效只有一层：2.8s 的吸气/呼气（上下 2dp + 1.5% 缩放），幅度小于加载态
/// 的爬行，避免空页面比有内容的页面更抢眼。系统开启「减少动态效果」时定格。
class KcChibiIdle extends StatefulWidget {
  const KcChibiIdle({
    super.key,
    this.width = 144,
    this.semanticLabel,
  });

  /// 小人显示宽度，轨道宽度按 1.5 倍推导的规则在这里不适用 —— 空态没有
  /// 轨道，人物本身就是构图的全部，所以比加载态略大一点。
  final double width;

  /// 无障碍标签。空状态的语义由下方标题承担，这里默认不重复朗读。
  final String? semanticLabel;

  @override
  State<KcChibiIdle> createState() => _KcChibiIdleState();
}

class _KcChibiIdleState extends State<KcChibiIdle>
    with SingleTickerProviderStateMixin {
  /// 素材（assets/loading/chibi_crawl.webp）的高宽比，720×420。
  static const double _aspect = 420 / 720;

  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 跟随系统的「减少动态效果」：定格在呼气末（最松弛的姿势）。
    if (kcReduceMotion(context)) {
      _breath
        ..stop()
        ..value = 0;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = w * _aspect;
    final image = RepaintBoundary(
      child: Image.asset(
        'assets/loading/chibi_crawl.webp',
        width: w,
        height: h,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        semanticLabel: widget.semanticLabel,
        excludeFromSemantics: widget.semanticLabel == null,
      ),
    );

    return AnimatedBuilder(
      animation: _breath,
      // 子组件在 builder 之外创建：每帧只更新 Transform，不重建图片 element。
      child: image,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_breath.value);
        return Transform.translate(
          // 负值是向上浮：吸气时身体微微立起来。
          offset: Offset(0, -2 * t),
          child: Transform.scale(
            scale: 1 + 0.015 * t,
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
    );
  }
}
