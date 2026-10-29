part of 'components.dart';

// 错误文案归一化（isAuthError / friendlyErrorMessage / HTTP 状态码映射）
// 已上移到 lib/utils/translations.dart，供 NetworkError 与 SnackBar
// 等所有出错路径共用一份实现，避免两套映射各自漂移。


/// 统一加载指示器 —— 应用默认加载态的唯一实现。
///
/// 集中约定尺寸与线宽，替代各处 strokeWidth 不一（1.4/1.8/2/默认）的裸
/// [CircularProgressIndicator]。新加载态请优先使用本组件，保持全局一致。
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({super.key, this.size = 32, this.strokeWidth = 2});

  final double size;

  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(strokeWidth: strokeWidth),
      ),
    );
  }
}

/// 慢网络提示 —— 加载态持续超过 [delay] 仍没有结果时，淡入一行说明。
///
/// 为什么需要它：请求的总超时是 15s，断网/弱网时用户会先盯着转圈或骨架屏
/// 十来秒。这段时间界面没有任何「还在努力」的信号，用户无法区分「正在
/// 加载」和「已经卡死」，容易直接杀进程。7s 出现，恰好落在超时之前，
/// 既不会在正常网络下闪一下，又能在真的慢时给出解释。
///
/// 计时器随组件销毁自动取消 —— 加载结束后本组件会整棵被替换掉。
class SlowLoadingHint extends StatefulWidget {
  const SlowLoadingHint({
    super.key,
    this.delay = const Duration(seconds: 7),
    this.chip = false,
  });

  final Duration delay;

  /// 叠在骨架屏等有内容画面上时置 true，加一层胶囊底保证可读。
  final bool chip;

  @override
  State<SlowLoadingHint> createState() => _SlowLoadingHintState();
}

class _SlowLoadingHintState extends State<SlowLoadingHint> {
  bool _visible = false;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (!mounted) return;
      setState(() {
        _visible = true;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget content = Text(
      "Network is slow, still loading…".tl,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: kcCaption, color: cs.onSurfaceVariant),
    );
    if (widget.chip) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(kcRadius16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: kcSpaceLg,
            vertical: kcSpaceSm,
          ),
          child: content,
        ),
      );
    }
    // AnimatedSize 让提示从 0 高度长出来，避免出现瞬间跳动；
    // 未显示时占 0 高，不影响原有加载态居中。
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      child: _visible
          ? Padding(
              padding: EdgeInsets.only(top: widget.chip ? 0 : kcSpaceMd),
              child: content,
            )
          : const SizedBox(width: double.infinity, height: 0),
    );
  }
}

/// 给骨架屏这类「铺满整块区域」的加载态叠一层慢网络提示。
///
/// 骨架屏本身是 GridView，没法在下面再塞一行，所以用 Stack 把提示浮在
/// 底部。提示自带胶囊底，压在灰色占位块上依然清晰。
class SlowLoadingOverlay extends StatelessWidget {
  const SlowLoadingOverlay({
    super.key,
    required this.child,
    this.delay = const Duration(seconds: 7),
  });

  final Widget child;

  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: kcSpaceLg,
          right: kcSpaceLg,
          bottom: 28,
          child: Center(
            child: SlowLoadingHint(delay: delay, chip: true),
          ),
        ),
      ],
    );
  }
}

class NetworkError extends StatelessWidget {
  const NetworkError({
    super.key,
    required this.message,
    this.retry,
    this.withAppbar = true,
    this.buttonText,
    this.action,
  });

  final String message;

  final void Function()? retry;

  final bool withAppbar;

