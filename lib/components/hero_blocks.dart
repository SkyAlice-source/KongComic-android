import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

// MenuEntry / showMenuX 经 components.dart 的 part（menu.dart）导出；
// HugeIcons、design tokens 也全部由 components.dart 转出；
// colorScheme 扩展在 foundation/context.dart；tl / tlParams 在 translations。
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/context.dart';
import 'package:kong_comic/foundation/history.dart';
import 'package:kong_comic/utils/translations.dart';

/// 方案 A（收藏/历史页配合主页风格）的公共部件集。
///
/// 全部只使用主页既有设计词汇：品牌红唯一强调色、胶囊 999、卡片圆角
/// 12/20、正文 kcBody / 辅助 kcCaption、hairline 描边。唯一新增图形元素
/// 是 3px 品牌红「页内进度条」——把"读到哪里"从文字升级为可扫视的图形。

/// 封面通用加载：http(s) 走网络缓存，本地路径走 FileImage，失败出占位图标。
Widget kcCoverImage(String cover, {BoxFit fit = BoxFit.cover}) {
  if (cover.startsWith('http')) {
    return CachedNetworkImage(
      imageUrl: cover,
      fit: fit,
      filterQuality: FilterQuality.high,
      placeholder: (_, __) => const SizedBox(),
      errorWidget: (_, __, ___) => const _CoverPlaceholder(),
    );
  }
  return Image(
    image: FileImage(File(cover)),
    fit: fit,
    filterQuality: FilterQuality.high,
    errorBuilder: (_, __, ___) => const _CoverPlaceholder(),
  );
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: HugeIcon(
        icon: HugeIcons.strokeRoundedImage01,
        size: 28,
        color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

/// 3px 页内进度条：方案 A 的统一进度语言。maxPage 未知（null/0）时不渲染。
class KcPageProgressBar extends StatelessWidget {
  const KcPageProgressBar({super.key, required this.history, this.height = 3});

  final History history;
  final double height;

  @override
  Widget build(BuildContext context) {
    final maxPage = history.maxPage ?? 0;
    if (maxPage <= 0) return const SizedBox.shrink();
    final ratio = (history.page / maxPage).clamp(0.0, 1.0);
    return Semantics(
      label: "Read @p percent".tlParams({'p': (ratio * 100).round()}),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: context.colorScheme.onSurface.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(height / 2),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: ratio,
          child: Container(
            decoration: BoxDecoration(
              color: kcAccentColor(context),
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
        ),
      ),
    );
  }
}

/// 续读英雄卡 —— 历史页顶部的「最近在读」。主页英雄卡 + 立即阅读按钮的
/// 直系翻译：surfaceContainerLow 大圆角卡、左封面右信息、品牌红胶囊主按钮。
class KcContinueHero extends StatelessWidget {
  const KcContinueHero({
    super.key,
    required this.history,
    required this.onOpen,
  });

  final History history;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 封面：12 圆角（kcCardRadius），与主页英雄卡一致。
                Container(
                  width: 76,
                  height: 104,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kcCardRadius),
                    color: cs.surfaceContainerHighest,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: kcCoverImage(history.cover),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        history.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: kcTitleLarge - 7, // 15：介于正文与标题之间
                          fontWeight: FontWeight.bold,
                          height: 1.25,
                        ),
                      ),
                      if (history.subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            history.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: kcCaption,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 8),
                        child: KcPageProgressBar(history: history),
                      ),
                      Material(
                        color: kcAccentColor(context),
                        borderRadius: BorderRadius.circular(kcPillRadius),
                        child: InkWell(
                          onTap: onOpen,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                HugeIcon(
                                  icon: HugeIcons.strokeRoundedPlay,
                                  size: 14,
                                  color: kcOnAccentColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  "Continue Reading".tl,
                                  style: TextStyle(
                                    fontSize: kcCaption,
                                    fontWeight: FontWeight.w600,
                                    color: kcOnAccentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 入口胶囊卡 —— 主页 `_FlatBox` 同款语言（图标 + 标签 + 数量徽标），
/// 收藏页顶部用作「收藏空间导航」。与主页组件合并收口留给第二批。
class KcEntryBox extends StatelessWidget {
  const KcEntryBox({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.highlight = false,
  });

  final Widget icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kcRadius22),
          color: cs.surfaceContainerLow,
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: kcBody, color: cs.onSurface),
              ),
            ),
            if (value != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                decoration: BoxDecoration(
                  color: highlight
                      ? kcAccentColor(context)
                      : kcAccentSurface(context),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    value!,
                    style: TextStyle(
                      fontSize: kcFont11,
                      fontWeight: FontWeight.w600,
                      color: highlight ? kcOnAccentColor : kcBrandAdaptive(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 历史分组吸顶组头：胶囊样式（hairline 描边）+ 条数。
class KcGroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  const KcGroupHeaderDelegate({required this.label, required this.count});

  final String label;
  final int count;

  static const double _height = 40;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final cs = context.colorScheme;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 16, right: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kcPillRadius),
              border: Border.all(color: cs.outlineVariant, width: kcHairline),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: kcCaption,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: kcCaption,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant KcGroupHeaderDelegate old) =>
      old.label != label || old.count != count;
}

/// 历史行 —— 方案 A 的紧凑 tile：小封面（底部内嵌页内进度条）+ 标题 /
/// 章节子题 / 进度 meta + 右侧相对时间。行高 ~80，替代原 152 的松散行。
class KcHistoryTile extends StatelessWidget {
  const KcHistoryTile({
    super.key,
    required this.history,
    required this.onTap,
    this.onLongPressed,
    this.menuOptions,
    this.selected = false,
    this.timeLabel,
  });

  final History history;
  final VoidCallback onTap;
  final VoidCallback? onLongPressed;
  final List<MenuEntry>? menuOptions;
  final bool selected;
  final String? timeLabel;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final chapter = history.ep >= 1 ? "Chapter @ep".tlParams({'ep': history.ep}) : '';
    final page = history.page >= 1 ? "Page @page".tlParams({'page': history.page}) : '';
    final meta = [chapter, page].where((s) => s.isNotEmpty).join(' · ');

    return Material(
      color: selected
          ? cs.secondaryContainer.withValues(alpha: 0.72)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 56,
                    height: 74,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: cs.surfaceContainerHighest,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: kcCoverImage(history.cover),
                  ),
                  // 页内进度条压在封面底缘（替代原深色文字胶囊）。
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: KcPageProgressBar(history: history, height: 3),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      history.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: kcBody,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    if (history.subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          history.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: kcCaption,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: kcCaption,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timeLabel ?? '',
                style: TextStyle(fontSize: kcCaption, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              ),
              if (menuOptions != null && menuOptions!.isNotEmpty)
                _TileMenuButton(options: menuOptions!),
            ],
          ),
        ),
      ),
    );
  }
}

class _TileMenuButton extends StatelessWidget {
  const _TileMenuButton({required this.options});

  final List<MenuEntry> options;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: HugeIcon(
        icon: HugeIcons.strokeRoundedMoreVertical,
        size: 18,
        color: context.colorScheme.onSurfaceVariant,
      ),
      tooltip: "More".tl,
      onPressed: () {
        final rb = context.findRenderObject() as RenderBox;
        showMenuX(context, rb.localToGlobal(Offset.zero), options);
      },
    );
  }
}
