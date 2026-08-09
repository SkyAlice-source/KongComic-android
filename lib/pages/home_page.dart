import 'dart:async';
import 'dart:io';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/consts.dart';
import 'package:kong_comic/foundation/custom_cover.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/history.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/pages/comic_details_page/comic_page.dart';
import 'package:kong_comic/pages/comic_source_page.dart';
import 'package:kong_comic/pages/follow_updates_page.dart';
import 'package:kong_comic/pages/image_favorites_page/image_favorites_page.dart';
import 'package:kong_comic/utils/translations.dart';

import 'local_comics_page.dart';

/// 平板/宽屏下英雄卡（封面大卡）的最大宽度，避免随屏宽线性放大导致卡片过大。
/// 手机屏宽 * 0.54 恒定小于此值，故手机版外观完全不变。
const double _maxHeroCardWidth = 420;

/// 平板/宽屏下主页内容列的最大宽度，超出则居中留白，避免单列拉满全屏。
/// 手机屏宽 < 该值，约束等价为不约束，外观与手机版一致。
const double _maxHomeContentWidth = 900;

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  final _currentComic = ValueNotifier<FavoriteItem?>(null);
  Key _bannerKey = UniqueKey();

  @override
  void dispose() { _currentComic.dispose(); super.dispose(); }

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
        // dock 浮层高度（含底部安全区），内容需避让以免被遮挡
        final dockHeight = 58.0 + MediaQuery.of(context).padding.bottom;
        // 中间卡片内在高度：主卡宽 sw*0.54、高 cardW*1.4
        final sw = MediaQuery.of(context).size.width;
        final cardW = (sw * 0.54).clamp(0.0, _maxHeroCardWidth);
        final cardHeight = cardW * 1.4;
        // 可用内容区高度（减去顶部状态栏和底部dock）
        final contentArea = availableHeight - context.padding.top - dockHeight;
        // 按比例分配：banner 占内容区 ~42%，其余 58% 给信息区+按钮+两行框
        // 这样无论分辨率如何，整块英雄区都能完整显示在一屏内
        final bannerHeight = (contentArea * 0.42).clamp(cardHeight * 0.8, cardHeight * 1.15);
        return _BannerProvider(
          bannerHeight: bannerHeight,
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            child: SmoothCustomScrollView(
              slivers: [
                SliverPadding(padding: EdgeInsets.only(top: context.padding.top)),
                _Banner(key: _bannerKey, height: bannerHeight, currentComicNotifier: _currentComic),
                _ComicInfoSection(currentComicNotifier: _currentComic),
                const _HomeHints(),
                const _HomeCapsules(),
                const _BottomModules(),
                SliverPadding(padding: EdgeInsets.only(bottom: dockHeight)),
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
          constraints: const BoxConstraints(maxWidth: _maxHomeContentWidth),
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
  @override bool updateShouldNotify(_BannerProvider old) => old.bannerHeight != bannerHeight;
}

class _Banner extends StatefulWidget {
  final double height;
  final ValueNotifier<FavoriteItem?> currentComicNotifier;
  const _Banner({super.key, this.height = 360, required this.currentComicNotifier});
  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> {
  int _currentIndex = 0;
  Timer? _timer;
  List<FavoriteItem> _comics = [];
  void _loadComics() {
    final allFolderNames = LocalFavoritesManager().folderNames;
    final selectedFolders = appdata.settings['homeBannerFolders'] as List;
    final folders = selectedFolders.isEmpty
        ? allFolderNames
        : selectedFolders.cast<String>().where((f) => allFolderNames.contains(f)).toList();
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
        widget.currentComicNotifier.value = _comics.isNotEmpty ? _comics[_currentIndex] : null;
      });
    }
  }
  @override
  void initState() {
    super.initState();
    // No PageController needed
    _loadComics(); LocalFavoritesManager().addListener(_loadComics); appdata.settings.addListener(_loadComics); _startTimer();
  }
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _comics.length < 2) return;
      setState(() { _currentIndex = (_currentIndex + 1) % _comics.length; widget.currentComicNotifier.value = _comics[_currentIndex]; });
    });
  }
  @override void dispose() { _timer?.cancel(); LocalFavoritesManager().removeListener(_loadComics); appdata.settings.removeListener(_loadComics); super.dispose(); }
  void _navigateToComic(FavoriteItem c) { context.to(() => ComicPage(id: c.id, sourceKey: c.type.comicSource?.key ?? '', cover: c.coverPath, title: c.name)); }

  @override
  Widget build(BuildContext context) {
    if (_comics.isEmpty) return const SliverToBoxAdapter(child: SizedBox());
    if (_comics.length < 3) {
      // Show single card centered when fewer than 3 comics
      return SliverToBoxAdapter(child: SizedBox(
        height: widget.height,
        child: Stack(alignment: Alignment.topCenter, children: [
          GestureDetector(
            onTap: () => _navigateToComic(_comics[_currentIndex]),
            child: _buildSingleCard(context, _comics[_currentIndex]),
          ),
        ]),
      ).paddingVertical(2).paddingBottom(8));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sw = MediaQuery.of(context).size.width;
    final cardW = (sw * 0.54).clamp(0.0, _maxHeroCardWidth);
    return SliverToBoxAdapter(
      child: SizedBox(height: widget.height,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            // Decorative stacked cards (background)
            ..._buildStackedCards(isDark, cardW, sw),
            // Main card with in-place replacement (AnimatedSwitcher)
            Positioned(top: 0, child: GestureDetector(
              onHorizontalDragEnd: (details) {
                if (details.velocity.pixelsPerSecond.dx > 80) {
                  final prev = (_currentIndex - 1 + _comics.length) % _comics.length;
                  setState(() { _currentIndex = prev; widget.currentComicNotifier.value = _comics[_currentIndex]; _startTimer(); });
                } else if (details.velocity.pixelsPerSecond.dx < -80) {
                  final next = (_currentIndex + 1) % _comics.length;
                  setState(() { _currentIndex = next; widget.currentComicNotifier.value = _comics[_currentIndex]; _startTimer(); });
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
                      child: _buildSingleCard(context, _comics[_currentIndex], width: cardW),
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

  List<Widget> _buildStackedCards(bool isDark, double cardW, double sw) {
    final items = <Widget>[];
    final overlap = cardW * 0.30;
    for (final layer in [-2, -1, 2, 1]) {
      int idx = (_currentIndex + layer) % _comics.length;
      if (idx < 0) idx += _comics.length;
      final comic = _comics[idx];
      final scale = 1.0 - layer.abs() * 0.1;
      final topOff = layer.abs() * 2.0;
      final pos = sw * 0.5 + layer * overlap - cardW * 0.5;
      items.add(Positioned(
        left: pos, top: topOff, width: cardW,
        child: Transform.scale(scale: scale,
          child: ClipRRect(borderRadius: BorderRadius.circular(kcRadius10),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.4), width: 3.0),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15), blurRadius: 6, offset: const Offset(0, 3)),
                  ],
                  borderRadius: BorderRadius.circular(kcRadius10),
                ),
                child: ClipRRect(borderRadius: BorderRadius.circular(kcRadius8),
                  child: SizedBox(height: cardW * 1.4, child: _buildCover(comic)),
                ),
              ),
            ),
          ),
      ));
    }
    return items;
  }

  Widget _buildSingleCard(BuildContext context, FavoriteItem comic, {double? width}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sw = MediaQuery.of(context).size.width;
    final cardW = width ?? (sw * 0.54).clamp(0.0, _maxHeroCardWidth);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15), blurRadius: 6, offset: const Offset(0, 3)),
          ],
          borderRadius: BorderRadius.circular(kcCardRadius),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(kcCardRadius),
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.4), width: 3.0), borderRadius: BorderRadius.circular(kcCardRadius)),
            child: ClipRRect(borderRadius: BorderRadius.circular(kcRadius10),
              child: SizedBox(width: cardW, height: cardW * 1.4, child: _buildCover(comic)),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildCover(FavoriteItem comic) {
    // 自定义封面优先
    final sourceKey = comic.type.comicSource?.key ?? 'local';
    final customPath = CustomCoverManager.getCustomCoverPath(sourceKey, comic.id);
    if (customPath != null && File(customPath).existsSync()) {
      return Image(
        image: FileImage(File(customPath)),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => const Center(child: HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: 40)),
      );
    }

    if (comic.coverPath.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: comic.coverPath,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        placeholder: (_, __) => const SizedBox(),
        errorWidget: (_, __, ___) => const Center(child: HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: 40)),
      );
    }
    return Image(
      image: FileImage(File(comic.coverPath)),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => const Center(child: HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: 40)),
    );
  }
}