  final String? buttonText;

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    var cfe = CloudflareException.fromString(message);
    final cs = context.colorScheme;
    final displayMessage = friendlyErrorMessage(
      cfe == null ? message : "Cloudflare verification required".tl,
    );
    Widget body = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedAlertCircle,
              size: 44,
              color: cs.error,
            ),
            const SizedBox(height: 16),
            Text(
              "Error".tl,
              style: TextStyle(
                fontSize: kcSubtitle,
                fontWeight: FontWeight.w600,
                color: cs.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              displayMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: kcBody,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
              if (retry != null)
              if (cfe != null)
                Button.filled(
                  onPressed: () => passCloudflare(
                    CloudflareException.fromString(message)!,
                    retry!,
                  ),
                  child: Text('Verify'.tl),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (action != null)
                      action!.paddingRight(8),
                    Button.filled(
                      onPressed: () => retry?.call(),
                      child: Text(buttonText ?? 'Retry'.tl),
                    ),
                  ],
                ),
            const SizedBox(height: 8),
            Button.text(
              onPressed: () {
                saveFile(
                  data: utf8.encode(Log().toString()),
                  filename: 'log.txt',
                );
              },
              child: Text("Export logs".tl),
            ),
          ],
        ),
      ),
    );
    if (withAppbar) {
      body = Column(
        children: [
          const Appbar(title: Text("")),
          Expanded(child: body),
        ],
      );
    }
    return Material(child: body);
  }
}

class ListLoadingIndicator extends StatelessWidget {
  const ListLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    // 和整页加载态同一套语言，只是缩小到 52dp：列表滚动到尾部时
    // 出现的是一只在爬的小人，而不是另一种风格的五个彩点。
    return const SizedBox(
      width: double.infinity,
      height: 80,
      child: Center(
        child: KcChibiCrawlLoading(charWidth: 52),
      ),
    );
  }
}

class SliverListLoadingIndicator extends StatelessWidget {
  const SliverListLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    // SliverToBoxAdapter can not been lazy loaded.
    // Use SliverList to make sure the animation can be lazy loaded.
    return SliverList.list(
      children: const [SizedBox(), ListLoadingIndicator()],
    );
  }
}

