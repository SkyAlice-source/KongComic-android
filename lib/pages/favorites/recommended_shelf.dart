part of 'favorites_page.dart';

/// 源里一个可用分类：拿它去调 [CategoryComicsData.load]。
class _CategoryTarget {
  const _CategoryTarget({
    required this.category,
    required this.param,
    required this.options,
  });

  /// 传给 load 的 category 名（可能和界面上显示的 label 不同）。
  final String category;

  /// 分类附加参数。不少源（比如百合会）在 load 里直接 `params.split('@')`，
  /// 传 null 会当场抛异常，所以必须带着分类页给的 param 一起发。
  final String? param;

  final List<String> options;
}

/// 「推荐」货架的取数依据：收藏里出现次数最多的标签 + 它在该源里对应的分类。
class _RecommendBasis {
  const _RecommendBasis({
    required this.tag,
    required this.target,
    required this.source,
    required this.owned,
  });

  /// 展示用的标签原文（副标题里「因为你喜欢 X」的 X）。
  final String tag;

  final _CategoryTarget target;

  final ComicSource source;

  /// 已收藏漫画的 `id|sourceKey` 集合：用来把推荐结果里已经收藏过的剔除，
  /// 否则推荐的第一排全是你书架上已有的书。
  final Set<String> owned;

  bool contains(Comic c) => owned.contains('${c.id}|${c.sourceKey}');
}

/// 把一个标签拆成可用于匹配分类名的候选。
///
/// 收藏库里的 tags 是「键:值」拼起来的（例如 百合会 存的是
/// `作者:xxx,更新:xxx,标签:条漫`），直接用整串去匹配分类名永远匹配不上；
/// 同时有些源的标签不带前缀，所以原文也要作为候选保留。
List<String> _tagCandidates(String raw) {
  final tag = raw.trim();
  if (tag.isEmpty) return const [];
  final res = <String>[tag];
  for (final sep in [':', '：']) {
    final i = tag.indexOf(sep);
    if (i <= 0 || i == tag.length - 1) continue;
    final suffix = tag.substring(i + 1).trim();
    if (suffix.isNotEmpty && !res.contains(suffix)) res.add(suffix);
  }
  return res;
}

/// 源的所有分类：界面显示名 → 可发请求的分类目标。
///
/// 结果按源缓存：这个列表来自 JS 侧的静态配置，一次会话内不会变，
/// 而 [DynamicCategoryPart] 每次读 categories 都会跑一遍 JS loader。
final Map<String, Map<String, _CategoryTarget>> _categoryTargetCache = {};

Map<String, _CategoryTarget> _categoryTargetsOf(ComicSource source) {
  final cached = _categoryTargetCache[source.key];
  if (cached != null) return cached;
  final data = source.categoryComicsData;
  final categoryData = source.categoryData;
  final res = <String, _CategoryTarget>{};
  if (data != null && categoryData != null) {
    for (final part in categoryData.categories) {
      List<CategoryItem> items;
      try {
        items = part.categories;
      } catch (e) {
        // 动态分类的 loader 抛异常不能把整页拖垮，跳过这一段继续。
        continue;
      }
      for (final item in items) {
        final target = item.target;
        if (target.page != 'category') continue;
        final attrs = target.attributes;
        final category = attrs?['category'];
        if (category is! String || category.isEmpty) continue;
        final attrOptions = attrs?['options'];
        final t = _CategoryTarget(
          category: category,
          param: attrs?['param']?.toString(),
          options: attrOptions is List
              ? List<String>.from(attrOptions)
              : _defaultCategoryOptions(data, category),
        );
        res.putIfAbsent(item.label, () => t);
        res.putIfAbsent(category, () => t);
      }
    }
  }
  return _categoryTargetCache[source.key] = res;
}

/// [CategoryComicsData.options] 的默认值：每个筛选项取第一个可选值。
///
/// 与 [CategoryComicsPage] 同规则 —— 某些筛选项只对部分分类生效。
List<String> _defaultCategoryOptions(CategoryComicsData data, String category) {
  return data.options
          ?.where((o) {
            if (o.notShowWhen.contains(category)) return false;
            final showWhen = o.showWhen;
            if (showWhen != null) return showWhen.contains(category);
            return true;
          })
          .map((o) => o.options.keys.first)
          .toList() ??
      const [];
}

