part of 'components.dart';

class Appbar extends StatefulWidget implements PreferredSizeWidget {
  const Appbar({
    required this.title,
    this.leading,
    this.actions,
    this.backgroundColor,
    this.style = AppbarStyle.blur,
    super.key,
  });

  final Widget title;

  final Widget? leading;

  final List<Widget>? actions;

  final Color? backgroundColor;

  final AppbarStyle style;

  @override
  State<Appbar> createState() => _AppbarState();

  @override
  Size get preferredSize => const Size.fromHeight(56);
}

class _AppbarState extends State<Appbar> {
  ScrollNotificationObserverState? _scrollNotificationObserver;
  bool _scrolledUnder = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollNotificationObserver?.removeListener(_handleScrollNotification);
    _scrollNotificationObserver = ScrollNotificationObserver.maybeOf(context);
    _scrollNotificationObserver?.addListener(_handleScrollNotification);
  }

  @override
  void dispose() {
    if (_scrollNotificationObserver != null) {
      _scrollNotificationObserver!.removeListener(_handleScrollNotification);
      _scrollNotificationObserver = null;
    }
    super.dispose();
  }

  void _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        defaultScrollNotificationPredicate(notification)) {
      final bool oldScrolledUnder = _scrolledUnder;
      final ScrollMetrics metrics = notification.metrics;
      switch (metrics.axisDirection) {
        case AxisDirection.up:
          // Scroll view is reversed
          _scrolledUnder = metrics.extentAfter > 0;
        case AxisDirection.down:
          _scrolledUnder = metrics.extentBefore > 0;
        case AxisDirection.right:
        case AxisDirection.left:
          // Scrolled under is only supported in the vertical axis, and should
          // not be altered based on horizontal notifications of the same
          // predicate since it could be a 2D scroller.
          break;
      }

      if (_scrolledUnder != oldScrolledUnder) {
        setState(() {
          // React to a change in MaterialState.scrolledUnder
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 与 SliverAppbar 对齐：侧栏面板内玻璃态会把面板内容糊进标题栏、并在左缘透出
    // 一道灰白色带，统一退回实心头（底色由 kcAppbarOpaqueColor 解析为面板同色）。
    final effectiveStyle = ModalRoute.of(context) is SideBarRoute
        ? AppbarStyle.shadow
        : widget.style;
    // 玻璃 tint 必须与页面底色同源：半透明的白/黑叠在页面底色上会被「提亮 / 压暗」，
    // 静止时就在顶栏下缘留下一条明显色带（浅色白 0.66 叠在 surface#FAF8FF 上偏亮）。
    // 用 scaffoldBackgroundColor 做基色，合成结果正好等于页面底色，滚动时仍可透出内容。
    final base = Theme.of(context).scaffoldBackgroundColor;
    final barTint = widget.backgroundColor ??
        base.withValues(alpha: isDark ? 0.54 : 0.66);
    // 背景完全透明时不套模糊：模糊会把弹窗背后的页面内容糊进标题栏，
    // 在对话框上表现为一块与内容区色差明显的灰白色块（ContentDialog 即如此）。
    final transparentBackground = barTint.a == 0;
    var content = Container(
      decoration: BoxDecoration(color: barTint),
      height: _kAppBarHeight + context.padding.top,
      child: Row(
        children: [
          const SizedBox(width: 8),
          widget.leading ??
              Tooltip(
                message: "Back".tl,
                child: IconButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, size: 18),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
          const SizedBox(
            width: 16,
          ),
          Expanded(
            child: DefaultTextStyle(
              style: DefaultTextStyle.of(context).style.copyWith(
                    fontSize: kcAppbarTitle,
                    fontWeight: FontWeight.w600,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: widget.title,
            ),
          ),
          ...?widget.actions,
          const SizedBox(
            width: 8,
          )
        ],
      ).paddingTop(context.padding.top),
    );
    if (effectiveStyle == AppbarStyle.shadow || transparentBackground) {
      return Material(
        // 半透明 tint 只用于玻璃态；实心/透明态一律用解析出的不透明底色，
        // 避免半透明白叠在面板底色上被提亮成一条色带。
        color: kcAppbarOpaqueColor(context, widget.backgroundColor),
        elevation: _scrolledUnder ? 2 : 0,
        child: content,
      );
    } else {
      // 真磨砂顶栏：BackdropFilter 模糊背后内容 + 半透明 tint，对齐底栏玻璃质感。
      // 滚动中降级为纯 tint（省掉每帧模糊），停止后恢复，见 KcGlassActivity。
      return ValueListenableBuilder<bool>(
        valueListenable: KcGlassActivity.scrolling,
        builder: (context, scrolling, _) {
          Widget bar = content;
          if (!scrolling) {
            bar = BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: bar,
            );
          }
          return ClipRect(child: bar);
        },
      );
    }
  }
}

enum AppbarStyle {
  blur,
  shadow,
}

/// 顶栏「不透明底色」的解析规则。
///
/// - 侧栏面板（[SideBarRoute]）的面板底色是 `colorScheme.surface`，顶栏必须同色，
///   否则会像一块浅色贴纸浮在面板上。此前一律用 `scaffoldBackgroundColor`（浅色纯白），
///   与 surface（浅色下约 #FAF8FF）差 3~5 个色阶，肉眼就是一条分层色带。
/// - 其余场景沿用页面底色 `scaffoldBackgroundColor`，与内容区无缝。
Color kcAppbarOpaqueColor(BuildContext context, [Color? background]) {
  if (background != null) return background;
  if (ModalRoute.of(context) is SideBarRoute) {
    return Theme.of(context).colorScheme.surface;
  }
  return Theme.of(context).scaffoldBackgroundColor;
}

class SliverAppbar extends StatelessWidget {
  const SliverAppbar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.radius = 0,
    this.style = AppbarStyle.blur,
    this.backgroundColor,
  });

  final Widget? leading;

  final Widget title;

  final List<Widget>? actions;

  final double radius;

  final AppbarStyle style;

  /// 实心（shadow）样式下的头部底色。默认沿用 scaffoldBackgroundColor；
  /// 放进居中浮层时传 surfaceContainerHigh，让固定头部与卡片底色一致，
  /// 否则头部会像一块贴在卡片上的浅色贴纸。
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    // 侧栏（SideBarRoute）内 AppBar 紧贴着同底色的面板内容，玻璃态
    // （半透明白 0.66 + BackdropFilter 模糊）在这里会与内容区形成明显色块分层：
    // 标题栏看起来「浮」在面板上，左缘还多出一道由模糊内容透出的灰白渐变色带。
    // 侧栏内退回不透明样式，与面板底色（colorScheme.surface / 全局 bg 同为纯白）一致。
    final effectiveStyle =
        ModalRoute.of(context) is SideBarRoute ? AppbarStyle.shadow : style;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _MySliverAppBarDelegate(
        leading: leading,
        title: title,
        actions: actions,
        topPadding: MediaQuery.of(context).padding.top,
        radius: radius,
        style: effectiveStyle,
        backgroundColor: backgroundColor,
      ),
    );
  }
}

