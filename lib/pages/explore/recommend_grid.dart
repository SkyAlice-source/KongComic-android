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
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final comics = _comics;
    final cs = Theme.of(context).colorScheme;

    // 「换一批」：加载中转圈，否则是可点的图标 + 文字。做成方法是因为空状态
    // 与网格状态都要用，且空状态要跟着提示一起居中。
    Widget refreshButton() => _loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : TextButton.icon(
            // 空结果也给「换一批」：源偶尔超时/限流时，整页只剩一句
            // 「暂无推荐」，用户没有重新拉取的入口。
            onPressed: () => _load(refresh: true),
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedRefresh,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
            label: Text(
              "Refresh".tl,
              style: TextStyle(fontSize: kcBody, color: cs.onSurfaceVariant),
            ),
          );

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        if (comics == null)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (comics.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "No recommendations".tl,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  refreshButton(),
                ],
              ),
            ),
          )
        else ...[
          // 与漫画源列表用同一个网格组件（内部是 SliverGridDelegateWithComics）：
          // 列数、宽高比、间距、字号档位全部跟随「格子大小」设置。之前这里手算
          // 3 列 + 固定 12 间距，结果推荐页的卡片比别的源明显大一圈，看着像另一套。
          SliverGridComics(
            comics: comics,
            showSourceOnCover: false,
            onTap: (c, _) => _openComic(c),
          ),
          SliverToBoxAdapter(
            child: Padding(
              // 底部留出浮岛式底栏与手势条：这里没有 SliverListLoadingIndicator
              // 兜底，不自己让位就会被底栏压住。
              padding: EdgeInsets.fromLTRB(
                kcSpaceLg,
                12,
                kcSpaceLg,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              child: Center(child: refreshButton()),
            ),
          ),
        ],
      ],
    );
  }
}
