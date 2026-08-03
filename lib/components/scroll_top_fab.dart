import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';

/// 回顶悬浮按钮的统一样式。
///
/// 暗色模式：使用 [ColorScheme.surfaceContainerHighest]（实心），
///   避免按钮与深色背景融为一体（之前纯 surface 在暗色下几乎看不见）。
/// 浅色模式：半透明 [ColorScheme.surface] + 细描边，呈现玻璃质感，
///   不再是一块死白的实心圆。
({Color background, Color foreground, BorderSide? side}) scrollTopFabColors(
  BuildContext context,
) {
  final cs = Theme.of(context).colorScheme;
  if (cs.brightness == Brightness.dark) {
    return (
      background: cs.surfaceContainerHighest,
      foreground: cs.onSurface,
      side: null,
    );
  }
  return (
    background: cs.surface.withValues(alpha: 0.82),
    foreground: cs.onSurface.withValues(alpha: 0.92),
    side: BorderSide(color: cs.outline.withValues(alpha: 0.16), width: 1),
  );
}

/// 统一的「回到顶部」悬浮按钮。
///
/// 三个页面（发现页 / 历史页 / 漫画详情页）共用此组件，确保图标、尺寸、
/// 圆角、明暗样式完全一致。[avoidNavBar] 为 true 时（带底部导航栏的页面）
/// 自动抬升到 [NaviPane] 之上，避免被导航栏遮挡，同时也与无导航栏的详情页
/// 形成一致的视觉基线。
class ScrollTopFab extends StatelessWidget {
  final VoidCallback onPressed;
  final bool avoidNavBar;
  final String? heroTag;

  const ScrollTopFab({
    super.key,
    required this.onPressed,
    this.avoidNavBar = false,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final colors = scrollTopFabColors(context);
    final fab = FloatingActionButton(
      heroTag: heroTag,
      onPressed: onPressed,
      shape: CircleBorder(side: colors.side ?? BorderSide.none),
      backgroundColor: colors.background,
      foregroundColor: colors.foreground,
      elevation: 2,
      child: HugeIcon(icon: HugeIcons.strokeRoundedArrowUp01, size: 18),
    );
    if (avoidNavBar) {
      return Padding(
        padding: EdgeInsets.only(bottom: NaviPane.of(context).bottomBarHeight),
        child: fab,
      );
    }
    return fab;
  }
}
