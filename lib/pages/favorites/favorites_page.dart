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

part 'favorite_actions.dart';
part 'side_bar.dart';
part 'local_favorites_page.dart';
part 'network_favorites_page.dart';
part 'recommended_shelf.dart';

const _kLeftBarWidth = 256.0;

const _kTwoPanelChangeWidth = 720.0;

/// 收藏页：自绘整条顶栏（标题 + 工具胶囊条），故实现 [SelfTopBarPage]
/// 请求共享顶栏整体让位，避免「两排工具栏」。
class FavoritesPage extends StatefulWidget implements SelfTopBarPage {
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

  /// 「推荐」货架取数依据的缓存 —— 见 [_recommendBasis]。
  /// 收藏变化时置空，否则每次 rebuild 都要重扫收藏库统计一遍标签。
  _RecommendBasis? _recommendBasisCache;

  /// 缓存是否已算过：null 本身是合法结果（没有可用依据），
  /// 光靠 [_recommendBasisCache] 判空会导致每次 rebuild 都重扫。
  bool _recommendBasisComputed = false;

  /// 「推荐」货架的取数依据：收藏里出现次数最多的标签 + 该标签所属漫画源。
  ///
  /// 锚点是「你已经收藏了什么」，所以只有收藏页拿得到这份偏好。拿不到依据时
  /// （没收藏 / 收藏全在本地 / 源不支持按标签取漫画 / 该源的分类筛选项要联网
  /// 才能确定）返回 null，那一排整排不渲染。
  _RecommendBasis? get _recommendBasis {
    if (_recommendBasisComputed) return _recommendBasisCache;
    _recommendBasisComputed = true;
    return _recommendBasisCache = _computeRecommendBasis();
  }

  _RecommendBasis? _computeRecommendBasis() {
    // key 用 \u0000 分隔：标签本身可能带空格，用空格拼接再 split 会把标签切开。
    final counts = <String, int>{};
    final targets = <String, _CategoryTarget>{};
    final sources = <String, ComicSource>{};
    final owned = <String>{};
    for (final item in LocalFavoritesManager().allComics()) {
      owned.add('${item.id}|${item.sourceKey}');
      final source = item.type.comicSource;
      if (source == null) continue;
      final data = source.categoryComicsData;
      // optionsLoader 表示筛选项要发一次请求才知道，这类源没法直接发取数请求。
      if (data == null || data.optionsLoader != null) continue;
      if (_categoryTargetsOf(source).isEmpty) continue;
      sources[source.key] = source;
      for (final raw in item.tags) {
        // 一个标签只贡献一次：同一本书的原文和「标签:」后面的值都命中时，
        // 计两遍会把这本书的权重算成两倍。
        for (final tag in _tagCandidates(raw)) {
          final target = _categoryTargetsOf(source)[tag];
          if (target == null) continue;
          final k = '$tag\u0000${source.key}';
          counts[k] = (counts[k] ?? 0) + 1;
          targets.putIfAbsent(k, () => target);
          break;
        }
      }
    }
    if (counts.isEmpty) return null;
    // 同频次按字典序兜底：List.sort 不是稳定排序，否则每次刷新推荐都在跳。
    final sorted = counts.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    final best = sorted.first;
    final parts = best.key.split('\u0000');
    return _RecommendBasis(
      tag: parts[0],
      target: targets[best.key]!,
      source: sources[parts[1]]!,
      owned: owned,
    );
  }

  /// 收藏变化时让 [_recommendBasis] 下次重算。
  void _onFavoritesChanged() {
    _recommendBasisComputed = false;
    _recommendBasisCache = null;
    // 回调可能来自 dispose 之后的异步路径。
    if (mounted) setState(() {});
  }