const _kAppBarHeight = 52.0;

class _MySliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget? leading;

  final Widget title;

  final List<Widget>? actions;

  final double topPadding;

  final double radius;

  final AppbarStyle style;

  final Color? backgroundColor;

  _MySliverAppBarDelegate({
    this.leading,
    required this.title,
    this.actions,
    required this.topPadding,
    this.radius = 0,
    this.style = AppbarStyle.blur,
    this.backgroundColor,
  });

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    var body = Row(
      children: [
        const SizedBox(width: 8),
        leading ??
            (Navigator.of(context).canPop()
                ? Tooltip(
                    message: "Back".tl,
                    child: IconButton(
                      icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, size: 18),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  )
                : const SizedBox()),
        const SizedBox(
          width: 16,
        ),
        Expanded(
          child: DefaultTextStyle(
            style: DefaultTextStyle.of(context).style.copyWith(
                  fontSize: kcAppbarTitle,
                  fontWeight: FontWeight.w600,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: title,
          ),
        ),
        ...?actions,
        const SizedBox(
          width: 8,
        )
      ],
    ).paddingTop(topPadding);

    if (style == AppbarStyle.blur) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      // 同 Appbar：tint 以页面底色为基色，否则会与内容区形成一条色带分层。
      final base = Theme.of(context).scaffoldBackgroundColor;
      final tint = base.withValues(alpha: isDark ? 0.54 : 0.66);
      return SizedBox.expand(
        child: ValueListenableBuilder<bool>(
          valueListenable: KcGlassActivity.scrolling,
          builder: (context, scrolling, _) {
            // 滚动中把 tint 加厚并去掉模糊：可读性反而更好，且省掉每帧高斯模糊。
            final effectiveTint =
                scrolling ? base.withValues(alpha: isDark ? 0.74 : 0.88) : tint;
            Widget bar = Material(
              color: effectiveTint,
              elevation: 0,
              borderRadius: BorderRadius.circular(radius),
              child: body,
            );
            if (!scrolling) {
              bar = BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: bar,
              );
            }
            return ClipRect(child: bar);
          },
        ),
      );
    } else {
      return SizedBox.expand(
        child: Material(
          color: kcAppbarOpaqueColor(context, backgroundColor),
          elevation: shrinkOffset == 0 ? 0 : 2,
          borderRadius: BorderRadius.circular(radius),
          child: body,
        ),
      );
    }
  }

  @override
  double get maxExtent => _kAppBarHeight + topPadding;

  @override
  double get minExtent => _kAppBarHeight + topPadding;

  @override
  bool shouldRebuild(SliverPersistentHeaderDelegate oldDelegate) {
    return oldDelegate is! _MySliverAppBarDelegate ||
        leading != oldDelegate.leading ||
        title != oldDelegate.title ||
        actions != oldDelegate.actions ||
        topPadding != oldDelegate.topPadding ||
        radius != oldDelegate.radius ||
        style != oldDelegate.style ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}

