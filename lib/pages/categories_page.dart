import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/pages/ranking_page.dart';
import 'package:kong_comic/pages/settings/settings_page.dart';
import 'package:kong_comic/utils/ext.dart';
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
        AutomaticKeepAliveClientMixin<CategoriesPage> {
  var categories = <String>[];

  late TabController controller;

  void onSettingsChanged() {
    var categories = List.from(
      appdata.settings["categories"],
    ).whereType<String>().toList();
    var allCategories = ComicSource.enabled()
        .map((e) => e.categoryData?.key)
        .where((element) => element != null)
        .map((e) => e!)
        .toList();
    categories = categories
        .where((element) => allCategories.contains(element))
        .toList();
    _sortBySourceOrder(categories);
    if (!categories.isEqualTo(this.categories)) {
      setState(() {
        this.categories = categories;
      });
      controller = TabController(length: categories.length, vsync: this);
    }
  }

  /// Sorts category keys by their owning source's position in [sourceOrder],
  /// preserving relative order within the same source (stable sort).
  void _sortBySourceOrder(List<String> list) {
    final order = appdata.settings['sourceOrder'];
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

    list.sort((a, b) => orderOf(a).compareTo(orderOf(b)));
  }

  @override
  void initState() {
    super.initState();
    var categories = List.from(
      appdata.settings["categories"],
    ).whereType<String>().toList();
    var allCategories = ComicSource.enabled()
        .map((e) => e.categoryData?.key)
        .where((element) => element != null)
        .map((e) => e!)
        .toList();
    this.categories = categories
        .where((element) => allCategories.contains(element))
        .toList();
    _sortBySourceOrder(this.categories);
    appdata.settings.addListener(onSettingsChanged);
    controller = TabController(length: categories.length, vsync: this);
  }

  void addPage() {
    showPopUpWidget(App.rootContext, setCategoryPagesWidget());
  }

  @override
  void dispose() {
    super.dispose();
    controller.dispose();
    appdata.settings.removeListener(onSettingsChanged);
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
          AppTabBar(
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
          ).paddingTop(context.padding.top),
          Expanded(
            child: TabBarView(
              controller: controller,
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
    final sourceKey = findComicSourceKey();
    var children = <Widget>[];
    if (data.enableRankingPage || data.buttons.isNotEmpty) {
      children.add(buildTitle(data.title));
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
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
                  buildTags(part.categories, context),
                ],
              );
            },
          ),
        );
      } else {
        children.add(buildTitle(part.title));
        children.add(buildTags(part.categories, context));
      }
    }
    return SingleChildScrollView(
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

  Widget buildTags(List<CategoryItem> categories, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
      child: Wrap(
        children: List<Widget>.generate(
          categories.length,
          (index) => buildCategory(categories[index]),
        ),
      ),
    );
  }

  Widget buildCategory(CategoryItem c) {
    final sourceKey = findComicSourceKey();
    return buildTag(
      c.label,
      () {
        var context = App.mainNavigatorKey!.currentContext!;
        c.target.jump(context);
      },
      sourceKey: sourceKey,
    );
  }

  /// 基于标签名 + 所属漫画源生成 chip 底色；AMOLED 模式下用灰阶。
  /// 混入 sourceKey 的哈希后，同一漫画源下的不同标签颜色错开，
  /// 不同漫画源之间的整体色调也不会因标签名相同而撞车。
  static Color _colorForTag(
    String label,
    Brightness brightness,
    bool amoled, {
    String? sourceKey,
  }) {
    var hash = label.hashCode.abs() + (sourceKey?.hashCode ?? 0).abs();
    return kcTagColor(hash, brightness, amoled: amoled);
  }

  Widget buildTag(String label, VoidCallback onClick, {String? sourceKey}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Builder(
        builder: (context) {
          final brightness = Theme.of(context).brightness;
          final amoled = appdata.isAmoledMode;
          final bg = _colorForTag(label, brightness, amoled, sourceKey: sourceKey);
          return Material(
            borderRadius: BorderRadius.circular(kcRadius8),
            color: bg,
            child: InkWell(
              borderRadius: BorderRadius.circular(kcRadius8),
              onTap: onClick,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kcRadius8),
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
