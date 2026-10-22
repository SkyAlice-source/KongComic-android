import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/pages/ranking_page.dart';
import 'package:kong_comic/pages/settings/settings_page.dart';
import 'package:kong_comic/utils/ext.dart';
import 'package:kong_comic/foundation/listen_mixin.dart';
import 'package:kong_comic/utils/translations.dart';

import 'comic_source_page.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage>
    with
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin<CategoriesPage>,
        AutoListenMixin {
  var categories = <String>[];

  late TabController controller;

  /// 重算「要显示哪些分类页」。
  ///
  /// 两个来源会改变这份列表：`appdata.settings['categories']` 里用户的配置，
  /// 以及**已启用源**的集合。后者以前没人监听 —— 用户在源设置里禁用/删除一个
  /// 源之后，`categories` 仍留着它的 key，而 [_CategoryPage] 的
  /// `getCategoryDataWithKey` 找不到就 `throw`，整页红屏。现在连同
  /// [ComicSourceManager] 一起听。
  void _reloadCategories({required bool notify}) {
    var categories = List.from(
      appdata.settings["categories"],
    ).whereType<String>().toList();
    final allCategories = ComicSource.enabled()
        .map((e) => e.categoryData?.key)
        .whereType<String>()
        .toSet();
    categories = categories
        .where((element) => allCategories.contains(element))
        .toList();
    _sortBySourceOrder(categories);
    if (categories.isEqualTo(this.categories)) return;

    if (notify) {
      setState(() {
        this.categories = categories;
      });
    } else {
      this.categories = categories;
    }
    // Dispose the previous one, otherwise every change leaks the
    // AnimationController + Ticker that TabController owns internally.
    // 长度变了必须换一个：TabBarView 与 AppTabBar 都按 controller.length 断言。
    controller.dispose();
    controller = TabController(length: categories.length, vsync: this);
  }

  /// Sorts category keys by their owning source's position in [sourceOrder],
  /// preserving relative order within the same source.
  ///
  /// Dart 的 `List.sort` **不是稳定排序**（introsort），所以「同源分类保持
  /// 声明顺序」不能靠运气：显式用原始下标做第二比较键，否则多个同类源之间
  /// 的分类顺序会在每次启动时重新洗牌（源里声明顺序通常有意义，比如「每日
  /// 更新」应排在「完结」前面）。
  void _sortBySourceOrder(List<String> list) {
    final order = appdata.settings['sourceOrder'];
    final originalIndex = <String, int>{};
    for (var i = 0; i < list.length; i++) {
      originalIndex.putIfAbsent(list[i], () => i);
    }

    int orderOf(String key) {
      for (var s in ComicSource.enabled()) {
        if (s.categoryData?.key == key) {
          if (order is List) {
            final i = order.indexOf(s.key);
            if (i != -1) return i;
          }
          return 1 << 30;
        }
      }
      return 1 << 30;
    }

    list.sort((a, b) {
      final bySource = orderOf(a).compareTo(orderOf(b));
      if (bySource != 0) return bySource;
      return (originalIndex[a] ?? 0).compareTo(originalIndex[b] ?? 0);
    });
  }

  @override
  void initState() {
    super.initState();
    // 先建一个空 controller：[_reloadCategories] 会 dispose 掉它并按实际数量
    // 重建（它自己也可能是「无变化直接 return」，那时留空更安全）。
    controller = TabController(length: 0, vsync: this);
    _reloadCategories(notify: false);
    listen(appdata.settings, _onSourcesChanged);
    // 源被启用 / 禁用 / 排序变化时，分类页的 key 集合会变，必须跟着重算。
    listen(ComicSourceManager(), _onSourcesChanged);
  }

  void _onSourcesChanged() {
    if (mounted) _reloadCategories(notify: true);
  }

  void addPage() {
    showPopUpWidget(App.rootContext, setCategoryPagesWidget());
  }

  @override
  void dispose() {
    // 先释放自持资源，再 super.dispose()（AutoListenMixin 的自动注销在 super 里）。
    controller.dispose();
    super.dispose();
  }

  Widget buildEmpty() {
    if (ComicSource.isEmpty) {
      return EmptyState(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedGrid, size: 18),
        title: "No Category Pages".tl,
        subtitle: "Please add some comic sources first".tl,
        actionLabel: "Manage".tl,
        onAction: () => context.to(() => const ComicSourcePage()),
      );
    }
    return EmptyState(
      icon: HugeIcon(icon: HugeIcons.strokeRoundedInbox, size: 18),
      title: "No Category Pages".tl,
      subtitle: "Please check your source settings".tl,
      actionLabel: "Manage".tl,
      onAction: addPage,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (categories.isEmpty) {
      return buildEmpty();
    }

    return Material(
      child: Column(
        children: [
          // 标签栏整条从系统返回手势里让开：否则从屏幕最左边起手横滑标签，
          // 会被系统判成「返回」并弹出确认退出（Flutter 侧拦不住，见
          // [SystemGestureExclusion]）。压到子页面下面时立刻撤销，让子页的
          // 边缘侧滑返回照常工作。
          SystemGestureExclusion(
            enabled: NaviPane.of(context).isRootTabPage,
            child: AppTabBar(
              controller: controller,
              key: PageStorageKey(categories.toString()),
              tabs: categories.map((e) {
                String title = e;
                try {
                  title = getCategoryDataWithKey(e).title;
                } catch (e) {
                  //
                }
                // 与页面内标题一致，统一走 .tl 翻译
                return Tab(text: title.tl, key: Key(e));
              }).toList(),
              actionButton: TabActionButton(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedAddCircle, size: 18),
                text: "Add".tl,
                onPressed: addPage,
              ),
            ),
          ).paddingTop(context.padding.top),
          Expanded(
            // 关闭手指横滑，只保留点 Tab 切换。
            //
            // 分类页是**根 tab 页**：屏幕最左/最右侧约 20dp 是系统返回手势的
            // 保留区，从那里起手横滑会被系统吃掉 —— 于是「想切分类」变成
            // 「弹出确认退出」。这个冲突在 Flutter 侧无法拦截（系统手势在
            // 原生层先于触摸事件分发），唯一的原生 API
            // `setSystemGestureExclusionRects` 又限制排除区总高 200dp，盖不住
            // 整块内容区。
            //
            // Material 3 也不给底部标签页之间定义横滑关系（横滑只用于同一页
            // 内的顶部 Tab）。所以这里按规范关掉拖拽：TabController 点选仍会
            // 驱动 PageView 做水平过渡动画，视觉上依旧是「切过去」，只是不再
            // 和系统返回抢同一个手势。
            child: TabBarView(
              controller: controller,
              physics: const NeverScrollableScrollPhysics(),
              children: categories.map((e) => _CategoryPage(e)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

typedef ClickTagCallback = void Function(String, String?);

class _CategoryPage extends StatelessWidget {
  const _CategoryPage(this.category);

  final String category;

  CategoryData get data => getCategoryDataWithKey(category);

  String findComicSourceKey() {
    for (var source in ComicSource.enabled()) {
      if (source.categoryData?.key == category) {
        return source.key;
      }
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    // 缓存一次：`data` 是个 getter，每次访问都会重新遍历已启用的源去查
    // CategoryData，而下面会用到它十几次。
    final data = this.data;
    final sourceKey = findComicSourceKey();
    var children = <Widget>[];
    if (data.enableRankingPage || data.buttons.isNotEmpty) {
      // 这里**不再**重复画一遍分类标题：顶部 TabBar 上写的就是同一个
      // `data.title`，两行同名文字只隔 40dp，看起来像渲染重影。工具行直接
      // 当页首，靠自身的内边距和上方 TabBar 拉开呼吸感。
      children.add(
        Padding(
          // 6 + chip 的 10 = 16，与下面的分组标题同一条轴线。
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 12),
          child: Wrap(
            children: [
              if (data.enableRankingPage)
                buildTag(
                  "Ranking".tl,
                  () {
                    context.to(() => RankingPage(categoryKey: data.key));
                  },
                  sourceKey: sourceKey,
                ),
              for (var buttonData in data.buttons)
                buildTag(
                  buttonData.label.tl,
                  buttonData.onTap,
                  sourceKey: sourceKey,
                ),
            ],
          ),
        ),
      );
    }

    for (var part in data.categories) {
      if (part.enableRandom) {
        children.add(
          StatefulBuilder(
            builder: (context, updater) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildTitleWithRefresh(part.title, () {
                    // 只在此处重新随机，其他 rebuild 保持缓存结果稳定
                    (part as RandomCategoryPart).refresh();
                    updater(() {});
                  }),
                  buildTags(part.categories, sourceKey: sourceKey),
                ],
              );
            },
          ),
        );
      } else {
        children.add(buildTitle(part.title));
        children.add(buildTags(part.categories, sourceKey: sourceKey));
      }
    }
    return SingleChildScrollView(
      // 记住每个分类各自的滚动位置：之前切走再切回来，页面总是被重置到最
      // 顶部 —— 分类多的时候等于每次都要重新往下找。
      key: PageStorageKey('category_scroll_$category'),
      padding: EdgeInsets.only(bottom: NaviPane.of(context).bottomBarHeight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget buildTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 5, 10),
      child: Text(
        title.tl,
        style: const TextStyle(fontSize: kcTitleLarge, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget buildTitleWithRefresh(String title, void Function() onRefresh) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 5, 10),
      child: Row(
        children: [
          Text(
            title.tl,
            style: const TextStyle(fontSize: kcTitleLarge, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(
            tooltip: "Refresh".tl,
            onPressed: onRefresh,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
          ),
        ],
      ),
    );
  }

  Widget buildTags(List<CategoryItem> categories, {required String sourceKey}) {
    return Padding(
      // 6 + chip 自身的 10 = 16：与 [buildTitle] 的左内边距对齐，否则每组
      // 胶囊比它上面的标题整体右移 4dp，整列看起来是歪的。
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 16),
      child: Wrap(
        children: List<Widget>.generate(
          categories.length,
          (index) => buildCategory(categories[index], sourceKey),
        ),
      ),
    );
  }

  Widget buildCategory(CategoryItem c, String sourceKey) {
    return buildTag(
      c.label.ts(sourceKey),
      () {
        // 分类项可能被点击时 App 已重建过 navigator：用 `?.` + 判空，别用
        // `!` —— 这里崩过（currentContext 在路由切换的那一帧为 null）。
        final navContext = App.mainNavigatorKey?.currentContext;
        if (navContext == null) return;
        c.target.jump(navContext);
      },
      sourceKey: sourceKey,
    );
  }

  /// 基于标签名生成 chip 底色（稳定哈希）；AMOLED 模式下用灰阶。
  /// 统一用「标签文本」取色：同一标签在全站都是同一颜色，且跨启动恒定
  /// （不再混入 sourceKey、也不用会随机化的 Dart String.hashCode）。
  static Color _colorForTag(
    String label,
    Brightness brightness,
    bool amoled, {
    String? sourceKey,
  }) {
    return kcTagColor(kcStableHash(label), brightness, amoled: amoled);
  }

  Widget buildTag(String label, VoidCallback onClick, {String? sourceKey}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Builder(
        builder: (context) {
          final brightness = Theme.of(context).brightness;
          final amoled = appdata.isAmoledMode;
          final bg = _colorForTag(label, brightness, amoled, sourceKey: sourceKey);
          return Material(
            borderRadius: BorderRadius.circular(kcRadius10),
            color: bg,
            child: InkWell(
              borderRadius: BorderRadius.circular(kcRadius10),
              onTap: onClick,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kcRadius10),
                  border: Border.all(
                    color: bg.withValues(alpha: 0.35),
                    width: 0.5,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: kcBody,
                    color: kcTagTextColor(bg),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