/// 收藏页底部的「推荐」货架。
///
/// 取数链路：收藏里出现最多的标签 → 该标签在该源里对应的分类 →
/// [CategoryComicsData.load] → 剔除已收藏的 → 一排横滑封面。
///
/// 任何一步拿不到数据（没有可用依据 / 源不支持分类取数 / 网络失败 /
/// 拉回来的全都已收藏）就整排不渲染：收藏页是「我的书架」，
/// 不该在底部挂一块错误占位或空壳。
class _RecommendedShelf extends StatefulWidget {
  const _RecommendedShelf({
    required this.basis,
    required this.cardW,
    required this.cardH,
    required this.onTap,
  });

  /// null 表示没有可用依据，直接不渲染。
  final _RecommendBasis? basis;

  final double cardW;

  final double cardH;

  final ValueChanged<Comic> onTap;

  @override
  State<_RecommendedShelf> createState() => _RecommendedShelfState();
}

class _RecommendedShelfState extends State<_RecommendedShelf> {
  /// null = 加载中；空列表 = 没内容（不渲染）。
  List<Comic>? _comics;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _RecommendedShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 收藏变了 → 偏好标签可能变了。用 tag+分类当身份，变了才重新拉，
    // 避免父级每次 setState 都发一遍网络请求。
    final old = oldWidget.basis;
    final now = widget.basis;
    if (old?.tag != now?.tag ||
        old?.target.category != now?.target.category ||
        old?.source.key != now?.source.key) {
      _comics = null;
      _load();
    }
  }

  Future<void> _load() async {
    final basis = widget.basis;
    if (basis == null) return;
    Res<List<Comic>> res;
    try {
      // 必须带超时：源站挂住不回时（实测百合会从模拟器访问恒 502/无响应），
      // 没有超时这一排会永远停在骨架屏上。
      res = await basis.source.categoryComicsData!
          .load(
            basis.target.category,
            basis.target.param,
            basis.target.options,
            1,
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      // 源脚本抛异常时 Res 永远拿不到：不兜住的话这一排会一直转圈。
      res = Res<List<Comic>>.error(friendlyError(e));
    }
    if (!mounted) return;
    final data = res.dataOrNull;
    if (data == null) {
      setState(() => _comics = const []);
      return;
    }
    final list = <Comic>[];
    for (final c in data) {
      if (basis.contains(c)) continue;
      list.add(c);
      if (list.length >= _FavoritesPageState._shelfLimit) break;
    }
    setState(() => _comics = list);
  }

  @override
  Widget build(BuildContext context) {
    final basis = widget.basis;
    if (basis == null) return const SizedBox.shrink();
    final comics = _comics;
    if (comics != null && comics.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _shelfHeader(
          context: context,
          title: "Recommended".tl,
          // 不显示数量：这一排是「某个分类下的一页」，不是「你还有多少本可读」。
          total: null,
          // 把推荐依据写出来，否则用户只会觉得这是又一个莫名其妙的热门榜。
          subtitle: "Because you like @tag".tlParams({'tag': basis.tag}),
          onOpenAll: null,
          topPadding: 24,
        ),
        if (comics == null)
          _buildSkeleton(context)
        else
          SizedBox(
            height: widget.cardH,
            child: ListView.separated(
              key: const ValueKey('shelf_recommended'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: kcSpaceLg, right: kcSpaceSm),
              physics: const BouncingScrollPhysics(),
              itemCount: comics.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final c = comics[i];
                return SizedBox(
                  width: widget.cardW,
                  child: ComicTile(
                    comic: c,
                    showSourceOnCover: false,
                    showBottomSourceDate: false,
                    // 推荐的书不在本地收藏里，别让它再去查一遍收藏库。
                    isFavorite: false,
                    onTap: () => widget.onTap(c),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// 加载中的占位：直接按成品尺寸摆 3 张灰卡，数据来了不会跳版。
  Widget _buildSkeleton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.cardH,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: kcSpaceLg, right: kcSpaceSm),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => Container(
          width: widget.cardW,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(kcCardRadius),
          ),
        ),
      ),
    );
  }
}