abstract class LoadingState<T extends StatefulWidget, S extends Object>
    extends State<T> {
  bool isLoading = false;

  S? data;

  String? error;

  Future<Res<S>> loadData();

  Future<Res<S>> loadDataWithRetry() async {
    int retry = 0;
    // 重试总预算：失败得很快（5xx 几百毫秒）时多试几次几乎无感；但如果是
    // 15s 超时这种慢失败，再叠 3 次就是用户盯着骨架屏一分钟。所以超过一个
    // 完整超时周期就不再重试。
    const totalBudget = Duration(seconds: 16);
    final start = DateTime.now();
    while (true) {
      Res<S> res;
      final attemptStart = DateTime.now();
      try {
        res = await loadData();
      } catch (e) {
        // 源脚本 / 网络层直接抛异常（而不是返回 Res.error）时，以前这里没有
        // catch：Future 带着错误结束，isLoading 永远停在 true，界面就是一片
        // 转圈或骨架屏，也没有任何提示。统一转成错误态。
        res = Res<S>.error(friendlyError(e));
      }
      if (res.success) {
        return res;
      }
      if (!mounted) return res;
      // 只对可能自愈的错误重试。断网 / DNS 失败 / 证书问题是硬失败。
      final elapsed = DateTime.now().difference(start);
      final attemptCost = DateTime.now().difference(attemptStart);
      if (retry >= 3 ||
          elapsed > totalBudget ||
          // 单次就耗掉 8 秒以上（几乎都是撞上连接/接收超时），说明链路确实
          // 不通。此时再叠一轮重试，用户要盯着加载态多等一个完整超时周期，
          // 不如直接把失败抛给错误页。
          attemptCost > const Duration(seconds: 8) ||
          !isRetryableError(res.errorMessage)) {
        return res;
      }
      retry++;
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  FutureOr<void> onDataLoaded() {}

  Widget buildContent(BuildContext context, S data);

  Widget? buildFrame(BuildContext context, Widget child) => null;

  Widget buildLoading() {
    return const KcPageLoading();
  }

  void retry() {
    setState(() {
      isLoading = true;
      error = null;
    });
    _performLoad();
  }

  /// 统一的「加载 → 落地」流程。两条入口（[initState] 与 [retry]）此前各写
  /// 一份 .then，且都没有兜住 [onDataLoaded] 抛异常的情况 —— 一旦它抛，
  /// isLoading 就停在 true，界面永远转圈。
  Future<void> _performLoad() async {
    final value = await loadDataWithRetry();
    if (!mounted) return;
    if (value.success) {
      try {
        data = value.data;
        await onDataLoaded();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          isLoading = false;
          error = friendlyError(e);
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
        error = friendlyError(value.errorMessage ?? "Unknown error".tl);
      });
    }
  }

  Widget buildError() {
    return NetworkError(message: error!, retry: retry);
  }

  @override
  @mustCallSuper
  void initState() {
    isLoading = true;
    Future.microtask(_performLoad);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (isLoading) {
      child = buildLoading();
    } else if (error != null) {
      child = buildError();
    } else {
      child = buildContent(context, data!);
    }

    return buildFrame(context, child) ?? child;
  }
}

abstract class MultiPageLoadingState<T extends StatefulWidget, S extends Object>
    extends State<T> {
  bool _isFirstLoading = true;

  bool _isLoading = false;

  List<S>? data;

  String? _error;

  int _page = 1;

  int? _maxPage;

  Future<Res<List<S>>> loadData(int page);

  Widget? buildFrame(BuildContext context, Widget child) => null;

  Widget buildContent(BuildContext context, List<S> data);

  bool get isLoading => _isLoading || _isFirstLoading;

  bool get isFirstLoading => _isFirstLoading;

  bool get haveNextPage => _maxPage == null || _page <= _maxPage!;

  void nextPage() {
    if (_maxPage != null && _page > _maxPage!) return;
    if (_isLoading) return;
    _isLoading = true;
    Future.microtask(() async {
      // 抛异常也要把 _isLoading 收回来，否则后续翻页会被永久挡住。
      Res<List<S>> value;
      try {
        value = await loadData(_page);
      } catch (e) {
        value = Res<List<S>>.error(friendlyError(e));
      } finally {
        _isLoading = false;
      }
      if (!mounted) return;
      if (value.success) {
        _page++;
        if (value.subData is int) {
          _maxPage = value.subData as int;
        }
        setState(() {
          data!.addAll(value.data);
        });
      } else {
        var message = friendlyError(value.errorMessage ?? "Network Error".tl);
        if (message.length > 20) {
          message = "${message.substring(0, 20)}...";
        }
        context.showMessage(message: message);
      }
    });
  }

  void reset() {
    setState(() {
      _isFirstLoading = true;
      _isLoading = false;
      data = null;
      _error = null;
      _page = 1;
    });
    firstLoad();
  }

  void firstLoad() {
    Future.microtask(() async {
      // 同 [nextPage]：异常必须落到错误态，不能把 _isFirstLoading 永远挂住。
      Res<List<S>> value;
      try {
        value = await loadData(_page);
      } catch (e) {
        value = Res<List<S>>.error(friendlyError(e));
      }
      if (!mounted) return;
      if (value.success) {
        _page++;
        if (value.subData is int) {
          _maxPage = value.subData as int;
        }
        setState(() {
          _isFirstLoading = false;
          data = value.data;
        });
      } else {
        setState(() {
          _isFirstLoading = false;
          _error = friendlyError(value.errorMessage ?? "Unknown error".tl);
        });
      }
    });
  }

  @override
  void initState() {
    firstLoad();
    super.initState();
  }

  Widget buildLoading(BuildContext context) {
    return const KcPageLoading();
  }

  Widget buildError(BuildContext context, String error) {
    return NetworkError(withAppbar: false, message: error, retry: reset);
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (_isFirstLoading) {
      child = buildLoading(context);
    } else if (_error != null) {
      child = buildError(context, _error!);
    } else {
      child = NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels ==
              notification.metrics.maxScrollExtent) {
            nextPage();
          }
          return false;
        },
        child: buildContent(context, data!),
      );
    }

    return buildFrame(context, child) ?? child;
  }
}

