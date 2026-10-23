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

/// 发现页「推荐」tab 整页：基于收藏偏好取一批（最多 9 本）展示。
///
/// 换一批有两个入口：**下拉**（主，任何滚动位置回到顶部即触发）与
/// 网格下方那颗「换一批」按钮（兜底，不知道下拉的人也能找到）。两者走同一条
/// [ExploreRecommendPageState.refresh]，把分类翻到下一页，到底再回到第一页。
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
  void refresh() {
    _load(next: true);
  }

  Future<void> _load({bool next = false}) async {
    final basis = _basis;
    if (basis == null) {
      if (mounted) {
        setState(() => _comics = const []);
      }
      return;
    }
    if (mounted) {
      setState(() => _loading = true);
    }
    var target = next ? _page + 1 : _page;
    var list = await loadRecommendComics(basis, limit: 9, page: target);
    if (!mounted) return;
    // 翻页到底（该分类没有更多）：回到第一页，保证永远有得看。
    if (next && list.isEmpty && target != 1) {
      target = 1;
      list = await loadRecommendComics(basis, limit: 9, page: 1);
      if (!mounted) return;
    }
    if (mounted) {
      setState(() {
        _page = target;
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
            onPressed: () => _load(next: true),
            icon: HugeIcon(
              // 交叉箭头 = 换一批；原来用的循环箭头（Refresh）会让人以为
              // 只是重新加载眼前这一批，而内容其实不会变。
              icon: HugeIcons.strokeRoundedShuffle,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
            label: Text(
              // 这个动作实际是「翻到下一页取另一批」，叫「刷新」会让人以为只是
              // 重拉同一批（那样内容根本不会变），文案必须和真实语义对齐。
              "Shuffle".tl,
              style: TextStyle(fontSize: kcBody, color: cs.onSurfaceVariant),
            ),
          );

    return RefreshIndicator(
      // 下拉 = 换一批。推荐页内容本来就一次一屏，下拉是这里最自然的手势：
      // 不用先滚到底去找按钮，也不占内容空间。
      onRefresh: () => _load(next: true),
      child: CustomScrollView(
        controller: scrollController,
        // 内容不足一屏（3 本以内、或空态）时也要能下拉，否则手势直接失效。
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (comics == null)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: AppLoadingIndicator(),
            )
          else if (comics.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedInbox,
                  size: 18,
                ),
                title: "No recommendations".tl,
                actionLabel: "Shuffle".tl,
                onAction: () => _load(next: true),
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
                // 底部必须让开「浮岛式底栏的实际遮挡高度」。
                // 原来写的是 `24 + 系统手势区`，比底栏真实占位（栏体 + 外边距 +
                // 手势区）小了一大截，于是这颗按钮一直藏在底栏下面——用户自然
                // 找不到换一批的入口。用 [NaviPane.bottomBarHeight] 才是同一套
                // 口径，和分类页/收藏页的列表底部一致。
                padding: EdgeInsets.fromLTRB(
                  kcSpaceLg,
                  12,
                  kcSpaceLg,
                  NaviPane.of(context).bottomBarHeight + kcSpaceSm,
                ),
                child: Center(child: refreshButton()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
