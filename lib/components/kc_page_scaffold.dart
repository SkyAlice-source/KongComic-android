part of 'components.dart';

// ════════════════════════════════════════════════════════════════════
// 二级页统一外壳（方案 F · 骨架归一）
//
// 改这个组件之前先看清楚它「不做什么」：
//   · 不改任何卡片：KcEntryBox / ToolsPill / 货架封面卡 / 玻璃 5-tab dock
//     的形状、圆角、描边、面色、字号、图标、动效全部保持原样。
//   · 不另造顶栏：内部直接复用 SliverAppbar，只是把「高度 / 标题基准 /
//     动作槽 / 底部让位」这几个反复分叉的参数收口到一个宿主里。
//
// 收口前二级页有 4 种顶栏宿主：Scaffold(appBar: Appbar)、
// Scaffold(body: CustomScrollView[SliverAppbar])、纯 Column 自绘 header、
// 无 Scaffold 的 SliverSearchBar；底部让位有 4 套写法。这里统一成 1 个。
// ════════════════════════════════════════════════════════════════════

/// 页面底部统一让位：悬浮玻璃 dock 高度（已含系统栏内边距）+ 一段呼吸空间。
///
/// 注意 [SmoothCustomScrollView] 会自动再补一次 `context.padding.bottom`，
/// 所以 [KcPageScaffold] 内部用裸 `CustomScrollView`，避免两次叠加把内容
/// 顶得过高。找不到 NaviPane（独立路由 / 弹层里的预览）时退化为系统栏高度。
double kcPageBottomInset(BuildContext context) {
  final pane = context.findAncestorStateOfType<NaviPaneState>();
  return (pane?.bottomBarHeight ?? MediaQuery.of(context).padding.bottom) +
      kcPageBottomGap;
}

/// 把一段内容收敛到统一内容列并居中。
///
/// 平板 2560dp 时网格会被拉成 7 列、右侧留大片空白；主页早先已有 900dp
/// 上限，这里让主页之外的英雄卡 / 设置详情 / 分组头也读同一个令牌。
/// Compact 下可用宽小于 900，等价于不约束，手机外观不变。
class KcPageContent extends StatelessWidget {
  const KcPageContent({
    super.key,
    required this.child,
    this.maxWidth = kcContentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// 二级页统一外壳：顶栏唯一、标题基准唯一、底部让位唯一。
///
/// [titleGap] 默认 8：`SliverAppbar` 左缘固定 8，加上 48dp 返回键后
/// `8 + 48 + 8 = 64`，与根页共享顶栏「16 padding + 48 leading + 标题」的
/// 水平基准一致；旧默认值 16 会让二级页标题比根页右移 8dp（实拍 52：
/// x=322 vs 根页 x=270）。
class KcPageScaffold extends StatelessWidget {
  const KcPageScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.leading,
    this.actions,
    this.titleGap = kcSpaceSm,
    this.bottomInset,
    this.style = AppbarStyle.blur,
    this.shadowOnScroll = false,
    this.backgroundColor,
    this.controller,
  });

  final Widget title;
  final List<Widget> slivers;

  /// 不传时 [SliverAppbar] 依据 `Navigator.canPop()` 自动生成统一返回键。
  final Widget? leading;
  final List<Widget>? actions;
  final double titleGap;

  /// 不传时由 [kcPageBottomInset] 统一计算。
  final double? bottomInset;
  final AppbarStyle style;
  final bool shadowOnScroll;
  final Color? backgroundColor;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: CustomScrollView(
        controller: controller,
        slivers: [
          SliverAppbar(
            title: title,
            leading: leading,
            actions: actions,
            titleGap: titleGap,
            height: kcRootTopBarHeight,
            style: style,
            shadowOnScroll: shadowOnScroll,
          ),
          ...slivers,
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: bottomInset ?? kcPageBottomInset(context),
            ),
          ),
        ],
      ),
    );
  }
}
