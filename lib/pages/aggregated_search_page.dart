import "package:flutter/material.dart";
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import "package:kong_comic/components/components.dart";
import "package:kong_comic/foundation/app.dart";
import "package:kong_comic/foundation/appdata.dart";
import "package:kong_comic/foundation/comic_source/comic_source.dart";
import "package:kong_comic/pages/comic_details_page/comic_page.dart";
import "package:kong_comic/pages/search_result_page.dart";
import "package:kong_comic/utils/translations.dart";

/// Normalize a comic title so that the same work from different sources
/// collapses to one key: lowercase, drop all whitespace and common
/// punctuation/brackets (works for CJK and Latin titles alike).
String _normalizeTitle(String s) {
  var t = s.toLowerCase();
  t = t.replaceAll(RegExp(r'\s+'), '');
  t = t.replaceAll(
    RegExp(
      r"[\]\[!@#%&*()_~|/.,:;'‘’“”【】（）《》「」『』、，。：；！？~^+\\-]",
    ),
    '',
  );
  return t;
}

/// A comic that matched across one or more sources. [representative] is the
/// first comic encountered (drives cover/title); [sources] lists every
/// per-source [Comic] that normalized to the same title.
class _DedupedComic {
  _DedupedComic(this.representative, this.sources);

  final Comic representative;

  final List<Comic> sources;
}

class AggregatedSearchPage extends StatefulWidget {
  const AggregatedSearchPage({super.key, required this.keyword, this.sourceKeys});

  final String keyword;

  final List<String>? sourceKeys;

  @override
  State<AggregatedSearchPage> createState() => _AggregatedSearchPageState();
}

class _AggregatedSearchPageState extends State<AggregatedSearchPage> {
  late final List<ComicSource> sources;

  late final SearchBarController controller;

  var _keyword = "";

  /// When true (default), results are merged across sources into a single
  /// de-duplicated grid. When false, the classic per-source row layout is used.
  var _aggregated = true;

  @override
  void initState() {
    var all = ComicSource.all()
        .where((e) => e.searchPageData != null)
        .map((e) => e.key)
        .toList();
    var sources = <String>[];
    if (widget.sourceKeys != null) {
      for (var source in widget.sourceKeys!) {
        if (all.contains(source)) {
          sources.add(source);
        }
      }
    } else {
      var settings = appdata.settings['searchSources'] as List;
      for (var source in settings) {
        if (all.contains(source)) {
          sources.add(source);
        }
      }
    }
    this.sources = sources.map((e) => ComicSource.find(e)!).toList();
    _keyword = widget.keyword;
    controller = SearchBarController(
      currentText: widget.keyword,
      onSearch: (text) {
        setState(() {
          _keyword = text;
        });
      },
    );
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(slivers: [
      SliverSearchBar(controller: controller),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OptionChip(
                text: "By Source".tl,
                isSelected: !_aggregated,
                onTap: () => setState(() => _aggregated = false),
              ),
              OptionChip(
                text: "Aggregate & Dedupe".tl,
                isSelected: _aggregated,
                onTap: () => setState(() => _aggregated = true),
              ),
            ],
          ),
        ),
      ),
      if (_aggregated)
        _AggregatedResults(
          key: ValueKey(_keyword),
          sources: sources,
          keyword: _keyword,
        )
      else
        SliverList(
          key: ValueKey(_keyword),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final source = sources[index];
              return _SliverSearchResult(
                key: ValueKey(source.key),
                source: source,
                keyword: _keyword,
              );
            },
            childCount: sources.length,
          ),
        ),
    ]);
  }
}

/// Fetches every enabled source in parallel, deduplicates by normalized title,
/// and renders a single grid. Tapping a multi-source comic opens a bottom
/// sheet to pick which source to view.
class _AggregatedResults extends StatefulWidget {
  const _AggregatedResults({
    required this.sources,
    required this.keyword,
    super.key,
  });

  final List<ComicSource> sources;

  final String keyword;