class AppTabBar extends StatefulWidget {
  const AppTabBar({
    super.key,
    this.controller,
    required this.tabs,
    this.actionButton,
    this.withUnderLine = true,
  });

  final TabController? controller;

  final List<Tab> tabs;

  final Widget? actionButton;

  final bool withUnderLine;

  @override
  State<AppTabBar> createState() => _AppTabBarState();
}

class _AppTabBarState extends State<AppTabBar> {
  late TabController _controller;

  /// `_controller` 是否已挂上 [onTabChanged]。
  ///
  /// `didChangeDependencies` 会被多次调用，而 `ChangeNotifier.addListener` 对同一
  /// 回调**不去重**；无条件 add 会累积多份，dispose 又只能摘掉一份，等于泄漏。
  bool _controllerBound = false;

  late List<GlobalKey> keys;

  static const _kTabHeight = 48.0;

  static const tabPadding = EdgeInsets.symmetric(horizontal: 6, vertical: 6);

  static const tabRadius = 16.0;

  _IndicatorPainter? painter;

  var scrollController = ScrollController();

  var tabBarKey = GlobalKey();

  var offsets = <double>[];

  @override
  void initState() {
    keys = widget.tabs.map((e) => GlobalKey()).toList();
    super.initState();
  }

  @override
  void dispose() {
    // 先摘监听再 super.dispose()：onTabChanged 里会走 PageStorage.of(context)，
    // widget 失效后再回调会抛「Looking up a deactivated widget's ancestor」。
    if (_controllerBound) {
      _controller.animation?.removeListener(onTabChanged);
    }
    scrollController.dispose();
    super.dispose();
  }

