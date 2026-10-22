import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/res.dart';
import 'package:kong_comic/utils/translations.dart';

/// 源里一个可用分类：拿它去调 [CategoryComicsData.load]。
class CategoryTarget {
  const CategoryTarget({
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
class RecommendBasis {
  const RecommendBasis({
    required this.tag,
    required this.target,
    required this.source,
    required this.owned,
  });

  /// 展示用的标签原文（副标题里「因为你喜欢 X」的 X）。
  final String tag;

  final CategoryTarget target;

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
final Map<String, Map<String, CategoryTarget>> _categoryTargetCache = {};

Map<String, CategoryTarget> _categoryTargetsOf(ComicSource source) {
  final cached = _categoryTargetCache[source.key];
  if (cached != null) return cached;
  final data = source.categoryComicsData;
  final categoryData = source.categoryData;
  final res = <String, CategoryTarget>{};
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
        final t = CategoryTarget(
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

/// 模块级缓存：收藏变化时 [invalidateRecommendBasis] 置空，下次再算。
/// null 本身是合法结果（没有可用依据），所以单独用一个 [_computed] 标记
/// 是否已算过，否则每次调用都重扫一遍收藏库统计标签。
RecommendBasis? _cache;
bool _computed = false;

/// 收藏页/发现页共用的「推荐」取数依据：收藏里出现最多的标签对应的分类。
///
/// 拿不到依据时（没收藏 / 收藏全在本地 / 源不支持按标签取漫画 / 该源的分类
/// 筛选项要联网才能确定）返回 null。
RecommendBasis? computeRecommendBasis() {
  if (_computed) return _cache;
  _computed = true;
  return _cache = _compute();
}

/// 收藏变化后让依据下次重算。
void invalidateRecommendBasis() {
  _computed = false;
  _cache = null;
}

RecommendBasis? _compute() {
  // key 用 \u0000 分隔：标签本身可能带空格，用空格拼接再 split 会把标签切开。
  final counts = <String, int>{};
  final targets = <String, CategoryTarget>{};
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
  return RecommendBasis(
    tag: parts[0],
    target: targets[best.key]!,
    source: sources[parts[1]]!,
    owned: owned,
  );
}

/// 按 [RecommendBasis] 拉一页推荐漫画，剔除已收藏的，至多取 [limit] 本。
///
/// [page] 用于「刷新」时翻到下一页，拿到不同的推荐。任何一步失败都返回空
/// 列表（不抛异常），调用方据此决定是显示骨架屏还是整段不渲染。
Future<List<Comic>> loadRecommendComics(
  RecommendBasis basis, {
  int limit = 9,
  int page = 1,
}) async {
  final list = <Comic>[];
  Res<List<Comic>> res;
  try {
    // 必须带超时：源站挂住不回时（实测百合会从模拟器访问恒 502/无响应），
    // 没有超时这一排会永远停在骨架屏上。
    res = await basis.source.categoryComicsData!
        .load(
          basis.target.category,
          basis.target.param,
          basis.target.options,
          page,
        )
        .timeout(const Duration(seconds: 20));
  } catch (e) {
    // 源脚本抛异常时 Res 永远拿不到：不兜住的话这一排会一直转圈。
    res = Res<List<Comic>>.error(friendlyError(e));
  }
  final data = res.dataOrNull;
  if (data == null) return list;
  for (final c in data) {
    if (basis.contains(c)) continue;
    list.add(c);
    if (list.length >= limit) break;
  }
  return list;
}