class _ComicInfoSection extends StatelessWidget {
  final ValueNotifier<FavoriteItem?> currentComicNotifier;
  const _ComicInfoSection({required this.currentComicNotifier});
  @override Widget build(BuildContext context) {
    return ValueListenableBuilder<FavoriteItem?>(
      valueListenable: currentComicNotifier,
      builder: (context, comic, _) {
        if (comic == null) return const SliverToBoxAdapter(child: SizedBox());
        final cs = Theme.of(context).colorScheme;
        final history = HistoryManager().find(comic.id, comic.type);
        final progress = history != null
            ? "Chapter %s · %s chapters read".tl
                .replaceFirst("%s", "${history.ep}")
                .replaceFirst("%s", "${history.readEpisode.length}")
            : null;
        final updatedTime = comic.time.isNotEmpty ? comic.time.substring(0, 10) : null;
        return SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 漫画名占三行高度
            SizedBox(height: 72, child: Align(alignment: Alignment.bottomLeft,
              child: Text(comic.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: kcTitleLarge, fontWeight: FontWeight.w700, color: cs.onSurface)))),
            const SizedBox(height: 6),
            if (comic.author.isNotEmpty || comic.tags.isNotEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  comic.author.isNotEmpty ? comic.author : comic.tags.first,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: kcFont13, color: cs.onSurfaceVariant))),
            if (progress != null)
              Padding(padding: const EdgeInsets.only(bottom: 4),
                child: Text(progress, style: TextStyle(fontSize: kcFont13, color: cs.onSurface))),
            Text("Total %s chapters".tl.replaceAll("%s", "${history?.maxPage ?? '?'}"), style: TextStyle(fontSize: kcCaption, color: cs.onSurfaceVariant)),
            if (updatedTime != null)
              Padding(padding: const EdgeInsets.only(top: 4),
                child: Text("Updated %s".tl.replaceAll("%s", updatedTime), style: TextStyle(fontSize: kcCaption, color: cs.onSurfaceVariant))),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, height: 44,
              child: ElevatedButton(
                onPressed: () => context.to(() => ComicPage(id: comic.id, sourceKey: comic.type.comicSource?.key ?? '', cover: comic.coverPath, title: comic.name)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: appdata.isAmoledMode
                      ? const Color(0xFF242424)
                      : Theme.of(context).colorScheme.primary,
                  foregroundColor: appdata.isAmoledMode
                      ? Colors.white
                      : Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kcRadius22)),
                  elevation: 0,
                ),
                child: Text("Read Now".tl, style: TextStyle(fontSize: kcSubtitle, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ));
      },
    );
  }
}