  /// 绑定（或换绑）TabController 的动画监听，保证「同一 controller 不重复注册、
  /// 换 controller 时先摘旧的」。
  void _bindController(TabController next) {
    if (_controllerBound && identical(next, _controller)) return;
    if (_controllerBound) {
      _controller.animation?.removeListener(onTabChanged);
    }
    _controller = next;
    _controller.animation!.addListener(onTabChanged);
    _controllerBound = true;
  }

  PageStorageBucket get bucket => PageStorage.of(context);

  @override
  void didChangeDependencies() {
    _bindController(widget.controller ?? DefaultTabController.of(context));
    initPainter();
    super.didChangeDependencies();
    var prevIndex = bucket.readState(context) as int?;
    if (prevIndex != null &&
        prevIndex != _controller.index &&
        prevIndex >= 0 &&
        prevIndex < widget.tabs.length) {
      _controller.index = prevIndex;
    }
  }

  @override
  void didUpdateWidget(covariant AppTabBar oldWidget) {
    if (widget.controller != oldWidget.controller) {
      _bindController(widget.controller ?? DefaultTabController.of(context));
      initPainter();
    }
    super.didUpdateWidget(oldWidget);
  }

  void initPainter() {
    var old = painter;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    painter = _IndicatorPainter(
      controller: _controller,
      // 选中胶囊走品牌红：AMOLED 的灰阶 primary 会把它做成一颗近白色药丸，
      // 纯黑底上又亮又平；红色既是全站唯一强调色，也能和阅读 CTA / 开关同源。
      color: kcAccentColor(context),
      // 红底上必须配白字：AMOLED 的 onPrimary 是黑，红底黑字既脏又只有 4.3:1。
      glow: isDark,
      padding: tabPadding,
      radius: tabRadius,
    );
    if (old != null && old.offsets != null && old.itemHeight != null) {
      painter!.update(old.offsets!, old.itemHeight!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller.animation ?? _controller,
      builder: buildTabBar,
    );
  }

  void _tabLayoutCallback(List<double> offsets, double itemHeight) {
    painter!.update(offsets, itemHeight);
    this.offsets = offsets;
  }

  Widget buildTabBar(BuildContext context, Widget? _) {
    var child = SmoothScrollProvider(
      controller: scrollController,
      builder: (context, controller, physics) {
        return SingleChildScrollView(
          key: const PageStorageKey('scroll'),
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          controller: controller,
          physics: physics is BouncingScrollPhysics
              ? const ClampingScrollPhysics()
              : physics,
          child: CustomPaint(
            painter: painter,
            child: _TabRow(
              callback: _tabLayoutCallback,
              children: List.generate(widget.tabs.length, buildTab)
                ..addIfNotNull(widget.actionButton?.padding(tabPadding)),
            ),
          ).paddingHorizontal(4),
        );
      },
    );
    return Container(
      key: tabBarKey,
      height: _kTabHeight,
      width: double.infinity,
      decoration: widget.withUnderLine
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: context.colorScheme.outlineVariant,
                  width: 0.6,
                ),
              ),
            )
          : null,
      child: widget.tabs.isEmpty ? const SizedBox() : child,
    );
  }

  int? previousIndex;

  void onTabChanged() {
    final int i = _controller.index;
    if (i == previousIndex) {
      return;
    }
    updateScrollOffset(i);
    previousIndex = i;
    bucket.writeState(context, i);
  }

  void updateScrollOffset(int i) {
    // try to scroll to center the tab
    final RenderBox tabBarBox =
        tabBarKey.currentContext!.findRenderObject() as RenderBox;
    final double tabLeft = offsets[i];
    final double tabRight = offsets[i + 1];
    final double tabWidth = tabRight - tabLeft;
    final double tabCenter = tabLeft + tabWidth / 2;
    final double tabBarWidth = tabBarBox.size.width;
    double scrollOffset = tabCenter - tabBarWidth / 2;
    if (scrollOffset == scrollController.offset) {
      return;
    }
    scrollOffset = scrollOffset.clamp(
      0.0,
      scrollController.position.maxScrollExtent,
    );
    scrollController.animateTo(
      scrollOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  void onTabClicked(int i) {
    _controller.animateTo(i);
  }

  Widget buildTab(int i) {
    return InkWell(
      onTap: () => onTabClicked(i),
      borderRadius: BorderRadius.circular(tabRadius),
      // 禁用点击高亮 splash，避免切 tab 滑动时残留圆角矩形“框”
      splashFactory: NoSplash.splashFactory,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      child: KeyedSubtree(
        key: keys[i],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DefaultTextStyle(
                style: DefaultTextStyle.of(context).style.copyWith(
                  color: i == _controller.animation?.value.round()
                      ? kcOnAccentColor
                      : context.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
            child: widget.tabs[i],
          ),
        ),
      ),
    ).padding(tabPadding);
  }
}

typedef _TabRenderCallback = void Function(
  List<double> offsets,
  double itemHeight,
);

class _TabRow extends Row {
  const _TabRow({required this.callback, required super.children});

  final _TabRenderCallback callback;

  @override
  RenderFlex createRenderObject(BuildContext context) {
    return _RenderTabFlex(
        direction: Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        textDirection: Directionality.of(context),
        verticalDirection: VerticalDirection.down,
        callback: callback);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderTabFlex renderObject) {
    super.updateRenderObject(context, renderObject);
    renderObject.callback = callback;
  }
}

class _RenderTabFlex extends RenderFlex {
  _RenderTabFlex({
    required super.direction,
    required super.mainAxisSize,
    required super.mainAxisAlignment,
    required super.crossAxisAlignment,
    required TextDirection super.textDirection,
    required super.verticalDirection,
    required this.callback,
  });

  _TabRenderCallback callback;

  @override
  void performLayout() {
    super.performLayout();
    RenderBox? child = firstChild;
    final List<double> xOffsets = <double>[];
    while (child != null) {
      final FlexParentData childParentData =
          child.parentData! as FlexParentData;
      xOffsets.add(childParentData.offset.dx);
      assert(child.parentData == childParentData);
      child = childParentData.nextSibling;
    }
    xOffsets.add(size.width);
    callback(xOffsets, firstChild!.size.height);
  }
}

class _IndicatorPainter extends CustomPainter {
  _IndicatorPainter({
    required this.controller,
    required this.color,
    required this.padding,
    this.radius = 4.0,
    this.glow = false,
  }) : super(repaint: controller.animation);

  final TabController controller;
  final Color color;
  final EdgeInsets padding;
  final double radius;

  /// 暗色下在胶囊外叠一圈极淡红晕：纯黑背景里，纯色块会显得「贴」在底上，
  /// 一点点光晕就能把选中态抬起来（亮色背景不需要，会显脏）。
  final bool glow;

  List<double>? offsets;
  double? itemHeight;
  Rect? _currentRect;

  void update(List<double> offsets, double itemHeight) {
    this.offsets = offsets;
    this.itemHeight = itemHeight;
  }

  int get maxTabIndex => offsets!.length - 2;

  Rect indicatorRect(Size tabBarSize, int tabIndex) {
    assert(offsets != null);
    assert(offsets!.isNotEmpty);
    assert(tabIndex >= 0);
    assert(tabIndex <= maxTabIndex);
    var (tabLeft, tabRight) = (offsets![tabIndex], offsets![tabIndex + 1]);

    // 胶囊背景块：高度固定、垂直居中于 tab，左右紧贴文字留少量边距，
    // 替代原 3px 底部横线，在长列表 + 暗色背景下更醒目。
    // 收窄高宽比，避免短标签（如"本地"）渲染成接近方形的圆角块。
    const horizontalInset = 8.0;
    const blockHeight = 32.0;
    const top = (_AppTabBarState._kTabHeight - blockHeight) / 2;

    var rect = Rect.fromLTWH(
      tabLeft + padding.left + horizontalInset,
      top,
      tabRight - tabLeft - padding.horizontal - horizontalInset * 2,
      blockHeight,
    );

    return rect;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (offsets == null || itemHeight == null) {
      return;
    }
    final double index = controller.index.toDouble();
    final double value = controller.animation!.value;
    final bool ltr = index > value;
    final int from = (ltr ? value.floor() : value.ceil()).clamp(0, maxTabIndex);
    final int to = (ltr ? from + 1 : from - 1).clamp(0, maxTabIndex);
    final Rect fromRect = indicatorRect(size, from);
    final Rect toRect = indicatorRect(size, to);
    _currentRect = Rect.lerp(fromRect, toRect, (value - from).abs());
    final RRect rrect = RRect.fromRectAndRadius(
      _currentRect!,
      Radius.circular(_currentRect!.height / 2),
    );
    if (glow) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawRRect(rrect, glowPaint);
    }
    // 上亮下暗的微渐变：胶囊有了一点「受光」的体积，不再是一块死平的色块。
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(color, Colors.white, 0.08)!,
          Color.lerp(color, Colors.black, 0.06)!,
        ],
      ).createShader(_currentRect!);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class TabViewBody extends StatefulWidget {
  /// Create a tab view body, which will show the child at the current tab index.
  const TabViewBody({super.key, required this.children, this.controller});

  final List<Widget> children;

  final TabController? controller;

  @override
  State<TabViewBody> createState() => _TabViewBodyState();
}

