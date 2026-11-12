part of 'components.dart';

/// 封面占位层：没有可画的东西时也把版面占住，用「书名首字 + 中性底」
/// 代替纯空白。
///
/// 为什么不用灰块：断网时一屏十几张灰块看起来像界面坏了；而「首字」既宣告
/// 这里是一张封面，又保留了「这是哪本书」的信息，成本和灰块一样低。
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({
    super.key,
    this.label,
    this.icon,
    this.iconSize = 26,
    this.fontSize = 40,
    this.showIcon = true,
  });

  /// 书名。取首字作为占位文字；为空时退化为图标。
  final String? label;

  /// 自定义图标（默认用图片图标）。HugeIcons 的图标常量是嵌套 List，不是 IconData。
  final List<List<dynamic>>? icon;

  final double iconSize;

  /// 首字字号。大卡（主页英雄卡）给小卡的值会让首字小得看不见。
  final double fontSize;

  final bool showIcon;

  String? get _initial {
    final text = label?.trim();
    if (text == null || text.isEmpty) return null;
    // runes 取首个码点：中文、日文、emoji 都不会被截成半个字符。
    return String.fromCharCode(text.runes.first);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = _initial;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        // 极弱的对角高光，避免一整块死灰；暗色下几乎不可见，只是让边缘有层次。
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.onSurface.withValues(alpha: 0.03),
            cs.onSurface.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Center(
        child: initial != null
            ? Text(
                initial,
                maxLines: 1,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                ),
              )
            : (showIcon
                  ? HugeIcon(
                      icon: icon ?? HugeIcons.strokeRoundedImage01,
                      size: iconSize,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                    )
                  : const SizedBox()),
      ),
    );
  }
}

/// 加载中的占位：书名首字 + **延迟出现**的加载环。
///
/// 两个设计约束：
/// 1. **延迟 320ms 才显示环**。多数封面 200–600ms 就回来了，立刻转圈会让
///    列表滚动时满屏「一闪而过的圈」，比没有指示更躁；只有过了延迟还没回来
///    的封面才算「真的慢」，这时候给指示才有信息量。
/// 2. **环套在首字外面，首字退到 0.55**。早先试过「环盖在字上 + 首字 0.22」：
///    实机放大看两头落空，字糊掉、14dp 的环只剩一小段弧，既丢了「这是哪本书」
///    又没说清「在加载」。再试「环紧贴字（1.45×）」，又变成「字被圈住」的
///    装饰感。最终取环径 = 首字字号 × 1.75（列表约 56dp、网格约 66dp），
///    环与字之间留出一圈空隙，字保留 0.55 作为可读的背景信息。
class _CoverLoadingPlaceholder extends StatefulWidget {
  const _CoverLoadingPlaceholder({
    this.label,
    this.fontSize = 40,
    this.showIcon = true,
    this.ringSize = 40,
    this.progress,
    this.showPercent = false,
  });

  final String? label;
  final double fontSize;
  final bool showIcon;

  /// 加载环直径。由 [CoverBox] 按首字字号推算，保证环始终套在字外面。
  final double ringSize;

  /// 真实下载进度。为 null 时环是不确定态（一直转）。
  ///
  /// 只有大卡（主页英雄卡、详情页封面）才接进来：列表里几十张小缩略图
  /// 同时刷百分比数字，会变成一屏跳动的数字，比一个安静的转圈噪得多。
  final ValueListenable<ImageChunkEvent?>? progress;

  /// 在环内显示百分比数字。需要环足够大（≥44dp），否则数字会顶到环上。
  final bool showPercent;

  @override
  State<_CoverLoadingPlaceholder> createState() =>
      _CoverLoadingPlaceholderState();
}

class _CoverLoadingPlaceholderState extends State<_CoverLoadingPlaceholder> {
  static const _ringDelay = Duration(milliseconds: 320);

