part of "components.dart";

void showMenuX(
  BuildContext context,
  Offset location,
  List<MenuEntry> entries, {
  Size? anchorSize,
}) {
  Navigator.of(
    context,
    rootNavigator: true,
  ).push(_MenuRoute(entries, location, anchorSize));
}

class _MenuRoute<T> extends PopupRoute<T> {
  final List<MenuEntry> entries;

  final Offset location;

  /// 触发按钮的尺寸。传了才按「贴按钮下方、右边缘对齐」弹出；
  /// 不传（长按 / 右键这类以触点为锚的场景）保持左上角对齐的原行为。
  final Size? anchorSize;

  _MenuRoute(this.entries, this.location, this.anchorSize);

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => "menu";

  double get entryHeight => App.isMobile ? 42 : 36;

  /// 每项高度：分隔线更矮、自定义行（如排序分段控件）按内容估高，
  /// 用于弹层定位时预估总高。
  double _entryHeight(MenuEntry e) {
    if (e.isDivider) return 9;
    if (e.child != null) return 40;
    return entryHeight;
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    // 宽度按内容定：有自定义行（分段控件）最宽；有图标行次之；纯文字最窄。
    // 240 保证日语排序标签（如「最近の追加」5 字）在三等分分段里不省略。
    var width = entries.any((e) => e.child != null)
        ? 240.0
        : entries.any((e) => e.icon != null)
            ? 180.0
            : 160.0;
    final size = MediaQuery.of(context).size;
    const margin = 10.0;
    const gap = 6.0;
    // 总高只用于定位估算；真正渲染时由 ConstrainedBox + 滚动兜底，
    // 大字号/长菜单在矮屏上不会再溢出到屏幕外。
    final estimated = 16 + entries.fold<double>(0, (sum, e) => sum + _entryHeight(e));
    final maxHeight = math.max(120.0, size.height - margin * 2);
    final height = math.min(estimated, maxHeight);

    var left = anchorSize == null
        ? location.dx
        // 右边缘与按钮右边缘对齐：菜单展开后不盖住触发按钮本身。
        : location.dx + anchorSize!.width - width;
    if (left + width > size.width - margin) {
      left = size.width - width - margin;
    }
    if (left < margin) left = margin;

    var top = anchorSize == null ? location.dy : location.dy + anchorSize!.height + gap;
    if (top + height > size.height - margin) {
      // 下方放不下：翻到按钮上方；上方也放不下就贴底并交给滚动。
      final above = location.dy - height - gap;
      top = above >= margin
          ? above
          : math.max(margin, size.height - height - margin);
    }
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kcRadius20),
              border: context.brightness == Brightness.dark
                  ? Border.all(color: context.colorScheme.outlineVariant)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: context.colorScheme.shadow.withValues(alpha: 0.2),
                  blurRadius: 8,
                  blurStyle: BlurStyle.outer,
                ),
              ],
            ),
            child: BlurEffect(
              borderRadius: BorderRadius.circular(kcRadius20),
              child: Material(
                color: context.colorScheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(kcRadius20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: width,
                    maxHeight: maxHeight,
                  ),
                  child: Container(
                    width: width,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 6,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: entries
                            .map((e) => buildEntry(e, context))
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildEntry(MenuEntry entry, BuildContext context) {
    // 分组分隔线：不响应点击，只画一条发丝线把不同性质的操作隔开。
    if (entry.isDivider) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Divider(
          height: 1,
          thickness: 0.6,
          color: context.colorScheme.outlineVariant,
        ),
      );
    }
    // 自定义整行（如菜单顶部的排序分段控件）：内容由调用方提供，
    // 行内子控件自己处理手势；包裹层负责点击后关闭菜单并触发回调。
    if (entry.child != null) {
      return InkWell(
        borderRadius: BorderRadius.circular(kcRadius20),
        onTap: () {
          Navigator.of(context).pop();
          entry.onCustomTap?.call();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
          child: entry.child,
        ),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(kcRadius20),
      onTap: () {
        Navigator.of(context).pop();
        entry.onClick();
      },
      child: SizedBox(
        height: entryHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (entry.icon != null)
                entry.icon!,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.text, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: entry.color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return FadeTransition(
      opacity: animation.drive(Tween<double>(begin: 0, end: 1)
          .chain(CurveTween(curve: Curves.ease))),
      child: child,
    );
  }
}

class MenuEntry {
  final String text;
  final Widget? icon;
  final Color? color;
  final void Function() onClick;

  /// 分组分隔线：只画线，不渲染文字。
  final bool isDivider;

  /// 自定义整行内容（如排序分段控件），点击后关闭菜单并触发 [onCustomTap]。
  final Widget? child;
  final void Function()? onCustomTap;

  /// 分隔线 / 自定义行没有菜单动作。用静态方法引用代替内联 `() {}`：
  /// 初始化列表里的空函数体 `{}` 会被解析器误认为构造函数体。
  static void _noOp() {}

  MenuEntry({required this.text, this.icon, this.color, required this.onClick})
      : isDivider = false,
        child = null,
        onCustomTap = null;

  /// 菜单内的分组分隔线。
  MenuEntry.divider()
      : text = "",
        icon = null,
        color = null,
        onClick = _noOp,
        isDivider = true,
        child = null,
        onCustomTap = null;

  /// 自定义整行（分段控件、预览块等）。
  MenuEntry.custom(Widget rowChild, {void Function()? rowAction})
      : text = "",
        icon = null,
        color = null,
        onClick = _noOp,
        isDivider = false,
        child = rowChild,
        onCustomTap = rowAction;
}
