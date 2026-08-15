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
    with SingleTickerProviderStateMixin {
  bool _canPop = true;

  /// Whether the current route is a root tab page (no inner page is shown).
  /// When true, the shared mobile top bar should be rendered.
  bool get showTopBarInMobile => _canPop;

  late int _currentPage = widget.initialPage;

  int get currentPage => _currentPage;

  set currentPage(int value) {
    if (value == _currentPage) return;
    _currentPage = value;
    widget.onPageChanged?.call(value);
  }

  void Function()? mainViewUpdateHandler;

  /// 当前页面可向全局顶栏注入的额外操作按钮（按页生效）。
  /// 例如历史页的多选/清空/刷新。为 null 时仅显示全局 [paneActions]。
  final pageActionsNotifier = ValueNotifier<List<PaneActionEntry>?>(null);

  void _onPageActionsChanged() {
    if (mounted) setState(() {});
  }

  late AnimationController controller;

  final _naviItemTapListeners = <NaviItemTapListener>[];

  void addNaviItemTapListener(NaviItemTapListener listener) {
    _naviItemTapListeners.add(listener);
  }

  void removeNaviItemTapListener(NaviItemTapListener listener) {
    _naviItemTapListeners.remove(listener);
  }

  static const _kBottomBarHeight = 58.0;

  static const _kFoldedSideBarWidth = 72.0;

  static const _kSideBarWidth = 224.0;

  static const _kTopBarHeight = 48.0;

  double get bottomBarHeight =>
      _kBottomBarHeight + MediaQuery.of(context).padding.bottom;

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
    widget.observer.addListener(onNavigatorStateChange);
    pageActionsNotifier.addListener(_onPageActionsChanged);
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
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
    final mq = MediaQuery.of(context);
    final sideInsets = (App.isMobile && mq.orientation == Orientation.landscape)
        ? EdgeInsets.only(
            left: math.max(mq.viewPadding.left, mq.systemGestureInsets.left),
            right: math.max(mq.viewPadding.right, mq.systemGestureInsets.right),
          )
        : EdgeInsets.zero;
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
        animation: controller,
        builder: (context, child) {
          final value = controller.value;
          Widget content = Stack(
            children: [
              Positioned(
                left: _kFoldedSideBarWidth * ((value - 2.0).clamp(-1.0, 0.0)),
                top: 0,
                bottom: 0,
                child: buildLeft(),
              ),
              Positioned.fill(
                left:
                    _kFoldedSideBarWidth * ((value - 1).clamp(0, 1)) +
                    (_kSideBarWidth - _kFoldedSideBarWidth) *
                        ((value - 2).clamp(0, 1)),
                child: buildMainView(),
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
        child: NotificationListener<NavigationNotification>(
          onNotification: (NavigationNotification notification) {
            final bool nextCanPop = !notification.canHandlePop;
            if (nextCanPop != _canPop) {
              setState(() {
                _canPop = nextCanPop;
              });
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
      height: _kBottomBarHeight,
      edgeToEdge: true,
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
            ...List<Widget>.generate(
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
            const Spacer(),
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
    return InkWell(
      borderRadius: BorderRadius.circular(kcCardRadius),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        height: 38,
        decoration: BoxDecoration(
          color: enabled ? colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(kcCardRadius),
        ),
        child: showTitle
            ? Row(
                children: [icon, const SizedBox(width: 12), Text(entry.label)],
              )
            : Align(alignment: Alignment.centerLeft, child: icon),
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
    return InkWell(
      onTap: entry.onTap,
      borderRadius: BorderRadius.circular(kcCardRadius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        height: 38,
        child: showTitle
            ? Row(
                children: [icon, const SizedBox(width: 12), Text(entry.label)],
              )
            : Align(alignment: Alignment.centerLeft, child: icon),
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
      animation: CurvedAnimation(parent: controller, curve: Curves.ease),
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
    final value = controller.value;
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = widget.enabled;
    final icon = isActive ? widget.entry.activeIcon : widget.entry.icon;
    final activeClr = colorScheme.primary;
    final inactiveClr = colorScheme.onSurfaceVariant;

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? activeClr.withValues(alpha: 0.12 * value) : Colors.transparent,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              isActive ? activeClr : inactiveClr,
              BlendMode.srcIn,
            ),
            child: SizedBox(width: 18, height: 18, child: icon),
          ),
          const SizedBox(height: 4),
          Text(
            widget.entry.label,
            style: TextStyle(
              fontSize: kcFont11,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive ? activeClr : inactiveClr.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
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
    return AlertDialog(
      title: Text("Confirm Exit".tl),
      content: StatefulBuilder(
        builder: (ctx, setSB) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Exit?".tl),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setSB(() => dontAsk = !dontAsk),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Checkbox(
                      value: dontAsk,
                      onChanged: (v) => setSB(() => dontAsk = v ?? false),
                    ),
                    Text("Don't ask again".tl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text("Cancel".tl),
        ),
        FilledButton(
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
    if (state.currentPage == 0 || state.currentPage == 2) return;
    final diff = offset - _lastScrollOffset;
    // 50px 阈值：避免轻微滚动/惯性滑动误隐藏上下导航
    // 触发隐藏/显示或超阈值后更新基准，防止 diff 累积失效
    if (diff > 50 && (_showBottomBar || _showTopBar)) {
      setState(() {
        _showBottomBar = false;
        _showTopBar = false;
      });
      _lastScrollOffset = offset;
    } else if (diff < -50 && (!_showBottomBar || !_showTopBar)) {
      setState(() {
        _showBottomBar = true;
        _showTopBar = true;
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
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollUpdateNotification) {
                        onScroll(notification.metrics.pixels);
                      }
                      return false;
                    },
                    child: AnimatedSwitcher(
                      duration: AppAnimations.duration(const Duration(milliseconds: 160)),
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
