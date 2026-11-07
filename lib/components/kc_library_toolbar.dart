part of 'components.dart';

// ════════════════════════════════════════════════════════════════════
// 书库页统一工具语言（菜单方案 A / B / C 的共用组件层）
//
// 背景见项目根 menu_design_proposals.html：收藏夹内页与历史页原来各说一种
// 顶栏语言，⋮ 里混了「模式切换 / 数据操作 / 全局导航 / 破坏性动作」四类。
// 最终形态：右上角只有裸搜索；筛选/排序状态在第一行 chip，结果数与重置在
// 第二行左侧，右侧是 [KcActionOverflowBar] 平铺动作 + 固定位按钮。
// 布局切换统一复用全站已有的 [ToolsPillLayoutButton]（发现页右上角那颗）：
// 同一个 appdata.settings 键只需要一个入口、一种交互，不再另造「排列方式」
// 弹窗或分段控件。
//
//   A · showKcActionDialog —— 通用居中大圆角动作弹窗（短分组 / 文字标签 /
//       破坏性项标红置底），保留为全站弹层语言的一部分，当前两页不再调用。
//   B · KcFilterChipRow —— 横滑 chip 行 + 辅助行动作区；筛选/排序有文字
//       证据、结果数与一键重置；动作默认平铺、窄屏才从末尾收拢。
//   C · KcDockedToolbar（多选贴底工具条）。
//
// 刻意不做：浮动工具条随滚动收拢（会与底部浮岛 dock 抢位）、二级嵌套子菜单、
// 只有上两角圆的贴底 sheet、给已有全局按钮再包一层弹窗。所有尺寸 / 颜色 /
// 字号都走 kc* 令牌与 ColorScheme，门禁 check_tokens.py 不允许新增裸数字。
// ════════════════════════════════════════════════════════════════════

