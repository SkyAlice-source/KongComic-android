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

/// 自绘整条顶栏（标题 + 工具栏）的根 Tab 页面标记。
///
/// 实现该接口的页面由 [NaviPane] 自动让位共享顶栏，不需要在
/// `topBarHiddenPages` 里手写页索引 —— 页面自己声明意图，底栏顺序怎么调
/// 都不会串位（此前 `const [1, 4]` 硬编码索引，加一个 Tab 就会指错页）。
abstract interface class SelfTopBarPage {}

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

    /// 整条共享顶栏都不显示的页面（页面自绘顶栏）。
    /// 与 [topBarTitleHiddenPages] 的区别：后者仍显示操作按钮、只隐藏标题；
    /// 本参数连操作按钮一起让位给页面自己的 AppBar，避免出现「两排工具栏」。
    this.topBarHiddenPages = const [],
    super.key,
  });

  final List<PaneItemEntry> paneItems;
  final List<PaneActionEntry> paneActions;

  final Widget Function(int page) pageBuilder;

  final void Function(int index)? onPageChanged;

  /// Page indices that render their own AppBar title and should not show the
  /// duplicated title in the shared top bar on mobile.
  final List<int> topBarTitleHiddenPages;

  /// Page indices whose root tab renders a full self-contained AppBar
  /// (title + actions). The shared top bar is hidden entirely for them.
  final List<int> topBarHiddenPages;

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
        with
        TickerProviderStateMixin,
        AutoListenMixin {
  /// 返回键分流信号：当前路由是否「内部就能吃掉一次 pop」。
  ///
  /// 注意它与 [isRootTabPage] 不是一回事：内联在根 tab 页里的组件只要注册了
  /// `PopScope(canPop: false)`（如收藏文件夹页的「返回先回总览」），框架就会
  /// 发出 `NavigationNotification(canHandlePop: true)`，把它置为 false —— 但
  /// 这**不代表有子页被 push**。若拿它当「是否根页」用，内联 PopScope 会让
  /// NaviPane 误判成子页态，把共享顶栏和底栏一起藏掉（v1.5.9 收藏页实测）。
  /// 「是否根页」看 [isRootTabPage]（基于 observer 的路由数）。
  bool _canPop = true;

  /// 上一次 [isRootTabPage] 的取值，用于在路由数跨越边界时触发一次重建。
  bool _wasAtRoot = true;

  /// 底栏是否被「滚动」收进屏幕底部（沉浸模式）。
  ///
  /// 必须放在 [NaviPaneState] 而不是 `_NaviMainViewState`：返回手势是在
  /// [buildMainView] 的 `PopScope` 里处理的，需要读到它才能做
  /// 「底栏收起时，第一次侧滑只把导航叫回来」。
  bool _bottomBarCollapsed = false;

  /// 底栏当前是否处于「滚动收起」状态。
  bool get bottomBarCollapsed => _bottomBarCollapsed;

  /// 收起 / 放下底栏。
  ///
  /// 只在滚动跨过阈值时被调用，一次收放一次 `setState`，不会每帧触发。
  void setBottomBarCollapsed(bool collapsed) {
    if (_bottomBarCollapsed == collapsed || !mounted) return;
    setState(() => _bottomBarCollapsed = collapsed);
  }

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
  ///
  /// 判据是 pane navigator 的**实际路由数**，而不是 [_canPop]：内联在根 tab
  /// 页里的 `PopScope(canPop: false)`（收藏文件夹页「返回回总览」、历史页
  /// 多选模式）只会把路由标记为「拦截 pop」，并不代表有子页压在上面 ——
  /// 用 `_canPop` 当判据会让共享顶栏 / 底栏在这些正常根页态下一起消失。
  bool get isRootTabPage => widget.observer.routes.length <= 1;

  /// Whether the shared mobile top bar should be rendered.
  ///
  /// Pages that draw their own full AppBar ([NaviPane.topBarHiddenPages])
  /// opt out entirely, otherwise the screen would show two toolbars.
  /// 注意：底栏不受此影响（见 [isRootTabPage]），否则隐藏共享顶栏的页面会连底栏一起丢。
  bool get showTopBarInMobile =>
      isRootTabPage && !widget.topBarHiddenPages.contains(currentPage);

  late int _currentPage = widget.initialPage;

  int get currentPage => _currentPage;

  set currentPage(int value) {
    if (value == _currentPage) return;
    _currentPage = value;
    widget.onPageChanged?.call(value);
    _pageNotifier.value = value;
  }

  void Function()? mainViewUpdateHandler;

  /// 当前页面可向全局顶栏注入的额外操作按钮（按页生效，精确 Widget，
  /// 例如历史页的筛选/多选/更多）。为 null 时仅显示全局 [paneActions]。
  final pageActionsNotifier = ValueNotifier<List<Widget>?>(null);

  /// 当前页面可覆盖的顶栏标题（按页生效）。为 null 时回退到
  /// [NaviPane.paneItems] 的静态标签。用于多选态「已选 N 项」、文件夹内页
  /// 「收藏」等动态标题；升级为 Widget 是为了让搜索态直接放输入框。
  final pageTitleNotifier = ValueNotifier<Widget?>(null);

  /// 当前页面可注入的顶栏 leading（返回键等），排在标题前。为 null 时
  /// 顶栏无 leading（根 tab）。文件夹内页的「回总览」箭头走这里。
  final pageLeadingNotifier = ValueNotifier<Widget?>(null);

  /// 当前页面可要求隐藏全局 [NaviPane.paneActions]（搜索/设置等）。收藏页
  /// 的文件夹内层/多选/搜索态在工具胶囊里已有夹内搜索，右上角再放全局
  /// 搜索是重复入口；由 pushTopBar 按视图声明，换 tab 复位为 false。
  final pageHideGlobalActionsNotifier = ValueNotifier<bool>(false);

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

  /// 栏体高度：值来自 [kcRootTopBarHeight]，自绘顶栏的根 tab 共用同一个
  /// 令牌，保证切换 tab 时标题不上下跳。
  static const _kTopBarHeight = kcRootTopBarHeight;

  /// 底栏**实际遮挡**的高度：栏体 + 下方留白 + 系统手势区。
  /// 页面（列表底部 padding、悬浮按钮）靠它给内容让位。
  double get bottomBarHeight =>
      bottomBarBodyHeight +
      _kBottomBarMarginV +
      MediaQuery.of(context).padding.bottom;

  /// 底栏外边距。底部额外留出系统手势区，避免胶囊压在手势条上。
  EdgeInsets bottomBarMargin(BuildContext context) => EdgeInsets.fromLTRB(
    _kBottomBarMarginH,
    _kBottomBarMarginV,
    _kBottomBarMarginH,
    _kBottomBarMarginV + MediaQuery.of(context).padding.bottom,
  );

  void onNavigatorStateChange() {
    // 路由数跨越「根页 / 子页」边界时重建一次：共享顶栏 / 底栏的显隐
    // （isRootTabPage）读的是路由数，而 NavigationNotification 不保证在这
    // 两种场景下都会带来一次 setState（例如从子页返回一个带 PopScope 的
    // 根页，canHandlePop 前后都是 true，通知侧看不到变化）。
    final bool atRoot = widget.observer.routes.length <= 1;
    if (atRoot != _wasAtRoot) {
      _wasAtRoot = atRoot;
      setState(() {
        // 从子页回到根页：底栏必须回来（滚动收起状态不跨层残留）。
        if (atRoot) _bottomBarCollapsed = false;
      });
    }
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
      // 换 tab 一定把底栏放回来：新页面从顶部开始，用户需要顶层入口，
      // 也让「收起」这个状态不会跨页面残留。
      _bottomBarCollapsed = false;
    });
    // 清掉上一页注入的顶栏操作 / 标题，避免跨 tab 污染（例如历史页的多选
    // 操作残留在探索页）。新页面若在 build 里通过 _syncTopBar 重新注入会立即补回。
    pageActionsNotifier.value = null;
    pageTitleNotifier.value = null;
    pageLeadingNotifier.value = null;
    pageHideGlobalActionsNotifier.value = false;
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
    listen(widget.observer, onNavigatorStateChange);
    listen(pageActionsNotifier, _onPageActionsChanged);
    listen(pageTitleNotifier, _onPageActionsChanged);
    listen(pageLeadingNotifier, _onPageActionsChanged);
    listen(pageHideGlobalActionsNotifier, _onPageActionsChanged);
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    _chromeController.dispose();
    _pageNotifier.dispose();
    pageActionsNotifier.dispose();
    pageTitleNotifier.dispose();
    pageLeadingNotifier.dispose();
    pageHideGlobalActionsNotifier.dispose();
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
        // 底栏被滚动收起时，宽屏侧滑先把导航叫回来，而不是直接退出/返回。
        // 与 Android 系统返回按钮走同一套规则（见 buildMainView 的 PopScope）。
        if (_bottomBarCollapsed) {
          setBottomBarCollapsed(false);
          return;
        }
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
              final sideBarWidth =
                  _kFoldedSideBarWidth +
                  (_kSideBarWidth - _kFoldedSideBarWidth) *
                      ((value - 2.0).clamp(0.0, 1.0));
              final sideBarVisibleLeft =
                  _kFoldedSideBarWidth * ((value - 2.0).clamp(-1.0, 0.0));
              final sideBarLeft =
                  sideBarVisibleLeft +
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
                    child: Semantics(container: true, child: buildMainView()),
                  ),
                ],
              );
              if (sideInsets != EdgeInsets.zero) {
                content = Padding(padding: sideInsets, child: content);
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
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) {
            return;
          }
          if (_canPop == false) {
            // 当前页面自己声明要处理返回（多选 / 搜索模式等），交给它。
            widget.navigatorKey.currentState?.maybePop(result);
            return;
          }
          // 兜底：`_canPop` 由 NavigationNotification 驱动，子页刚 push 上来
          // 就立刻返回时可能还慢一拍。直接问一下内层 Navigator，避免在子页上
          // 误弹「确认退出」。已是根页时 canPop() 为 false，不改变原有语义。
          final innerNav = widget.navigatorKey.currentState;
          if (innerNav != null && innerNav.canPop()) {
            innerNav.maybePop(result);
            return;
          }
          // 已确认在根 tab 页。若底栏正被滚动收起，第一次返回先把导航叫回来。
          //
          // 底栏收起后页面与普通子页长得一模一样，用户侧滑的本意通常是
          // 「回上一层」；此时直接弹「确认退出」会让人莫名其妙（弹窗本身没错，
          // 错在出现的时机）。先放回底栏，既回答了「我在哪」，也把顶层切换
          // 入口还回去；再滑一次才谈退出。这也是「保留沉浸感」的代价所在。
          if (_bottomBarCollapsed) {
            setBottomBarCollapsed(false);
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
                  // 回到根 tab 页：底栏必须回来。
                  // 这里原来只翻转 _canPop，`_showBottomBar` 的收起状态会跨
                  // 「进子页 → 返回」存活 —— 滚到深处点进详情、再返回，底栏
                  // 不出现，得再往上滑 50px 才回来，像是导航丢了。
                  if (nextCanPop) _bottomBarCollapsed = false;
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
    final pageLeading = pageLeadingNotifier.value;
    final pageTitle = pageTitleNotifier.value;
    final hideGlobalActions = pageHideGlobalActionsNotifier.value;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Container(
        padding: const EdgeInsets.only(left: 16, right: 16),
        height: _kTopBarHeight,
        width: double.infinity,
        child: Row(
          children: [
            // 页面注入的 leading（文件夹内页的「回总览」返回键等）。
            if (pageLeading != null) pageLeading,
            // 标题：页面注入 Widget（搜索态输入框 / 多选态文本）优先，
            // 否则回退到当前 tab 的静态标签（kcTitleMain + 粗体，与
            // 各根 tab 的 SliverAppbar 标题逐项一致）。
            if (!hideTitle)
              Expanded(
                child: pageTitle ??
                    Text(
                      widget.paneItems[currentPage].label,
                      style: TextStyle(
                        fontSize: kcTitleMain,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
              )
            else
              // 无标题时用 Spacer 把操作推到右侧。注意它不能与上面的
              // Expanded 并存 —— 两个 flex 子节点会平分剩余空间，标题被
              // 挤到一半宽（窄屏 + 宽工具胶囊下直接放不下两个字）。
              const Spacer(),
            // 页面注入的精确操作（历史页的筛选/多选/更多等），保留其原有视觉
            // （如筛选激活时变红、自定义 showMenuX 菜单），不再强转 PaneActionEntry。
            if (pageActions != null) ...pageActions,
            // 全局共享操作（布局切换 / 搜索 / 设置），按 PaneActionEntry 渲染。
            // 页面可通过 pageHideGlobalActionsNotifier 隐藏（收藏页内层已
            // 有夹内搜索，全局入口留在总览层）。
            // 注意语义标签必须走 IconButton/PopupMenuButton 的 tooltip 参数
            // （映射到无障碍 content-desc）；外层 Tooltip 的 message 只进
            // tooltipText 通道，读屏与 uiautomator 都拿不到（实证 3 次重采
            // 均无标签，与页面注入操作的 IconButton(tooltip:) 表现不一致）。
            if (!hideGlobalActions)
              for (var action in widget.paneActions)
              if (action.menu != null)
                PopupMenuButton<dynamic>(
                  icon: action.icon,
                  tooltip: action.label,
                  itemBuilder: (_) => action.menu!,
                  onSelected: action.onSelected,
                )
              else
                IconButton(
                  icon: action.icon,
                  tooltip: action.label,
                  onPressed: action.onTap,
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
            // （发现/历史的「切换列表/网格视图」，见 _showLayoutToggle），于是
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
          borderRadius: BorderRadius.circular(kcPillRadius),
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
          tween: Tween<double>(begin: page.toDouble(), end: page.toDouble()),
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
                        borderRadius: BorderRadius.circular(kcPillRadius),
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
                      style: TextStyle(fontSize: kcBody, color: cs.onSurface),
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

  double _lastScrollOffset = 0;
  int _lastPage = 0;

  void onScroll(double offset) {
    // 滚动只收起底栏，顶栏永远固定。
    //
    // 顶栏很薄（48px），收掉换来的空间很少，却会连标题和操作入口一起丢；
    // 更重要的是：共享顶栏只出现在根 tab 页（子页自带 AppBar），所以
    // 「顶栏还在」本身就是「我在根页」的标识 —— 这正是底栏可以放心
    // 收起的前提，也是本方案能保住沉浸感又不至于让人迷路的关键。
    //
    // 三种情况不碰这个状态：
    // · 主页（index 2）：默认首屏，底栏常驻。
    // · 子页（isRootTabPage == false）：已有 AppBar + 返回箭头交代层级；
    //   且子页的滚动通知会冒泡到这里的 NotificationListener，不挡住会被
    //   误记成「根页也收起了」。
    // · 宽屏（>= changePoint）：用左侧栏导航，根本没有底栏；iOS 宽屏侧滑
    //   会把「收起的底栏」当作要恢复的对象，结果侧滑像没反应。
    if (state.currentPage == 2 ||
        !state.isRootTabPage ||
        state.controller.value >= 2) {
      return;
    }
    final diff = offset - _lastScrollOffset;
    // 50px 阈值：避免轻微滚动/惯性滑动误隐藏底部导航。
    // 状态存在 NaviPaneState 上：返回手势那边要读它、也能重置它。
    if (diff > 50 && !state.bottomBarCollapsed) {
      state.setBottomBarCollapsed(true);
      _lastScrollOffset = offset;
    } else if (diff < -50 && state.bottomBarCollapsed) {
      state.setBottomBarCollapsed(false);
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
    var shouldShowAppBar =
        state.controller.value < 2 && state.showTopBarInMobile;
    // 底栏只跟「是否根 tab 页」有关：自绘顶栏的页面（如历史）仍需要底部导航，
    // 早前与顶栏共用同一个条件，导致隐藏共享顶栏时底栏一起消失。
    var shouldShowBottomBar = state.controller.value < 2 && state.isRootTabPage;

    if (state.currentPage != _lastPage) {
      _lastPage = state.currentPage;
      // 换页只重置滚动基准；底栏由 NaviPaneState.updatePage 统一放回。
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
                  duration: AppAnimations.duration(
                    const Duration(milliseconds: 200),
                  ),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  // 顶栏在手机上就是「根 tab 页」的标志，永不收起。
                  child: state.buildTop().paddingTop(context.padding.top),
                ),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: shouldShowAppBar,
                  removeBottom: true,
                  child: NotificationListener<ScrollNotification>(
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
                    // tab 切换不做任何转场动画，直接换页。
                    //
                    // 原来这里套了 AnimatedSwitcher：它默认用 Stack 把上一个
                    // child 和新 child 叠在一起做 320ms 交叉淡入淡出。两个全屏
                    // 页面同时半透明 → 旧页面内容会透出来：从分类切到收藏，能
                    // 看到分类页的彩色胶囊和「需要登陆」文字压在收藏封面上，像
                    // "没刷新干净"。把轮播改成只保留当前 child 后，虽然叠影没
                    // 了，但整页仍要经历约 120ms 的半透明期（截图里封面发白发
                    // 灰），切换依旧不够干脆。
                    //
                    // 底部 tab 切换在 Material 里本来就没有转场动画 —— 用户按下
                    // 就已经看到目标页，任何淡入都会被感知成"慢一拍"。这里直接
                    // 换 child，配合页面自己的骨架屏即可。
                    child: state.buildMainViewContent(),
                  ),
                ),
              ),
            ],
          ),
          if (shouldShowBottomBar)
            Positioned(
              left: 0.0,
              right: 0.0,
              bottom: 0.0,
              child: AnimatedSize(
                duration: AppAnimations.duration(
                  const Duration(milliseconds: 200),
                ),
                curve: Curves.easeInOut,
                alignment: Alignment.bottomCenter,
                child: !state.bottomBarCollapsed
                    ? state.buildBottom(context)
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}
