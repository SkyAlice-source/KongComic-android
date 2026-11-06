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
// 空态不再在这里另起一套：全 App 统一用 components.dart 的 EmptyState
// （角色插画 + 标题 + 副标题 + 主/次 CTA），避免两套空态字重与内边距漂移。
// 后续可把设置页的私有件也改走这里，彻底去重。
// ════════════════════════════════════════════════════════════════════

/// 行的左右内缩：全库页面外壳的唯一水平栅格。
/// 设置 / 分类 / 发现 / 速搜各页都读这个值，不再各自写 20 / 28 / 16。
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

/// 分区标题：替代把原生 Material 列表行当分区标题用的错误写法。
/// 小一号、灰色、带字距，与设置页 _SettingPartTitle 同一套语言；上边距比下边距大，
/// 形成组的呼吸感。
class KcSectionHeader extends StatelessWidget {
  const KcSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    this.onTap,
    this.topPadding,
    this.padding,
    this.showDivider = false,
    this.fontSize,
  });

  final String title;
  final Widget? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// 分区与上一块内容的竖向间距。默认 [kcSpace18]；宽屏应显式传
  /// `kcSectionGap(context)`，让 20/28 两档随尺寸类别切换。
  final double? topPadding;

  /// 完全覆盖内缩（少数侧栏里的分区头有自己的栅格），优先级高于 [topPadding]。
  final EdgeInsetsGeometry? padding;

  /// 是否在标题下方补一条发丝线。追更页两处带下边框的分组标题走这个开关，
  /// 线宽 / 颜色统一到 `kcHairline` + `kcHairlineColor`。
  final bool showDivider;

  /// 大分区标题可显式升档（如追更页的 `kcSectionTitle`），默认 [kcCaption]。
  /// 只允许用 kc* 语义阶梯，不再各自写 12 / 16 / 17 / 22。
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final header = Padding(
      padding: padding ??
          EdgeInsets.fromLTRB(
            kcRowInsetH,
            topPadding ?? kcSpace18,
            kcRowInsetH,
            kcSpace6,
          ),
      child: Row(
        children: [
          if (icon != null)
            IconTheme.merge(
              data: IconThemeData(
                size: kcSpaceLg,
                color: cs.onSurfaceVariant.withValues(alpha: 0.65),
              ),
              child: icon!,
            ),
          if (icon != null) const SizedBox(width: kcSpaceSm),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: fontSize ?? kcCaption,
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
    final decorated = showDivider
        ? DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: kcHairlineColor(context),
                  width: kcHairline,
                ),
              ),
            ),
            child: header,
          )
        : header;
    if (onTap == null) return decorated;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: cs.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.035)
            : Colors.black.withValues(alpha: 0.025),
        child: decorated,
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
    this.contentPadding,
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

  /// 覆盖默认内缩（默认 `horizontal: kcRowInsetH, vertical: 12`）。
  ///
  /// 只给「已在父级做过内缩、行本身需要贴边」的场景用（如卡片内的一行），
  /// 其余一律留空走默认值，避免又出现两套 inset。
  final EdgeInsetsGeometry? contentPadding;

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
        // 无障碍下限：默认内边距下整行只有 42.9dp（14×1.35 + 12×2），比 M3 要求的
        // 48dp 点击区少 5dp，指腹落在两行交界处容易点进邻行。ConstrainedBox 把
        // minHeight 一路传给 InkWell / Padding / Row，内容自然垂直居中，只多 5dp。
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kcMinTapTarget),
          child: Material(
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
                padding:
                    contentPadding ??
                    const EdgeInsets.symmetric(
                      horizontal: kcRowInsetH,
                      vertical: 12,
                    ),
                child: row,
              ),
            ),
          ),
        ),
        if (showDivider) const KcRowDivider(),
      ],
    );
  }
}

// KcEmptyState 已移除：原先它（500 字重 / 14·12 字号 / 32+48 内缩）与
// EmptyState（600 字重 / 14 副标题 / 40 内缩 / 角色插画 + 双 CTA）并存，
// 却全库零引用。空态只有一种，统一到 components.dart 的 EmptyState。