class _TabViewBodyState extends State<TabViewBody> {
  late TabController _controller;

  /// 同 `_AppTabBarState._controllerBound`：避免重复注册 / 漏摘旧 controller。
  bool _controllerBound = false;

  int _currentIndex = 0;

  void updateIndex() {
    if (!mounted) return;
    if (_controller.index != _currentIndex) {
      setState(() {
        _currentIndex = _controller.index;
      });
    }
  }

  void _bindController(TabController next) {
    if (_controllerBound && identical(next, _controller)) return;
    if (_controllerBound) {
      _controller.removeListener(updateIndex);
    }
    _controller = next;
    _currentIndex = _controller.index;
    _controller.addListener(updateIndex);
    _controllerBound = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindController(widget.controller ?? DefaultTabController.of(context));
  }

  @override
  void didUpdateWidget(covariant TabViewBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _bindController(widget.controller ?? DefaultTabController.of(context));
    }
  }

  @override
  void dispose() {
    if (_controllerBound) {
      _controller.removeListener(updateIndex);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.children[_currentIndex];
  }
}

class SearchBarController {
  _SearchBarMixin? _state;

  final void Function(String text)? onSearch;

  String currentText;

  void setText(String text) {
    _state?.setText(text);
  }

  String get text => _state?.getText() ?? '';

