import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:kong_comic/design_tokens.dart';

/// 通用「选中态胶囊」：选中 = accent 红实心底 + `kcOnAccentColor` 前景；
/// 未选中 = 透明底 + `outlineVariant` 发丝描边（[kcHairline]）。
///
/// 取代散落各页的手写选中胶囊，保证「同一处选中」不再分叉成多种形状
/// / 多种红（见 comic_source_page 顶栏过滤胶囊的统一史）。
/// 行式胶囊（侧栏文件夹行，带计数徽标 / trailing）结构不同，勿强行套用。
class KcPillChip extends StatelessWidget {
  const KcPillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.height = 32,
    this.horizontalPadding = 14,
  });

  final String label;

  final bool selected;

  final VoidCallback onTap;

  /// HugeIcons 路径数据（`List<List<dynamic>>`，不是 IconData），可选。
  final List<List<dynamic>>? icon;

  final double height;

  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kcPillRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: height,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          decoration: BoxDecoration(
            color: selected ? kcAccentColor(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(kcPillRadius),
            border: Border.all(
              color: selected ? Colors.transparent : cs.outlineVariant,
              width: kcHairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                HugeIcon(
                  icon: icon!,
                  size: 15,
                  color: selected ? kcOnAccentColor : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: kcBody,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? kcOnAccentColor : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
