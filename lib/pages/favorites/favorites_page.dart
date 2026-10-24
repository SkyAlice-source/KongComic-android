import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:sliver_tools/sliver_tools.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/components/scroll_top_fab.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_type.dart';
import 'package:kong_comic/foundation/consts.dart';
import 'package:kong_comic/foundation/bookshelf_layout.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/history.dart';
import 'package:kong_comic/foundation/listen_mixin.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/foundation/res.dart';
import 'package:kong_comic/network/download.dart';
import 'package:kong_comic/network/cache.dart';
import 'package:kong_comic/pages/comic_details_page/comic_page.dart';
import 'package:kong_comic/pages/comic_source_page.dart';
import 'package:kong_comic/pages/image_favorites_page/image_favorites_page.dart';
import 'package:kong_comic/pages/local_comics_page.dart';
import 'package:kong_comic/pages/reader/reader.dart';
import 'package:kong_comic/pages/search_page.dart';
import 'package:kong_comic/pages/settings/settings_page.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:kong_comic/utils/opencc.dart';
import 'package:kong_comic/utils/tags_translation.dart';
import 'package:kong_comic/utils/translations.dart';
import 'package:kong_comic/pages/favorites/recommend_basis.dart';

part 'favorite_actions.dart';
part 'side_bar.dart';
part 'local_favorites_page.dart';
part 'network_favorites_page.dart';

const _kLeftBarWidth = 256.0;

const _kTwoPanelChangeWidth = 720.0;

/// 相邻两本书之间的基础间距（倾斜外扩另算）。
const double _kShelfBookGap = 6.0;

/// 货架右缘渐隐宽度，同时也是横滑行末尾的留白（两者相等，滑到尽头时
/// 渐隐正好落在空白上，不会把最后一本封面擦淡）。
const double _kShelfEdgeFade = 24.0;

/// 书籍斜放角度（弧度）。负值 = 顶部向左倒，书脊落在左侧。
///
/// 角度刻意压得很小：既要一眼看出「斜放」，又要让绕底边旋转之后的封面上角
/// 仍然待在货架槽位里。历史越界 bug 的根因就是没给这点外扩留空间——
/// 行高恰好等于封面高，旋转后的上角直接探出去压到了标题行。
const double _kShelfLeanAngle = -0.05;

/// 绕底边中点倾斜后，封面相对原外框多占的尺寸。
///
/// 用来给货架槽位预留高度/水平留白，把「斜放」限制在几何上算得出来的范围内，
/// 而不是靠拍一个固定 padding 去兜。
class _ShelfLean {
  const _ShelfLean({
    required this.rise,
    required this.bleed,
    required this.sink,
  });

  /// 封面上角相对原外框向上多出的高度。
  final double rise;

  /// 倾斜侧（左侧）相对原外框多出的宽度。
  final double bleed;

  /// 翘起侧的**对角**底角往下沉了多少。
  ///
  /// 绕底边中点转必然一只角上翘、另一只角下沉；不把下沉量算进来，那半只角
  /// 就会被横向滚动区裁掉，圆角变成一刀切平。
  final double sink;

  static _ShelfLean of({required double width, required double height}) {
    final sin = math.sin(-_kShelfLeanAngle).abs();
    final cos = math.cos(_kShelfLeanAngle);
    // 绕底边中点旋转：最高点 = (w/2)·sinθ + h·cosθ，故相对原高多出
    // (w/2)·sinθ − h·(1−cosθ)；水平同理多出 h·sinθ − (w/2)·(1−cosθ)；
    // 最低点则比原底边低 (w/2)·sinθ。
    final rise = (width / 2) * sin - height * (1 - cos);
    final bleed = height * sin - (width / 2) * (1 - cos);
    return _ShelfLean(
      rise: rise > 0 ? rise : 0,
      bleed: bleed > 0 ? bleed : 0,
      sink: (width / 2) * sin,
    );
  }
}

