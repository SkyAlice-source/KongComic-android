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
import 'package:kong_comic/pages/reader/reader.dart';
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

/// 网络源收藏数探测结果。
///
/// [count] 为探测到的收藏总数：每页数量小于首页视为末页（各源分页大小
/// 恒定的合理假设），最多探测 5 页，超出则 [capped]=true、徽标显示「N+」。
/// [count] == -1 表示探测失败（网络错误 / 源脚本异常）——保留入口但不出
/// 徽标，不用一次瞬时错误惩罚用户。
class _NetworkFavProbe {
  final int count;

  final bool capped;

  const _NetworkFavProbe(this.count, {this.capped = false});

  static const _NetworkFavProbe error = _NetworkFavProbe(-1);

  bool get failed => count < 0;
}

class _FavoritesPageState extends State<FavoritesPage> with AutoListenMixin {
  String? folder;

  bool isNetwork = false;

  FolderList? folderList;

  /// 网络源收藏数：key -> 探测结果；value 为 null 表示探测中。
  /// 会话级缓存，只在首次构建总览时探测一次，翻页/切文件夹不会重复发请求。
  final Map<String, _NetworkFavProbe?> _networkProbes = {};

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
  /// settings['favorites']，不过滤的话装一堆源就会在总览底部排出一列
  /// 同图标的死入口（用户反馈）。空列表时总览的整个 Network 区不渲染。
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
    final net = _computeNetworkFolders();

    // 总览态顶栏：标题「收藏」；窄屏右上角「文件夹」入口（宽屏左栏常驻，
    // 不重复提供）。sig 带宽度分档——文件夹按钮只在窄屏注入。
    final narrow = context.width <= _kTwoPanelChangeWidth;
    pushTopBar(
      sig: 'ov_${narrow ? 'n' : 'w'}',
      title: Text(
        "Favorites".tl,
        style: TextStyle(fontSize: kcTitleMain, fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
      ),
      actions: narrow
          ? [
              IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedFolder01,
                  size: 22,
                ),
                tooltip: "Folders".tl,
                onPressed: showFolderSelector,
              ),
            ]
          : null,
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

        final empty = shelves.isEmpty && net.isEmpty;

        return CustomScrollView(
          controller: _scrollController,
          // 独立存储槽：文件夹视图会往同一个 PageStorage 桶里写滚动偏移，
          // 不加 key 时从深滚过的文件夹回到总览会落在半山腰。
          key: const PageStorageKey('favoritesOverview'),
          slivers: [
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
              if (net.isNotEmpty)
                SliverToBoxAdapter(child: _buildNetworkSection(net)),
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

  /// 网络收藏源入口：不预加载内容（要发网络请求），只做分组入口。
  ///
  /// 附带一次性的收藏数探测：拉回 0 收藏的源直接从总览移除（用户反馈
  /// 「一排点击就报错的死入口」），探测失败（网络错误）则保留不惩罚。
  Widget _buildNetworkSection(List<String> net) {
    // 探测放在 post-frame：build 期间只读缓存，避免 setState 重入。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _probeNetworkSources(net),
    );
    final visible = net
        .where((k) => !(_networkProbes[k] != null && _networkProbes[k]!.count == 0))
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 与文件夹货架共用同一套分区标题排版（只是没有箭头：网络源是
          // 一张张独立卡片，各自可点，不需要「整组进入」）。
          _sectionHeader(
            context: context,
            title: "Network".tl,
            total: visible.length,
            topPadding: 0,
            bottomPadding: kcSpaceXs,
          ),
          for (final k in visible) _networkTile(k),
        ],
      ),
    );
  }

  void _probeNetworkSources(List<String> keys) {
    for (final k in keys) {
      if (_networkProbes.containsKey(k)) continue;
      _networkProbes[k] = null; // 占位：探测中
      _probeOneNetworkSource(k);
    }
  }

  /// 顺序拉取某源的收藏页估算总数：首页为空即 0；某页数量小于首页视为
  /// 末页；到 5 页仍未触底则封顶为「N+」。失败时标记 error、保留入口。
  Future<void> _probeOneNetworkSource(String key) async {
    final loadComic = getFavoriteDataOrNull(key)?.loadComic;
    var total = 0;
    var capped = false;
    var failed = loadComic == null;
    if (!failed) {
      int? pageSize;
      for (var page = 1; page <= 5; page++) {
        final res = await loadComic(page);
        if (res.error) {
          failed = true;
          break;
        }
        final comics = res.data;
        if (comics.isEmpty) break;
        pageSize ??= comics.length;
        total += comics.length;
        if (comics.length < pageSize) break;
        if (page == 5) capped = true;
      }
    }
    if (!mounted) return;
    setState(() {
      _networkProbes[key] = failed
          ? _NetworkFavProbe.error
          : _NetworkFavProbe(total, capped: capped);
    });
  }

  /// 网络分组行：源头像（key 哈希出的专属色相 + 源名首字）+ 名称 + 收藏数
  /// 徽标 + 箭头。头像取代过去千篇一律的地球图标，多个源一眼可分；
  /// 徽标探测完成才出现，探测中是转圈、失败则什么都不显示。
  Widget _networkTile(String key) {
    final cs = Theme.of(context).colorScheme;
    final title = getFavoriteDataOrNull(key)?.title ?? key;
    final probe = _networkProbes[key];
    // key.hashCode 可能为负，先取绝对值再取模；首字直接取 UTF-16 码元即可
    // 覆盖中文与拉丁字母（源名不含代理对字符）。
    final hue = (key.hashCode.abs() % 360).toDouble();
    final avatarFg = HSLColor.fromAHSL(1, hue, 0.55, 0.42).toColor();
    return Padding(
      padding: const EdgeInsets.fromLTRB(kcSpaceLg, 0, kcSpaceLg, kcSpaceSm),
      child: Material(
        color: cs.surfaceContainerLow,
        // 描边 + 圆角：光靠底色不够「可点击」，加一圈边框让它看起来是
        // 独立卡片入口（用户反馈），与设置页分类项的可点击样式一致。
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kcCardRadius),
          side: BorderSide(color: cs.outlineVariant, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setFolder(true, key),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: avatarFg.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(kcRadius8),
                  ),
                  child: Center(
                    child: Text(
                      title.isEmpty ? '?' : title[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: kcBody,
                        fontWeight: FontWeight.w700,
                        color: avatarFg,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: kcBody,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (probe == null)
                  // 探测中：小转圈提示「数字在路上」，避免徽标位置跳动。
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  )
                else if (!probe.failed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(kcPillRadius),
                    ),
                    child: Text(
                      probe.capped ? '${probe.count}+' : '${probe.count}',
                      style: TextStyle(
                        fontSize: kcCaption,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowRight01,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
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
