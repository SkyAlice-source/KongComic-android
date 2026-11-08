import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_type.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/history.dart';
import 'package:kong_comic/foundation/image_provider/cached_image.dart';
import 'package:kong_comic/foundation/image_provider/image_favorites_provider.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/pages/comic_details_page/comic_page.dart';
import 'package:kong_comic/pages/search_page.dart';
import 'package:kong_comic/utils/opencc.dart';
import 'package:kong_comic/utils/translations.dart';

/// 速搜的数据范围。
///
/// 三个库页共用同一个浮层：视觉、键盘行为、空态、底部网络搜索兜底完全一致，
/// 只是「搜哪份数据」和「点结果去哪」不同。这样收藏 / 图片收藏 / 本地漫画
/// 不再各自维护一套内联搜索条，也不会出现「换个页面就得重搜一次」。
enum QuickSearchScope {
  /// 我的库：收藏（全部文件夹）+ 阅读历史。
  library,

  /// 图片收藏。
  imageFavorites,

  /// 本地漫画。
  local,
}

/// 打开「速搜」浮层：一处搜遍 收藏（全部文件夹）+ 阅读历史。
///
/// 为什么不再用页面内联搜索条：
/// - 收藏内页的内联条只筛**当前文件夹**，历史页的入口又只管历史 —— 同一个书名
///   要在两个页面各搜一次，还得先切到对的 tab / 文件夹；
/// - 内联条会顶掉共享顶栏的标题与工具胶囊，进出搜索态整页跳一下。
///
/// 改成居中浮层后：搜的是「我的库」整体，与当前停在哪个页面无关；关闭即恢复
/// 原样，页面状态零破坏。结果按来源分组，行内标注收藏夹 / 阅读进度，点即进详情；
/// 本地搜不到时底部一行直达网络搜索（把关键词带过去，不用重打）。
///
/// 传 [scope] 可切换到图片收藏 / 本地漫画的数据源，UI 与交互保持不变。
Future<void> showQuickSearch(
  BuildContext context, {
  QuickSearchScope scope = QuickSearchScope.library,
  String? initialQuery,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => QuickSearchDialog(
      scope: scope,
      initialQuery: initialQuery,
    ),
  );
}

/// 一条可点开的搜索结果。[hay] 是预先拼好的检索文本（含标题 / 作者 / 标签 /
/// 收藏夹名），避免每次敲键都对全部条目重新拼串。
class _QuickHit {
  _QuickHit({
    required this.id,
    required this.sourceKey,
    required this.cover,
    required this.image,
    required this.title,
    required this.meta,
    required this.hay,
    this.comicType,
  });

  final String id;
  final String sourceKey;

  /// 本地漫画的精确类型。源被卸载后 `ComicType.fromKey(sourceKey)` 反查
  /// 不回来，本地条目必须直接带原始 type 才能定位到库里的那一条。
  final ComicType? comicType;

  /// 原始封面地址，进详情页时透传（详情页靠它先占位，再拉正式封面）。
  final String cover;

  /// 封面 provider，走 App 自己的缩略图缓存（[CachedImageProvider]）。
  ///
  /// 不能用 `kcCoverImage` 那种裸 `CachedNetworkImage`：列表卡片用的是
  /// `CachedImageProvider` / `HistoryImageProvider`（带自有磁盘缩略图缓存和
  /// 本地封面兜底），换成另一套加载器后同一个 URL 在浮层里会当成新图重下，
  /// 实测网络稍差就整列变成空白/占位图。
  final ImageProvider? image;

  final String title;

  /// 第二行副标题：收藏夹名（收藏）或「第 N 章 · 月-日」（历史）。
  final String meta;

  final String hay;

  late final String hayLower = hay.toLowerCase();
}

/// 结果列表里的分组（与 [_QuickHit] 一起塞进同一个扁平列表）。
class _Section {
  const _Section(this.label, this.hits);