  void setFolder(bool isNetwork, String? folder) {
    setState(() {
      this.isNetwork = isNetwork;
      this.folder = folder;
    });
    _showFab.value = true; // 切到别的文件夹后回到顶部，回顶按钮重新出现
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
  List<String> _computeNetworkFolders() {
    final all = ComicSource.enabled()
        .where((e) => e.favoriteData != null)
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
    final folders =
        userFolderNames().where((f) => !hidden.contains(f)).toList();
    final net = _computeNetworkFolders();

    return LayoutBuilder(
      builder: (context, constraints) {
        // 卡片宽度按内容区（而不是整屏）算：宽屏下左栏已占 256，
        // 用 MediaQuery 会把卡片算大一圈，一行连第 4 张的边都露不出来。
        // -52 = 左侧留白 16 + 右侧让位 24 + 两张卡间距 12。
        final cardW = math.max(96.0, (constraints.maxWidth - 52) / 3.3);
        // 封面按 0.64 宽高比，再留一行标题（货架卡不叠来源/日期黑条）。
        final cardH = cardW / 0.64 + 34;

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
            SliverAppbar(
              leading: context.width <= _kTwoPanelChangeWidth
                  ? Tooltip(
                      message: "Folders".tl,
                      child: IconButton(
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedMenu02,
                          size: 18,
                        ),
                        color: kcBrandAdaptive(context),
                        onPressed: showFolderSelector,
                      ),
                    )
                  : null,
              title: Text(
                "Favorites".tl,
                style: const TextStyle(
                  fontSize: kcSectionTitle,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (empty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedFolder01, size: 18),
                  title: 'No favorites yet'.tl,
                  subtitle:
                      'Favorite a comic from any source and it shows up here.'.tl,
                ),
              )
            else ...[
              for (final s in shelves) SliverToBoxAdapter(child: s),
              if (net.isNotEmpty)
                SliverToBoxAdapter(child: _buildNetworkSection(net)),
              // 推荐放最底部：它要联网取数，排在文件夹货架之后，
              // 「一进收藏页先看到自己的书架」才不会被网络请求拖住。
              SliverToBoxAdapter(
                child: _RecommendedShelf(
                  basis: _recommendBasis,
                  cardW: cardW,
                  cardH: cardH,
                  onTap: _openComic,
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: SizedBox(height: context.padding.bottom + kcSpaceLg),
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
    final comics = LocalFavoritesManager()
        .getFolderComicsPaginated(folder, limit: _shelfLimit, offset: 0);
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
  Widget _buildNetworkSection(List<String> net) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kcSpaceLg,
              0,
              kcSpaceLg,
              kcSpaceSm,
            ),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    "Network".tl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: kcSubtitle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  net.length.toString(),
                  style: TextStyle(
                    fontSize: kcCaption,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          for (final k in net) _networkTile(k),
        ],
      ),
    );
  }

  /// 网络分组行：图标块 + 名称 + 箭头，做成卡片而不是裸行，
  /// 否则整页只有「货架 + 几行灰字」，视觉上像没做完。
  Widget _networkTile(String key) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kcSpaceLg, 0, kcSpaceLg, kcSpaceSm),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kcCardRadius),
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
                    color: kcAccentSurface(context, alpha: 0.12),
                    borderRadius: BorderRadius.circular(kcRadius8),
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedGlobe02,
                      size: 18,
                      color: kcAccentColor(context),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    getFavoriteDataOrNull(key)?.title ?? key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: kcBody,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
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
/// 做成顶层函数（而不是 [_FavoritesPageState] 的方法），是为了让独立加载数据的
/// 「推荐」货架 [_RecommendedShelf] 复用同一套尺寸、间距与标题排版 —— 否则
/// 收藏页里会出现两套看起来不一样、但其实是同一种东西的货架。
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
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _shelfHeader(
        context: context,
        title: title,
        total: total,
        subtitle: subtitle,
        onOpenAll: onOpenAll,
        topPadding: topPadding,
      ),
      SizedBox(
        height: cardH,
        child: ListView.separated(
          // 不用 PageStorageKey：货架内容随收藏变化，记住旧偏移只会滑到空白处；
          // 也避开与纵向列表共用 PageStorage 标识导致的 `as double?` 崩溃。
          key: ValueKey('shelf_$title'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: kcSpaceLg, right: kcSpaceSm),
          physics: const BouncingScrollPhysics(),
          itemCount: comics.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final c = comics[i];
            return SizedBox(
              width: cardW,
              child: ComicTile(
                comic: c,
                showSourceOnCover: false,
                // 货架卡片本来就小，再叠一条「来源 · 收藏日期」黑条会把封面
                // 压掉 1/6 且字号糊成一团；来源信息留给列表页和详情页。
                showBottomSourceDate: false,
                onTap: () => onTap(c),
              ),
            );
          },
        ),
      ),
    ],
  );
}

/// 货架标题行：标题 + （可选）数量 + （可选）一行说明 + （可选）「全部」入口。
Widget _shelfHeader({
  required BuildContext context,
  required String title,
  int? total,
  String? subtitle,
  VoidCallback? onOpenAll,
  double topPadding = 24,
}) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: EdgeInsets.fromLTRB(
      kcSpaceLg,
      topPadding,
      kcSpaceSm,
      kcSpaceSm,
    ),
    child: Row(
      children: [
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
                    Text(
                      total.toString(),
                      style: TextStyle(
                        fontSize: kcCaption,
                        color: cs.onSurfaceVariant,
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
        if (onOpenAll != null)
          InkWell(
            borderRadius: BorderRadius.circular(kcPillRadius),
            onTap: onOpenAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "All".tl,
                    style: TextStyle(
                      fontSize: kcBody,
                      fontWeight: FontWeight.w500,
                      color: kcAccentColor(context),
                    ),
                  ),
                  const SizedBox(width: 2),
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    size: 14,
                    color: kcAccentColor(context),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
