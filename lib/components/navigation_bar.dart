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
      _kBottomBarHeight + _kBottomBarMarginV + MediaQuery.of(context).padding.bottom;

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
      height: _kBottomBarHeight,
      edgeToEdge: true,
      // ColorOS 17 浮岛式导航：胶囊底栏悬浮在内容之上，两侧与底部留白，
      // 而非全宽贴边，强化「轻盈、分层」的视觉。
      margin: bottomBarMargin(context),
      indicator: (width) => _LiquidIndicator(
        pageListenable: _pageNotifier,
        count: widget.paneItems.length,
        width: width,
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
        duration: AppAnimations.duration(const Duration(milliseconds: 200)),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
            Text(
              widget.entry.label,
              style: TextStyle(
                fontSize: kcFont11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? activeClr : inactiveClr,
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

  const _LiquidIndicator({
    required this.pageListenable,
    required this.count,
    required this.width,
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
                      height: 44,
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
    return ContentDialog(
      title: "Confirm Exit".tl,
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
