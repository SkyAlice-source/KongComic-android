part of 'components.dart';

class SideBarRoute<T> extends PopupRoute<T> {
  SideBarRoute(this.widget,
      {this.showBarrier = true,
      this.useSurfaceTintColor = false,
      this.dismissible = true,
      required this.width,
      this.addBottomPadding = true,
      this.addTopPadding = true});

  final Widget widget;

  final bool showBarrier;

  final bool useSurfaceTintColor;

  final bool dismissible;

  final double width;

  final bool addTopPadding;

  final bool addBottomPadding;

  @override
  Color? get barrierColor => showBarrier ? Colors.black54 : Colors.transparent;

  @override
  bool get barrierDismissible => dismissible;

  @override
  String? get barrierLabel => "exit";

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    bool showSideBar = MediaQuery.of(context).size.width > width;

    Widget body = widget;

    if (addTopPadding) {
      body = Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: body,
        ),
      );
    }

    final sideBarWidth = math.min(width, MediaQuery.of(context).size.width);

    body = Container(
      decoration: BoxDecoration(
        borderRadius: showSideBar
            ? const BorderRadius.horizontal(left: Radius.circular(kcRadius16))
            : null,
        color: Theme.of(context).colorScheme.surface,
        boxShadow: context.brightness == ui.Brightness.dark ? [
          BoxShadow(
            color: Colors.white.withAlpha(50),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ] : null,
      ),
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(maxWidth: sideBarWidth),
      height: MediaQuery.of(context).size.height,
      child: GestureDetector(
        child: Material(
          child: ClipRect(
            clipBehavior: Clip.antiAlias,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  0,
                  0,
                  MediaQuery.of(context).padding.right,
                  addBottomPadding
                      ? MediaQuery.of(context).padding.bottom +
                          MediaQuery.of(context).viewInsets.bottom
                      : 0),
              color: useSurfaceTintColor
                  ? Theme.of(context).colorScheme.primary.withAlpha(20)
                  : null,
              child: body,
            ),
          ),
        ),
      ),
    );

    if (App.isIOS) {
      body = IOSBackGestureDetector(
        enabledCallback: () => true,
        gestureWidth: 20.0,
        onStartPopGesture: () =>
            IOSBackGestureController(controller!, navigator!),
        child: body,
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: body,
    );
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    var offset =
        Tween<Offset>(begin: const Offset(1, 0), end: const Offset(0, 0));
    return SlideTransition(
      position: offset.animate(CurvedAnimation(
        parent: animation,
        curve: Curves.fastOutSlowIn,
      )),
      child: child,
    );
  }
}

Future<void> showSideBar(BuildContext context, Widget widget,
    {bool showBarrier = true,
    bool useSurfaceTintColor = false,
    bool dismissible = true,
    double width = 500,
    bool addTopPadding = false}) {
  // Always push onto the main navigator (NaviPane's inner Navigator) when
  // available, so the SideBarRoute lives in the same stack as the page that
  // triggered it. Falling back to the root navigator only happens in single-
  // Navigator setups. Pushing onto the root navigator from within a NaviPane
  // page puts the sidebar above the comic details page, so Android's
  // predictive back gesture has to first commit a pop on the modal-style
  // SideBarRoute (2-3 swipes) before it can pop the page underneath. The
  // previous "use nearest Navigator" approach broke callers that pass
  // `App.rootContext` (e.g. `_ComicPageActions.showComments`) since
  // `Navigator.of(rootContext)` would still resolve to the root navigator.
  var navigatorState = App.mainNavigatorKey?.currentState ??
      App.rootNavigatorKey.currentState!;
  return navigatorState.push(
    SideBarRoute(
      widget,
      showBarrier: showBarrier,
      useSurfaceTintColor: useSurfaceTintColor,
      dismissible: dismissible,
      width: width,
      addTopPadding: addTopPadding,
      addBottomPadding: true,
    ),
  );
}

/// 居中悬浮面板：把「选择型」内容（章节列表、阅读设置、下载选章等）以 Material 3
/// 对话框的形式浮在屏幕中央，替代原来的右侧滑入 SideBar。
///
/// 这些内容的 widget 自带 AppBar / SliverAppBar 头部，并在点选后自行
/// `Navigator.pop()`，所以直接放进一张圆角卡片即可，不需要额外的标题/按钮。
/// 卡片尺寸受限（maxWidth 默认 560 / 屏宽-32，maxHeight 默认 屏高-96），
/// 内部的 ListView / CustomScrollView 因此能正常滚动，不会撑爆。
///
/// 和 `showSideBar` 一样走主导航栈，保证在 NaviPane 内触发时关闭面板不会误
/// 把底下的页面一起 pop 掉。
Future<T?> showCenteredPanel<T>(
  BuildContext context,
  Widget widget, {
  bool dismissible = true,
  double? maxWidth,
  double? maxHeight,
}) {
  final navigatorState =
      App.mainNavigatorKey?.currentState ?? App.rootNavigatorKey.currentState!;
  return navigatorState.push<T>(
    DialogRoute<T>(
      context: context,
      barrierDismissible: dismissible,
      barrierColor: Colors.black54,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final cs = Theme.of(ctx).colorScheme;
        final isDark = cs.brightness == Brightness.dark;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth ?? math.min(560, mq.size.width - 48),
              // 高度收到屏高的 82%（最多 720dp）：像对话框一样四周留白，
              // 而不是「圆角整页」。列表更长时在卡片内部滚动即可。
              maxHeight: maxHeight ?? math.min(720, mq.size.height * 0.82),
            ),
            // 与 ContentDialog 完全一致的视觉语言：24dp 大圆角 + 极细凝光
            // 描边 + 抬升表面色（surfaceContainerHigh）。否则同 app 里会出现
            // 两套长得不同的对话框（旧的是 24dp 描边，这里是 16dp 阴影）。
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(kcSurfaceRadius),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: widget,
              ),
            ),
          ),
        );
      },
    ),
  );
}
