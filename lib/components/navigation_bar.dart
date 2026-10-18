part of 'components.dart';

class PaneItemEntry {
  String label;

  Widget icon;

  Widget activeIcon;

  PaneItemEntry({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

class PaneActionEntry {
  String label;

  Widget icon;

  VoidCallback onTap;

  /// 可选溢出菜单。提供时顶栏用 [PopupMenuButton] 渲染该操作，
  /// 否则用普通 [IconButton]。
  final List<PopupMenuEntry<dynamic>>? menu;

  final void Function(dynamic)? onSelected;

  PaneActionEntry({
    required this.label,
    required this.icon,
    required this.onTap,
    this.menu,
    this.onSelected,
  });
}

class NaviPane extends StatefulWidget {
  const NaviPane({
    required this.paneItems,
    required this.paneActions,
    required this.pageBuilder,
    this.initialPage = 0,
    this.onPageChanged,
    required this.observer,
    required this.navigatorKey,
    /// Page indices whose root tab already renders its own title/AppBar.
    /// On mobile, the shared top bar will still show [paneActions] but hide
    /// the duplicated title label for these tabs.
    this.topBarTitleHiddenPages = const [],
    super.key,
  });

  final List<PaneItemEntry> paneItems;

  final List<PaneActionEntry> paneActions;

  final Widget Function(int page) pageBuilder;

  final void Function(int index)? onPageChanged;

  /// Page indices that render their own AppBar title and should not show the
  /// duplicated title in the shared top bar on mobile.
  final List<int> topBarTitleHiddenPages;

  final int initialPage;

  final NaviObserver observer;

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<NaviPane> createState() => NaviPaneState();

  static NaviPaneState of(BuildContext context) {
    return context.findAncestorStateOfType<NaviPaneState>()!;
  }
}

typedef NaviItemTapListener = void Function(int);

class NaviPaneState extends State<NaviPane>
    // 必须用复数版：本 State 现在有两个 AnimationController（宽度分档 controller
    // + 收起导航 _chromeController）。SingleTickerProviderStateMixin 只允许一个
    // Ticker，再建第二个时 debug 模式会直接抛
    // "SingleTickerProviderStateMixin is already used as a TickerProvider"。
    with TickerProviderStateMixin {
  bool _canPop = true;

  /// 全屏页面（目前是阅读器）要求收起导航框架的**请求数**。
  ///
  /// 用计数而不是 bool：路由 replace 时新页面 init 早于旧页面 dispose，
  /// bool 会被旧页面的 dispose 误刷回「显示」，计数不会。
  /// 横屏手机宽度 > [changePoint] 时左侧栏常驻，全屏阅读会一直挤占画面
  /// （issue #3），这里让它滑动收起。
  int _chromeHideRequests = 0;

  bool get chromeHidden => _chromeHideRequests > 0;

  /// 0 = 导航框架正常显示，1 = 完全收起。
  late final AnimationController _chromeController = AnimationController(
    duration: const Duration(milliseconds: 200),
    value: 0,
    vsync: this,
  );

  /// 全屏页面进入/退出时调用，收起或恢复左侧栏与主视图左边距。
  void setChromeHidden(bool hidden) {
    // 阅读器 dispose 可能晚于本 State（例如应用正在退出），此时动画控制器
    // 已释放，再驱动它会抛断言。
    if (!mounted) return;
    if (hidden) {
      _chromeHideRequests++;
    } else if (_chromeHideRequests > 0) {
      _chromeHideRequests--;
    }
    final target = chromeHidden ? 1.0 : 0.0;
    if (_chromeController.value != target) {
      _chromeController.animateTo(target);
    }
  }

  /// Whether the current route is a root tab page (no inner page is shown).
  /// When true, the shared mobile top bar should be rendered.
  bool get showTopBarInMobile => _canPop;

  late int _currentPage = widget.initialPage;

  int get currentPage => _currentPage;

  set currentPage(int value) {
    if (value == _currentPage) return;
    _currentPage = value;
    widget.onPageChanged?.call(value);
    _pageNotifier.value = value;
  }

  void Function()? mainViewUpdateHandler;

  /// 当前页面可向全局顶栏注入的额外操作按钮（按页生效）。
  /// 例如历史页的多选/清空/刷新。为 null 时仅显示全局 [paneActions]。
  final pageActionsNotifier = ValueNotifier<List<PaneActionEntry>?>(null);

  void _onPageActionsChanged() {
    if (mounted) setState(() {});
  }

  late AnimationController controller;

  /// 当前页 notifier：直接驱动底栏「液体选中框」滑动，不依赖父级重建。
  final _pageNotifier = ValueNotifier<int>(0);

  final _naviItemTapListeners = <NaviItemTapListener>[];

  void addNaviItemTapListener(NaviItemTapListener listener) {
    _naviItemTapListeners.add(listener);
  }

  void removeNaviItemTapListener(NaviItemTapListener listener) {
    _naviItemTapListeners.remove(listener);
  }

  static const _kBottomBarHeight = 58.0;

  /// 底栏栏体的实际高度（随系统字体缩放自适应）。
  ///
  /// 每个 tab 的内容是「图标 22 + 间隙 3 + 文字」这一列，系统字体放大时它会变高。
  /// 1080×2400@420 + fontScale 1.8 实测：内容需要 54dp，而栏体扣掉上下各 4dp
  /// 内边距后只剩 50dp，5 个 tab 会一起抛
  /// 「RenderFlex overflowed by 4.0 pixels on the bottom」（见 navigation_bar.dart
  /// 的 buildContent）。所以栏体高度跟随文字缩放同步长高，上限 1.6 倍
  /// （对应 fontScale≈3.0 仍放得下），避免大字号下底栏把导航内容裁掉。
  double get bottomBarBodyHeight {
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    return _kBottomBarHeight * scale.clamp(1.0, 1.6);
  }

  /// 悬浮胶囊底栏四周的留白（浮岛式导航：不贴边、不贴底）。
  /// ⚠️ 改动这里的竖向值必须同步 [bottomBarHeight]，否则页面预留的底部
  /// 空间和底栏实际占位不一致，列表最后一项会被压在底栏下面。
  static const _kBottomBarMarginH = 14.0;
  static const _kBottomBarMarginV = 10.0;

  static const _kFoldedSideBarWidth = 72.0;

  static const _kSideBarWidth = 224.0;

  static const _kTopBarHeight = 48.0;

  /// 底栏**实际遮挡**的高度：栏体 + 下方留白 + 系统手势区。
  /// 页面（列表底部 padding、悬浮按钮）靠它给内容让位。
  double get bottomBarHeight =>
      bottomBarBodyHeight + _kBottomBarMarginV + MediaQuery.of(context).padding.bottom;

  /// 底栏外边距。底部额外留出系统手势区，避免胶囊压在手势条上。
  EdgeInsets bottomBarMargin(BuildContext context) => EdgeInsets.fromLTRB(
        _kBottomBarMarginH,
        _kBottomBarMarginV,
        _kBottomBarMarginH,
        _kBottomBarMarginV + MediaQuery.of(context).padding.bottom,
      );

  void onNavigatorStateChange() {
    onRebuild(context);
  }

  void updatePage(int index) {
    for (var listener in _naviItemTapListeners) {
      listener(index);
    }
    if (widget.observer.routes.length > 1) {
      widget.navigatorKey.currentState!.popUntil((route) => route.isFirst);
    }
    if (currentPage == index) {
      return;
    }
    setState(() {
      currentPage = index;
    });
    mainViewUpdateHandler?.call();
  }

  @override
  void initState() {
    controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      lowerBound: 0,
      upperBound: 3,
      vsync: this,
    );
    _pageNotifier.value = widget.initialPage;
    widget.observer.addListener(onNavigatorStateChange);
    pageActionsNotifier.addListener(_onPageActionsChanged);
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    _chromeController.dispose();
    _pageNotifier.dispose();
    widget.observer.removeListener(onNavigatorStateChange);
    pageActionsNotifier.removeListener(_onPageActionsChanged);
    super.dispose();
  }

  double targetFormContext(BuildContext context) {
    var width = MediaQuery.of(context).size.width;
    double target = 0;
    if (width > changePoint) {
      target = 2;
    }
    if (width > changePoint2) {
      target = 3;
    }
    return target;
  }

  double? animationTarget;

  void onRebuild(BuildContext context) {
    double target = targetFormContext(context);
    if (controller.value != target || animationTarget != target) {
      if (controller.isAnimating) {
        if (animationTarget == target) {
          return;
        } else {
          controller.stop();
        }
      }
      controller.animateTo(target);
      animationTarget = target;
    }
  }

  @override
  Widget build(BuildContext context) {
    onRebuild(context);
    return _NaviPopScope(
      action: () {
        if (App.mainNavigatorKey!.currentState!.canPop()) {
          App.mainNavigatorKey!.currentState!.maybePop();
        } else {
          SystemNavigator.pop();
        }
      },
      popGesture: App.isIOS && context.width >= changePoint,
      child: AnimatedBuilder(
        // 外层监听「收起导航」动画、内层监听宽度分档动画，任一变化都要重绘。
        // 不用 Listenable.merge 是避免每次 build 都新建 Listenable。
        animation: _chromeController,
        builder: (context, _) {
          return AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final value = controller.value;
              // hideProgress 0 → 1：左侧栏整条滑出屏幕，主视图补满全宽。
              final hideProgress = _chromeController.value;
              final sideBarWidth = _kFoldedSideBarWidth +
                  (_kSideBarWidth - _kFoldedSideBarWidth) *
                      ((value - 2.0).clamp(0.0, 1.0));
              final sideBarVisibleLeft =
                  _kFoldedSideBarWidth * ((value - 2.0).clamp(-1.0, 0.0));
              final sideBarLeft = sideBarVisibleLeft +
                  (-sideBarWidth - sideBarVisibleLeft) * hideProgress;
              final mainVisibleLeft =
                  _kFoldedSideBarWidth * ((value - 1).clamp(0, 1)) +
                  (_kSideBarWidth - _kFoldedSideBarWidth) *
                      ((value - 2).clamp(0, 1));
              final mainLeft = mainVisibleLeft * (1 - hideProgress);
              // 横屏安全区留白（刘海 / 手势区）。收起导航 = 全屏页面接管整屏，
              // 留白同步收缩到 0：否则侧栏滑出后左边仍会留下一条与侧栏几乎等宽
              // 的空白（看起来像"没收干净"），而且阅读器被挤在安全区里、相对
              // 整屏偏右。
              final mq = MediaQuery.of(context);
              final fullInsets =
                  (App.isMobile && mq.orientation == Orientation.landscape)
                  ? EdgeInsets.only(
                      left: math.max(
                        mq.viewPadding.left,
                        mq.systemGestureInsets.left,
                      ),
                      right: math.max(
                        mq.viewPadding.right,
                        mq.systemGestureInsets.right,
                      ),
                    )
                  : EdgeInsets.zero;
              final sideInsets = EdgeInsets.lerp(
                fullInsets,
                EdgeInsets.zero,
                hideProgress,
              )!;
              Widget content = Stack(
                children: [
                  Positioned(
                    left: sideBarLeft,
                    top: 0,
                    bottom: 0,
                    child: buildLeft(),
                  ),
                  Positioned.fill(
                    left: mainLeft,
                    // 主视图内部（Navigator → route → ModalBarrier）会设置
                    // BlockSemantics 来把「排在自己前面的兄弟」从语义树里清掉
                    // （见 modal_barrier.dart：ModalBarrier 用 BlockSemantics
                    // 包住 ExcludeSemantics）。这个「屏蔽前序兄弟」的标记会沿
                    // 语义树向上传播，直到撞上一个语义边界才停；而本 Stack 与
                    // 主视图之间没有任何边界，于是主视图反过来把左侧栏（同层、
                    // 排在它前面的兄弟）整条从语义树里抹掉 —— 这才是宽屏下
                    // 「左侧栏整条子树对 TalkBack / uiautomator 不可见」的真正
                    // 原因，跟侧栏自身有没有补 Semantics 无关。
                    // 修复：给主视图套一个语义边界（container），把内部的
                    // BlockSemantics 关在边界内，不再向上泄漏到 Stack。
                    child: Semantics(
                      container: true,
                      child: buildMainView(),
                    ),
                  ),
                ],
              );
              if (sideInsets != EdgeInsets.zero) {
                content = Padding(
                  padding: sideInsets,
                  child: content,
                );
              }
              return content;
            },
          );
        },
      ),
    );
  }

