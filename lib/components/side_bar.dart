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
            ? const BorderRadius.horizontal(left: Radius.circular(16))
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