/// 底部动作面板里的一行动作。
///
/// [icon] 是 HugeIcons 的路径数据（`List<List<dynamic>>`），不是 IconData。
/// [danger] 只改前景色为 error；置底由调用方在 sections 里排序保证。
class KcActionEntry {
  const KcActionEntry({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  final dynamic icon;
  final String title;
  final String? subtitle;
  final bool danger;
  final VoidCallback onTap;
}

/// 居中动作弹窗的分组：一组动作，或一块自定义控件。
class KcActionDialogSection {
  const KcActionDialogSection.entries(this.entries, {this.title}) : child = null;

  const KcActionDialogSection.child(this.child, {this.title}) : entries = null;

  final String? title;
  final List<KcActionEntry>? entries;
  final Widget? child;
}

/// A · 通用居中大圆角动作弹窗。
///
/// 按用户反馈从贴底 bottom sheet 改成屏幕居中的卡片：与 ContentDialog /
/// LoadingDialog / QuickSearchDialog / KcChoiceDialog 同一套 Dialog 语言，
/// 四角都是 [kcSurfaceRadius] 大圆角 + 0.5dp 凝光描边（不再是只有上两角圆
/// 的 sheet），因此四面弧度一致、深色下也有清晰轮廓。
/// 文字标签 + 分组标题保留（读屏可读），破坏性动作放在最后一个 section
/// 并标红；点任一项先关弹窗再执行，避免确认框叠在弹窗上面。
/// [footer] 是可选底部区块；结果数 / 重置已搬到内容区辅助行。
Future<void> showKcActionDialog({
  required BuildContext context,
  required String title,
  required List<KcActionDialogSection> sections,
  Widget? footer,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final cs = Theme.of(dialogContext).colorScheme;
      final isDark = cs.brightness == Brightness.dark;
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kcSurfaceRadius),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: kcSpaceLg,
          vertical: kcSpaceLg,
        ),
        elevation: 6,
        shadowColor: cs.shadow.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        backgroundColor: cs.surfaceContainerHigh,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kcChoiceDialogMaxWidth),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              kcDialogInset,
              kcSpaceLg,
              kcDialogInset,
              kcDialogInset,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: kcTitleMain,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: kcSpaceMd),
                for (final section in sections) ...[
                  if (section.title != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: kcSpaceSm,
                        bottom: kcSpaceXs,
                      ),
                      child: Text(
                        section.title!,
                        style: TextStyle(
                          fontSize: kcCaption,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (section.child != null) section.child!,
                  if (section.entries != null)
                    for (final entry in section.entries!)
                      KcListTile(
                        leading: HugeIcon(
                          icon: entry.icon,
                          size: kcSpace18,
                          color: entry.danger ? cs.error : null,
                        ),
                        title: Text(
                          entry.title,
                          style: TextStyle(
                            fontSize: kcBody,
                            color: entry.danger ? cs.error : null,
                          ),
                        ),
                        subtitle: entry.subtitle == null
                            ? null
                            : Text(entry.subtitle!),
                        showDivider: false,
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          entry.onTap();
                        },
                      ),
                ],
                if (footer != null) ...[
                  const KcRowDivider(),
                  const SizedBox(height: kcSpaceSm),
                  footer,
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// 四面全圆的浮起底部面板外壳。
///
/// 搜索页两个「选择漫画源」面板原来直接用 `showModalBottomSheet` 的
/// `BorderRadius.vertical(top: ...)`，只有上面两角是圆的、下面两角是直角，
/// 与全站 Dialog（四角 [kcSurfaceRadius]）并排看时弧度对不上。这里统一成
/// 左右下方留一点呼吸空间的浮起卡片：四角同弧 + 0.5dp 凝光描边，
/// 顶部自绘把手（不再用只适配贴底全宽 sheet 的系统 showDragHandle）。
/// 外层透明，卡片自己画面，超高内容交给 [SingleChildScrollView]。
Future<T?> showKcFloatingSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useRootNavigator = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final cs = Theme.of(sheetContext).colorScheme;
      final isDark = cs.brightness == Brightness.dark;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            kcSpaceSm,
            0,
            kcSpaceSm,
            kcSpaceSm,
          ),
          child: Material(
            color: cs.surfaceContainerHigh,
            elevation: 6,
            shadowColor: cs.shadow.withValues(alpha: 0.18),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kcSurfaceRadius),
              side: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                width: 0.5,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        vertical: kcSpaceSm,
                      ),
                      width: kcSpace18 + kcSpaceMd,
                      height: kcSpaceXs,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(kcRadius4),
                      ),
                    ),
                  ),
                  builder(sheetContext),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// B · chip 行的一颗：标签 + 选中态，可选计数徽标与下拉箭头（排序用）。
class KcFilterChipData {
  const KcFilterChipData({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.showArrow = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final bool showArrow;
}

// ── 辅助行动作：默认全部平铺，窄屏才自动收拢 ──────────────────────────
/// 内容区辅助行里的一枚动作。同一份数据既能渲染成常驻裸图标按钮，也能在
/// 宽度不够时被收进 ⋮ 菜单，避免「按钮版」和「菜单版」各写一套文案与回调、
/// 改一处漏一处。之前 ⋮ 里的低频动作、被删掉的多选、按条件才出现的清除
/// 筛选，现在统一由这份列表驱动。
class KcToolbarAction {
  const KcToolbarAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.enabled = true,
  });

  /// HugeIcons 路径数据（`List<List<dynamic>>`），不是 IconData。
  final dynamic icon;

  /// 按钮 tooltip / 溢出菜单文字，共用同一条翻译。
  final String label;
  final VoidCallback onTap;

  /// 破坏性动作传 `colorScheme.error`，图标与菜单文字一起变红。
  final Color? color;

  /// 当前上下文不适用时（如「全部收藏」里的管理 / 删除文件夹）仍然
  /// 放出来，只是置灰不可点 —— 位置够就别藏。
  final bool enabled;

  MenuEntry toMenuEntry() => MenuEntry(
    icon: HugeIcon(icon: icon, size: kcSpace18, color: color),
    text: label,
    color: color,
    onClick: enabled ? onTap : () {},
  );
}