  set text(String text) {
    setText(text);
  }

  SearchBarController({this.onSearch, this.currentText = ''});
}

abstract mixin class _SearchBarMixin {
  void setText(String text);

  String getText();
}

class SliverSearchBar extends StatefulWidget {
  const SliverSearchBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.action,
    this.focusNode,
  });

  final SearchBarController controller;

  final void Function(String)? onChanged;

  final Widget? action;

  final FocusNode? focusNode;

  @override
  State<SliverSearchBar> createState() => _SliverSearchBarState();
}

class _SliverSearchBarState extends State<SliverSearchBar>
    with _SearchBarMixin {
  late TextEditingController _editingController;

  late SearchBarController _controller;

  @override
  void initState() {
    _controller = widget.controller;
    _controller._state = this;
    _editingController = TextEditingController(text: _controller.currentText);
    super.initState();
  }

  @override
  void setText(String text) {
    _editingController.text = text;
  }

  @override
  String getText() {
    return _editingController.text;
  }

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _SliverSearchBarDelegate(
        editingController: _editingController,
        controller: _controller,
        topPadding: MediaQuery.of(context).padding.top,
        onChanged: widget.onChanged,
        action: widget.action,
        focusNode: widget.focusNode,
      ),
    );
  }

  @override
  void dispose() {
    _editingController.dispose();
    super.dispose();
  }
}

