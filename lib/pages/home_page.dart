import 'dart:async';
import 'dart:math' as math;
import 'package:kong_comic/foundation/appdata.dart';
import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/consts.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/history.dart';
import 'package:kong_comic/foundation/listen_mixin.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/pages/comic_details_page/comic_page.dart';
import 'package:kong_comic/pages/comic_source_page.dart';
import 'package:kong_comic/foundation/follow_updates.dart';
import 'package:kong_comic/pages/follow_updates_page.dart';
import 'package:kong_comic/pages/image_favorites_page/image_favorites_page.dart';
import 'package:kong_comic/utils/translations.dart';

import 'local_comics_page.dart';

/// 平板/宽屏下英雄卡（封面大卡）的最大宽度，避免随屏宽线性放大导致卡片过大。
/// 手机屏宽 * 0.54 恒定小于此值，故手机版外观完全不变。
const double _maxHeroCardWidth = 420;

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _currentComic = ValueNotifier<FavoriteItem?>(null);
  Key _bannerKey = UniqueKey();

  @override
  void dispose() {
    _currentComic.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    setState(() {
      _bannerKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        // dock 浮层高度跟随自适应底栏（大字号下栏体会长高），写死 58dp
        // 会让末行被浮岛底栏压住；bottomBarHeight 已含系统手势区。
        final dockHeight = NaviPane.of(context).bottomBarHeight;
        // 中间卡片内在高度：主卡宽 sw*0.54、高 cardW*1.4。
        // 用 LayoutBuilder 的内容列宽，而不是 MediaQuery 的整屏宽：宽屏下
        // 内容列被限到 900dp 并居中，按整屏算装饰卡会错位 112dp 并被裁。
        final sw = constraints.maxWidth;
        // 可用内容区高度（减去顶部状态栏和底部 dock）。
        final contentArea = math.max(
          0.0,
          availableHeight - context.padding.top - dockHeight,
        );
        // 手机竖屏首屏还要容下标题区 + CTA + 两行入口卡，banner 按整屏
        // 42% 会把 Follow Updates / Image Favorites 推进玻璃 dock 的覆盖区
        // （实拍 62/65）。Compact 收到 32%，平板仍保持 42%。再往下压虽能多
        // 挤一点首屏，但封面会小到失去主视觉，1.3 字号仍容不下两行入口，
        // 因此 32% 是「卡片可读 / 入口可见」的折中，余下靠滚动到底查看。
        final compact = MediaQuery.sizeOf(context).shortestSide < 600;
        final bannerHeight = contentArea * (compact ? 0.32 : 0.42);
        // 骨架归一：卡片高度必须完整落在 banner 内。旧版 cardW 只按屏宽算，
        // cardW*1.4 常大于 bannerHeight，Stack 又是 Clip.none，于是 5 张
        // 半透明封面互相叠压、主卡溢出压住标题和底部入口（实拍 42/46/50）。
        // 现在由 banner 高度反算 cardW，再交给唯一的 _Banner。
        final cardW = math.min(
          math.min(sw * 0.54, _maxHeroCardWidth),
          math.max(0.0, (bannerHeight - kcSpaceMd) / 1.4),
        );
        return _BannerProvider(
          bannerHeight: bannerHeight,
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            child: SmoothCustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(top: context.padding.top),
                ),
                _Banner(
                  key: _bannerKey,
                  height: bannerHeight,
                  width: sw,
                  cardWidth: cardW,
                  currentComicNotifier: _currentComic,
                ),
                _ComicInfoSection(currentComicNotifier: _currentComic),
                const _HomeHints(),
                const _HomeCapsules(),
                const _BottomModules(),
                SliverPadding(
                  padding: EdgeInsets.only(
                    bottom: dockHeight + kcPageBottomGap + kcSpaceLg,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    // 宽屏/平板：限制内容最大宽度并居中，避免单列在宽屏上拉满全屏、
    // 按钮/卡片被过度拉伸。手机宽度 < changePoint，分支不进入，外观与手机版一致。
    if (context.width > changePoint) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kcContentMaxWidth),
          child: content,
        ),
      );
    }
    return content;
  }
}