/// 把 [actions] 尽量全部平铺成常驻图标按钮；宽度不够时才从**末尾**开始把
/// 放不下的收进一颗 ⋮（[showMenuX] 锚定菜单）。
///
/// 危险项由调用方排在列表末尾，因此窄屏上优先被收起来，不会退化成
/// 「一排常驻红图标」。每枚按钮仍占 [kcMinTapTarget] 的 48dp 命中区，
/// 不为了塞下更多按钮牺牲无障碍下限。
class KcActionOverflowBar extends StatelessWidget {
  const KcActionOverflowBar({
    super.key,
    required this.actions,
    required this.maxWidth,
    this.fixed = const <Widget>[],
  });

  final List<KcToolbarAction> actions;

  /// 本行可用宽度（由 [LayoutBuilder] 提供）。
  final double maxWidth;

  /// 不参与收拢的固定按钮：[ToolsPillLayoutButton] 一键布局切换、网络文件夹
  /// 需要自带 context 的「同步」Flyout。高频或菜单行放不下的都放这里。
  final List<Widget> fixed;

  @override
  Widget build(BuildContext context) {
    final slot = kcMinTapTarget.toDouble();
    final available = maxWidth - fixed.length * slot;
    var visible = actions.length;
    if (available.isFinite) {
      final fit = (available / slot).floor();
      // 一旦需要 ⋮，就预留一个槽位给它，否则整行会溢出。
      if (fit < actions.length) visible = fit > 1 ? fit - 1 : 0;
    }
    final shown = actions.take(visible).toList();
    final overflow = actions.skip(visible).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...fixed,
        for (final action in shown) _KcToolbarIconButton(action: action),
        if (overflow.isNotEmpty)
          Builder(
            builder: (ctx) => IconButton(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedMoreVertical,
                size: kcSpace18,
              ),
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              tooltip: "More".tl,
              constraints: const BoxConstraints(
                minWidth: kcMinTapTarget,
                minHeight: kcMinTapTarget,
              ),
              padding: EdgeInsets.zero,
              splashRadius: kcMinTapTarget / 2,
              onPressed: () {
                final rb = ctx.findRenderObject() as RenderBox;
                showMenuX(
                  ctx,
                  rb.localToGlobal(Offset.zero),
                  [for (final a in overflow) a.toMenuEntry()],
                  anchorSize: rb.size,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _KcToolbarIconButton extends StatelessWidget {
  const _KcToolbarIconButton({required this.action});

  final KcToolbarAction action;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: HugeIcon(icon: action.icon, size: kcSpace18),
      color: action.color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      tooltip: action.label,
      onPressed: action.enabled ? action.onTap : null,
      constraints: const BoxConstraints(
        minWidth: kcMinTapTarget,
        minHeight: kcMinTapTarget,
      ),
      padding: EdgeInsets.zero,
      splashRadius: kcMinTapTarget / 2,
    );
  }
}

/// B · 内容区顶部常驻的横滑筛选行。
///
/// 关键不是「把筛选搬到下面」，而是让「当前按什么筛/排」在结果页上有文字
/// 证据（选中态常驻），并给出结果数；排序作为独立 chip 混在同一行但语义
/// 分开——它点开的是单选弹窗，不是筛选面板。
///
/// 第二行是辅助操作区：左边「显示 N 项 / 重置」，右边固定位放全站共用的
/// [ToolsPillLayoutButton]，其后 [KcActionOverflowBar] 把多选 / 管理 / 删除等
/// 动作默认全部平铺出来；只有窄屏、大字号这类真的放不下的情况，末尾几枚才收进 ⋮。
class KcFilterChipRow extends StatelessWidget {
  const KcFilterChipRow({
    super.key,
    required this.chips,
    this.resultCount,
    this.onReset,
    this.actions = const <KcToolbarAction>[],
    this.fixedActions = const <Widget>[],
  });

  final List<KcFilterChipData> chips;
  final int? resultCount;
  final VoidCallback? onReset;

  /// 右侧辅助动作：默认全部平铺成可见按钮，只有宽度真的不够时才由
  /// [KcActionOverflowBar] 把末尾几枚收进 ⋮。
  final List<KcToolbarAction> actions;

  /// 不参与收拢的固定按钮：[ToolsPillLayoutButton] 与网络文件夹「同步」的
  /// Flyout（自带 context）。
  final List<Widget> fixedActions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = resultCount;
    final reset = onReset;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kcSpaceLg,
        vertical: kcSpaceXs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: kcMinTapTarget,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: chips.length,
              separatorBuilder: (_, __) => const SizedBox(width: kcSpaceXs),
              itemBuilder: (_, i) => KcPillChip(
                label: chips[i].label,
                selected: chips[i].selected,
                onTap: chips[i].onTap,
                count: chips[i].count,
                showArrow: chips[i].showArrow,
              ),
            ),
          ),
          if (count != null ||
              reset != null ||
              actions.isNotEmpty ||
              fixedActions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kcSpaceXs),
              child: LayoutBuilder(
                builder: (context, rowConstraints) {
                  // 结果数文字最多占半行，剩下的宽度全留给动作按钮：
                  // 长语言 / 大字号下也不会把按钮挤成窄缝或整行溢出。
                  final labelMaxWidth = rowConstraints.maxWidth / 2;
                  return Row(
                    children: [
                      if (count != null)
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: labelMaxWidth),
                          child: Text(
                            "Showing @c items".tlParams({'c': count}),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: kcCaption,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (reset != null)
                        Button.text(
                          onPressed: reset,
                          height: 32,
                          padding: const EdgeInsets.symmetric(
                            horizontal: kcSpaceSm,
                          ),
                          child: Text(
                            "Reset".tl,
                            style: TextStyle(fontSize: kcCaption),
                          ),
                        ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: LayoutBuilder(
                            builder: (actionContext, actionConstraints) =>
                                KcActionOverflowBar(
                              actions: actions,
                              fixed: fixedActions,
                              maxWidth: actionConstraints.maxWidth,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// 贴底工具条相对 [kcPageBottomInset] 的额外抬升。
///
/// 底栏是浮岛式胶囊，除了底部的系统手势区，顶部也有一圈 margin；而
/// [kcPageBottomInset] 只算了「栏体 + 下方留白 + 手势区」。直接用它当
/// `Positioned.bottom` 时实拍量到工具条底边压进 dock 约 7dp。两页统一加
/// 这段，列表底部留白也读同一个常量，保证末行能滚到工具条上方。
const double kcDockedToolbarLift = kcSpaceLg;

/// C · 多选模式的贴底工具条。
///
/// 由页面用 `Positioned(bottom: kcPageBottomInset(context))` 放在浮岛 dock
/// 上方；这里只负责胶囊外观与动作槽，不自己决定位置。顶栏在多选态清空，
/// 所有选择动作都落在单手可达的下半屏。
class KcDockedToolbar extends StatelessWidget {
  const KcDockedToolbar({
    super.key,
    required this.actions,
    this.selectedCount,
    this.onExit,
  });

  final List<Widget> actions;
  final int? selectedCount;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = selectedCount;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kcContentMaxWidth),
          child: Material(
            color: cs.surfaceContainerHigh,
            elevation: 3,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(kcPillRadius),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kcPillRadius),
                border: Border.all(
                  color: kcHairlineColor(context),
                  width: kcHairline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (count != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: kcSpaceLg),
                      child: Text(
                        "Selected @c comics".tlParams({'c': count}),
                        style: TextStyle(
                          fontSize: kcCaption,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: kcSpaceSm),
                  ],
                  ...actions,
                  if (onExit != null)
                    IconButton(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedCancel01,
                        size: kcSpace18,
                        color: cs.onSurfaceVariant,
                      ),
                      tooltip: "Exit Multi-Select".tl,
                      constraints: const BoxConstraints(
                        minWidth: kcMinTapTarget,
                        minHeight: kcMinTapTarget,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: onExit,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
