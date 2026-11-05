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
    RegExp(r"[\]\[!@#%&*()_~|/.,:;'‘’“”【】（）《》「」『』、，。：；！？~^+\\-]"),
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
  const AggregatedSearchPage({
    super.key,
    required this.keyword,
    this.sourceKeys,
  });

  final String keyword;

  final List<String>? sourceKeys;

  @override
  State<AggregatedSearchPage> createState() => _AggregatedSearchPageState();
}

/// 单个源的一次查询状态。
///
/// 搜索在父级统一发一次，两个视图吃同一份结果。之前「聚合」和「按源」各自
/// 是一个 StatefulWidget、各自在 initState 里请求：切一次档整批网络请求重发
/// 一遍，3 个源就是 3 次往返，用户看到的是分段条一动、下面整屏回骨架屏。
class _SourceResult {
  _SourceResult(this.source);

  final ComicSource source;

  /// null 表示还没回来；空列表表示搜过但没结果。
  List<Comic>? comics;

  String? error;

  bool get isLoading => comics == null && error == null;
}

class _AggregatedSearchPageState extends State<AggregatedSearchPage> {
  late final List<ComicSource> sources;

  late final SearchBarController controller;

  var _keyword = "";

  /// When true (default), results are merged across sources into a single
  /// de-duplicated grid. When false, the classic per-source row layout is used.
  var _aggregated = true;

  /// 每个源一份查询结果，两个视图共用（切档不重新请求）。
  List<_SourceResult> _queries = const [];

  /// 请求代数。改关键词会重发一批，旧的那批回来时按代号丢弃，避免慢源的
  /// 旧结果盖掉新关键词的结果。
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    var all = ComicSource.enabled()
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
    // 源可能在搜索发起后被禁用或删除（用户切后台改了源配置）。强解包会让
    // 整个聚合结果页白屏，这里过滤掉解析不到的键，剩下的源照常请求。
    this.sources = sources
        .map(ComicSource.find)
        .whereType<ComicSource>()
        .toList();
    _keyword = widget.keyword;
    controller = SearchBarController(
      currentText: widget.keyword,
      onSearch: (text) {
        if (text == _keyword || text.trim().isEmpty) return;
        _keyword = text;
        _startSearch();
      },
    );
    _startSearch(notify: false);
  }

  /// 一次性给每个源建一份查询并发起请求。
  ///
  /// [notify] 为 false 时只赋值不 setState（initState 首帧之前用）。
  void _startSearch({bool notify = true}) {
    final queries = sources.map(_SourceResult.new).toList();
    final generation = ++_generation;
    if (notify) {
      setState(() => _queries = queries);
    } else {
      _queries = queries;
    }
    for (final q in queries) {
      _fetchSource(q, generation);
    }
  }

  /// 拉一个源的第一页。
  ///
  /// 错误按源记录而不是整页失败：三个源里挂掉一个，另外两个的结果照常显示，
  /// 挂掉的那个在「按源」视图里单独提示。「聚合」视图则只看成功源的数据。
  Future<void> _fetchSource(_SourceResult q, int generation) async {
    var comics = <Comic>[];
    String? error;
    try {
      final data = q.source.searchPageData!;
      final options = (data.searchOptions ?? [])
          .map((e) => e.defaultValue)
          .toList();
      if (data.loadPage != null) {
        final res = await data.loadPage!(_keyword, 1, options);
        if (res.error) {
          error = rawSourceError(res.errorMessage);
        } else {
          comics = res.data;
        }
      } else if (data.loadNext != null) {
        final res = await data.loadNext!(_keyword, null, options);
        if (res.error) {
          error = rawSourceError(res.errorMessage);
        } else {
          comics = res.data;
        }
      }
    } catch (e) {
      // 源脚本/网络层直接抛异常（不是返回 Res.error）。
      error = friendlyError(e);
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      q.comics = comics;
      q.error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverSearchBar(controller: controller),
        SliverToBoxAdapter(
          child: _ViewModeSwitch(
            aggregated: _aggregated,
            onChanged: (value) => setState(() => _aggregated = value),
          ),
        ),
        if (_aggregated)
          _AggregatedResults(queries: _queries)
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return _SliverSearchResult(
                query: _queries[index],
                keyword: _keyword,
              );
            }, childCount: _queries.length),
          ),
      ],
    );
  }
}

