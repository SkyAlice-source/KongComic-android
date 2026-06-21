import 'dart:async';
import 'dart:io';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    var widget = LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final bannerHeight = (availableHeight - 380).clamp(260.0, 420.0);
        return _BannerProvider(
          bannerHeight: bannerHeight,
          child: SmoothCustomScrollView(
            slivers: [
              SliverPadding(padding: EdgeInsets.only(top: context.padding.top)),
              _Banner(height: bannerHeight),
              const _ReadingStats(),
              SliverToBoxAdapter(child: const _HomeCapsules()),
              const _BottomModules(),
              SliverPadding(padding: EdgeInsets.only(top: context.padding.bottom)),
            ],
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
  const _Banner({this.height = 360});
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
      setState(() { _currentIndex = (_currentIndex + 1) % _comics.length; _startTimer(); });
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
                  setState(() { _currentIndex = prev; _startTimer(); });
                } else if (details.velocity.pixelsPerSecond.dx < -80) {
                  final next = (_currentIndex + 1) % _comics.length;
                  setState(() { _currentIndex = next; _startTimer(); });
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
      Padding(padding: const EdgeInsets.only(top: 4),
        child: Text(comic.name, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 12, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
      ),
    ]);
  }

  Widget _buildCover(FavoriteItem comic) {
    if (comic.coverPath.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: comic.coverPath,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        placeholder: (_, __) => const SizedBox(),
        errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 40)),
      );
    }
    return Image(
      image: FileImage(File(comic.coverPath)),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 40)),
    );
  }
}

class _ReadingStats extends StatefulWidget {
  const _ReadingStats();
  @override State<_ReadingStats> createState() => _ReadingStatsState();
}
class _ReadingStatsState extends State<_ReadingStats> {
  int _favorites = 0;
  int _localCount = 0;
  void _refresh() { if (!mounted) return; setState(() { _favorites = LocalFavoritesManager().totalComics; _localCount = LocalManager().count; }); }
  @override void initState() { super.initState(); _refresh(); LocalFavoritesManager().addListener(_refresh); LocalManager().addListener(_refresh); }
  @override void dispose() { LocalFavoritesManager().removeListener(_refresh); LocalManager().removeListener(_refresh); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final d = Theme.of(context).brightness == Brightness.dark;
    return SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 6), child: Row(children: [
      Expanded(child: _ModuleCapsule(icon: FluentIcons.apps_24_regular, label: "Categories".tl, isDark: d, onTap: () => context.to(() => const CategoriesPage()))),
      const SizedBox(width: 10),
      Expanded(child: _ModuleCapsule(icon: FluentIcons.bookmark_24_regular, label: "Favorites".tl, value: "$_favorites", isDark: d, onTap: () => NaviPane.of(context).updatePage(1))),
    ])));
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
  @override void initState() { super.initState(); _refresh(); LocalFavoritesManager().addListener(_refresh); LocalManager().addListener(_refresh); HistoryManager().addListener(_refresh); }
  @override void dispose() { LocalFavoritesManager().removeListener(_refresh); LocalManager().removeListener(_refresh); HistoryManager().removeListener(_refresh); super.dispose(); }
  @override Widget build(BuildContext context) {
    final d = Theme.of(context).brightness == Brightness.dark; final hc = HistoryManager().length; final lc = LocalManager().count;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 6), child: Row(children: [
        Expanded(child: _ModuleCapsule(icon: FluentIcons.arrow_sync_24_regular, label: "Follow Updates".tl, value: _updateCount > 0 ? "$_updateCount" : null, isDark: d, onTap: () => context.to(() => const FollowUpdatesPage()))),
        const SizedBox(width: 10),
        Expanded(child: _ModuleCapsule(icon: FluentIcons.clock_24_regular, label: "History".tl, value: "$hc", isDark: d, onTap: () => context.to(() => const HistoryPage()))),
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 6), child: Row(children: [
        Expanded(child: _ModuleCapsule(icon: FluentIcons.arrow_download_24_regular, label: "Download".tl, value: "$lc", isDark: d, onTap: () {
          if (LocalManager().downloadingTasks.isNotEmpty) {
            context.to(() => const DownloadingPage());
          } else {
            context.to(() => const LocalComicsPage());
          }
        })),
        const SizedBox(width: 10),
        Expanded(child: _ModuleCapsule(icon: FluentIcons.folder_24_regular, label: "Local".tl, value: "$lc", isDark: d, onTap: () => context.to(() => const LocalComicsPage()))),
      ])),
    ]);
  }
}

class _BottomModules extends StatelessWidget {
  const _BottomModules();
  @override Widget build(BuildContext context) {
    final d = Theme.of(context).brightness == Brightness.dark; final cc = ComicSource.all().length;
    return SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 6), child: Row(children: [
      Expanded(child: _ModuleCapsule(icon: FluentIcons.image_24_regular, label: "Image Favorites".tl, isDark: d, onTap: () => context.to(() => const ImageFavoritesPage()))),
      const SizedBox(width: 10),
      Expanded(child: _ModuleCapsule(icon: FluentIcons.apps_24_regular, label: "Comic Source".tl, value: "$cc", isDark: d, onTap: () => context.to(() => const ComicSourcePage()))),
    ])));
  }
}

class _ModuleCapsule extends StatelessWidget {
  final IconData icon; final String label; final String? value; final bool isDark; final VoidCallback? onTap;
  const _ModuleCapsule({required this.icon, required this.label, this.value, required this.isDark, this.onTap});
  @override Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap,
      child: Container(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(colors: isDark ? [const Color(0xFF1A1A1E).withValues(alpha: 0.7), const Color(0xFF1A1A1E).withValues(alpha: 0.4)] : [const Color(0xFF0EA5E9).withValues(alpha: 0.12), const Color(0xFF0EA5E9).withValues(alpha: 0.04)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFF0EA5E9).withValues(alpha: 0.2), width: 0.5),
          boxShadow: [BoxShadow(color: isDark ? Colors.black.withValues(alpha: 0.25) : const Color(0xFF0EA5E9).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          Icon(icon, size: 32, color: isDark ? const Color(0xFFDDDDDD) : const Color(0xFF0EA5E9)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontSize: 16, color: isDark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF333333)))),
          if (value != null) Text(value!, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: isDark ? const Color(0xFFDDDDDD) : const Color(0xFF0EA5E9))),
        ]),
      ),
    );
  }
}

