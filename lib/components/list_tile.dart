import 'package:flutter/material.dart';

import 'package:kong_comic/components/components.dart';

// ════════════════════════════════════════════════════════════════════
// 通用列表 / 分区元件（2026-10-20 抽取）
//
// 设置页重做时沉淀了一套克制、统一的视觉语言（_KcSettingTile / _KcChevron /
// _KcRowDivider / _KcValueChip / _SettingPartTitle），但那些都还是
// `part of 'settings_page.dart'` 的私有件，浏览类页面没法复用，于是各页还在
// 散用 Material 默认 ListTile、或直接拿 ListTile 当分区标题，造成「分裂」。
//
// 这里把它们抽成**公开、与业务无关**的基础件，供全 App（阅读器除外）复用：
//   KcSectionHeader  分区标题（替代把 ListTile 当标题用的错误写法）
//   KcListTile       通用列表行（替代散落的 Material ListTile）
//   KcRowDivider     发丝分隔线（两端渐隐，AMOLED 下不消失）
//   KcValueChip      行内当前值胶囊
//   KcChevron        弱化的右 / 下箭头
//   KcEmptyState     统一空态
// 后续可把设置页的私有件也改走这里，彻底去重。
// ════════════════════════════════════════════════════════════════════

/// 行的左右内缩。与设置页 _kcRowInset 一致，文字与发丝线之间留出呼吸。
const double kcRowInsetH = 20;

/// 弱化的右 / 下箭头：列表行里的箭头是「可以进去」的提示，不该和正文抢注意力，
/// 统一压低到 onSurfaceVariant 的 42%。
class KcChevron extends StatelessWidget {
  const KcChevron({super.key, this.down = false, this.size = 18});

  final bool down;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return HugeIcon(
      icon: down
          ? HugeIcons.strokeRoundedArrowDown01
          : HugeIcons.strokeRoundedArrowRight01,
      size: size,
      color: cs.onSurfaceVariant.withValues(alpha: 0.42),
    );
  }
}

/// 行与行之间的发丝线。不用 `outlineVariant`：AMOLED 下它约为 #2A2A2A，和纯黑底
/// 只差一点点，截图里几乎整条线消失；亮色下又偏灰。改为按亮度取黑 / 白 + 极低透明度，
/// 两端 8% 渐变淡出，视觉上是一条柔和的定位线，而不是硬切的表格框。
class KcRowDivider extends StatelessWidget {
  const KcRowDivider({super.key, this.inset = kcRowInsetH});

  final double inset;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final line = (isDark ? Colors.white : Colors.black).withValues(
      alpha: isDark ? 0.085 : 0.06,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: SizedBox(
        height: 0.7,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                line.withValues(alpha: 0),
                line,
                line,
                line.withValues(alpha: 0),
              ],
              stops: const [0, 0.08, 0.92, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// 行内当前值胶囊：裸的灰色文本在长行里看不出「这是一个可选项的当前值」；
/// 给一层极淡底 + 小圆角后，行内形成「标题 / 值」两段结构，扫视更快。
class KcValueChip extends StatelessWidget {
  const KcValueChip(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : cs.onSurface.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(kcRadius8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: kcBody,
          height: 1.3,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 分区标题：替代把 `ListTile(title: Text(...))` 当分区标题用的错误写法。
/// 小一号、灰色、带字距，与设置页 _SettingPartTitle 同一套语言；上边距比下边距大，
/// 形成组的呼吸感。
class KcSectionHeader extends StatelessWidget {
  const KcSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    this.onTap,
  });

  final String title;
  final Widget? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(kcRowInsetH, 18, kcRowInsetH, 6),
      child: Row(
        children: [
          if (icon != null)
            IconTheme.merge(
              data: IconThemeData(
                size: 16,
                color: cs.onSurfaceVariant.withValues(alpha: 0.65),
              ),
              child: icon!,
            ),
          if (icon != null) const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: kcCaption,
                height: 1.35,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: cs.onSurfaceVariant.withValues(alpha: 0.75),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
    if (onTap == null) return header;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: cs.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.035)
            : Colors.black.withValues(alpha: 0.025),
        child: header,
      ),
    );
  }
}

/// 通用列表行：替代散落的 Material ListTile，统一 inset / 排版 / 分隔线 / 箭头。
///
/// 与设置页 _KcSettingTile 同一套语言：整行点击区、无圆形水波（暗色下不脏）、
/// 20dp 内缩、标题 0.93 墨色（暗色下更像纸面印刷）、发丝分隔线。
class KcListTile extends StatelessWidget {
  const KcListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.showDivider = true,
    this.chevron = false,
    this.enabled = true,
  });

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool showDivider;
  final bool chevron;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleStyle = TextStyle(
      fontSize: kcBody,
      height: 1.35,
      fontWeight: FontWeight.w500,
      color: isDark ? cs.onSurface.withValues(alpha: 0.93) : cs.onSurface,
    );
    final captionStyle = TextStyle(
      fontSize: kcCaption,
      height: 1.35,
      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
    );

    final effectiveTrailing = chevron && trailing == null
        ? const KcChevron()
        : trailing;

    final row = Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                DefaultTextStyle.merge(style: titleStyle, child: title!),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: DefaultTextStyle.merge(
                    style: captionStyle,
                    child: subtitle!,
                  ),
                ),
            ],
          ),
        ),
        if (effectiveTrailing != null) ...[
          const SizedBox(width: 8),
        effectiveTrailing,
      ],
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: selected
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : cs.primary.withValues(alpha: 0.06))
              : Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            splashFactory: NoSplash.splashFactory,
            highlightColor: isDark
                ? Colors.white.withValues(alpha: 0.035)
                : Colors.black.withValues(alpha: 0.025),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kcRowInsetH,
                vertical: 12,
              ),
              child: row,
            ),
          ),
        ),
        if (showDivider) const KcRowDivider(),
      ],
    );
  }
}

/// 统一空态：图标 + 标题 + 可选副标题 / 操作，替代各处不一致的「空白提示」。
class KcEmptyState extends StatelessWidget {
  const KcEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final Widget icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: kcSubtitle,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: kcCaption,
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            if (action != null)
              Padding(padding: const EdgeInsets.only(top: 16), child: action!),
          ],
        ),
      ),
    );
  }
}
