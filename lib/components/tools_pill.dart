part of "components.dart";

/// 顶栏「工具胶囊条」—— 收藏页 / 历史页等列表页共用同一套外观。
///
/// 圆角 999 容器 + 1px 细分隔线，内部放若干 [ToolsPillButton]。
/// 设计语义：红只用于「激活 / 危险」这类状态，默认图标一律 onSurfaceVariant，
/// 避免出现「一排红图标 + 一颗红选中胶囊」的同屏多红噪音。
class ToolsPill extends StatelessWidget {
  const ToolsPill({super.key, required this.children, this.height = 36});

  final List<Widget> children;

  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kids = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      kids.add(children[i]);
      if (i < children.length - 1) {
        kids.add(Container(width: 1, height: 20, color: cs.outlineVariant));
      }
    }
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kcPillRadius),
        border: Border.all(color: cs.outlineVariant, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: kids),
    );
  }
}

/// 胶囊条内的单个图标按钮：紧凑 36×36、中性色；[active] 时走 accent 红。
class ToolsPillButton extends StatelessWidget {
  const ToolsPillButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.color,
    this.tooltip,
    this.size = 18,
  });

  /// HugeIcons 常量（`List<List<dynamic>>` 形式的路径数据），不是 IconData。
  final dynamic icon;

  final VoidCallback? onPressed;

  /// 激活态（如「已启用筛选」）：图标走 accent 红。
  final bool active;

  /// 覆盖图标色（如危险操作用 `colorScheme.error`）。优先级高于 [active]。
  final Color? color;

  final String? tooltip;

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final btn = IconButton(
      icon: HugeIcon(icon: icon, size: size),
      color: color ?? (active ? kcAccentColor(context) : cs.onSurfaceVariant),
      constraints: const BoxConstraints(minWidth: 38, minHeight: 36),
      padding: EdgeInsets.zero,
      splashRadius: 20,
      onPressed: onPressed,
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

/// 胶囊条内的「双态分段控件」：把互斥的两种视图并排摆出来。
///
/// 取代原先「单图标按钮 + 图标随状态反转」的做法——那种写法只显示「点完之后会
/// 变成什么」，用户看不出当前处于哪种布局，也容易误读成筛选/排序。分段控件把
/// 「当前是哪个 / 还能切到哪个」同时呈现，当前项用 accent 红 + 淡红底标记。
class ToolsPillSegment extends StatelessWidget {
  const ToolsPillSegment({
    super.key,
    required this.icons,
    required this.selectedIndex,
    required this.onSelected,
    this.tooltips,
    this.size = 17,
  });

  /// 每段的 HugeIcons 常量（路径数据，不是 IconData），顺序即展示顺序。
  final List<dynamic> icons;

  final List<String>? tooltips;

  final int selectedIndex;

  final ValueChanged<int> onSelected;

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < icons.length; i++) _segment(context, cs, i),
      ],
    );
  }

  Widget _segment(BuildContext context, ColorScheme cs, int i) {
    final selected = i == selectedIndex;
    final btn = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: IconButton(
        icon: HugeIcon(icon: icons[i], size: size),
        color: selected ? kcAccentColor(context) : cs.onSurfaceVariant,
        style: IconButton.styleFrom(
          backgroundColor: selected
              ? kcAccentSurface(context, alpha: 0.14)
              : Colors.transparent,
          minimumSize: const Size(38, 28),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () {
          if (!selected) onSelected(i);
        },
      ),
    );
    final tip = tooltips != null && i < tooltips!.length ? tooltips![i] : null;
    return tip == null ? btn : Tooltip(message: tip, child: btn);
  }
}

/// 胶囊条内的「更多」按钮：点击在按钮自身位置弹出菜单（复刻 MenuButton 的
/// showMenuX 逻辑，但去掉自带圆角背景，融入胶囊条）。
///
/// ⚠️ 必须用 [Builder] 拿「按钮自己」的 context 去取 RenderBox：
/// 直接用外层 State 的 context，`findRenderObject()` 会一路回溯到整页根节点，
/// `localToGlobal(Offset.zero)` 得到 (0,0)，菜单就会弹到屏幕左上角
/// （实测过：点右侧「⋯」菜单跑到标题下方）。
class ToolsPillMoreButton extends StatelessWidget {
  const ToolsPillMoreButton({super.key, required this.entries, this.tooltip, this.icon});

  final List<MenuEntry> entries;

  final String? tooltip;

  /// 自定义图标（默认「⋯」）——排序这类「点开是菜单」的功能按钮复用
  /// 同一套弹出定位逻辑，只换图标。
  final dynamic icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final btn = Builder(
      builder: (ctx) => IconButton(
        icon: HugeIcon(
          icon: icon ?? HugeIcons.strokeRoundedMoreHorizontal,
          size: 18,
        ),
        color: cs.onSurfaceVariant,
        constraints: const BoxConstraints(minWidth: 38, minHeight: 36),
        padding: EdgeInsets.zero,
        splashRadius: 20,
        onPressed: () {
          final rb = ctx.findRenderObject() as RenderBox;
          showMenuX(ctx, rb.localToGlobal(Offset.zero), entries);
        },
      ),
    );
    return Tooltip(message: tooltip ?? "More".tl, child: btn);
  }
}
