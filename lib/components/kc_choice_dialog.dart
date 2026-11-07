part of "components.dart";

// ════════════════════════════════════════════════════════════════════
// 单选 / 筛选弹窗的统一外观（参考式样）
//
// 参考式样四要素：大圆角浅色卡、左上角粗标题、红色圆环 + 实心圆点的
// 单选项、右下角红色全圆胶囊「确认」。旧式样散在四处：本地漫画排序用
// 自绘 Material 卡 + 原生 RadioListTile，图片收藏排序用 ContentDialog +
// TabBar + 原生 RadioListTile，收藏 / 历史筛选用 ContentDialog + 下拉
// Select（一点即生效，没有确认），通用 showSelectDialog 又是下拉 Select。
// 现在统一到 KcChoiceDialog / KcRadioOption / KcChoiceTabBar /
// showKcRadioDialog 四件套。
//
// 实拍二次收紧：首版把参考图的「宽行距」照搬成 60dp 行高 + 20sp 文字，
// 在 411dp 手机上 5 个选项就把弹窗顶满整屏，标题与 tab 还互相重复。
// 现在降到 16sp / 48dp、选中行给淡色底、标题随 tab 变化、分段控件等宽，
// 保留大圆角 / 红环 / 红胶囊三个记忆点，信息密度回到手机上舒适的范围。
//
// 不改业务语义：所有选择仍然在「确认」时一次性落盘；点遮罩 / 返回键取消。
// ════════════════════════════════════════════════════════════════════

/// 参考式样弹窗外壳：大圆角面 + 粗标题 + 内容 + 右下红色胶囊确认。
///
/// [content] 由调用方决定（单选列、Tab 分页、说明文字均可）；外壳只负责
/// 统一的圆角 / 内边距 / 标题层级 / 确认按钮，不替业务做选择。
class KcChoiceDialog extends StatelessWidget {
  const KcChoiceDialog({
    super.key,
    required this.title,
    required this.content,
    this.subtitle,
    this.onConfirm,
    this.confirmText,
    this.confirmEnabled = true,
    this.onCancel,
    this.maxWidth = kcChoiceDialogMaxWidth,
  });

  final String title;
  final String? subtitle;
  final Widget content;

  /// 右下角红色胶囊的回调；不传则不画按钮（纯信息弹窗）。
  final VoidCallback? onConfirm;

  /// 自定义确认文案，默认 `Confirm`.tl。
  final String? confirmText;

  /// 未选任何项时置灰并禁用，保留「先选再确认」的语义。
  final bool confirmEnabled;