class _BannerProvider extends InheritedWidget {
  final double bannerHeight;
  const _BannerProvider({required this.bannerHeight, required super.child});
  @override
  bool updateShouldNotify(_BannerProvider old) =>
      old.bannerHeight != bannerHeight;
}

class _Banner extends StatefulWidget {
  final double height;

  /// 内容列的宽度（由主页 LayoutBuilder 传入），不是整屏宽。
  /// 装饰卡按它居中，才不会在 900dp 内容列里按整屏宽偏出去 112dp 并被裁。
  final double width;

  /// 由主页 LayoutBuilder 统一算好的主卡宽度（受 banner 高度上限约束）。
  /// _Banner 不再自己按屏宽算，避免父子两套 cardW 不一致导致溢出。
  final double cardWidth;
  final ValueNotifier<FavoriteItem?> currentComicNotifier;
  const _Banner({
    super.key,
    this.height = 360,
    required this.width,
    required this.cardWidth,
    required this.currentComicNotifier,
  });
  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with AutoListenMixin {
  int _currentIndex = 0;
  Timer? _timer;

  /// 手动滑动切换后暂停自动轮播
  bool _pauseAutoPlay = false;

  /// 已确认加载失败的封面（按漫画 id）。
  ///
  /// 轮播每 4 秒换一张，AnimatedSwitcher 会把整张卡重建一次、CoverBox 的
  /// State 也随之销毁；不在这里记一笔，断网时会看到它一遍遍「重新加载」，
  /// 永远等不到失败态，也就永远没有重试按钮。
  final Set<String> _failedCovers = {};
  List<FavoriteItem> _comics = [];
  void _loadComics() {
    final allFolderNames = userFolderNames();
    final selectedFolders = appdata.settings['homeBannerFolders'] as List;
    final folders = selectedFolders.isEmpty
        ? allFolderNames
        : selectedFolders
              .cast<String>()
              .where((f) => allFolderNames.contains(f))
              .toList();
    final all = <FavoriteItem>[];
    for (final folder in folders) {
      all.addAll(LocalFavoritesManager().getFolderComics(folder));
    }
    all.shuffle();
    final comics = all.take(7).toList();
    if (mounted) {
      setState(() {
        _comics = comics;
        if (_currentIndex >= _comics.length) {
          _currentIndex = _comics.isEmpty ? 0 : _comics.length - 1;
        }
        widget.currentComicNotifier.value = _comics.isNotEmpty
            ? _comics[_currentIndex]
            : null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // No PageController needed
    _loadComics();
    listen(LocalFavoritesManager(), _loadComics);
    listen(appdata.settings, _loadComics);
    _startTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只把 AnimatedSwitcher 归零是不够的：Timer 照跑会变成每 4 秒**瞬切**
    // 一张封面，比原来的淡入更刺眼。减少动效时必须让轮播彻底停摆。
    // MediaQuery 变化会重新触发这里，用户运行中改设置也能立即生效。
    if (kcReduceMotion(context)) {
      _timer?.cancel();
      _timer = null;
    } else if (_timer == null && !_pauseAutoPlay) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    // 手动滑动切换后暂停自动轮播（下拉刷新重建页面后恢复）
    if (_pauseAutoPlay || AppAnimations.reduceMotion) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _comics.length < 2) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _comics.length;
        widget.currentComicNotifier.value = _comics[_currentIndex];
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _navigateToComic(FavoriteItem c) {
    context.to(
      () => ComicPage(
        id: c.id,
        sourceKey: c.type.comicSource?.key ?? '',
        cover: c.coverPath,
        title: c.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_comics.isEmpty) return const SliverToBoxAdapter(child: SizedBox());
    if (_comics.length < 3) {
      // Show single card centered when fewer than 3 comics
      return SliverToBoxAdapter(
        child: SizedBox(
          height: widget.height,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              GestureDetector(
                onTap: () => _navigateToComic(_comics[_currentIndex]),
                child: _buildSingleCard(
                  context,
                  _comics[_currentIndex],
                  width: widget.cardWidth,
                ),
              ),
            ],
          ),
        ).paddingVertical(2).paddingBottom(8),
      );
    }

    final cardW = widget.cardWidth;
    return SliverToBoxAdapter(
      child: SizedBox(
        height: widget.height,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          alignment: Alignment.topCenter,
          children: [
            // Main card with in-place replacement (AnimatedSwitcher)
            Positioned(
              top: 0,
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  if (details.velocity.pixelsPerSecond.dx > 80) {
                    final prev =
                        (_currentIndex - 1 + _comics.length) % _comics.length;
                    _pauseAutoPlay = true;
                    setState(() {
                      _currentIndex = prev;
                      widget.currentComicNotifier.value =
                          _comics[_currentIndex];
                    });
                  } else if (details.velocity.pixelsPerSecond.dx < -80) {
                    final next = (_currentIndex + 1) % _comics.length;
                    _pauseAutoPlay = true;
                    setState(() {
                      _currentIndex = next;
                      widget.currentComicNotifier.value =
                          _comics[_currentIndex];
                    });
                  }
                },
                child: AnimatedSwitcher(
                  duration: kcReduceMotion(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    );
                  },
                  child: SizedBox(
                    key: ValueKey(_currentIndex),
                    width: cardW,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => _navigateToComic(_comics[_currentIndex]),
                        child: _buildSingleCard(
                          context,
                          _comics[_currentIndex],
                          width: cardW,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ).paddingVertical(2).paddingBottom(8),
    );
  }

  Widget _buildSingleCard(
    BuildContext context,
    FavoriteItem comic, {
    double? width,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sw = widget.width;
    final cardW = width ?? (sw * 0.54).clamp(0.0, _maxHeroCardWidth);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
            borderRadius: BorderRadius.circular(kcCardRadius),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kcCardRadius),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.4),
                  width: 3.0,
                ),
                borderRadius: BorderRadius.circular(kcCardRadius),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(kcRadius10),
                child: SizedBox(
                  width: cardW,
                  height: cardW * 1.4,
                  child: _buildCover(comic),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCover(FavoriteItem comic, {bool decorative = false}) {
    // 走全 App 统一的封面加载链（自定义封面 > 本地漫画 > CacheManager 网络缓存），
    // 不再用裸 CachedNetworkImage：那是第二套 HTTP 缓存，和 App 自己的
    // CacheManager 互不复用 —— 收藏页刚下好的封面到了主页要重下一遍，
    // 断网时主页就是一片空白（其它页面反而有图，用户会以为是主页坏了）。
    //
    // 占位/失败态由 CoverBox 兜住：加载中显示「书名首字」，失败给重试。
    return CoverBox(
      image: comicCoverImageProvider(comic),
      // 堆叠卡只是背景装饰：不显示首字和图标，也不给重试按钮，
      // 否则一屏会同时出现四五个「重试」，比空白还吵。
      label: decorative ? null : comic.name,
      showIcon: !decorative,
      retryable: !decorative,
      failed: _failedCovers.contains(comic.id),
      onFailed: () => _failedCovers.add(comic.id),
      initialFontSize: 52,
    );
  }
}

class _ComicInfoSection extends StatelessWidget {
  final ValueNotifier<FavoriteItem?> currentComicNotifier;
  const _ComicInfoSection({required this.currentComicNotifier});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FavoriteItem?>(
      valueListenable: currentComicNotifier,
      builder: (context, comic, _) {
        if (comic == null) return const SliverToBoxAdapter(child: SizedBox());
        final cs = Theme.of(context).colorScheme;
        // 漫画名固定 72dp 是按 1.0 字号两行算的；系统字号 1.3 时两行需约
        // 88.7dp。按实际 textScaler 放大预留高度，避免第二行被裁。
        final titleScale =
            MediaQuery.textScalerOf(context).scale(kcTitleLarge) / kcTitleLarge;
        final history = HistoryManager().find(comic.id, comic.type);
        final progress = history != null
            ? "Chapter %s · %s chapters read".tl
                  .replaceFirst("%s", "${history.ep}")
                  .replaceFirst("%s", "${history.readEpisode.length}")
            : null;
        final updatedTime = comic.time.isNotEmpty
            ? comic.time.substring(0, 10)
            : null;
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(kcSpaceLg, kcSpaceXs, kcSpaceLg, kcSpaceXs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 漫画名占两行高度（随系统字号缩放）
                SizedBox(
                  height: 60 * titleScale,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      comic.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: kcTitleLarge,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (comic.author.isNotEmpty || comic.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: kcSpaceXs),
                    child: Text(
                      comic.author.isNotEmpty ? comic.author : comic.tags.first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: kcBody,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (progress != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: kcSpaceXs),
                    child: Text(
                      progress,
                      style: TextStyle(fontSize: kcBody, color: cs.onSurface),
                    ),
                  ),
                Text(
                  "Total @count chapters".tlParams({
                    'count': "${history?.maxPage ?? '?'}",
                  }),
                  style: TextStyle(
                    fontSize: kcCaption,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (updatedTime != null)
                  Padding(
                    padding: const EdgeInsets.only(top: kcSpaceXs),
                    child: Text(
                      "Updated @time".tlParams({'time': updatedTime}),
                      style: TextStyle(
                        fontSize: kcCaption,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  // 浅色与深色都用「上亮下饱和」的红色渐变 + 柔和大半径红晕包裹，
                  // 主 CTA 才有体积与质感；AMOLED 零彩色，退化为实心灰底、无光晕。
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(kcRadius22),
                      gradient: kcIsAmoled()
                          ? null
                          : const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              // 主页入口卡渐变底：上端用深色版品牌红提亮层次，
                              // 下端落到标准品牌红 —— 两支都必须是品牌色本身，
                              // 不换成 colorScheme 派生色（AMOLED 下整块渐变直接去掉）。
                              // 上端与 kcBrandColorOnDark 同值，直接引用 token。
                              colors: [kcBrandColorOnDark, kcBrandColor],
                            ),
                      boxShadow: kcIsAmoled()
                          ? null
                          : [
                              BoxShadow(
                                color: kcBrandColor.withValues(alpha: 0.30),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () => context.to(
                        () => ComicPage(
                          id: comic.id,
                          sourceKey: comic.type.comicSource?.key ?? '',
                          cover: comic.coverPath,
                          title: comic.name,
                        ),
                      ),
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedPlayCircle,
                        size: 20,
                      ),
                      label: Text(
                        "Read Now".tl,
                        style: TextStyle(
                          fontSize: kcSubtitle,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        // 渐变由外层 Container 提供，按钮本身透明只承载文字/涟漪；
                        // AMOLED 则退回中性灰实心（与灰阶按钮同源）。
                        backgroundColor: kcIsAmoled()
                            ? kcAccentColor(context)
                            : Colors.transparent,
                        foregroundColor: kcOnAccentColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kcRadius22),
                        ),
                        // 显式清掉边线：深色主题给 ElevatedButton 强加了灰描边，
                        // 会在这个灰底 CTA 外再套一圈灰环。
                        side: BorderSide.none,
                        elevation: 0,
                        surfaceTintColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeCapsules extends StatefulWidget {
  const _HomeCapsules();
  @override
  State<_HomeCapsules> createState() => _HomeCapsulesState();
}

class _HomeCapsulesState extends State<_HomeCapsules> with AutoListenMixin {
  int _updateCount = 0;
  List<String> get folders => getEffectiveFollowFolders();
  void _refresh() {
    if (!mounted) return;
    setState(() {
      _updateCount = folders.fold(
        0,
        (sum, f) => sum + LocalFavoritesManager().countUpdates(f),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    listen(LocalFavoritesManager(), _refresh);
    listen(LocalManager(), _refresh);
  }

  @override
  Widget build(BuildContext context) {
    final lc = LocalManager().count;
    return SliverToBoxAdapter(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg, vertical: kcSpaceXs),
            child: Row(
              children: [
                Expanded(
                  child: _FlatBox(
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedRefresh,
                      size: 20,
                    ),
                    label: "Follow Updates".tl,
                    value: _updateCount > 0 ? "$_updateCount" : null,
                    alert: _updateCount > 0,
                    onTap: () => context.to(() => const FollowUpdatesPage()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FlatBox(
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedFolder01,
                      size: 20,
                    ),
                    label: "Local".tl,
                    value: "$lc",
                    onTap: () => context.to(() => const LocalComicsPage()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomModules extends StatelessWidget {
  const _BottomModules();
  @override
  Widget build(BuildContext context) {
    final cc = ComicSource.all().length;
    final imgCount = ImageFavoriteManager().length;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg, vertical: kcSpaceXs),
        child: Row(
          children: [
            Expanded(
              child: _FlatBox(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: 20),
                label: "Image Favorites".tl,
                value: imgCount > 0 ? "$imgCount" : null,
                onTap: () => context.to(() => const ImageFavoritesPage()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _FlatBox(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedGlobe02, size: 20),
                label: "Comic Source".tl,
                value: "$cc",
                onTap: () => context.to(() => const ComicSourcePage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlatBox extends StatelessWidget {
  final Widget icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool alert;
  const _FlatBox({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.alert = false,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            // 大字号下「Follow Updates / Image Favorites」会换行，写死 48dp
            // 时第二行与数字徽章会溢出，并被玻璃 dock 盖住（实拍 46/50）。
            constraints: BoxConstraints(
              minHeight: kcMinTapTarget *
                  MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: kcSpaceMd),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: kcBody, color: cs.onSurface),
                  ),
                ),
                if (value != null)
                  Container(
                    margin: const EdgeInsets.only(right: kcSpaceMd),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    decoration: BoxDecoration(
                      // 未读强调走品牌红（设计系统：强调一律 accent 红），不再用 errorContainer。
                      color: alert
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
                          color: alert
                              ? kcOnAccentColor
                              : kcBrandAdaptive(context),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 轻量主页底部提示区 —— 根据当前状态显示上下文引导文字。
/// 纯展示（SliverToBoxAdapter），不触碰任何现有组件逻辑/状态。
class _HomeHints extends StatefulWidget {
  const _HomeHints();

  @override
  State<_HomeHints> createState() => _HomeHintsState();
}

class _HomeHintsState extends State<_HomeHints> with AutoListenMixin {
  int _localCount = 0;
  int _favoriteCount = 0;
  int _sourceCount = 0;

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _localCount = LocalManager().count;
      _favoriteCount = LocalFavoritesManager().totalComics;
      _sourceCount = ComicSource.enabled().length;
    });
  }

  @override
  void initState() {
    super.initState();
    _localCount = LocalManager().count;
    _favoriteCount = LocalFavoritesManager().totalComics;
    _sourceCount = ComicSource.enabled().length;
    listen(LocalManager(), _refresh);
    listen(LocalFavoritesManager(), _refresh);
    listen(ComicSourceManager(), _refresh);
  }

  @override
  Widget build(BuildContext context) {
    // 只要任意一类内容存在，就不显示引导提示
    if (_sourceCount > 0 || _localCount > 0 || _favoriteCount > 0) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final shown = <String>[
      'Go to "Comic Source" to add sources and discover more.'.tl,
      'No local comics yet? Tap "Local" above to add a comic folder.'.tl,
    ].take(2).toList();

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg, vertical: 20),
        child: Column(
          children: shown.map((hint) => _HintCard(text: hint)).toList(),
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  final String text;
  const _HintCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kcRadius18),
        // 柔光微投影：让提示卡从纯白页面上轻轻「浮」起，增加质感而不抢眼。
        boxShadow: kcContourGlow(context),
      ),
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedBulb,
            size: 20,
            color: kcBrandAdaptive(context).withValues(alpha: 0.8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: kcBody,
                color: cs.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