class _SliverSearchBarDelegate extends SliverPersistentHeaderDelegate {
  final TextEditingController editingController;

  final SearchBarController controller;

  final double topPadding;

  final void Function(String)? onChanged;

  final Widget? action;

  final FocusNode? focusNode;

  const _SliverSearchBarDelegate({
    required this.editingController,
    required this.controller,
    required this.topPadding,
    this.onChanged,
    this.action,
    this.focusNode,
  });

  static const _kAppBarHeight = 52.0;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: _kAppBarHeight + topPadding,
      width: double.infinity,
      padding: EdgeInsets.only(top: topPadding),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const BackButton(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextField(
                focusNode: focusNode,
                controller: editingController,
                decoration: InputDecoration(
                  hintText: "Search".tl,
                  border: InputBorder.none,
                ),
                onSubmitted: (text) {
                  controller.onSearch?.call(text);
                },
                onChanged: onChanged,
              ),
            ),
          ),
          ListenableBuilder(
            listenable: editingController,
            builder: (context, child) {
              return editingController.text.isEmpty
                  ? const SizedBox()
                  : IconButton(
                      iconSize: 20,
                      icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
                      onPressed: () {
                        editingController.clear();
                        onChanged?.call("");
                      },
                    );
            },
          ),
          if (action != null) action!,
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  double get maxExtent => _kAppBarHeight + topPadding;

  @override
  double get minExtent => _kAppBarHeight + topPadding;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return oldDelegate is! _SliverSearchBarDelegate ||
        editingController != oldDelegate.editingController ||
        controller != oldDelegate.controller ||
        topPadding != oldDelegate.topPadding;
  }
}

class AppSearchBar extends StatefulWidget {
  const AppSearchBar({super.key, required this.controller, this.action});

  final SearchBarController controller;

  final Widget? action;

  @override
  State<AppSearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<AppSearchBar> with _SearchBarMixin {
  late TextEditingController _editingController;

  late SearchBarController _controller;

  @override
  void setText(String text) {
    _editingController.text = text;
  }

  @override
  String getText() {
    return _editingController.text;
  }

  @override
  void initState() {
    _controller = widget.controller;
    _controller._state = this;
    _editingController = TextEditingController(text: _controller.currentText);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      height: _kAppBarHeight + topPadding,
      width: double.infinity,
      padding: EdgeInsets.only(top: topPadding),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const BackButton(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextField(
                controller: _editingController,
                decoration: InputDecoration(
                  hintText: "Search".tl,
                  border: InputBorder.none,
                ),
                onSubmitted: (text) {
                  _controller.onSearch?.call(text);
                },
              ),
            ),
          ),
          ListenableBuilder(
            listenable: _editingController,
            builder: (context, child) {
              return _editingController.text.isEmpty
                  ? const SizedBox()
                  : IconButton(
                      iconSize: 20,
                      icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
                      onPressed: () {
                        _editingController.clear();
                      },
                    );
            },
          ),
          if (widget.action != null) widget.action!,
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _editingController.dispose();
    super.dispose();
  }
}

class TabActionButton extends StatelessWidget {
  const TabActionButton({
    super.key,
    required this.icon,
    required this.text,
    required this.onPressed,
  });

  final Widget icon;

  final String text;

  final void Function() onPressed;

  static const _kTabHeight = 46.0;

  @override
  Widget build(BuildContext context) {
    // 次级动作：选中胶囊已经是整行的唯一红色焦点，右侧「+」再上红会抢戏，
    // 这里降为高对比的中性灰（不是禁用态那种发虚的灰）。
    final fg = context.colorScheme.onSurfaceVariant.withValues(alpha: 0.85);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(kcRadius8),
      child: Container(
        height: _kTabHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: IconTheme(
          data: IconThemeData(size: 20, color: fg),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 8),
              Text(text, style: ts.withColor(fg)),
            ],
          ),
        ),
      ),
    );
  }
}