/// Q 版人物加载动画 —— 全应用加载态的统一实现。
///
/// 尺寸由 [charWidth] 一档控制（素材 720×420，横构图，四周已裁到画面边缘）：
/// - 整章图片列表、选图遮罩这类全屏加载用 96–110dp，五官与服饰都清晰；
/// - 单张图片的小格子用 52–60dp，人物细节会糊但剪影仍可辨认，视觉语言统一。
///
/// 素材是透明背景的 webp：底色由调用方的背景决定，深色阅读器与浅色列表
/// 共用同一份，不需要两套图。
///
/// 交互逻辑：
/// - [progress] 为 null：不确定态。人物原地爬（跑步机感），下方进度条改为流光。
/// - [progress] 为 0..1：确定态。**人物沿轨道从左爬到右，位置即进度**，爬到
///   头刚好加载完；下方进度条同步填充。
/// 进度已经由「人物位置 + 进度条」双重编码，所以不再显示百分比数字 —— 第三种
/// 表达既占高度又要额外视线跳转，在 52–60dp 的小格子里尤其局促。
/// 进度来自离散的字节上报，直接绑定会一顿一顿地弹，所以位置和条都走
/// 420ms 的缓动追赶目标值，视觉上是连续爬行。
///
/// 尊重系统「减少动态效果」：开启时人物静止、进度瞬间到位，只保留造型。
class KcChibiCrawlLoading extends StatefulWidget {
  const KcChibiCrawlLoading({
    super.key,
    this.charWidth = 96,
    this.progress,
    this.color,
  });

  /// 人物的显示宽度，轨道宽度按 1.5 倍自动推导。
  final double charWidth;

  /// 进度，0..1。null（或 NaN）表示不确定态。
  final double? progress;

  /// 进度条颜色，默认用主题 primary。
  final Color? color;

  @override
  State<KcChibiCrawlLoading> createState() => _KcChibiCrawlLoadingState();
}