/// 结果视图分段控件：同一批结果的两种摆法，互斥二选一。
///
/// 前置（搜索页）不再有「按源 / 聚合」模式档：勾几个源就是搜几个源，用
/// 「全选」胶囊表达。这里只保留后置的视图切换 —— 数据已经拿回来了，用户
/// 看到结果后才决定按源分组对比、还是合并去重看总览。
/// 「互斥二选一用分段、可多选筛选用胶囊」从此是一条稳定规则。
class _ViewModeSwitch extends StatelessWidget {
  const _ViewModeSwitch({
    required this.aggregated,
    required this.onChanged,
  });

  final bool aggregated;

  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final reduced = kcReduceMotion(context);
    return Padding(
      // 下留 16dp：分段条自身的槽边界已经是一层，不再套浅卡片变成两层框。
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Container(
        height: 38,
        width: double.infinity,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          // 深色下槽要比背景亮一点、又比滑块暗一级；用 surfaceContainerLow
          // 时槽几乎融进纯黑背景，整条控件只剩选中块可见，分段感就没了。
          color: isDark ? cs.surfaceContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(kcRadius10),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.55),
            width: kcHairline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // LayoutBuilder 拿到的是扣掉左右 3dp padding 的槽宽，两段等分。
            final segmentWidth = constraints.maxWidth / 2;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  left: aggregated ? segmentWidth : 0,
                  top: 0,
                  bottom: 0,
                  width: segmentWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      // 深色下槽压暗、滑块提亮两级，选中块才看得见。
                      color: isDark
                          ? cs.surfaceContainerHighest
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? kcBrandAdaptive(context).withValues(alpha: 0.45)
                            : cs.outlineVariant.withValues(alpha: 0.9),
                        width: kcHairline,
                      ),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.07),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    _ViewModeSegment(
                      text: "By Source".tl,
                      selected: !aggregated,
                      onTap: () => onChanged(false),
                    ),
                    _ViewModeSegment(
                      text: "Aggregate & Dedupe".tl,
                      selected: aggregated,
                      onTap: () => onChanged(true),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ViewModeSegment extends StatelessWidget {
  const _ViewModeSegment({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;

  final bool selected;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.onSurface : cs.onSurfaceVariant;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.expand(
          child: Center(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: kcBody,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Deduplicates the already-fetched results by normalized title and renders a
/// single grid. Tapping a multi-source comic opens a bottom sheet to pick which
/// source to view.
///
/// 纯展示：数据由父级统一拉取（[_SourceResult]），这里不再自己发请求。
class _AggregatedResults extends StatelessWidget {
  const _AggregatedResults({required this.queries});

  final List<_SourceResult> queries;

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
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kcSurfaceRadius),
        ),
      ),
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
              return KcListTile(
                showDivider: c != entry.sources.last,
                leading: SizedBox(
                  width: 36,
                  height: 48,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(kcRadius8),
                    child: CachedNetworkImage(
                      imageUrl: c.cover,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: context.colorScheme.surfaceContainerLow,
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: context.colorScheme.surfaceContainerLow,
                      ),
                    ),
                  ),
                ),
                title: Text(source?.name ?? c.sourceKey),
                subtitle: c.subtitle?.isNotEmpty == true
                    ? Text(c.subtitle!)
                    : null,
                chevron: true,
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
    // 只要还有源在路上就继续转圈；先回来的源不抢着渲染，避免列表成批跳动。
    if (queries.any((q) => q.isLoading)) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 240,
          child: KcPageLoading(charWidth: 88, color: kcAccentColor(context)),
        ),
      );
    }

    final all = <Comic>[
      for (final q in queries) ...?q.comics,
    ];

    if (all.isEmpty) {
      // 全部源都没结果：有错误就报错误（各源错误基本同因，取第一条即可），
      // 否则是「确实没搜到」。
      final error = queries.map((q) => q.error).whereType<String>().firstOrNull;
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 200,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                error ?? "No search results found".tl,
                textAlign: TextAlign.center,
                style: error == null
                    ? TextStyle(color: context.colorScheme.outline)
                    : null,
              ),
            ),
          ),
        ),
      );
    }

    final map = <String, _DedupedComic>{};
    for (final c in all) {
      final key = _normalizeTitle(c.title);
      if (key.isEmpty) continue;
      final existing = map[key];
      if (existing == null) {
        map[key] = _DedupedComic(c, [c]);
      } else {
        existing.sources.add(c);
      }
    }
    final list = map.values.toList()
      ..sort((a, b) {
        final cmp = b.sources.length.compareTo(a.sources.length);
        if (cmp != 0) return cmp;
        return a.representative.title.compareTo(b.representative.title);
      });

    _DedupedComic? entryFor(Comic comic) => map[_normalizeTitle(comic.title)];

    // 真正返回了结果的源数。统计行写的是「N 条结果来自 M 个源」，M 不能用
    // 请求的源数：某个源被 Cloudflare 拦住、或干脆没搜到时，请求了 3 个源
    // 也会显示「来自 3 个源」。
    final sourceHits = queries
        .where((q) => q.comics?.isNotEmpty ?? false)
        .length;

    final works = "works".tl;
    final hitsAcross = "hits across".tl;
    final sourcesLabel = "sources".tl;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            // 卡片下沿 12dp 之后再来这一行说明，别让它紧贴着胶囊读成同一组。
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: Text(
              "${list.length} $works · ${all.length} $hitsAcross $sourceHits $sourcesLabel",
              style: TextStyle(
                fontSize: kcCaption,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        SliverGridComics(
          comics: list.map((e) => e.representative).toList(),
          showSourceOnCover: true,
          badgeBuilder: (comic) {
            final entry = entryFor(comic);
            if (entry == null) return null;
            final n = entry.sources.length;
            return n > 1 ? "$n $sourcesLabel" : null;
          },
          onTap: (comic, heroID) {
            final entry = entryFor(comic);
            if (entry == null) return;
            if (entry.sources.length == 1) {
              _openDetail(entry.sources.first, heroID);
            } else {
              _showSourcePicker(context, entry);
            }
          },
        ),
      ],
    );
  }
}