  Widget buildMainView() {
    return HeroControllerScope(
      controller: MaterialApp.createMaterialHeroController(),
      child:         PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) {
              return;
            }
            if (_canPop == false) {
              // 存在子页面，正常返回上一级
              widget.navigatorKey.currentState?.maybePop(result);
              return;
            }
            // 已在根页面（无子页面），处理退出确认
            if (appdata.settings['exitConfirm'] != true) {
              SystemNavigator.pop();
              return;
            }
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => const _ExitConfirmDialog(),
            );
            if (confirm == true) {
              SystemNavigator.pop();
            }
          },
        child: NotificationListener<Notification>(
          onNotification: (Notification notification) {
            // 滚动中把玻璃降级为实色（省掉每帧背景模糊），见 KcGlassActivity。
            if (notification is ScrollNotification) {
              KcGlassActivity.markScrolling();
            } else if (notification is NavigationNotification) {
              final bool nextCanPop = !notification.canHandlePop;
              if (nextCanPop != _canPop) {
                setState(() {
                  _canPop = nextCanPop;
                });
              }
            }
            return false;
          },
          child: Navigator(
            observers: [widget.observer],
            key: widget.navigatorKey,
            onGenerateRoute: (settings) => AppPageRoute(
              preventRebuild: false,
              builder: (context) {
                return _NaviMainView(state: this);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget buildMainViewContent() {
    return widget.pageBuilder(currentPage);
  }

  Widget buildTop() {
    final hideTitle = widget.topBarTitleHiddenPages.contains(currentPage);
    final pageActions = pageActionsNotifier.value;
    final actions = [
      if (pageActions != null) ...pageActions,
      ...widget.paneActions,
    ];
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Container(
        padding: const EdgeInsets.only(left: 16, right: 16),
        height: _kTopBarHeight,
        width: double.infinity,
        child: Row(
          children: [
            if (!hideTitle)
              Expanded(
                child: Text(
                  widget.paneItems[currentPage].label,
                  style: TextStyle(fontSize: kcTitleMain, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Spacer(),
            for (var action in actions)
              if (action.menu != null)
                Tooltip(
                  message: action.label,
                  child: PopupMenuButton<dynamic>(
                    icon: action.icon,
                    itemBuilder: (_) => action.menu!,
                    onSelected: action.onSelected,
                  ),
                )
              else
                Tooltip(
                  message: action.label,
                  child: IconButton(
                    icon: action.icon,
                    onPressed: action.onTap,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget buildBottom(BuildContext context) {
    return GlassBottomBar(
      height: bottomBarBodyHeight,
      edgeToEdge: true,
      // ColorOS 17 浮岛式导航：胶囊底栏悬浮在内容之上，两侧与底部留白，
      // 而非全宽贴边，强化「轻盈、分层」的视觉。
      margin: bottomBarMargin(context),
      indicator: (width) => _LiquidIndicator(
        pageListenable: _pageNotifier,
        count: widget.paneItems.length,
        width: width,
        // 药丸高度与栏体同步（保持 44/58 的比例），否则大字号下底栏长高了、
        // 选中药丸还是原来那个小尺寸，观感会很别扭。
        height: bottomBarBodyHeight * 44 / _kBottomBarHeight,
      ),
      children: [
        ...List<Widget>.generate(widget.paneItems.length, (index) {
          return Expanded(
            child: _SingleBottomNaviWidget(
              enabled: currentPage == index,
              entry: widget.paneItems[index],
              onTap: () {
                updatePage(index);
              },
              key: ValueKey(index),
            ),
          );
        }),
      ],
    );
  }

  Widget buildLeft() {
    final value = controller.value;
    const paddingHorizontal = 12.0;
    return Material(
      child: Container(
        width:
            _kFoldedSideBarWidth +
            (_kSideBarWidth - _kFoldedSideBarWidth) * ((value - 2).clamp(0, 1)),
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 1.0,
            ),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 16),
            SizedBox(height: MediaQuery.of(context).padding.top),
            // 侧栏内容的总高度并不固定：main_page 会按当前页额外注入一个动作
            // （收藏页的「切换列表/网格视图」，见 _showLayoutToggle），于是
            // 动作区在 2 项和 3 项之间浮动，每项 46dp。
            // 横屏手机的高度只有 ~400dp：891x411dp 的折叠侧栏遇到 3 个动作时
            // 5 个入口 + 3 个动作 + 上下留白共需 ~432dp，实测抛
            // 「RenderFlex overflowed by 17 pixels on the bottom」。
            //
            // 这里把入口区改成可滚动、动作区固定在底部：空间足够时 Expanded
            // 占据剩余空间、把动作压到底，观感与原 Spacer 完全一致；空间不够时
            // 入口区可上下滚动，而不是把整个 Column 顶破。
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List<Widget>.generate(
                    widget.paneItems.length,
                    (index) => _SideNaviWidget(
                      enabled: currentPage == index,
                      entry: widget.paneItems[index],
                      showTitle: value == 3,
                      onTap: () {
                        updatePage(index);
                      },
                      key: ValueKey(index),
                    ),
                  ),
                ),
              ),
            ),
            ...List<Widget>.generate(
              widget.paneActions.length,
              (index) => _PaneActionWidget(
                entry: widget.paneActions[index],
                showTitle: value == 3,
                key: ValueKey(index + widget.paneItems.length),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SideNaviWidget extends StatelessWidget {
  const _SideNaviWidget({
    required this.enabled,
    required this.entry,
    required this.onTap,
    required this.showTitle,
    super.key,
  });

  final bool enabled;

  final PaneItemEntry entry;

  final VoidCallback onTap;

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = enabled ? entry.activeIcon : entry.icon;
    // 宽屏（>changePoint）下导航由底部胶囊换成左侧栏，而左侧栏整条子树默认
    // 不会进入语义树 —— 实测 1706x1066dp 的平板界面上，侧栏 5 个入口对
    // uiautomator / TalkBack 完全不可见（底部导航却正常暴露）。
    // 结果是用读屏软件的平板/横屏用户根本没有导航可用。
    //
    // 根因：单纯给节点补 label/button/onTap 不够。Flutter 里
    // `excludeSemantics:true` 只让节点「排除子树」，并不会让它成为语义边界
    // （语义边界由 `container` 或 `identifier` 决定，见 rendering/object.dart
    // 的 `isSemanticBoundary = container || identifier != null`）。缺少边界时
    // 该节点的 label/onTap 会被合并到最近的边界祖先（这里是根节点）而丢失。
    // 所以这里必须 `container:true` 让它成为独立语义节点，再用
    // `excludeSemantics:true` 排除内部 Text，避免折叠态/展开态重复朗读。
    return Semantics(
      container: true,
      label: entry.label,
      button: true,
      selected: enabled,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(kcCardRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppAnimations.duration(const Duration(milliseconds: 260)),
          curve: kcSpring,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          height: 38,
          decoration: BoxDecoration(
            color: enabled ? colorScheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(kcCardRadius),
          ),
          child: showTitle
              ? Row(
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(entry.label, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                )
              : Align(alignment: Alignment.centerLeft, child: icon),
        ),
      ),
    ).paddingVertical(4);
  }
}

class _PaneActionWidget extends StatelessWidget {
  const _PaneActionWidget({
    required this.entry,
    required this.showTitle,
    super.key,
  });

  final PaneActionEntry entry;

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final icon = entry.icon;
    // 同 _SideNaviWidget：侧栏里的动作项（搜索/切换视图等）也要补语义节点，
    // 否则宽屏下读屏用户同样看不到这些入口。同样需要 container:true 成为
    // 独立语义边界，否则 label/onTap 会被合并到根节点而丢失。
    return Semantics(
      container: true,
      label: entry.label,
      button: true,
      onTap: entry.onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: entry.onTap,
        borderRadius: BorderRadius.circular(kcCardRadius),
        child: AnimatedContainer(
          duration: AppAnimations.duration(const Duration(milliseconds: 260)),
          curve: kcSpring,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          height: 38,
          child: showTitle
              ? Row(
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(entry.label, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                )
              : Align(alignment: Alignment.centerLeft, child: icon),
        ),
      ),
    ).paddingVertical(4);
  }
}

class _SingleBottomNaviWidget extends StatefulWidget {
  const _SingleBottomNaviWidget({
    required this.enabled,
    required this.entry,
    required this.onTap,
    super.key,
  });

  final bool enabled;

  final PaneItemEntry entry;

  final VoidCallback onTap;

  @override
  State<_SingleBottomNaviWidget> createState() =>
      _SingleBottomNaviWidgetState();
}

class _SingleBottomNaviWidgetState extends State<_SingleBottomNaviWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;

  bool isHovering = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SingleBottomNaviWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled) {
        controller.forward(from: 0);
      } else {
        controller.reverse(from: 1);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      value: widget.enabled ? 1 : 0,
      vsync: this,
      duration: AppAnimations.duration(const Duration(milliseconds: 160)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: CurvedAnimation(parent: controller, curve: kcSpring),
      builder: (context, child) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (details) => setState(() => isHovering = true),
          onExit: (details) => setState(() => isHovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onTap,
            child: buildContent(),
          ),
        );
      },
    );
  }

  Widget buildContent() {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = widget.enabled;
    final icon = isActive ? widget.entry.activeIcon : widget.entry.icon;
    final activeClr = colorScheme.primary;
    // 贴吧里未选中是接近纯黑/纯白的高对比色（alpha 0.80），而不是发灰的 secondary，
    // 这样「选中=蓝色药丸」和「未选中=实色图标」的对比才够干脆。
    final inactiveClr = colorScheme.onSurface.withValues(alpha: 0.80);

    // 贴吧式选中态：一颗实心胶囊药丸，把图标和文字一起包住。
    // 旧实现是 56×56 的淡色圆形色斑，只在图标外圈晕一点色，观感差很远。
    return Center(
      child: AnimatedContainer(
        duration: AppAnimations.duration(const Duration(milliseconds: 260)),
        curve: kcSpring,
        // 横向 padding 从 16 收到 10：448dp 宽的手机屏（如 1344×2992@480）分 5 格
        // 后每格约 83dp，16 的 padding 只剩 51dp，11sp 的 "Categories"（约 57dp）
        // 放不下，会在底部导航里溢出约 7px（文字被裁成 "Categorie"）。
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          // 选中态背景交给底栏的「液体选中框」滑动药丸（_LiquidIndicator），
          // 这里只保留文字/图标的高亮色，避免两层背景叠加。
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                isActive ? activeClr : inactiveClr,
                BlendMode.srcIn,
              ),
              child: SizedBox(width: 22, height: 22, child: icon),
            ),
            const SizedBox(height: 3),
            // 更长的标签（或更大字号/更窄的屏）再兜一层：缩放到格子内，
            // 短标签不受影响，避免出现省略号或裁字。
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.entry.label,
                maxLines: 1,
                style: TextStyle(
                  // 底栏标签跟 M3 规范对齐到 12sp（原本 11sp 偏小，与正文辅助层
                  // kcCaption 一致）；外层有 FittedBox(scaleDown)，窄屏也不会溢出。
                  fontSize: kcCaption,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive ? activeClr : inactiveClr,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底栏「液体选中框」：一颗胶囊药丸在等宽 item 间弹性滑动，移动途中横向
/// 微拉伸模拟液体。背景由它提供，item 自身只负责图标/文字高亮。
class _LiquidIndicator extends StatelessWidget {
  /// 当前页监听：页面变化时自动弹性滑到对应格。
  final ValueNotifier<int> pageListenable;
  final int count;

  /// 底栏内容宽度（由 GlassBottomBar 的 LayoutBuilder 测得）。
  final double width;

  /// 药丸高度，跟随栏体高度自适应（大字号下栏体变高）。
  final double height;

  const _LiquidIndicator({
    required this.pageListenable,
    required this.count,
    required this.width,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final itemW = width / count;
    // ValueListenableBuilder + TweenAnimationBuilder：直接监听当前页，页面一变
    // 就从旧位置弹性滑到新位置，不依赖父级重建；Positioned 直接挂在 Stack 下生效。
    return ValueListenableBuilder<int>(
      valueListenable: pageListenable,
      builder: (context, page, _) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(
            begin: page.toDouble(),
            end: page.toDouble(),
          ),
          duration: const Duration(milliseconds: 420),
          curve: Curves.elasticOut,
          builder: (context, value, _) {
            final left = value * itemW;
            // 移动途中（value 非整数）横向微拉伸模拟液体；静止时 frac=0 → 不拉伸。
            final frac = value - value.floorToDouble();
            final stretch = 1 + 0.08 * math.sin(frac * math.pi);
            return Positioned(
              left: left,
              top: 0,
              bottom: 0,
              width: itemW,
              child: IgnorePointer(
                child: Center(
                  child: Transform.scale(
                    scaleX: stretch,
                    child: Container(
                      // 显式尺寸：药丸需要包住 item 的「图标 22 + 间隙 3 + 文字」，
                      // 不能靠 padding 撑（无 child 时只有 32×8 的小点，看不见）。
                      width: 62,
                      height: height,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class NaviObserver extends NavigatorObserver implements Listenable {
  var routes = Queue<Route>();

  int get pageCount {
    int count = 0;
    for (var route in routes) {
      if (route is AppPageRoute) {
        count++;
      }
    }
    return count;
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    routes.removeLast();
    notifyListeners();
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    routes.addLast(route);
    notifyListeners();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    routes.remove(route);
    notifyListeners();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    routes.remove(oldRoute);
    if (newRoute != null) {
      routes.add(newRoute);
    }
    notifyListeners();
  }

  List<VoidCallback> listeners = [];

  @override
  void addListener(VoidCallback listener) {
    listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners.remove(listener);
  }

  void notifyListeners() {
    for (var listener in listeners) {
      listener();
    }
  }
}

class _NaviPopScope extends StatelessWidget {
  const _NaviPopScope({
    required this.child,
    this.popGesture = false,
    required this.action,
  });

  final Widget child;
  final bool popGesture;
  final VoidCallback action;

  static bool panStartAtEdge = false;

  @override
  Widget build(BuildContext context) {
    Widget res = child;
    if (popGesture) {
      res = GestureDetector(
        onPanStart: (details) {
          if (details.globalPosition.dx < 64) {
            panStartAtEdge = true;
          }
        },
        onPanEnd: (details) {
          if (details.velocity.pixelsPerSecond.dx < 0 ||
              details.velocity.pixelsPerSecond.dx > 0) {
            if (panStartAtEdge) {
              action();
            }
          }
          panStartAtEdge = false;
        },
        child: res,
      );
    }
    return res;
  }
}

/// 根页面系统/侧滑返回时弹出的退出确认对话框。
/// 勾选"不再提示"会直接关闭退出确认开关（下次返回将直接退出）。
class _ExitConfirmDialog extends StatelessWidget {
  const _ExitConfirmDialog();

  @override
  Widget build(BuildContext context) {
    var dontAsk = false;
    final cs = Theme.of(context).colorScheme;
    return ContentDialog(
      // 标题已经说明意图，正文不再重复「确定要退出吗？」——否则两句话说的是
      // 同一件事，弹窗只剩噪音。正文只留一个可点的勾选行。
      title: "Confirm Exit".tl,
      contentPadding: ContentDialog.hPadding,
      content: StatefulBuilder(
        builder: (ctx, setSB) {
          void toggle() => setSB(() => dontAsk = !dontAsk);
          // 不再用「白底圆角小卡」再包一层：弹窗本身已是 surfaceContainerHigh，
          // 里面再叠一块 surfaceContainerLow 会在浅灰面上浮出一个白盒，看起来
          // 像两张卡片叠在一起、不像同一个弹窗。这里回归单层表面 —— 只保留一行
          // 可点的勾选项，由 InkWell 提供点击反馈，整块对话框是一个整体。
          return InkWell(
            borderRadius: BorderRadius.circular(kcRadius10),
            onTap: toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
              child: Row(
                children: [
                  Checkbox(
                    value: dontAsk,
                    // 收缩点击热区：整行已由外层 InkWell 接管，默认 48dp 的
                    // 命中区会额外撑出左缩进，让复选框与上方正文对不齐。
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => setSB(() => dontAsk = v ?? false),
                  ).paddingRight(6),
                  Expanded(
                    child: Text(
                      "Don't ask again".tl,
                      style: TextStyle(
                        fontSize: kcBody,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      actions: [
        Button.text(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text("Cancel".tl),
        ),
        const SizedBox(width: kcSpaceSm),
        Button.filled(
          onPressed: () {
            if (dontAsk) {
              appdata.settings['exitConfirm'] = false;
              appdata.saveData();
            }
            Navigator.of(context).pop(true);
          },
          child: Text("Exit".tl),
        ),
      ],
    );
  }
}

class _NaviMainView extends StatefulWidget {
  const _NaviMainView({required this.state});

  final NaviPaneState state;

  @override
  State<_NaviMainView> createState() => _NaviMainViewState();
}

class _NaviMainViewState extends State<_NaviMainView> {
  NaviPaneState get state => widget.state;

  bool _showBottomBar = true;
  bool _showTopBar = true;
  double _lastScrollOffset = 0;
  int _lastPage = 0;

  void onScroll(double offset) {
    // 主页(2)保持底部导航常驻（默认首屏）。
    // 其余页面滚动时【只隐藏底部导航】，顶部栏（标题+设置等 action）固定显示，
    // 避免滚下去后想改设置还得滚回顶部。顶部栏很薄(48px)，隐藏它换来的空间
    // 很少、却会丢失标题与操作入口，性价比低；主流 app 也普遍仅隐藏底部 tab。
    if (state.currentPage == 2) return;
    final diff = offset - _lastScrollOffset;
    // 50px 阈值：避免轻微滚动/惯性滑动误隐藏底部导航
    // 触发隐藏/显示或超阈值后更新基准，防止 diff 累积失效
    if (diff > 50 && _showBottomBar) {
      setState(() {
        _showBottomBar = false;
      });
      _lastScrollOffset = offset;
    } else if (diff < -50 && !_showBottomBar) {
      setState(() {
        _showBottomBar = true;
      });
      _lastScrollOffset = offset;
    } else if (diff.abs() >= 50) {
      _lastScrollOffset = offset;
    }
  }

  @override
  void initState() {
    state.mainViewUpdateHandler = () {
      setState(() {});
    };
    _lastPage = state.currentPage;
    super.initState();
  }

  @override
  void dispose() {
    state.mainViewUpdateHandler = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // On mobile the shared top bar is visible only on root tab pages.
    // When a child page is shown it supplies its own AppBar, so we hide this
    // top bar to avoid double titles/actions.
    var shouldShowAppBar = state.controller.value < 2 && state.showTopBarInMobile;

    if (state.currentPage != _lastPage) {
      _lastPage = state.currentPage;
      _showBottomBar = true;
      _showTopBar = true;
      _lastScrollOffset = 0;
    }

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        children: [
          Column(
            children: [
              if (shouldShowAppBar)
                AnimatedSize(
                  duration: AppAnimations.duration(const Duration(milliseconds: 200)),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: _showTopBar
                      ? state.buildTop().paddingTop(context.padding.top)
                      : const SizedBox.shrink(),
                ),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: shouldShowAppBar && _showTopBar,
                  removeBottom: true,
                  child:                     NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollUpdateNotification) {
                          // 仅响应纵向滚动。分类页用 TabBarView（横向 PageView）
                          // 翻页时也会冒泡 ScrollUpdateNotification，且其 pixels 是
                          // 横向页面位移，跨过阈值会让底部导航栏误隐藏/显示造成抖动。
                          if (notification.metrics.axis == Axis.vertical) {
                            onScroll(notification.metrics.pixels);
                          }
                        }
                        return false;
                      },
                    child: AnimatedSwitcher(
                      duration: AppAnimations.duration(const Duration(milliseconds: 320)),
                      switchInCurve: kcSpring,
                      switchOutCurve: kcSpring,
                      child: state.buildMainViewContent(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (shouldShowAppBar)
            Positioned(
              left: 0.0,
              right: 0.0,
              bottom: 0.0,
              child: AnimatedSize(
                duration: AppAnimations.duration(const Duration(milliseconds: 200)),
                curve: Curves.easeInOut,
                alignment: Alignment.bottomCenter,
                child: _showBottomBar
                    ? state.buildBottom(context)
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}
