import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';

/// 回顶悬浮按钮的统一样式。
///
/// 配色与翻页胶囊共用 [kcFloatingGlassColors]：两个控件经常同屏（发现页分页
/// 模式底部并排），一处改两处一起变，不会出现「一个半透明、一个实心」。
({Color background, Color foreground, BorderSide? side}) scrollTopFabColors(
  BuildContext context,
) => kcFloatingGlassColors(context);

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
      // Material 3 Expressive：标准尺寸（56dp）实心 FAB，比 mini 更具存在感。
      mini: false,
      onPressed: onPressed,
      shape: CircleBorder(side: colors.side ?? BorderSide.none),
      backgroundColor: colors.background,
      foregroundColor: colors.foreground,
      elevation: 0,
      highlightElevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      disabledElevation: 0,
      child: HugeIcon(icon: HugeIcons.strokeRoundedArrowUp01, size: 22),
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
