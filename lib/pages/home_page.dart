import 'dart:async';
import 'dart:io';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/pages/categories_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:sliver_tools/sliver_tools.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/consts.dart';
import 'package:kong_comic/foundation/custom_cover.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/history.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/pages/comic_details_page/comic_page.dart';
import 'package:kong_comic/pages/comic_source_page.dart';
import 'package:kong_comic/pages/downloading_page.dart';
import 'package:kong_comic/pages/follow_updates_page.dart';
import 'package:kong_comic/pages/history_page.dart';
import 'package:kong_comic/pages/image_favorites_page/image_favorites_page.dart';
import 'package:kong_comic/utils/data_sync.dart';
import 'package:kong_comic/utils/import_comic.dart';
import 'package:kong_comic/utils/tags_translation.dart';
import 'package:kong_comic/utils/translations.dart';

import 'local_comics_page.dart';

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
    // Allow the banner to rebuild and load new comics
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    var widget = LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final bannerHeight = (availableHeight - 380).clamp(260.0, 420.0);
        return _BannerProvider(
          bannerHeight: bannerHeight,
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            child: SmoothCustomScrollView(
              slivers: [
                SliverPadding(padding: EdgeInsets.only(top: context.padding.top)),
                _Banner(key: _bannerKey, height: bannerHeight, currentComicNotifier: _currentComic),
                _ComicInfoSection(currentComicNotifier: _currentComic),
                const _HomeCapsules(),
                const _BottomModules(),
                SliverPadding(padding: EdgeInsets.only(top: context.padding.bottom)),
              ],
            ),
          ),
        );
      },
    );
    return context.width > changePoint ? widget.paddingHorizontal(8) : widget;
  }
}

class _BannerProvider extends InheritedWidget {
  final double bannerHeight;
  const _BannerProvider({required this.bannerHeight, required super.child});
  static _BannerProvider of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_BannerProvider>()!;
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
    final folders = LocalFavoritesManager().folderNames;
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
    _loadComics(); LocalFavoritesManager().addListener(_loadComics); _startTimer();
  }
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _comics.length < 2) return;
      setState(() { _currentIndex = (_currentIndex + 1) % _comics.length; widget.currentComicNotifier.value = _comics[_currentIndex]; });
    });
  }
  @override void dispose() { _timer?.cancel(); LocalFavoritesManager().removeListener(_loadComics); super.dispose(); }
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
    final cardW = sw * 0.54;
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
                duration: const Duration(milliseconds: 300),
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
final opacity = 1.0;
      final pos = sw * 0.5 + layer * overlap - cardW * 0.5;
      items.add(Positioned(
        left: pos, top: topOff, width: cardW,
        child: Transform.scale(scale: scale,
          child: Opacity(
            opacity: opacity,
            child: ClipRRect(borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.4), width: 3.0),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15), blurRadius: 6, offset: const Offset(0, 3)),
                    BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.18), blurRadius: 12, offset: const Offset(-4, 0)),
                    BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.18), blurRadius: 12, offset: const Offset(4, 0)),
                  ],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: SizedBox(height: cardW * 1.4, child: _buildCover(comic)),
                ),
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
    final cardW = width ?? sw * 0.54;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15), blurRadius: 6, offset: const Offset(0, 3)),
            BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.18), blurRadius: 12, offset: const Offset(-4, 0)),
            BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.18), blurRadius: 12, offset: const Offset(4, 0)),
          ],
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.4), width: 3.0), borderRadius: BorderRadius.circular(12)),
            child: ClipRRect(borderRadius: BorderRadius.circular(10),
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
        final progress = history != null && history.maxPage != null && history.maxPage! > 0
            ? "${(history.page * 100 / history.maxPage!).clamp(0, 100).toInt()}%"
            : null;
        final updatedTime = comic.time.isNotEmpty ? comic.time.substring(0, 10) : null;
        return SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 漫画名占三行高度
            SizedBox(height: 72, child: Align(alignment: Alignment.bottomLeft,
              child: Text(comic.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface)))),
            const SizedBox(height: 6),
            if (comic.author.isNotEmpty || comic.tags.isNotEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  comic.author.isNotEmpty ? comic.author : comic.tags.first,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
            if (progress != null)
              Padding(padding: const EdgeInsets.only(bottom: 4),
                child: Text("Reading progress %s".tl.replaceAll("%s", progress ?? ""), style: TextStyle(fontSize: 13, color: cs.onSurface))),
            Text("Total %s chapters".tl.replaceAll("%s", "${history?.maxPage ?? '?'}"), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            if (updatedTime != null)
              Padding(padding: const EdgeInsets.only(top: 4),
                child: Text("Updated %s".tl.replaceAll("%s", updatedTime), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, height: 44,
              child: ElevatedButton(
                onPressed: () => context.to(() => ComicPage(id: comic.id, sourceKey: comic.type.comicSource?.key ?? '', cover: comic.coverPath, title: comic.name)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)), elevation: 0),
                child: Text("Read Now".tl, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
    setState(() { if (folder == null) _updateCount = 0; else if (LocalFavoritesManager().folderNames.contains(folder)) _updateCount = LocalFavoritesManager().countUpdates(folder!); else _updateCount = 0; });
  }
  @override void initState() { super.initState(); _refresh(); LocalFavoritesManager().addListener(_refresh); LocalManager().addListener(_refresh); }
  @override void dispose() { LocalFavoritesManager().removeListener(_refresh); LocalManager().removeListener(_refresh); super.dispose(); }
  @override Widget build(BuildContext context) {
    final lc = LocalManager().count;
    return SliverToBoxAdapter(child: Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Row(children: [
        Expanded(child: _FlatBox(icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 20), label: "Follow Updates".tl, value: _updateCount > 0 ? "$_updateCount" : null, onTap: () => context.to(() => const FollowUpdatesPage()))),
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
  const _FlatBox({required this.icon, required this.label, this.value, this.onTap});
  @override Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: cs.surfaceContainerLow,
        ),
        child: Row(children: [
          icon,
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: cs.onSurface))),
          if (value != null)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
              child: Text(value!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onPrimaryContainer)),
            ),
        ]),
      ),
    );
  }
}