  /// 可选的文字「取消」；参考式样本身没有，需要显式双按钮时才传。
  final VoidCallback? onCancel;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = kcAccentColor(context);
    final label = confirmText ?? "Confirm".tl;
    final isDark = cs.brightness == Brightness.dark;
    return Dialog(
      shape: RoundedRectangleBorder(
        // 四角圆弧与 ContentDialog / QuickSearchDialog / 整理弹窗同为
        // kcSurfaceRadius（kcDialogRadius 已指向它），描边也补齐：显式设
        // shape 会覆盖全局 dialogTheme，不写 side 就只有这个弹窗没有
        // 深色下的凝光轮廓。
        borderRadius: BorderRadius.circular(kcDialogRadius),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      insetPadding: const EdgeInsets.all(kcDialogInset),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: cs.surfaceContainerHigh,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(kcDialogInset),
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
              if (subtitle != null) ...[
                const SizedBox(height: kcSpaceSm),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: kcBody,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: kcSpaceLg),
              content,
              if (onConfirm != null || onCancel != null) ...[
                const SizedBox(height: kcSpace18),
                Row(
                  children: [
                    if (onCancel != null)
                      Button.text(
                        onPressed: onCancel!,
                        child: Text("Cancel".tl),
                      ),
                    const Spacer(),
                    if (onConfirm != null)
                      Semantics(
                        button: true,
                        enabled: confirmEnabled,
                        label: label,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(kcPillRadius),
                          onTap: confirmEnabled ? onConfirm : null,
                          child: AnimatedContainer(
                            duration: kcReduceMotion(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            height: kcDialogConfirmHeight,
                            padding: const EdgeInsets.symmetric(
                              horizontal: kcDialogConfirmPadding,
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: confirmEnabled
                                  ? accent
                                  : cs.onSurfaceVariant.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(kcPillRadius),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: kcFont15,
                                fontWeight: FontWeight.w600,
                                color: kcOnAccentColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 等宽分段控件：弹窗里「排序 / 筛选」这类两态切换用。
///
/// 与 AppTabBar（下划线 + 自动宽度滑块）不同：弹窗宽度有限，两个 tab 必须
/// 各占一半、滑块也是半宽，才不会出现「红色小块孤零零贴在左边、右边一大片
/// 空白」的失衡感。选中态沿用品牌红 + [kcOnAccentColor]，与确认按钮同源。
class KcChoiceTabBar extends StatelessWidget {
  const KcChoiceTabBar({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = kcAccentColor(context);
    return Container(
      height: kcDialogTabHeight,
      padding: const EdgeInsets.all(kcSpaceXs),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kcPillRadius),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                selected: index == i,
                button: true,
                label: labels[i],
                child: InkWell(
                  borderRadius: BorderRadius.circular(kcPillRadius),
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: kcReduceMotion(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 160),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: index == i ? accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(kcPillRadius),
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: kcBody,
                        fontWeight:
                            index == i ? FontWeight.w600 : FontWeight.w500,
                        color: index == i
                            ? kcOnAccentColor
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 参考式样单选项：红色圆环 + 红色实心圆点（选中）/ 中性灰空心圆环（未选）。
///
/// 不用 Material 的 [Radio]：它的 18dp 小圈与按压水波在紧凑行高里太挤，
/// 而且选中色会随 ColorScheme 走，绿色 / 蓝色主题下会冒出一颗非品牌色的点。
/// 选中行给一层极淡的品牌色底，代替首版「12dp 宽行距」的分组方式——
/// 手机上不再散成一列互不相干的大字，大字号时行高也能自己撑开。
class KcRadioOption<T> extends StatelessWidget {
  const KcRadioOption({
    super.key,
    required this.value,
    required this.groupValue,
    required this.label,
    required this.onChanged,
    this.height = kcDialogOptionHeight,
  });

  final T value;
  final T? groupValue;
  final String label;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final cs = Theme.of(context).colorScheme;
    final accent = kcAccentColor(context);
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(kcCardRadius),
        child: AnimatedContainer(
          duration: kcReduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          // minHeight 而非固定 SizedBox：系统字号 1.3 时 16sp 中文会顶到
          // 20.8sp，行自己长高，不会把第二行字压在框里。
          constraints: BoxConstraints(minHeight: height),
          padding: const EdgeInsets.symmetric(horizontal: kcSpaceMd),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.09)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(kcCardRadius),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: kcReduceMotion(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                width: kcRadioOuter,
                height: kcRadioOuter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    // 参考式样的未选圈是深炭灰，不是 M3 outline 的浅灰；
                    // 深色下 onSurfaceVariant 又自然翻成亮灰，两端都够对比。
                    color: selected ? accent : cs.onSurfaceVariant,
                    width: selected
                        ? kcRadioRingSelected
                        : kcRadioRingIdle,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: kcRadioInner,
                          height: kcRadioInner,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: kcSpaceMd),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: kcSubtitle,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一组单选 + 确认，返回被选中的值；点遮罩 / 返回键 / 未选即取消均返回 null。
///
/// [options] 用命名 record，调起来是 `(value: ..., label: "Name".tl)`，
/// 不必在调用处再造一层 Map / 索引映射。
Future<T?> showKcRadioDialog<T>({
  required BuildContext context,
  required String title,
  required List<({T value, String label})> options,
  T? initial,
  String? confirmText,
}) {
  T? selected = initial;
  return showDialog<T?>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => KcChoiceDialog(
        title: title,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < options.length; i++) ...[
              KcRadioOption<T>(
                value: options[i].value,
                groupValue: selected,
                label: options[i].label,
                onChanged: (v) => setState(() => selected = v),
              ),
              if (i < options.length - 1)
                const SizedBox(height: kcDialogRowGap),
            ],
          ],
        ),
        confirmEnabled: selected != null,
        confirmText: confirmText,
        onConfirm: () => Navigator.pop(context, selected),
      ),
    ),
  );
}