class _HomeCapsules extends StatefulWidget {
  const _HomeCapsules();
  @override State<_HomeCapsules> createState() => _HomeCapsulesState();
}
class _HomeCapsulesState extends State<_HomeCapsules> {
  int _updateCount = 0;
  String? get folder => appdata.settings["followUpdatesFolder"];
  void _refresh() {
    if (!mounted) return;
    setState(() {
      if (folder == null) {
        _updateCount = 0;
      } else if (LocalFavoritesManager().folderNames.contains(folder)) {
        _updateCount = LocalFavoritesManager().countUpdates(folder!);
      } else {
        _updateCount = 0;
      }
    });
  }
  @override void initState() { super.initState(); _refresh(); LocalFavoritesManager().addListener(_refresh); LocalManager().addListener(_refresh); }
  @override void dispose() { LocalFavoritesManager().removeListener(_refresh); LocalManager().removeListener(_refresh); super.dispose(); }
  @override Widget build(BuildContext context) {
    final lc = LocalManager().count;
    return SliverToBoxAdapter(child: Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Row(children: [
        Expanded(child: _FlatBox(icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 20), label: "Follow Updates".tl, value: _updateCount > 0 ? "$_updateCount" : null, alert: _updateCount > 0, onTap: () => context.to(() => const FollowUpdatesPage()))),
        const SizedBox(width: 10),
        Expanded(child: _FlatBox(icon: HugeIcon(icon: HugeIcons.strokeRoundedFolder01, size: 20), label: "Local".tl, value: "$lc", onTap: () => context.to(() => const LocalComicsPage()))),
      ])),
    ]));
  }
}