/// 收藏页：顶栏（标题 / leading / 工具）已全部并入 NaviPane 共享顶栏，
/// 总览与各文件夹内页通过 [pushTopBar] 注入各自的顶栏内容。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> with AutoListenMixin {
  String? folder;

  bool isNetwork = false;

  FolderList? folderList;

  // 收藏页整体回顶按钮：复用与发现/历史页一致的 ScrollTopFab
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showFab = ValueNotifier(true);
  double _scrollPos = 0;

  /// 收藏变化：让模块级推荐依据缓存下次重算（发现页也会用到同一份依据）。
  void _onFavoritesChanged() {
    invalidateRecommendBasis();
    // 回调可能来自 dispose 之后的异步路径。
    if (mounted) setState(() {});
  }

  /// 顶栏注入签名（本页各视图共用一个写入器；同一时刻只有一个视图前台）。
  String? _topBarSig;

  /// 本页在 NaviPane 底栏里的索引（首次 build 时记录）。语义与历史页
  /// _syncTopBar 相同：不在前台时清签名，切回来能重新注入。
  int? _myPageIndex;

  /// 把本视图的顶栏 leading / 标题 / 操作同步进 NaviPane 共享顶栏。
  ///
  /// 写值机制与历史页 _syncTopBar 相同：不能在 build 期直接写 notifier
  /// （「build 期间 setState」会被框架丢弃），必须 post-frame；sig 由调用方
  /// 构造（含影响顶栏内容的全部因素），防重复注入。
  void pushTopBar({
    required String sig,
    Widget? leading,
    Widget? title,
    List<Widget>? actions,
    bool hideGlobalActions = false,
  }) {
    final pane = NaviPane.of(context);
    _myPageIndex ??= pane.currentPage;
    if (pane.currentPage != _myPageIndex) {
      _topBarSig = null;
      return;
    }
    if (_topBarSig == sig) return;
    _topBarSig = sig;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _myPageIndex == null) return;
      if (pane.currentPage != _myPageIndex) return;
      pane.pageLeadingNotifier.value = leading;
      pane.pageTitleNotifier.value = title;
      pane.pageActionsNotifier.value = actions;
      pane.pageHideGlobalActionsNotifier.value = hideGlobalActions;
    });
  }

  void setFolder(bool isNetwork, String? folder) {
    setState(() {
      this.isNetwork = isNetwork;
      this.folder = folder;
    });
    _showFab.value = true; // 切到别的文件夹后回到顶部，回顶按钮重新出现
    // 内联切换视图与换 tab 同理：新视图从顶部开始看，底栏放回来。
    // 否则在总览滚到深处（底栏已被滚动收起）点进文件夹，底栏一直不出现。
    NaviPane.of(context).setBottomBarCollapsed(false);
    folderList?.update();
    appdata.implicitData['favoriteFolder'] = {
      'name': folder,
      'isNetwork': isNetwork,
    };
    appdata.writeImplicitData();
  }

  @override
  void initState() {
    var data = appdata.implicitData['favoriteFolder'];
    if (data != null) {
      folder = data['name'];
      isNetwork = data['isNetwork'] ?? false;
    }
    if (folder != null &&
        !isNetwork &&
        !LocalFavoritesManager().existsFolder(folder!)) {
      folder = null;
    }
    // 不设默认文件夹：folder == null 就是「货架总览」，收藏 Tab 一进来先看
    // 各个文件夹的横排书架，而不是被硬塞进某个文件夹的网格里。
    listen(LocalFavoritesManager(), _onFavoritesChanged);
    // 排序等设置变化时重刷货架（内页里切的排序，回总览即刻生效）。
    listen(appdata.settings, _onFavoritesChanged);
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _showFab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedPositioned(
          left: context.width <= _kTwoPanelChangeWidth ? -_kLeftBarWidth : 0,
          top: 0,
          bottom: 0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: _kLeftBarWidth,
            color: Theme.of(context).colorScheme.surface,
            child: const _LeftBar(),
          ),
        ),
        Positioned(
          top: 0,
          left: context.width <= _kTwoPanelChangeWidth ? 0 : _kLeftBarWidth,
          right: 0,
          bottom: 0,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: buildBody(),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: ValueListenableBuilder<bool>(
            valueListenable: _showFab,
            builder: (context, visible, _) => AnimatedSwitcher(
              duration: kcReduceMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              reverseDuration: kcReduceMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              child: (visible && folder != null)
                  ? _buildScrollTopFab()
                  : const SizedBox(),
              transitionBuilder: (widget, animation) {
                final tween = Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: const Offset(0, 0),
                );
                return SlideTransition(
                  position: tween.animate(animation),
                  child: widget,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final current = n.metrics.pixels;
    if (current > _scrollPos && current != 0 && _showFab.value) {
      _showFab.value = false;
    } else if ((current < _scrollPos - 50 || current == 0) && !_showFab.value) {
      _showFab.value = true;
    }
    if (current > _scrollPos || current < _scrollPos - 50) {
      _scrollPos = current;
    }
    return false;
  }

  Widget _buildScrollTopFab() {
    return ScrollTopFab(
      avoidNavBar: true,
      heroTag: 'favoritesScrollTopFab',
      onPressed: () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      },
    );
  }

  void showFolderSelector() {
    // 用 showGeneralDialog 统一动画：遮罩与卡片同步淡入 + 轻微缩放。
    // 系统默认 DialogRoute 只淡入卡片，遮罩首帧就已铺满，慢设备上会先闪一屏灰。
    final reduceMotion = kcReduceMotion(context);
    showGeneralDialog(
      context: App.mainNavigatorKey?.currentContext ?? context,
      barrierDismissible: true,
      barrierLabel: 'Folders'.tl,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, __) =>
          _FolderSelectorDialog(favPage: this),
      transitionBuilder: (context, animation, _, child) {
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.93, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// 复刻 _LeftBarState.findNetworkFolders：从已启用源的 favoriteData 键与
  /// settings['favorites'] 求交集，得到网络分组文件夹列表。
  ///
  /// 只保留**已登录**的源：网络收藏挂在账号下，未登录的源不可能有收藏，
  /// 而装源时 [_addAllPagesWithComicSource] 会自动把 favoriteData.key 写进
  /// settings['favorites']，不过滤的话文件夹选择器/胶囊行就会排出一列
  /// 点了只会报错的死入口（用户反馈）。
  List<String> _computeNetworkFolders() {
    final all = ComicSource.enabled()
        .where((e) => e.favoriteData != null && e.isLogged)
        .map((e) => e.favoriteData!.key)
        .toList();
    final settings = appdata.settings['favorites'];
    final net = <String>[];
    if (settings is List) {
      for (var p in settings) {
        if (p is String && all.contains(p) && !net.contains(p)) {
          net.add(p);
        }
      }
    }
    return net;
  }

  /// 每个货架最多展示多少本（多出来的走「全部」）。
  static const int _shelfLimit = 12;

  void _openComic(Comic c) {
    App.mainNavigatorKey?.currentContext?.to(
      () => ComicPage(id: c.id, sourceKey: c.sourceKey, cover: c.cover),
    );
  }

  /// 货架式总览：每个文件夹一排横滑封面 + 网络分组入口 + 底部「推荐」。
  ///
  /// 与平铺网格的差别在「分组一眼可见」：一屏能同时看到每个文件夹各有什么，
  /// 而不是把所有漫画混在一起、再靠顶部胶囊猜自己在哪儿。
  Widget _buildOverview() {
    final hidden = BookshelfLayout.hiddenFolders;
    final folders = userFolderNames()
        .where((f) => !hidden.contains(f))
        .toList();

    // 总览态顶栏：标题「收藏」+ 统一工具胶囊（方向 A：全站根 tab 一种顶栏
    // 语言）。窄屏 [文件夹 | 搜索 | ⋮]，宽屏左栏已有文件夹管理，收成
    // [搜索 | ⋮]；设置收进 ⋮ 菜单，不再让全局裸图标散在标题旁。
    final narrow = context.width <= _kTwoPanelChangeWidth;
    pushTopBar(
      sig: 'ov_${narrow ? 'n' : 'w'}',
      title: Text(
        "Favorites".tl,
        style: TextStyle(fontSize: kcTitleMain, fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        ToolsPill(
          children: [
            if (narrow)
              ToolsPillButton(
                icon: HugeIcons.strokeRoundedFolder01,
                tooltip: "Folders".tl,
                onPressed: showFolderSelector,
              ),
            ToolsPillButton(
              icon: HugeIcons.strokeRoundedSearch02,
              tooltip: "Search".tl,
              onPressed: () => context.to(() => const SearchPage()),
            ),
            ToolsPillMoreButton(
              entries: [
                // 原总览 2×2 入口卡的次频项收编于此（全部收藏保留为高卡，
                // 网络收藏并进「文件夹」选择器）；设置用分隔线隔在最后。
                MenuEntry(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedBook02, size: 18),
                  text: "Local".tl,
                  onClick: () => context.to(() => const LocalComicsPage()),
                ),
                MenuEntry(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedImage01,
                    size: 18,
                  ),
                  text: "Image Favorites".tl,
                  onClick: () => context.to(() => const ImageFavoritesPage()),
                ),
                MenuEntry(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedGlobe02,
                    size: 18,
                  ),
                  text: "Comic Source".tl,
                  onClick: () => context.to(() => const ComicSourcePage()),
                ),
                MenuEntry.divider(),
                MenuEntry(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedSettings01,
                    size: 18,
                  ),
                  text: "Settings".tl,
                  onClick: () => context.to(() => const SettingsPage()),
                ),
              ],
            ),
          ],
        ),
      ],
      hideGlobalActions: true,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // 卡片宽度按内容区（而不是整屏）算：宽屏下左栏已占 256，
        // 用 MediaQuery 会把卡片算大一圈，一行连第 4 张的边都露不出来。
        // -52 = 左侧留白 16 + 右侧让位 24 + 两张卡间距 12。
        final cardW = math.max(96.0, (constraints.maxWidth - 52) / 3.3);
        // cardH 只是**封面**高度，按 0.7 宽高比（接近标准封面 2:3，减少裁切）。
        // 书名行的开销由 [_shelf] 自己按 [comicTileTitleBlock] 加上去——写死在
        // 这里就会和 ComicTile 的实际排版对不上，多出来的高度表现为整排下面的
        // 一片空白（不同字号档位下尤其明显）。
        final cardH = cardW / 0.7;

        final shelves = <Widget>[];
        for (final f in folders) {
          final shelf = _buildShelf(f, cardW, cardH);
          if (shelf != null) shelves.add(shelf);
        }

        final empty =
            shelves.isEmpty && _computeNetworkFolders().isEmpty;

        return CustomScrollView(
          controller: _scrollController,
          // 独立存储槽：文件夹视图会往同一个 PageStorage 桶里写滚动偏移，
          // 不加 key 时从深滚过的文件夹回到总览会落在半山腰。
          key: const PageStorageKey('favoritesOverview'),
          slivers: [
            // 方案 A：总览顶部「收藏空间导航」——主页 _FlatBox 同款语言的
            // 入口卡 2×2（全部收藏 / 网络收藏 / 图片收藏 / 漫画源）。
            // 文件夹内容仍由下方货架承担，这里只做空间导航与统计。
            if (!empty) ..._overviewEntryCards(),
            // 顶栏已并入 NaviPane 共享栏：标题「收藏」贴左，窄屏右上角
            // 保留「文件夹」入口（宽屏左栏常驻，无需重复）。原自绘
            // SliverAppbar 删除，样式由共享栏统一保证（同高/纯色/粗体标题）。
            if (empty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedFolder01,
                    size: 18,
                  ),
                  title: 'No favorites yet'.tl,
                  subtitle:
                      'Favorite a comic from any source and it shows up here.'
                          .tl,
                ),
              )
            else ...[
              for (final s in shelves) SliverToBoxAdapter(child: s),
            ],
            SliverToBoxAdapter(
              // 底栏是浮岛式、覆盖在页面之上的，必须按它的实际占位让出空间。
              // 只留系统手势区（context.padding.bottom）会让最后一行（网络入口）
              // 被压在底栏下面，滚到底也露不出来。
              child: SizedBox(
                height: NaviPane.of(context).bottomBarHeight + kcSpaceLg,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 总览入口卡：只留「全部收藏」一张高卡（KcEntryBox）。
  ///
  /// 原方案 A 的 2×2（本地/网络/图片收藏）与下方货架、文件夹选择器职责
  /// 重复，已按反馈瘦身：次频入口收进顶栏 ⋮ 菜单，网络收藏并进顶栏
  /// 「文件夹」选择器；总览正文只承担「货架」这一件事。
  List<Widget> _overviewEntryCards() {
    final total = LocalFavoritesManager().totalComics;

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: KcEntryBox(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedFavourite,
              size: 20,
              // 品牌红块底座配白前景，两种主题下都与 42dp 底座保持可读对比。
              color: kcOnAccentColor,
            ),
            label: "All Favorites".tl,
            value: "$total",
            highlight: true,
            onTap: () => setFolder(false, _localAllFolderLabel),
          ),
        ),
      ),
    ];
  }

  /// 单个文件夹货架。空文件夹不占位——否则刚建的文件夹会把整页拉得空空荡荡，
  /// 要管理空文件夹走左上角文件夹弹窗。
  Widget? _buildShelf(String folder, double cardW, double cardH) {
    final total = LocalFavoritesManager().getFolderComicCount(folder);
    if (total == 0) return null;
    final comics = LocalFavoritesManager().getFolderComicsPaginated(
      folder,
      limit: _shelfLimit,
      offset: 0,
      // 跟随全局收藏排序（内页胶囊条里切换，这里的货架即时同步）。
      orderBy: LocalFavoritesManager.favoriteSortOrderBy(
        appdata.settings['favoriteSort'] as String?,
      ),
    );
    if (comics.isEmpty) return null;

    final name = getFavoriteDataOrNull(folder)?.title ?? folder;
    return _shelf(
      context: context,
      title: name,
      total: total,
      comics: comics,
      cardW: cardW,
      cardH: cardH,
      onOpenAll: () => setFolder(false, folder),
      onTap: _openComic,
    );
  }

  /// 收藏页右上角工具胶囊条 —— 唯一实现见 `components/tools_pill.dart`
  /// 的 [ToolsPill]（历史页等列表页共用同一套外观，别再复制一份）。
  Widget _favToolsPill(BuildContext context, List<Widget> children) {
    return ToolsPill(children: children);
  }

  /// 工具胶囊条内的单个图标按钮 —— 见 [ToolsPillButton]。
  Widget _toolIconButton(
    BuildContext context, {
    required dynamic icon,
    bool active = false,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return ToolsPillButton(
      icon: icon,
      active: active,
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }

  /// 工具胶囊条内的「更多」按钮 —— 见 [ToolsPillMoreButton]。
  ///
  /// 定位坑已收进组件内部：必须用按钮自身 context 取 RenderBox，
  /// 否则菜单会弹到屏幕左上角（点右边弹左边）。
  Widget _toolMoreButton(BuildContext context, List<MenuEntry> entries) {
    return ToolsPillMoreButton(entries: entries);
  }

  Widget buildBody() {
    if (folder == null) {
      return _buildOverview();
    }
    if (!isNetwork) {
      return _LocalFavoritesPage(
        folder: folder!,
        controller: _scrollController,
        key: PageStorageKey("local_$folder"),
      );
    } else {
      var favoriteData = getFavoriteDataOrNull(folder!);
      if (favoriteData == null) {
        folder = null;
        return buildBody();
      } else {
        return NetworkFavoritePage(
          favoriteData,
          controller: _scrollController,
          key: PageStorageKey("network_$folder"),
        );
      }
    }
  }
}

abstract interface class FolderList {
  void update();

  void updateFolders();
}

/// 一排货架：标题行 + 横滑封面。
///
/// 做成顶层函数（而不是 [_FavoritesPageState] 的方法），便于复用同一套尺寸、
/// 间距与标题排版；目前收藏页的文件夹货架都走这里。
Widget _shelf({
  required BuildContext context,
  required String title,
  required int? total,
  required List<Comic> comics,
  required double cardW,
  required double cardH,
  required ValueChanged<Comic> onTap,
  VoidCallback? onOpenAll,
  String? subtitle,
  double topPadding = 24,
}) {
  // 书名行开销：书名放在封面下方独立一行，卡片高度必须和 [ComicTile] 内部
  // 完全一致。之前书名叠在封面底部渐变上，封面被卡片高度「吃掉」标题那一段、
  // 书名又和「第 X 话 · 进度」胶囊抢同一条底边，部分设备上直接看不见。
  final titleBlock = comicTileTitleBlock(
    cardW,
    MediaQuery.textScalerOf(context),
  );
  // 斜放带来的外扩：槽位高度与左右留白都按它算，保证旋转后的封面不会探出货架。
  final lean = _ShelfLean.of(width: cardW, height: cardH + titleBlock);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionHeader(
        context: context,
        title: title,
        total: total,
        subtitle: subtitle,
        onTap: onOpenAll,
        topPadding: topPadding,
      ),
      SizedBox(
        // 槽位 = 封面 + 书名行 + 顶端上翘外扩 + 底角下沉 + 1px 余量：整个旋转
        // 外框都兜在这一行里，所以不需要靠 Clip.none 去「放行」溢出——那会让
        // 横向滚动区把书画到页面外面的左栏上。
        height: cardH + titleBlock + lean.rise + lean.sink + 1,
        child: ShaderMask(
          // 右缘渐隐：横滑列表被屏幕边缘一刀切会显得「没做完」，也给不出
          // 「后面还有」的暗示。渐隐宽度与右侧留白一致（_kShelfEdgeFade），
          // 滑到末尾时渐隐正好落在空白上，不会把最后一本的封面擦掉。
          shaderCallback: (rect) {
            final stop = ((rect.width - _kShelfEdgeFade) / rect.width).clamp(
              0.0,
              1.0,
            );
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.white,
                Colors.white,
                Colors.white.withValues(alpha: 0),
              ],
              stops: [0.0, stop, 1.0],
            ).createShader(rect);
          },
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // 行内已容得下整本书，左内边距再补一份 bleed，让第一本的上角
            // 不会贴到（甚至压出）视口边界。
            padding: EdgeInsets.only(
              left: kcSpaceLg + lean.bleed,
              right: _kShelfEdgeFade,
            ),
            physics: const BouncingScrollPhysics(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final c in comics) ...[
                  _shelfBook(
                    comic: c,
                    width: cardW,
                    height: cardH + titleBlock,
                    onTap: () => onTap(c),
                  ),
                  // 间距要容得下单本书向左的外扩，否则相邻两本会在顶角处压叠。
                  SizedBox(width: _kShelfBookGap + lean.bleed),
                ],
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

/// 书架上的单本书：整体向左微倾，像从书架上抽出来还没摆正的一本。
///
/// 这里**不再**叠「书脊」那条暗渐变：封面在卡片内本来就有几像素透明内缩
/// （卡片背景透出来），任何贴着左边缘画的渐变都会把那圈内缩染成一条白灰
/// 边，看起来像封面外多了一圈边框。要书脊感就得先让封面真正铺满卡片，
/// 那是 ComicTile 内部的事，不该在这一层硬压。
Widget _shelfBook({
  required Comic comic,
  required double width,
  required double height,
  required VoidCallback onTap,
}) {
  final lean = _ShelfLean.of(width: width, height: height);

  return Padding(
    // 上留 rise+1、下沉 sink：旋转后的整本书正好落在自己的布局框里，
    // 最下那只角就是这一行的基线，不会再被横向滚动区切平。
    padding: EdgeInsets.only(top: lean.rise + 1, bottom: lean.sink),
    child: Transform.rotate(
      angle: _kShelfLeanAngle,
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: width,
        height: height,
        child: ComicTile(
          comic: comic,
          showSourceOnCover: false,
          // 货架卡片本来就小，再叠一条「来源 · 收藏日期」黑条会把封面
          // 压掉 1/6 且字号糊成一团；来源信息留给列表页和详情页。
          showBottomSourceDate: false,
          // 锁定 brief（纯封面 + 下方书名）：detailed 模式的封面宽按行高算
          // （height * 0.68），塞进 cardW 窄槽位必横向溢出 57px、书名被挤成
          // 0 宽（logcat 实证 comic.dart _buildDetailedMode Row OVERFLOWING）。
          // 货架本意就是封面卡，模式不该随全局「详细列表」设置漂移。
          displayMode: 'brief',
          showTitleAtBottom: false,
          onTap: onTap,
        ),
      ),
    ),
  );
}

/// 分区标题：名称 + 数量胶囊 +（可点进入时）右侧箭头。
///
/// 收藏总览里，「文件夹货架」和「网络收藏源」共用这一套标题排版，避免同一页
/// 出现两种分区头的字号/间距。
///
/// 整行都是点击区（而不是只有原来那截「全部 ›」小字）：40dp 高、跨满宽度的
/// InkWell 才有像样的按压反馈，也不会让人误以为只有右侧文字能点进去。
Widget _sectionHeader({
  required BuildContext context,
  required String title,
  int? total,
  String? subtitle,
  VoidCallback? onTap,
  double topPadding = 24,
  double bottomPadding = 0,
}) {
  final cs = Theme.of(context).colorScheme;
  final children = <Widget>[
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: kcSubtitle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (total != null) ...[
                const SizedBox(width: 6),
                // 数量做成小胶囊：裸数字贴在标题后面，看起来像标题的一部分，
                // 分不清是「第 5 个文件夹」还是「5 本」。
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(kcPillRadius),
                  ),
                  child: Text(
                    total.toString(),
                    style: TextStyle(
                      fontSize: kcCaption,
                      height: 1.35,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: kcCaption,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    ),
    // 箭头是「这一整块能进去」的唯一提示：把「全部 ›」那截红字删掉，
    // 避免同一行出现两个指向同一动作的入口。
    if (onTap != null) ...[
      const SizedBox(width: kcSpaceSm),
      HugeIcon(
        icon: HugeIcons.strokeRoundedArrowRight01,
        size: 16,
        color: cs.onSurfaceVariant,
      ),
    ],
  ];

  final content = Padding(
    // 横向 8 的内边距 + 外层 8 的负向补偿，让文字仍然落在 kcSpaceLg 基准线上。
    padding: const EdgeInsets.symmetric(horizontal: kcSpaceSm, vertical: 10),
    child: Row(children: children),
  );

  return Padding(
    padding: EdgeInsets.fromLTRB(
      kcSpaceSm,
      topPadding,
      kcSpaceSm,
      bottomPadding,
    ),
    child: onTap == null
        ? content
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(kcRadius8),
            child: content,
          ),
  );
}
