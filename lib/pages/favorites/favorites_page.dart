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

  /// 收藏变化：让模块级推荐依据缓存下次重算（发现页也会用到同一份依据）。
  void _onFavoritesChanged() {
    invalidateRecommendBasis();
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
    final folders = userFolderNames()
        .where((f) => !hidden.contains(f))
        .toList();
    final net = _computeNetworkFolders();

    return LayoutBuilder(
      builder: (context, constraints) {
        // 卡片宽度按内容区（而不是整屏）算：宽屏下左栏已占 256，
        // 用 MediaQuery 会把卡片算大一圈，一行连第 4 张的边都露不出来。
        // -52 = 左侧留白 16 + 右侧让位 24 + 两张卡间距 12。
        final cardW = math.max(96.0, (constraints.maxWidth - 52) / 3.3);
        // 封面按 0.7 宽高比（接近标准封面 2:3，减少裁切）；标题已叠在封面
        // 底部渐变上，不再需要预留下方标题行的高度。
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
                // 不自定义字号：继承 SliverAppbar 的默认标题样式（kcAppbarTitle
                // + w600），与历史/发现等根 tab 页的大字标题一致（用户反馈）。
              ),
            ),
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
  // 斜放带来的外扩：槽位高度与左右留白都按它算，保证旋转后的封面不会探出货架。
  final lean = _ShelfLean.of(width: cardW, height: cardH);

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
        // 槽位 = 封面 + 顶端上翘外扩 + 底角下沉 + 1px 余量：整个旋转外框都
        // 兜在这一行里，所以不需要靠 Clip.none 去「放行」溢出——那会让横向
        // 滚动区把书画到页面外面的左栏上。
        height: cardH + lean.rise + lean.sink + 1,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // 行内已容得下整本书，左内边距再补一份 bleed，让第一本的上角
          // 不会贴到（甚至压出）视口边界。
          padding: EdgeInsets.only(
            left: kcSpaceLg + lean.bleed,
            right: kcSpaceSm,
          ),
          physics: const BouncingScrollPhysics(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final c in comics) ...[
                _shelfBook(
                  comic: c,
                  width: cardW,
                  height: cardH,
                  onTap: () => onTap(c),
                ),
                // 间距要容得下单本书向左的外扩，否则相邻两本会在顶角处压叠。
                SizedBox(width: _kShelfBookGap + lean.bleed),
              ],
            ],
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
          // 书籍样式：封面底部压一条暗色渐变显示漫画名。
          showTitleAtBottom: true,
          onTap: onTap,
        ),
      ),
    ),
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
    padding: EdgeInsets.fromLTRB(kcSpaceLg, topPadding, kcSpaceSm, kcSpaceSm),
    child: Row(
      children: [
        Expanded(
          child: InkWell(
            // 整块标题区（标题 + 数量 + 副标题）都能点进文件夹，不必只戳「全部 ›」。
            onTap: onOpenAll,
            borderRadius: BorderRadius.circular(kcRadius8),
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