  @override
  State<_AggregatedResults> createState() => _AggregatedResultsState();
}

class _AggregatedResultsState extends State<_AggregatedResults> {
  bool isLoading = true;

  String? error;

  List<_DedupedComic>? deduped;

  /// Lookup from normalized title -> deduped entry, for badge/tap resolution.
  final Map<String, _DedupedComic> _byKey = {};

  int _totalHits = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<List<Comic>> _fetchOne(ComicSource source) async {
    try {
      final data = source.searchPageData!;
      final options =
          (data.searchOptions ?? []).map((e) => e.defaultValue).toList();
      if (data.loadPage != null) {
        final res = await data.loadPage!(widget.keyword, 1, options);
        if (!res.error) return res.data;
      } else if (data.loadNext != null) {
        final res = await data.loadNext!(widget.keyword, null, options);
        if (!res.error) return res.data;
      }
    } catch (e) {
      // One failing source must not break the whole aggregation.
      debugPrint("Aggregated search failed for ${source.key}: $e");
    }
    return const [];
  }

  Future<void> load() async {
    try {
      final results = await Future.wait(widget.sources.map(_fetchOne));
      if (!mounted) return;
      final all = results.expand((e) => e).toList();
      final map = <String, _DedupedComic>{};
      for (var c in all) {
        final key = _normalizeTitle(c.title);
        if (key.isEmpty) continue;
        final existing = map[key];
        if (existing == null) {
          map[key] = _DedupedComic(c, [c]);
        } else {
          existing.sources.add(c);
        }
      }
      final list = map.values.toList();
      list.sort((a, b) {
        final cmp = b.sources.length.compareTo(a.sources.length);
        if (cmp != 0) return cmp;
        return a.representative.title.compareTo(b.representative.title);
      });
      setState(() {
        deduped = list;
        _byKey
          ..clear()
          ..addAll(map);
        _totalHits = all.length;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  _DedupedComic? _entryFor(Comic comic) =>
      _byKey[_normalizeTitle(comic.title)];

  void _openDetail(Comic c, int heroID) {
    App.mainNavigatorKey?.currentContext?.to(
      () => ComicPage(
        id: c.id,
        sourceKey: c.sourceKey,
        cover: c.cover,
        title: c.title,
        heroID: heroID >= 0 ? heroID : null,
      ),
    );
  }

  void _showSourcePicker(BuildContext context, _DedupedComic entry) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                entry.representative.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(height: 1),
            ...entry.sources.map((c) {
              final source = ComicSource.find(c.sourceKey);
              return ListTile(
                leading: SizedBox(
                  width: 36,
                  height: 48,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: c.cover,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: context.colorScheme.surfaceContainerLow),
                      errorWidget: (_, __, ___) => Container(color: context.colorScheme.surfaceContainerLow),
                    ),
                  ),
                ),
                title: Text(source?.name ?? c.sourceKey),
                subtitle: c.subtitle?.isNotEmpty == true ? Text(c.subtitle!) : null,
                trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: 18),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openDetail(c, -1);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 240,
          child: Center(
            child: CircularProgressIndicator(
              color: context.colorScheme.primary,
            ),
          ),
        ),
      );
    }

    if (error != null) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 200,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(error!),
            ),
          ),
        ),
      );
    }

    if (deduped == null || deduped!.isEmpty) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 200,
          child: Center(
            child: Text(
              "No search results found".tl,
              style: TextStyle(color: context.colorScheme.outline),
            ),
          ),
        ),
      );
    }

    final works = "works".tl;
    final hitsAcross = "hits across".tl;
    final sourcesLabel = "sources".tl;
    return SliverMainAxisGroup(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            "${deduped!.length} $works · $_totalHits $hitsAcross ${widget.sources.length} $sourcesLabel",
            style: TextStyle(
              fontSize: kcFont13,
              color: context.colorScheme.outline,
            ),
          ),
        ),
      ),
      SliverGridComics(
        comics: deduped!.map((e) => e.representative).toList(),
        showSourceOnCover: true,
        badgeBuilder: (comic) {
          final entry = _entryFor(comic);
          if (entry == null) return null;
          final n = entry.sources.length;
          return n > 1 ? "$n $sourcesLabel" : null;
        },
        onTap: (comic, heroID) {
          final entry = _entryFor(comic);
          if (entry == null) return;
          if (entry.sources.length == 1) {
            _openDetail(entry.sources.first, heroID);
          } else {
            _showSourcePicker(context, entry);
          }
        },
      ),
    ]);
  }
}

