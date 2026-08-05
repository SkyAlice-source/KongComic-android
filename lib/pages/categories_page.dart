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
    var allCategories = ComicSource.all()
        .map((e) => e.categoryData?.key)
        .where((element) => element != null)
        .map((e) => e!)
        .toList();
    categories = categories
        .where((element) => allCategories.contains(element))
        .toList();
    if (!categories.isEqualTo(this.categories)) {
      setState(() {
        this.categories = categories;
      });
      controller = TabController(length: categories.length, vsync: this);
    }
  }

  @override
  void initState() {
    super.initState();
    var categories = List.from(
      appdata.settings["categories"],
    ).whereType<String>().toList();
    var allCategories = ComicSource.all()
        .map((e) => e.categoryData?.key)
        .where((element) => element != null)
        .map((e) => e!)
        .toList();
    this.categories = categories
        .where((element) => allCategories.contains(element))
        .toList();
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
              return Tab(text: title, key: Key(e));
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
    for (var source in ComicSource.all()) {
      if (source.categoryData?.key == category) {
        return source.key;
      }
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    var children = <Widget>[];
    if (data.enableRankingPage || data.buttons.isNotEmpty) {
      children.add(buildTitle(data.title));
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
          child: Wrap(
            children: [
              if (data.enableRankingPage)
                buildTag("Ranking".tl, () {
                  context.to(() => RankingPage(categoryKey: data.key));
                }),
              for (var buttonData in data.buttons)
                buildTag(buttonData.label.tl, buttonData.onTap),
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
                  buildTitleWithRefresh(part.title, () => updater(() {})),
                  buildTags(part.categories),
                ],
              );
            },
          ),
        );
      } else {
        children.add(buildTitle(part.title));
        children.add(buildTags(part.categories));
      }
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget buildTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 5, 10),
      child: Text(
        title.tl,
        style: const TextStyle(fontSize: kcTitleLarge, fontWeight: FontWeight.w500),
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
            style: const TextStyle(fontSize: kcTitleLarge, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          IconButton(onPressed: onRefresh, icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18)),
        ],
      ),
    );
  }

  Widget buildTags(List<CategoryItem> categories) {
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
    return buildTag(c.label, () {
      var context = App.mainNavigatorKey!.currentContext!;
      c.target.jump(context);
    });
  }

  /// 基于标签名哈希生成柔和彩色，饱和度适中确保浅色底可读
  static final List<Color> _tagPalette = [
    const Color(0xFFBBDEFB), // 蓝 (更饱和)
    const Color(0xFFF8BBD0), // 粉
    const Color(0xFFC8E6C9), // 绿
    const Color(0xFFFFCC80), // 橙
    const Color(0xFFE1BEE7), // 紫
    const Color(0xFF80DEEA), // 青
    const Color(0xFFFFAB91), // 珊瑚/红
    const Color(0xFFDCEDC8), // 浅绿
    const Color(0xFFFFE082), // 黄
    const Color(0xFFD1C4E9), // 深紫
    const Color(0xFFB2DFDB), // 蓝灰
    const Color(0xFFFFCDD2), // 暖红
  ];

  static Color _colorForTag(String label) {
    var hash = label.hashCode.abs();
    return _tagPalette[hash % _tagPalette.length];
  }

  Widget buildTag(String label, VoidCallback onClick) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Builder(
        builder: (context) {
          return Material(
            borderRadius: BorderRadius.circular(kcRadius8),
            color: _colorForTag(label),
            child: InkWell(
              borderRadius: BorderRadius.circular(kcRadius8),
              onTap: onClick,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kcRadius8),
                  border: Border.all(
                    color: _colorForTag(label).withValues(alpha: 0.35),
                    width: 0.5,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: kcBody,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool get enableTranslation => App.locale.languageCode == 'zh';
}
