part of 'components.dart';

class PopUpWidget<T> extends PopupRoute<T> {
  PopUpWidget(this.widget);

  final Widget widget;

  @override
  Color? get barrierColor => Colors.black54;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => "exit";

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    var height = MediaQuery.of(context).size.height * 0.9;
    bool showPopUp = MediaQuery.of(context).size.width > 500;
    // 宽屏（>500）时才做成卡片 + 玻璃；手机上 PopUpWidget 是全屏页面，玻璃背景
    // 会把背后页面模糊透出来，正文压在糊掉的底图上既难读、看着也像「没背景」。
    // 全屏时一律用不透明的主题底色。
    Widget shell = showPopUp
        ? GlassContainer(
            blurStrength: 25,
            opacity: 0.20,
            borderRadius: const BorderRadius.all(Radius.circular(kcCardRadius)),
            border: GlassContainer.iosBorder(context),
            boxShadow: GlassContainer.liquidShadow(context),
            width: 500,
            height: height,
            child: widget,
          )
        : Container(
            width: double.infinity,
            height: double.infinity,
            color: Theme.of(context).colorScheme.surface,
            child: widget,
          );
    Widget body = PopupIndicatorWidget(child: shell);
    if (App.isIOS) {
      body = IOSBackGestureDetector(
        enabledCallback: () => true,
        gestureWidth: 20.0,
        onStartPopGesture: () =>
            IOSBackGestureController(controller!, navigator!),
        child: body,
      );
    }
    if (showPopUp) {
      return MediaQuery.removePadding(
        removeTop: true,
        context: context,
        child: Center(
          child: body,
        ),
      );
    }
    return body;
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 350);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return FadeTransition(
      opacity: animation.drive(
        Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.ease)),
      ),
      child: child,
    );
  }
}

class PopupIndicatorWidget extends InheritedWidget {
  const PopupIndicatorWidget({super.key, required super.child});

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => false;

  static PopupIndicatorWidget? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PopupIndicatorWidget>();
  }
}

Future<T> showPopUpWidget<T>(BuildContext context, Widget widget) async {
  // 推到主干导航栈(mainNavigator)，使弹窗生命周期附属当前页面，
  // 关闭时回到来源页而非直接退到主页(之前 rootNavigator 会把主干栈一起带走)。
  final target = App.mainNavigatorKey?.currentContext ?? context;
  return await Navigator.of(target).push(PopUpWidget(widget));
}

class PopUpWidgetScaffold extends StatefulWidget {
  const PopUpWidgetScaffold(
      {required this.title, required this.body, this.tailing, super.key});

  final Widget body;
  final List<Widget>? tailing;
  final String title;

  @override
  State<PopUpWidgetScaffold> createState() => _PopUpWidgetScaffoldState();
}

class _PopUpWidgetScaffoldState extends State<PopUpWidgetScaffold> {
  bool top = true;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: Container(
              height: 56 + context.padding.top,
              padding: EdgeInsets.only(top: context.padding.top),
              width: double.infinity,
              child: Row(
              children: [
                const SizedBox(
                  width: 8,
                ),
                Tooltip(
                  message: "Back".tl,
                  child: IconButton(
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, size: 18),
                    onPressed: () =>
                        context.canPop() ? context.pop() : App.pop(),
                  ),
                ),
                const SizedBox(
                  width: 16,
                ),
                Text(
                  widget.title,
                  style: const TextStyle(
                      fontSize: kcFont22, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                if (widget.tailing != null) ...widget.tailing!,
                const SizedBox(width: 8),
              ],
            ),
          ),
          ),
          NotificationListener<ScrollNotification>(
            onNotification: (notifications) {
              if (notifications.metrics.axisDirection != AxisDirection.down) {
                return false;
              }
              if (notifications.metrics.pixels ==
                      notifications.metrics.minScrollExtent &&
                  !top) {
                setState(() {
                  top = true;
                });
              } else if (notifications.metrics.pixels !=
                      notifications.metrics.minScrollExtent &&
                  top) {
                setState(() {
                  top = false;
                });
              }
              return false;
            },
            child: MediaQuery.removePadding(
              removeTop: true,
              context: context,
              child: Expanded(child: widget.body),
            ),
          ),
          SizedBox(
            height: MediaQuery.of(context).viewInsets.bottom -
                        0.05 * MediaQuery.of(context).size.height >
                    0
                ? MediaQuery.of(context).viewInsets.bottom -
                    0.05 * MediaQuery.of(context).size.height
                : 0,
          )
        ],
      ),
    );
  }
}