class _SliverSearchResult extends StatefulWidget {
  const _SliverSearchResult({
    required this.source,
    required this.keyword,
    super.key,
  });

  final ComicSource source;

  final String keyword;

  @override
  State<_SliverSearchResult> createState() => _SliverSearchResultState();
}

class _SliverSearchResultState extends State<_SliverSearchResult>
    with AutomaticKeepAliveClientMixin {
  bool isLoading = true;

  static const _kComicHeight = 164.0;

  get _comicWidth => _kComicHeight * 0.7;

  static const _kLeftPadding = 16.0;

  List<Comic>? comics;

  String? error;

  void load() async {
    final data = widget.source.searchPageData!;
    var options =
        (data.searchOptions ?? []).map((e) => e.defaultValue).toList();
    if (data.loadPage != null) {
      var res = await data.loadPage!(widget.keyword, 1, options);
      if (!mounted) return;
      if (!res.error) {
        setState(() {
          comics = res.data;
          isLoading = false;
        });
      } else {
        setState(() {
          error = res.errorMessage ?? "Unknown error".tl;
          isLoading = false;
        });
      }
    } else if (data.loadNext != null) {
      var res = await data.loadNext!(widget.keyword, null, options);
      if (!mounted) return;
      if (!res.error) {
        setState(() {
          comics = res.data;
          isLoading = false;
        });
      } else {
        setState(() {
          error = res.errorMessage ?? "Unknown error".tl;
          isLoading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Widget buildPlaceHolder() {
    return Container(
      height: _kComicHeight,
      width: _comicWidth,
      margin: const EdgeInsets.only(left: _kLeftPadding),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kcRadius8),
      ),
    );
  }

  Widget buildComic(Comic c) {
    return SimpleComicTile(comic: c, withTitle: true)
        .paddingLeft(_kLeftPadding)
        .paddingBottom(2);
  }

  @override
  Widget build(BuildContext context) {
    if (error != null && error!.startsWith("CloudflareException")) {
      error = "Cloudflare verification required".tl;
    }
    super.build(context);
    return InkWell(
      onTap: () {
        context.to(
          () => SearchResultPage(
            text: widget.keyword,
            sourceKey: widget.source.key,
          ),
        );
      },
      child: Column(
        children: [
          ListTile(
            mouseCursor: SystemMouseCursors.click,
            title: Text(widget.source.name),
          ),
          if (isLoading)
            SizedBox(
              height: _kComicHeight,
              width: double.infinity,
              child: Shimmer(
                child: LayoutBuilder(builder: (context, constrains) {
                  var itemWidth = _comicWidth + _kLeftPadding;
                  var items = (constrains.maxWidth / itemWidth).ceil();
                  return Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Row(
                          children: List.generate(
                            items,
                            (index) => buildPlaceHolder(),
                          ),
                        ),
                      )
                    ],
                  );
                }),
              ),
            )
          else if (error != null || comics == null || comics!.isEmpty)
            SizedBox(
              height: _kComicHeight,
              child: Column(
                children: [
                  Row(
                    children: [
                      HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error ?? "No search results found".tl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    ],
                  ),
                  const Spacer(),
                ],
              ).paddingHorizontal(16),
            )
          else
            SizedBox(
              height: _kComicHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var c in comics!) buildComic(c),
                ],
              ),
            ),
        ],
      ).paddingBottom(16),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
