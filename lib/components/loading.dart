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
    return const SizedBox(
      width: double.infinity,
      height: 80,
      child: Center(child: FiveDotLoadingAnimation()),
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
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [AppLoadingIndicator(), SlowLoadingHint()],
      ),
    );
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
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [AppLoadingIndicator(), SlowLoadingHint()],
      ),
    );
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

class FiveDotLoadingAnimation extends StatefulWidget {
  const FiveDotLoadingAnimation({super.key});

  @override
  State<FiveDotLoadingAnimation> createState() =>
      _FiveDotLoadingAnimationState();
}

class _FiveDotLoadingAnimationState extends State<FiveDotLoadingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      upperBound: 6,
    )..repeat(min: 0, max: 5.2, period: const Duration(milliseconds: 1200));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _colors = [
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.yellow,
    Colors.purple,
  ];

  static const _padding = 12.0;

  static const _dotSize = 12.0;

  static const _height = 24.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: _dotSize * 5 + _padding * 6,
          height: _height,
          child: Stack(children: List.generate(5, (index) => buildDot(index))),
        );
      },
    );
  }

  Widget buildDot(int index) {
    var value = _controller.value;
    var startValue = index * 0.8;
    return Positioned(
      left: index * _dotSize + (index + 1) * _padding,
      bottom:
          (math.sin(math.pi / 2 * (value - startValue).clamp(0, 2))) *
          (_height - _dotSize),
      child: Container(
        width: _dotSize,
        height: _dotSize,
        decoration: BoxDecoration(
          color: _colors[index],
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