  Timer? _timer;
  bool _showRing = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_ringDelay, () {
      // 图片在延迟内到达时，整个占位会被 AnimatedSwitcher 换走并 dispose，
      // 这里先判 mounted，避免对已卸载的 State 调 setState。
      if (mounted) setState(() => _showRing = true);
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
    final duration = kcReduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    return Stack(
      fit: StackFit.expand,
      children: [
        // 环出现时首字退到 0.55：完全保留会和环抢同一个视觉中心（两者同权重
        // 时看起来像「字被圈住了」而不是「在加载」），完全隐去又丢掉书名的
        // 线索。0.55 是两者都成立的那一档。带百分比的大卡再退到 0.30：
        // 环心要放「42%」这类数字，首字不退就会和数字叠成一团墨。
        AnimatedOpacity(
          opacity: _showRing ? (widget.showPercent ? 0.30 : 0.55) : 1,
          duration: duration,
          child: CoverPlaceholder(
            label: widget.label,
            fontSize: widget.fontSize,
            showIcon: widget.showIcon,
          ),
        ),
        if (_showRing)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: duration,
            builder: (context, value, child) =>
                Opacity(opacity: value, child: child),
            child: Center(child: _buildRing(cs)),
          ),
      ],
    );
  }

  Widget _buildRing(ColorScheme cs) {
    final listenable = widget.progress;
    if (listenable == null) {
      return _ring(cs: cs, value: null);
    }
    // 只重建这一颗环，不让每个 chunk 事件把整棵封面树刷一遍。
    return ValueListenableBuilder<ImageChunkEvent?>(
      valueListenable: listenable,
      builder: (context, event, _) {
        final total = event?.expectedTotalBytes;
        final loaded = event?.cumulativeBytesLoaded;
        // 服务器不报 content-length（chunked 响应）或还没收到第一个 chunk 时
        // 算不出比例 —— 这时候宁可转不确定环，也不要画一个停在 0% 的假进度。
        final value = (total != null && total > 0 && loaded != null)
            ? (loaded / total).clamp(0.0, 1.0).toDouble()
            : null;
        return _ring(cs: cs, value: value);
      },
    );
  }

  Widget _ring({required ColorScheme cs, required double? value}) {
    // 中性色而不是品牌红：一屏可能同时有三个慢封面，红色圆环会把它们变成
    // 三个抢注意力的焦点，而它们只是「在等」。
    //
    // 有比例时加重：一张 68% 的环如果淡到看不出走到哪，百分比就白写了。
    // 列表小卡仍用轻的一档 —— 它们只需要「在转」这个信息。
    final hasRatio = value != null;
    final color = cs.onSurfaceVariant.withValues(
      alpha: hasRatio && widget.showPercent ? 0.80 : 0.62,
    );
    final showNumber =
        widget.showPercent && value != null && widget.ringSize >= 44;
    return SizedBox(
      width: widget.ringSize,
      height: widget.ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: value,
            strokeWidth: hasRatio && widget.showPercent ? 3.0 : 2.4,
            // 圆头端点：方头在细环上会显出一截生硬的直角。
            strokeCap: StrokeCap.round,
            // 轨道只在「有比例」时画：不确定态带一条完整底圈，看起来像已经
            // 走完了却永远不动。
            backgroundColor: value == null
                ? null
                : cs.onSurfaceVariant.withValues(alpha: 0.16),
            valueColor: AlwaysStoppedAnimation(color),
          ),
          if (showNumber)
            // 环内径留出 36% 给环本身：`100%` 这种三位数、或用户把系统字号
            // 放大到 2 倍时，FittedBox 会等比缩小而不是让数字顶到环上。
            Padding(
              padding: EdgeInsets.all(widget.ringSize * 0.18),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${(value * 100).round()}%',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: kcFont11,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    color: cs.onSurfaceVariant,
                    // 等宽数字：40% → 41% 时数字不会左右跳。
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 统一的封面容器：占位 → 淡入 → 失败可重试。
///
/// 之前各页面各写一套 `CachedNetworkImage` + `FileImage`，占位普遍是
/// `SizedBox()`，断网时就是「白卡片」。这里把三件事收口：
/// 1. 加载中永远有一张 [CoverPlaceholder] 顶着，不会白；
/// 2. 失败时在封面右下角给「重试」，点一下 evict 掉失败缓存重新拉；
/// 3. 成功走 [AnimatedImage] 的 200ms 淡入，和列表卡片观感一致。
class CoverBox extends StatefulWidget {
  const CoverBox({
    super.key,
    required this.image,
    this.label,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.medium,
    this.retryable = true,
    this.failed = false,
    this.onFailed,
    this.showIcon = true,
    this.initialFontSize = 40,
    this.showProgressPercent = false,
    this.cacheWidth,
    this.cacheHeight,
  });

  /// 为 null 时只渲染占位（例如本地漫画记录丢失）。
  final ImageProvider? image;

  /// 占位用的文字来源（书名）。
  final String? label;

  final BoxFit fit;
  final FilterQuality filterQuality;

  /// 重试入口是否用「图标 + 重试」的 pill 形态。
  ///
  /// 这只影响形态、不影响是否可重试：小缩略图（<90dp）一律给紧凑圆点，
  /// 否则要么 pill 盖住半张图，要么（旧行为）干脆不给入口——失败和加载中
  /// 长得一模一样，用户只能对着首字一直等。
  final bool retryable;

  /// 外部已知该封面加载失败（例如轮播每次切页都会重建整棵子树，
  /// 失败信息必须由调用方记住，否则会一遍遍从「加载中」重新开始）。
  final bool failed;

  /// 首次失败时回调，供调用方把「已失败」记在更长寿的 State 里。
  final VoidCallback? onFailed;

  /// 占位里是否画那颗图片图标。纯装饰背景（如主页轮播的堆叠卡）
  /// 传 false，只留一块底色。
  final bool showIcon;

  final double initialFontSize;

  /// 加载环里是否画真实百分比（`42%`）。
  ///
  /// 只给大卡用：主页英雄卡、详情页封面。列表里几十张小缩略图同时跳数字
  /// 比安静的转圈噪得多，而且 30dp 的环也塞不下两位数。
  final bool showProgressPercent;

  final int? cacheWidth;
  final int? cacheHeight;

  /// 全局「封面代次」：整页重取数据（下拉刷新）时 +1。
  ///
  /// 下拉刷新只清列表数据，不重建每个卡片：`CoverBox` 的 State 仍在，
  /// `AnimatedImage` 的 key 也没变，于是**已经失败的封面不会因为刷新而重试**
  /// ——用户下拉了、数据也回来了，缺图还是缺图，只能一张张点重试。
  /// 这里给存活的失败封面一个统一的重来信号，不需要再加一个「重载封面」按钮。
  static final ValueNotifier<int> generation = ValueNotifier<int>(0);

  /// 让所有处于失败态的封面重试一次（成功的封面不动，它们本来就有图）。
  static void refreshAll() => generation.value++;

  @override
  State<CoverBox> createState() => _CoverBoxState();
}

class _CoverBoxState extends State<CoverBox> {
  /// 重试计数：换掉 [AnimatedImage] 的 key，逼它重新 resolve 一次。
  int _attempt = 0;
  late bool _failed = widget.failed;

  /// 真实下载进度（由 AnimatedImage 转发 chunk 事件）。
  ///
  /// 用 notifier 而不是 setState：一个 chunk 事件只该让那颗环重生，不该把
  /// 整个封面（含 RawImage 分支）重刷 —— 一张封面有 20–30 个 chunk。
  final ValueNotifier<ImageChunkEvent?> _progress =
      ValueNotifier<ImageChunkEvent?>(null);

  /// 慢网抖动的一次性自动重试。
  ///
  /// 卡片封面走 `failFast: true`（不做 1/2/4/8 秒退避，避免慢网下把并发槽
  /// 占满），代价是一次瞬断就永久缺图 —— 用户看到的就是「首字占位一直不变」，
  /// 分不清是在等还是已经失败。这里补一次带抖动的自动重试：抖动能错开一屏
  /// 同时失败的十几张封面，不至于同一毫秒集体重发。
  Timer? _autoRetry;
  bool _autoRetried = false;

  @override
  void initState() {
    super.initState();
    CoverBox.generation.addListener(_onGeneration);
  }

  /// 整页刷新后，只让**失败**的封面重来：成功的封面在磁盘/内存缓存里，
  /// 再造一次只会白闪一下淡入动画。
  void _onGeneration() {
    if (!mounted || !_failed) return;
    _autoRetry?.cancel();
    _autoRetried = false;
    _progress.value = null;
    // 和手动重试走同一条路：先 evict 掉内存里那份失败的 completer，否则
    // 新 State 重新 resolve 时会直接拿到缓存的失败结果，看起来像没重试。
    widget.image?.evict();
    setState(() {
      _failed = false;
      _attempt++;
    });
  }

  @override
  void didUpdateWidget(CoverBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _failed = widget.failed;
      _attempt = 0;
      _autoRetried = false;
      _progress.value = null;
      _autoRetry?.cancel();
    } else if (widget.failed != oldWidget.failed) {
      _failed = widget.failed;
    }
  }

  @override
  void dispose() {
    CoverBox.generation.removeListener(_onGeneration);
    _autoRetry?.cancel();
    _progress.dispose();
    super.dispose();
  }

  void _autoRetryOnce() {
    if (_autoRetried) return;
    _autoRetried = true;
    // 900–1600ms 的确定性抖动：同一屏里失败的封面会各自错开，不会形成
    // 「一次失败 → 同时重发」的尖峰。
    final delayMs = 900 + (_attempt * 137 + hashCode % 700);
    _autoRetry?.cancel();
    _autoRetry = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted || !_failed) return;
      _retry();
    });
  }

  void _retry() {
    // evict 只清内存缓存，App 自己的磁盘缩略图缓存保留 —— 磁盘有图时
    // 重试是一瞬间的事；真的没网，也只是再失败一次，不会更糟。
    widget.image?.evict();
    // 上一轮的 82% 不能留给新一轮，否则新请求还没吐字节就先显示旧进度。
    _progress.value = null;
    setState(() {
      _failed = false;
      _attempt++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final placeholder = CoverPlaceholder(
      label: widget.label,
      fontSize: widget.initialFontSize,
      showIcon: widget.showIcon,
    );

    if (image == null) return placeholder;

    return LayoutBuilder(
      builder: (context, constraints) {
        // AnimatedImage 内部是 loose 约束的 AnimatedSwitcher：只给 Stack 的
        // expand 约束不够，RawImage 会按图片固有尺寸居中绘制，容器上下露出
        // secondaryContainer 的浅粉底，看起来就是「封面框填充不满、上下都空」。
        // 把容器尺寸显式传给 AnimatedImage，BoxFit.cover 才有明确的填充目标。
        // unbounded 场景（少数无固定尺寸的调用方）传 null，保持原行为。
        final w = constraints.hasBoundedWidth ? constraints.maxWidth : null;
        final h = constraints.hasBoundedHeight ? constraints.maxHeight : null;
        // 环径跟着首字走（1.75×），既要套在字外面又要留出一圈空隙：
        // 1.45× 时环几乎贴着字的外框，看起来像「字被圈住」，不像加载指示。
        // 大卡上限提到 76：环心要塞「42%」三个字，60 太挤。
        final loadingPlaceholder = _CoverLoadingPlaceholder(
          label: widget.label,
          fontSize: widget.initialFontSize,
          showIcon: widget.showIcon,
          ringSize: (widget.initialFontSize * 1.75)
              .clamp(30.0, widget.showProgressPercent ? 76.0 : 60.0)
              .toDouble(),
          // 只有大卡接真实进度：小卡的 30dp 环放不下数字，变成一小段不动
          // 的弧反而像坏了，不如让它们统一转不确定环。
          progress: widget.showProgressPercent ? _progress : null,
          showPercent: widget.showProgressPercent,
        );
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            loadingPlaceholder,
            AnimatedImage(
              key: ValueKey('cover_${image.hashCode}_$_attempt'),
              image: image,
              width: w,
              height: h,
              fit: widget.fit,
              filterQuality: widget.filterQuality,
              cacheWidth: widget.cacheWidth,
              cacheHeight: widget.cacheHeight,
              // 占位由外层 Stack 提供；这里透明，避免把首字盖住。
              placeholder: const SizedBox.shrink(),
              errorWidget: const SizedBox.shrink(),
              onProgress: (event) {
                // 组件的 notifier 可能已被 dispose（封面刚好在这一帧被移除、
                // 而图片流还在回调）。直接写会抛「used after being disposed」。
                if (mounted) _progress.value = event;
              },
              onError: (_, __) {
                widget.onFailed?.call();
                if (!_failed && mounted) setState(() => _failed = true);
                _autoRetryOnce();
              },
            ),
            // 失败必须可见：以前只在 ≥90dp 的封面上给「重试」，小封面上
            // 失败和加载中长得一模一样，用户只能一直等一个永远不会来的图。
            if (_failed)
              Positioned(
                right: widget.retryable ? 8 : 0,
                bottom: widget.retryable ? 8 : 0,
                child: _CoverRetryButton(
                  onTap: _retry,
                  compact: !widget.retryable,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CoverRetryButton extends StatelessWidget {
  const _CoverRetryButton({required this.onTap, this.compact = false});

  final VoidCallback onTap;

  /// 小封面（列表 / 网格里的 90dp 以下）用紧凑圆点：pill 形态的「重试」两个字
  /// 在小封面上会盖住半张图，而这里只需要一个「可以点一下再试」的暗示。
  /// 视觉直径 24dp，外面套 34dp 的透明热区，手指才点得准。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = HugeIcon(
      icon: HugeIcons.strokeRoundedRefresh,
      size: 13,
      color: cs.onSurfaceVariant,
    );
    final panel = BoxDecoration(
      // 半透明面板：不管封面是深是浅，按钮都能读出来。
      color: cs.surface.withValues(alpha: 0.88),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: 0.6),
        width: 0.5,
      ),
    );

    if (compact) {
      // 紧凑圆点里没有文字，必须自己给语义标签：否则读屏只会念「按钮」，
      // 用户不知道点它会做什么（labeledTapTargetGuideline 也会判它不合规）。
      return Semantics(
        button: true,
        label: 'Retry'.tl,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: Container(
                width: 24,
                height: 24,
                decoration: panel.copyWith(
                  // 24dp 的方形容器配 24 半径 = 正圆（半径已到半宽）。
                  borderRadius: BorderRadius.circular(kcRadius24),
                ),
                child: Center(child: icon),
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(kcSpaceSm, 5, 10, 5),
        decoration: panel.copyWith(
          borderRadius: BorderRadius.circular(kcRadius22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 4),
            Text(
              'Retry'.tl,
              style: TextStyle(fontSize: kcFont11, color: cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