  final String label;
  final List<_QuickHit> hits;
}

class QuickSearchDialog extends StatefulWidget {
  const QuickSearchDialog({
    super.key,
    this.scope = QuickSearchScope.library,
    this.initialQuery,
  });

  final QuickSearchScope scope;

  /// 外部带进来的关键词（例如从别的页面「搜一下图片收藏」跳进来）。
  final String? initialQuery;

  @override
  State<QuickSearchDialog> createState() => _QuickSearchDialogState();
}

class _QuickSearchDialogState extends State<QuickSearchDialog> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  /// 打开时一次性读库，之后敲键纯内存过滤。按 scope 分成一到两个分组。
  List<_Section> _all = const [];

  /// 收藏里出现过的 (id, type)：历史分组据此去重，同一本书不占两行。
  final _favKeys = <(String, int)>{};

  String _query = '';

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery?.trim() ?? '';
    _controller = TextEditingController(text: _query);
    _all = switch (widget.scope) {
      QuickSearchScope.library => _buildLibrary(),
      QuickSearchScope.imageFavorites => [
        _Section("Image Favorites".tl, _buildImageFavorites()),
      ],
      QuickSearchScope.local => [_Section("Local".tl, _buildLocal())],
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 收藏 + 历史两个分组。
  List<_Section> _buildLibrary() {
    return [
      _Section("Favorites".tl, _buildFavorites()),
      _Section("History".tl, _buildHistory()),
    ];
  }

  /// 收藏：遍历所有用户文件夹（跳过已废弃的「稍后阅读」），同一本书在多个
  /// 文件夹重复收藏只留一条。顺序按收藏时间倒序，空关键词时的「最近」直接可用。
  List<_QuickHit> _buildFavorites() {
    final manager = LocalFavoritesManager();
    final out = <(_QuickHit, String)>[];
    for (final folder in userFolderNames()) {
      final folderName = getFavoriteDataOrNull(folder)?.title ?? folder;
      for (final comic in manager.getFolderComics(folder)) {
        if (!_favKeys.add((comic.id, comic.type.value))) continue;
        out.add((
          _QuickHit(
            id: comic.id,
            sourceKey: comic.sourceKey,
            cover: comic.cover,
            // 与收藏网格同一套加载器：命中自有缩略图缓存，网络差也能出图。
            image: CachedImageProvider(
              comic.cover,
              sourceKey: comic.sourceKey,
              cid: comic.id,
              fallbackToLocalCover: true,
            ),
            title: comic.title,
            meta: folderName,
            hay: [
              comic.title,
              comic.author,
              comic.tags.join(' '),
              folderName,
            ].join(' '),
          ),
          comic.time,
        ));
      }
    }
    out.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in out) e.$1];
  }

  /// 历史：按最近阅读倒序；已经出现在收藏分组里的同一条目不再重复列出，
  /// 否则「收藏 + 刚读过」的书会占两行，看着像两份数据。
  ///
  /// 用 [HistoryManager.getAllBrief] 而不是 `getAll()`：后者会把每条记录的
  /// `readEpisode` 拆成 Set（连载几百话就是几百个字符串），上千条历史在打开
  /// 弹窗这一帧里光解析就要十几毫秒；速搜只要标题/封面/章节号。
  List<_QuickHit> _buildHistory() {
    final out = <_QuickHit>[];
    for (final h in HistoryManager().getAllBrief()) {
      if (_favKeys.contains((h.id, h.type.value))) continue;
      final chapter = h.ep >= 1 ? "Chapter @ep".tlParams({'ep': h.ep}) : '';
      final date =
          '${h.time.month.toString().padLeft(2, '0')}-'
          '${h.time.day.toString().padLeft(2, '0')}';
      out.add(
        _QuickHit(
          id: h.id,
          sourceKey: h.sourceKey,
          cover: h.cover,
          // 历史封面同样走缩略图缓存（HistoryImageProvider 在 cover 带路径时
          // 也是这条路径，这里不用为了它去重建一个完整 History 对象）。
          image: h.cover.isEmpty
              ? null
              : CachedImageProvider(h.cover, sourceKey: h.sourceKey, cid: h.id),
          title: h.title,
          meta: [chapter, date].where((e) => e.isNotEmpty).join(' · '),
          hay: '${h.title} ${h.subtitle}',
        ),
      );
    }
    return out;
  }

  /// 图片收藏：一条 = 一本漫画（与列表页的行一一对应），按收藏时间倒序。
  /// 缩略图用第一张收藏图；[ImageFavoritesProvider] 走自己的磁盘缓存，
  /// 没缓存 / 加载失败时结果行下面还有占位图标垫底，不会露出空白方块。
  List<_QuickHit> _buildImageFavorites() {
    final list = ImageFavoriteManager().getAll();
    list.sort((a, b) => b.time.compareTo(a.time));
    final out = <_QuickHit>[];
    for (final c in list) {
      final first = c.images.isEmpty ? null : c.images.first;
      final date =
          '${c.time.month.toString().padLeft(2, '0')}-'
          '${c.time.day.toString().padLeft(2, '0')}';
      out.add(
        _QuickHit(
          id: c.id,
          sourceKey: c.sourceKey,
          cover: '',
          image: first == null ? null : ImageFavoritesProvider(first),
          title: c.title,
          meta: [
            "@c images".tlParams({'c': c.images.length}),
            date,
          ].join(' · '),
          hay: [
            c.title,
            c.subTitle,
            c.author,
            c.tags.join(' '),
            c.translatedTags.join(' '),
          ].join(' '),
        ),
      );
    }
    return out;
  }

  /// 本地漫画：按导入时间倒序，封面直接读本地文件（不走网络）。
  /// 检索文本包含标题 / 副标题 / 标签 / 目录名，`src:` / `id:` 之类的旧前缀
  /// 语法不再需要 —— 空格分词 + 简繁互通对文件名更好用。
  List<_QuickHit> _buildLocal() {
    final list = LocalManager().getComics(LocalSortType.timeDesc);
    final out = <_QuickHit>[];
    for (final c in list) {
      final date =
          '${c.createdAt.month.toString().padLeft(2, '0')}-'
          '${c.createdAt.day.toString().padLeft(2, '0')}';
      out.add(
        _QuickHit(
          id: c.id,
          // 源被卸载/脚本损坏时 LocalComic.sourceKey 里的 `comicSource!` 会
          // 直接崩（本方法在 initState 里跑 → 速搜弹窗根本打不开）。
          sourceKey: c.comicType.comicSource?.key ?? "local",
          comicType: c.comicType,
          cover: c.cover,
          image: c.cover.isEmpty ? null : FileImage(c.coverFile),
          title: c.title,
          meta: [c.directory, date].where((e) => e.isNotEmpty).join(' · '),
          hay: [
            c.title,
            c.subtitle,
            c.tags.join(' '),
            c.directory,
          ].join(' '),
        ),
      );
    }
    return out;
  }

  /// 关键词拆词 + 繁简变体：与收藏页原来的搜索体验保持一致（空格分词、
  /// 忽略大小写、简繁互通）。
  ///
  /// 正则提成 static：每次敲键都要拆一次词，就地 `RegExp(...)` 会重复编译。
  static final _whitespace = RegExp(r'\s+');

  List<String> get _tokens => _query
      .trim()
      .toLowerCase()
      .split(_whitespace)
      .where((e) => e.isNotEmpty)
      .toList();

  List<String> _alts(List<String> tokens) {
    return [
      for (final t in tokens)
        if (OpenCC.hasChineseSimplified(t))
          OpenCC.simplifiedToTraditional(t).toLowerCase()
        else if (OpenCC.hasChineseTraditional(t))
          OpenCC.traditionalToSimplified(t).toLowerCase()
        else
          '',
    ];
  }

  List<_QuickHit> _filter(List<_QuickHit> source, List<String> tokens) {
    if (tokens.isEmpty) return const [];
    final alts = _alts(tokens);
    return source.where((h) {
      for (var i = 0; i < tokens.length; i++) {
        if (h.hayLower.contains(tokens[i])) continue;
        if (alts[i].isNotEmpty && h.hayLower.contains(alts[i])) continue;
        return false;
      }
      return true;
    }).toList();
  }

  /// 空关键词展示「最近」，打开弹窗就有东西可点，而不是一片空白。
  List<_Section> _sectionsFor(List<String> tokens) {
    final showingRecent = tokens.isEmpty;
    return [
      for (final s in _all)
        if (s.hits.isNotEmpty)
          _Section(
            s.label,
            showingRecent
                ? s.hits.take(3).toList()
                : _filter(s.hits, tokens),
          ),
    ].where((s) => s.hits.isNotEmpty).toList();
  }

  void _openHit(_QuickHit hit) {
    Navigator.of(context).pop();
    if (widget.scope == QuickSearchScope.local) {
      // 本地漫画不进网络详情页：直接接着上次进度打开阅读器，与网格点击一致。
      LocalManager()
          .find(hit.id, hit.comicType ?? ComicType.fromKey(hit.sourceKey))
          ?.read();
      return;
    }
    App.mainNavigatorKey?.currentContext?.to(
      () => ComicPage(
        id: hit.id,
        sourceKey: hit.sourceKey,
        cover: hit.cover,
        title: hit.title,
      ),
    );
  }

  void _openWebSearch() {
    final keyword = _query.trim();
    if (keyword.isEmpty) return;
    Navigator.of(context).pop();
    App.mainNavigatorKey?.currentContext?.to(
      () => SearchPage(initialKeyword: keyword),
    );
  }

  String get _hint => switch (widget.scope) {
    QuickSearchScope.library => "Search favorites & history".tl,
    QuickSearchScope.imageFavorites => "Search image favorites".tl,
    QuickSearchScope.local => "Search local comics".tl,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = (size.height - keyboard - 96).clamp(240.0, 560.0);
    final width = math.min(480.0, size.width - 32);

    final tokens = _tokens;
    final sections = _sectionsFor(tokens);
    final showingRecent = tokens.isEmpty;

    // 高度跟着结果走：只有一条结果时不该撑出一个空白大框，结果多到装不下
    // 才封顶到 [maxHeight] 并让列表自己滚。行高 / 分组标题高度在这里按渲染
    // 值写死（62 / 30），比"先渲一帧再量"简单，也不会和键盘弹出抢帧。
    const rowH = 62.0;
    const sectionH = 32.0;
    const inputH = 57.0;
    const webRowH = 47.0;
    final hitsHeight = 12.0 +
        sections.fold<double>(
          0,
          (sum, s) => sum + sectionH + s.hits.length * rowH,
        );
    final hasHits = sections.isNotEmpty;
    final height =
        (hitsHeight +
                inputH +
                kcHairline +
                (hasHits ? 0 : 140.0) +
                (showingRecent ? 0 : webRowH))
            .clamp(hasHits ? 160.0 : 220.0, maxHeight);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: kcSpaceLg, vertical: 48),
      backgroundColor: cs.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kcSurfaceRadius),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.5),
          width: kcHairline,
        ),
      ),
      // 结果条数变化时高度平滑过渡，不会每敲一个字就"啪"地跳一下。
      child: AnimatedSize(
        duration: kcReduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          height: height,
          child: Column(
            children: [
              _buildInput(cs),
              Divider(
                height: kcHairline,
                thickness: kcHairline,
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
              Expanded(child: _buildResults(cs, sections: sections)),
              if (!showingRecent) _buildWebRow(cs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kcSpaceLg, kcSpaceXs, kcSpaceSm, kcSpaceXs),
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedSearch02,
            size: 18,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: kcSubtitle, color: cs.onSurface),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: _hint,
                hintStyle: TextStyle(
                  fontSize: kcSubtitle,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: (v) {
                setState(() {
                  _query = v;
                });
              },
              onSubmitted: (_) {
                final tokens = _tokens;
                if (tokens.isEmpty) return;
                final sections = _sectionsFor(tokens);
                if (sections.isNotEmpty) {
                  _openHit(sections.first.hits.first);
                } else {
                  _openWebSearch();
                }
              },
            ),
          ),
          if (_query.isNotEmpty)
            IconButton(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 16),
              color: cs.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
              tooltip: "Cancel".tl,
              onPressed: () {
                _controller.clear();
                setState(() {
                  _query = '';
                });
                _focusNode.requestFocus();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildResults(
    ColorScheme cs, {
    required List<_Section> sections,
  }) {
    if (sections.isEmpty) {
      return _buildEmpty(cs);
    }
    // 扁平化成「分组标题 / 结果行」两种条目，走 builder 惰性构建：
    // 大库（上千条收藏）命中几百条时，ListView(children:) 会一次性
    // 建出所有行（每行还带一张封面 Image），开弹窗就能感到卡。
    final items = <Object>[
      for (final s in sections) ...[
        _Section(s.label, s.hits),
        ...s.hits,
      ],
    ];
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: kcSpaceMd),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        // 分组标记是 _Section，结果行是 _QuickHit，靠类型区分即可。
        return item is _Section
            ? _sectionHeader(cs, item.label, item.hits.length)
            : _row(cs, item as _QuickHit);
      },
    );
  }

  Widget _sectionHeader(ColorScheme cs, String label, int count) {
    // 与设置 / 详情 / 搜索结果页共用同一套分区标题，只保留「数量」作为尾部。
    return KcSectionHeader(
      title: label,
      padding: const EdgeInsets.fromLTRB(
        kcRowInsetH, kcSpaceMd, kcRowInsetH, kcSpaceXs,
      ),
      trailing: Text(
        '$count',
        style: TextStyle(
          fontSize: kcCaption,
          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _row(ColorScheme cs, _QuickHit hit) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return InkWell(
      onTap: () => _openHit(hit),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg, vertical: kcSpace6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(kcRadius8),
              child: Container(
                width: 38,
                height: 50,
                color: cs.surfaceContainerHighest,
                // 占位图标垫在图片下面：图还没到 / 加载失败时不会只剩一块灰，
                // 也不会因为 AnimatedImage 出错时不画东西而看起来像卡住了。
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedImage01,
                        size: 15,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                      ),
                    ),
                    // 38×50 的小缩略图按屏宽解码，别把整张封面原样读进内存。
                    if (hit.image != null)
                      AnimatedImage(
                        key: ValueKey(hit.image.hashCode),
                        image: hit.image!,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                        cacheWidth: (38 * dpr).ceil().clamp(24, 400),
                        cacheHeight: (50 * dpr).ceil().clamp(24, 400),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: kcBody,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  if (hit.meta.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        hit.meta,
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
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedSearch01,
              size: 28,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 10),
            Text(
              "No results".tl,
              style: TextStyle(fontSize: kcBody, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              "Try different keywords".tl,
              style: TextStyle(
                fontSize: kcCaption,
                color: cs.onSurfaceVariant.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebRow(ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          height: kcHairline,
          thickness: kcHairline,
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
        InkWell(
          onTap: _openWebSearch,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg, vertical: 13),
            child: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedGlobe02,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Search "@k" on the web'.tlParams({'k': _query.trim()}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: kcBody, color: cs.onSurface),
                  ),
                ),
                HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowRight01,
                  size: 14,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