class _KcChibiCrawlLoadingState extends State<KcChibiCrawlLoading>
    with TickerProviderStateMixin {
  /// 素材（assets/loading/chibi_crawl.webp）的高宽比，720×420。
  static const double _aspect = 420 / 720;

  /// 爬行周期：一次手脚交替 + 身体起伏。
  late final AnimationController _bob;
  late final AnimationController _shift;

  /// 复用的图片 widget —— 放在动画 builder 之外，避免每帧重建 element。
  Widget? _cachedChar;
  double _cachedCharWidth = 0;

  @override
  void initState() {
    super.initState();
    _bob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    _shift = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _syncProgress(initial: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _bob.stop();
      // 减少动效时不做追赶，进度直接落位。
      _snapProgress();
    } else if (!_bob.isAnimating) {
      _bob.repeat();
      _syncProgress();
    }
  }

  @override
  void didUpdateWidget(KcChibiCrawlLoading old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress) _syncProgress();
  }

  @override
  void dispose() {
    _bob.dispose();
    _shift.dispose();
    super.dispose();
  }

  /// 把 [_shift] 推向当前进度（带缓动）；不确定态则归零。
  void _syncProgress({bool initial = false}) {
    final target = _target;
    if (target == null) {
      _shift.stop();
      _shift.value = 0;
      return;
    }
    if (initial || MediaQuery.of(context).disableAnimations) {
      _shift.value = target;
    } else {
      _shift.animateTo(target, curve: Curves.easeOutCubic);
    }
  }

  void _snapProgress() {
    final target = _target;
    if (target != null) {
      _shift.stop();
      _shift.value = target;
    }
  }

  double? get _target {
    final p = widget.progress;
    if (p == null || p.isNaN) return null;
    return p.clamp(0.0, 1.0);
  }

  Widget _character(double width, double height) {
    if (_cachedChar == null || _cachedCharWidth != width) {
      _cachedCharWidth = width;
      // 素材已裁到画面边缘，BoxFit.contain 下宽高比一致、不会留白，
      // 所以「人物框」= 「可见轮廓」，跨轨移动的距离就是视觉上的位移。
      _cachedChar = RepaintBoundary(
        child: Image.asset(
          'assets/loading/chibi_crawl.webp',
          width: width,
          height: height,
          // 必须显式指定 fit：fit 为 null 时 RenderImage 按图片原始像素尺寸绘制，
          // 720×420 的素材塞进 110×64 会被裁成「只剩一个脑袋」。
          fit: BoxFit.contain,
          // high（三次插值）在缩小采样时比 bilinear 锐利，人物五官和发丝
          // 不会糊成一团；这只影响采样，不影响每帧的绘制次数。
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      );
    }
    return _cachedChar!;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = widget.color ?? cs.primary;
    final charW = widget.charWidth;
    final charH = charW * _aspect;
    final trackW = charW * 1.5;
    final determinate = _target != null;

    return AnimatedBuilder(
      animation: Listenable.merge([_bob, _shift]),
      builder: (context, _) {
        final phase = _bob.isAnimating ? _bob.value : 0.0;
        final wave = math.sin(phase * 2 * math.pi);
        // 平滑后的进度：位置与进度条同源，永不失步。
        final t = _shift.value;
        final travel = trackW - charW;

        // 确定态从左爬到右；不确定态在中段原地爬，前后小幅挪动。
        final x = determinate ? travel * t : travel * 0.5 + wave * charW * 0.06;
        // 爬行时身体轻微上下颠簸。
        final dy = wave * (determinate ? 1.6 : 2.2);
        final tilt = math.sin(phase * 2 * math.pi + 0.6) * 0.035;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: trackW,
              height: charH + 4,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: x,
                    bottom: 2,
                    width: charW,
                    height: charH,
                    child: Transform.translate(
                      offset: Offset(0, -dy),
                      child: Transform.rotate(
                        angle: tilt,
                        alignment: Alignment.bottomCenter,
                        child: _character(charW, charH),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: trackW,
              height: 3,
              child: CustomPaint(
                painter: _CrawlTrackPainter(
                  value: determinate ? t : null,
                  phase: phase,
                  color: accent,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 爬行轨道下方的细进度条：确定态左对齐填充，不确定态一段流光循环。
class _CrawlTrackPainter extends CustomPainter {
  const _CrawlTrackPainter({
    required this.value,
    required this.phase,
    required this.color,
  });

  /// 0..1；null 表示不确定态。
  final double? value;

  /// 循环相位，驱动不确定态的流光位置。
  final double phase;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    canvas.drawRRect(rr, Paint()..color = color.withValues(alpha: 0.16));

    canvas.save();
    canvas.clipRRect(rr);

    final v = value;
    if (v != null) {
      final w = size.width * v;
      // 低于 1px 时也画出来，避免刚起步的进度「看不见」。
      if (w > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, math.max(w, size.height), size.height),
            Radius.circular(size.height / 2),
          ),
          Paint()..color = color,
        );
      }
    } else {
      // 流光：一段高亮带从左侧滑出、右侧淡出。
      final bandW = size.width * 0.34;
      final dx = (size.width + bandW) * phase - bandW;
      final rect = Rect.fromLTWH(dx, 0, bandW, size.height);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              color.withValues(alpha: 0),
              color.withValues(alpha: 0.95),
              color.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CrawlTrackPainter old) =>
      old.value != value || old.phase != phase || old.color != color;
}

/// 页面 / 大区块的加载态：爬行人物 + 慢网络提示。
///
/// 全应用「整块内容在载入」只保留这一种画法。此前二十多处各写一个
/// `Center(child: CircularProgressIndicator())`：尺寸（24/32/48）、颜色
/// （默认 / 品牌红）、有没有慢网络提示，全凭当时的心情，页面之间跳来跳去
/// 加载样式一直在变。收口到这里之后，换素材、调节奏只改一处。
///
/// 尺寸分三档，按容器高度选，别硬塞：
/// - 110：整页 / 整屏（详情页、评论页、探索页、收藏同步）；
/// - 88：半屏区块（聚合搜索结果、240 高的 sliver 占位）；
/// - 52：列表底部「加载更多」（见 [ListLoadingIndicator]）。
class KcPageLoading extends StatelessWidget {
  const KcPageLoading({
    super.key,
    this.charWidth = 110,
    this.showSlowHint = true,
    this.color,
  });

  final double charWidth;

  /// 超过 7s 仍未结束时的「网络较慢」说明。列表底部、按钮内联等
  /// 空间局促的场景关掉。
  final bool showSlowHint;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KcChibiCrawlLoading(charWidth: charWidth, color: color),
          if (showSlowHint) const SlowLoadingHint(),
        ],
      ),
    );
  }
}
