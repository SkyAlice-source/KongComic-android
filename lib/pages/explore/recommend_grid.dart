import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/global_state.dart';
import 'package:kong_comic/pages/comic_details_page/comic_page.dart';
import 'package:kong_comic/pages/favorites/recommend_basis.dart';
import 'package:kong_comic/utils/translations.dart';

/// 「推荐」在发现页 tab 栏中的占位 key（真实探索页 tab 用页面标题作 key，
/// 不会与此冲突）。
const String kRecommendTabKey = '__recommend__';

/// 发现页「推荐」tab 整页：基于收藏偏好取数，3×3 展示，右下角可刷新。
///
/// 仅在确有推荐依据（收藏里有可作推荐依据的网络漫画）时才会作为第一个 tab
/// 出现；是否显示由「设置 → 探索 → Show recommendations on explore」控制。
class ExploreRecommendPage extends StatefulWidget {
  const ExploreRecommendPage({super.key});

  @override
  State<ExploreRecommendPage> createState() => ExploreRecommendPageState();
}

class ExploreRecommendPageState
    extends AutomaticGlobalState<ExploreRecommendPage> {
  final RecommendBasis? _basis = computeRecommendBasis();
  List<Comic>? _comics; // null = 加载中
  int _page = 1;
  bool _loading = false;

  var scrollController = ScrollController();

  @override
  Object? get key => kRecommendTabKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  void toTop() {
    if (scrollController.hasClients) {
      scrollController.animateTo(
        scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  /// 换一批：翻到推荐依据分类的下一页；到底后回到第一页，保证永远有得看。
  @override
  void refresh() => _load(refresh: true);

  Future<void> _load({bool refresh = false}) async {
    final basis = _basis;
    if (basis == null) {
      if (mounted) {
        setState(() => _comics = const []);
      }
      return;
    }
    if (refresh) _page += 1;
    if (mounted) {
      setState(() => _loading = true);
    }
    var list = await loadRecommendComics(basis, limit: 9, page: _page);
    if (!mounted) return;
    // 翻页到底（该分类没有更多）：刷新按钮回到第一页，保证永远有得看。
    if (refresh && list.isEmpty) {
      _page = 1;
      list = await loadRecommendComics(basis, limit: 9, page: 1);
      if (!mounted) return;
    }
    if (mounted) {
      setState(() {
        _comics = list;
        _loading = false;
      });
    }
  }

  void _openComic(Comic c) {
    App.mainNavigatorKey?.currentContext?.to(
      () => ComicPage(
        id: c.id,
        sourceKey: c.sourceKey,
        cover: c.cover,
        title: c.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final basis = _basis;
    if (basis == null) {
      return Center(
        child: Text(
          "No recommendations".tl,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    final comics = _comics;
    final cs = Theme.of(context).colorScheme;

    final width = MediaQuery.of(context).size.width;
    const pad = kcSpaceLg;
    const gap = 12.0;
    final cardW = (width - pad * 2 - gap * 2) / 3;
    final coverH = cardW / 0.7;
    // 格子高度要和 ComicTile（brief 模式、标题在封面下方）的真实开销对齐：
    // 标题块（上内边距 4 + 行高，随字号档位与系统字号缩放变化）＋ ComicTile
    // 自带的上下各 8 内边距。原先把高度写死成「封面 + 22」，只够标题、没算
    // 内边距，封面被压短、四周露出卡片底色，看着像「越界」。
    final titleFont = cardW < 120
        ? kcCaption
        : cardW < 150
            ? kcBody
            : kcFont15;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final titleBlock = 4 + titleFont * 1.2 * textScale;
    final cellH = coverH + titleBlock + 16; // 封面 + 标题块 + 上下内边距
    final childAspect = cardW / cellH;

    return SingleChildScrollView(
      controller: scrollController,
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, 12, pad, pad + MediaQuery.of(context).padding.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Recommended".tl,
                    style: const TextStyle(
                      fontSize: kcSectionTitle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    "Because you like @tag".tlParams({'tag': basis.tag}),
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
            const SizedBox(height: 10),
            if (comics == null)
              SizedBox(
                height: cellH * 3 + gap * 2,
                child: const Center(child: CircularProgressIndicator()),
              )
            else if (comics.isEmpty)
              SizedBox(
                height: 72,
                child: Center(
                  child: Text(
                    "No recommendations".tl,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              )
            else
              GridView.count(
                crossAxisCount: 3,
                childAspectRatio: childAspect,
                crossAxisSpacing: gap,
                mainAxisSpacing: gap,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final c in comics)
                    ComicTile(
                      comic: c,
                      showSourceOnCover: false,
                      showBottomSourceDate: false,
                      onTap: () => _openComic(c),
                    ),
                ],
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Spacer(),
                _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedRefresh,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                        tooltip: "Refresh".tl,
                        onPressed: () => _load(refresh: true),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