class _BottomModules extends StatelessWidget {
  const _BottomModules();
  @override Widget build(BuildContext context) {
    final cc = ComicSource.all().length;
    return SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Row(children: [
      Expanded(child: _FlatBox(icon: HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: 20), label: "Image Favorites".tl, onTap: () => context.to(() => const ImageFavoritesPage()))),
      const SizedBox(width: 10),
      Expanded(child: _FlatBox(icon: HugeIcon(icon: HugeIcons.strokeRoundedAppStore, size: 20), label: "Comic Source".tl, value: "$cc", onTap: () => context.to(() => const ComicSourcePage()))),
    ])));
  }
}

class _FlatBox extends StatelessWidget {
  final Widget icon; final String label; final String? value; final VoidCallback? onTap;
  final bool alert;
  const _FlatBox({required this.icon, required this.label, this.value, this.onTap, this.alert = false});
  @override Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(onTap: onTap,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kcRadius22),
            color: cs.surfaceContainerLow,
          ),
          child: Row(children: [
            icon,
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(fontSize: kcBody, color: cs.onSurface))),
            if (value != null)
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                decoration: BoxDecoration(
                  color: alert ? cs.errorContainer : cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(value!, style: TextStyle(fontSize: kcFont11, fontWeight: FontWeight.w600, color: alert ? cs.onErrorContainer : cs.onPrimaryContainer)),
                ),
              ),
          ]),
        ),
        if (alert && value != null)
          Positioned(
            top: 4, right: 6,
            child: Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                color: cs.error,
                shape: BoxShape.circle,
                border: Border.all(color: cs.surfaceContainerLow, width: 1.5),
              ),
            ),
          ),
      ]),
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

class _HomeHintsState extends State<_HomeHints> {
  int _localCount = 0;
  int _favoriteCount = 0;
  int _sourceCount = 0;

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _localCount = LocalManager().count;
      _favoriteCount = LocalFavoritesManager().totalComics;
      _sourceCount = ComicSource.all().length;
    });
  }

  @override
  void initState() {
    super.initState();
    _localCount = LocalManager().count;
    _favoriteCount = LocalFavoritesManager().totalComics;
    _sourceCount = ComicSource.all().length;
    LocalManager().addListener(_refresh);
    LocalFavoritesManager().addListener(_refresh);
    ComicSourceManager().addListener(_refresh);
  }

  @override
  void dispose() {
    LocalManager().removeListener(_refresh);
    LocalFavoritesManager().removeListener(_refresh);
    ComicSourceManager().removeListener(_refresh);
    super.dispose();
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kcRadius18),
      ),
      child: Row(
        children: [
          HugeIcon(icon: HugeIcons.strokeRoundedBulb, size: 20, color: cs.primary.withValues(alpha: 0.8)),
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