/// 「按源」视图里的一行：源名 + 该源结果横向列表。
///
/// 纯展示，数据来自父级的 [_SourceResult] —— 这里不再发请求，所以来回切
/// 分段控件不会重发网络请求。
class _SliverSearchResult extends StatelessWidget {
  const _SliverSearchResult({
    required this.query,
    required this.keyword,
  });

  final _SourceResult query;

  /// 点源名进入单源结果页时要带的词。
  final String keyword;

  static const _kComicHeight = 164.0;

  static const _comicWidth = _kComicHeight * 0.7;

  static const _kLeftPadding = 16.0;

  Widget _buildPlaceHolder(BuildContext context) {
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

  Widget _buildComic(Comic c) {
    return SimpleComicTile(
      comic: c,
      withTitle: true,
    ).paddingLeft(_kLeftPadding).paddingBottom(2);
  }

  @override
  Widget build(BuildContext context) {
    final source = query.source;
    final comics = query.comics;
    var error = query.error;
    if (error != null && error.startsWith("CloudflareException")) {
      error = "Cloudflare verification required".tl;
    }
    return InkWell(
      onTap: () {
        context.to(
          () => SearchResultPage(
            text: keyword,
            sourceKey: source.key,
          ),
        );
      },
      child: Column(
        children: [
          KcListTile(showDivider: false, title: Text(source.name)),
          if (query.isLoading)
            SizedBox(
              height: _kComicHeight,
              width: double.infinity,
              child: Shimmer(
                child: LayoutBuilder(
                  builder: (context, constrains) {
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
                              (index) => _buildPlaceHolder(context),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            )
          else if (error != null || comics == null || comics.isEmpty)
            // 原来这里用 SizedBox(height: _kComicHeight) 撑满一个封面的高度，
            // 再用 Spacer 把提示顶到顶部：三个源都没结果时，整页变成三大片
            // 空白，看着像排版坏了或加载卡住。提示只占一行，高度随内容走。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedAlertCircle,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error ?? "No search results found".tl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: _kComicHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [for (var c in comics) _buildComic(c)],
              ),
            ),
        ],
      ).paddingBottom(16),
    );
  }
}
