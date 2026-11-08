part of 'settings_page.dart';

class ExploreSettings extends StatefulWidget {
  const ExploreSettings({super.key});

  @override
  State<ExploreSettings> createState() => _ExploreSettingsState();
}

class _ExploreSettingsState extends State<ExploreSettings> {
  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Explore".tl)),
        // 三段：怎么显示 → 显示哪些页 / 搜哪些源 → 屏蔽什么。
        // 以前 15 项平铺，页面管理和关键词过滤夹在显示项中间，找「屏蔽词」
        // 得先滚过一堆开关。
        _SettingPartTitle(
          title: "Display".tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedGridView, size: 20),
        ),
        SelectSetting(
          title: "Display mode of comic tile".tl,
          settingKey: "comicDisplayMode",
          optionTranslation: {"detailed": "Detailed".tl, "brief": "Brief".tl},
        ).toSliver(),
        _SliderSetting(
          title: "Size of comic tile".tl,
          settingsIndex: "comicTileScale",
          interval: 0.05,
          min: 0.5,
          max: 1.5,
        ).toSliver(),
        _SwitchSetting(
          title: "Show recommendations on explore".tl,
          settingKey: "showRecommendOnExplore",
        ).toSliver(),
        _SwitchSetting(
          title: "Show favorite status on comic tile".tl,
          settingKey: "showFavoriteStatusOnTile",
        ).toSliver(),
        _SwitchSetting(
          title: "Show history on comic tile".tl,
          settingKey: "showHistoryStatusOnTile",
        ).toSliver(),
        SelectSetting(
          title: "Load mode of comic list".tl,
          settingKey: "comicListDisplayMode",
          optionTranslation: {
            "paging": "Paging".tl,
            "continuous": "Continuous".tl,
          },
        ).toSliver(),
        // 主页轮播来源（来自本地收藏文件夹）
        _HomeBannerFoldersSetting().toSliver(),
        _SettingPartTitle(
          title: "Pages & search".tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedGlobe02, size: 20),
        ),
        _PopupWindowSetting(
          title: "Explore Pages".tl,
          builder: setExplorePagesWidget,
        ).toSliver(),
        _PopupWindowSetting(
          title: "Category Pages".tl,
          builder: setCategoryPagesWidget,
        ).toSliver(),
        _PopupWindowSetting(
          title: "Network Favorite Pages".tl,
          builder: setFavoritesPagesWidget,
        ).toSliver(),
        _PopupWindowSetting(
          title: "Search Sources".tl,
          builder: setSearchSourcesWidget,
        ).toSliver(),
        SelectSetting(
          title: "Default Search Target".tl,
          settingKey: "defaultSearchTarget",
          optionTranslation: {
            '_aggregated_': "Aggregated".tl,
            ...(() {
              var map = <String, String>{};
              for (var c in ComicSource.all()) {
                map[c.key] = c.name;
              }
              return map;
            }()),
          },
        ).toSliver(),
        SelectSetting(
          title: "Auto Language Filters".tl,
          settingKey: "autoAddLanguageFilter",
          optionTranslation: {
            'none': "None".tl,
            'chinese': "Chinese",
            'english': "English",
            'japanese': "Japanese",
          },
        ).toSliver(),
        _SettingPartTitle(
          title: "Content filtering".tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedFilter, size: 20),
        ),
        _PopupWindowSetting(
          title: "Keyword blocking".tl,
          builder: () => const _ManageBlockingWordView(),
        ).toSliver(),
        _PopupWindowSetting(
          title: "Comment keyword blocking".tl,
          builder: () => const _ManageBlockingCommentWordView(),
        ).toSliver(),
      ],
    );
  }
}

/// 取一个「字符串列表」型设置项；坏数据（null / 非 List，多来自旧版本或导入
/// 的备份）就地修成空列表并写回，避免 build 里 `.length` 直接抛异常。
List<dynamic> _listSetting(String key) {
  final raw = appdata.settings[key];
  if (raw is List) return raw;
  final fixed = <dynamic>[];
  appdata.settings[key] = fixed;
  return fixed;
}

class _ManageBlockingWordView extends StatefulWidget {
  const _ManageBlockingWordView();

  @override
  State<_ManageBlockingWordView> createState() =>
      _ManageBlockingWordViewState();
}

class _ManageBlockingWordViewState extends State<_ManageBlockingWordView> {
  @override
  Widget build(BuildContext context) {
    // 以前这行是 `assert(appdata.settings["blockedWords"] is List)`：assert 在
    // release 会被剥离，值被导入/同步写成 null 或非 List 时，下面的 `.length`
    // 就是 NoSuchMethodError —— 发生在 build 里，整个页面红屏且没有恢复入口。
    // 这里就地修成空列表，并把修好的值写回 settings。
    final words = _listSetting("blockedWords");
    return PopUpWidgetScaffold(
      title: "Keyword blocking".tl,
      tailing: [
        Button.text(
          onPressed: add,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedAddCircle, size: 18),
              const SizedBox(width: 6),
              Text("Add".tl),
            ],
          ),
        ),
      ],
      body: ListView.builder(
        itemCount: words.length,
        itemBuilder: (context, index) {
          return KcListTile(
            showDivider: index < words.length - 1,
            title: Text('${words[index]}'),
            trailing: IconButton(
              tooltip: "Delete".tl,
              icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
              onPressed: () {
                words.removeAt(index);
                appdata.saveData();
                setState(() {});
              },
            ),
          );
        },
      ),
    );
  }

  void add() {
    final controller = TextEditingController();
    showDialog(
      context: App.rootContext,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setState) {
            return ContentDialog(
              title: "Add keyword".tl,
              content: TextField(
                controller: controller,
                decoration: kcInputDecoration(
                  context,
                  labelText: "Keyword".tl,
                  errorText: error,
                ),
                onChanged: (s) {
                  if (error != null) {
                    setState(() {
                      error = null;
                    });
                  }
                },
              ).paddingHorizontal(12),
              actions: [
                Button.filled(
                  onPressed: () {
                    // 必须先拦住空串：isBlocked 用 `title.contains(word)` 判定，
                    // 而任何字符串都 contains("")==true —— 一旦存进空关键词，
                    // 全站漫画列表会被判定成「全部命中屏蔽词」而瞬间清空，
                    // 用户也想不到是刚才那个没填字的输入框干的。
                    final text = controller.text.trim();
                    if (text.isEmpty) {
                      setState(() {
                        error = "Keyword cannot be empty".tl;
                      });
                      return;
                    }
                    final words = _listSetting("blockedWords");
                    if (words.contains(text)) {
                      setState(() {
                        error = "Keyword already exists".tl;
                      });
                      return;
                    }
                    words.add(text);
                    appdata.saveData();
                    this.setState(() {});
                    context.pop();
                  },
                  child: Text("Add".tl),
                ),
              ],
            );
          },
        );
      },
      // Covers every dismissal path: button, back gesture and barrier tap.
    ).then((_) => controller.dispose());
  }
}

Widget setExplorePagesWidget() {
  var pages = <String, String>{};
  for (var c in ComicSource.all()) {
    for (var page in c.explorePages) {
      pages[page.title] = page.title.ts(c.key);
    }
  }
  return _MultiPagesFilter(
    title: "Explore Pages".tl,
    settingsIndex: "explore_pages",
    pages: pages,
  );
}

Widget setCategoryPagesWidget() {
  var pages = <String, String>{};
  for (var c in ComicSource.all()) {
    if (c.categoryData != null) {
      pages[c.categoryData!.key] = c.categoryData!.title;
    }
  }
  return _MultiPagesFilter(
    title: "Category Pages".tl,
    settingsIndex: "categories",
    pages: pages,
  );
}

Widget setFavoritesPagesWidget() {
  var pages = <String, String>{};
  for (var c in ComicSource.all()) {
    if (c.favoriteData != null) {
      pages[c.favoriteData!.key] = c.favoriteData!.title;
    }
  }
  return _MultiPagesFilter(
    title: "Network Favorite Pages".tl,
    settingsIndex: "favorites",
    pages: pages,
  );
}

Widget setSearchSourcesWidget() {
  var pages = <String, String>{};
  for (var c in ComicSource.all()) {
    if (c.searchPageData != null) {
      pages[c.key] = c.name;
    }
  }
  return _MultiPagesFilter(
    title: "Search Sources".tl,
    settingsIndex: "searchSources",
    pages: pages,
  );
}

class _ManageBlockingCommentWordView extends StatefulWidget {
  const _ManageBlockingCommentWordView();

  @override
  State<_ManageBlockingCommentWordView> createState() =>
      _ManageBlockingCommentWordViewState();
}

class _ManageBlockingCommentWordViewState
    extends State<_ManageBlockingCommentWordView> {
  @override
  Widget build(BuildContext context) {
    // 同关键词屏蔽：assert 在 release 会被剥离，坏值直接让本页红屏。
    final words = _listSetting("blockedCommentWords");
    return PopUpWidgetScaffold(
      title: "Comment keyword blocking".tl,
      tailing: [
        Button.text(
          onPressed: add,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedAddCircle, size: 18),
              const SizedBox(width: 6),
              Text("Add".tl),
            ],
          ),
        ),
      ],
      body: ListView.builder(
        itemCount: words.length,
        itemBuilder: (context, index) {
          return KcListTile(
            showDivider: index < words.length - 1,
            title: Text('${words[index]}'),
            trailing: IconButton(
              tooltip: "Delete".tl,
              icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
              onPressed: () {
                words.removeAt(index);
                appdata.saveData();
                setState(() {});
              },
            ),
          );
        },
      ),
    );
  }

  void add() {
    final controller = TextEditingController();
    showDialog(
      context: App.rootContext,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setState) {
            return ContentDialog(
              title: "Add keyword".tl,
              content: TextField(
                controller: controller,
                decoration: kcInputDecoration(
                  context,
                  labelText: "Keyword".tl,
                  errorText: error,
                ),
                onChanged: (s) {
                  if (error != null) {
                    setState(() {
                      error = null;
                    });
                  }
                },
              ).paddingHorizontal(12),
              actions: [
                Button.filled(
                  onPressed: () {
                    // 同关键词屏蔽：空串会让 `content.contains("")` 恒真，
                    // 评论区会被整片隐藏。
                    final text = controller.text.trim();
                    if (text.isEmpty) {
                      setState(() {
                        error = "Keyword cannot be empty".tl;
                      });
                      return;
                    }
                    final words = _listSetting("blockedCommentWords");
                    if (words.contains(text)) {
                      setState(() {
                        error = "Keyword already exists".tl;
                      });
                      return;
                    }
                    words.add(text);
                    appdata.saveData();
                    this.setState(() {});
                    context.pop();
                  },
                  child: Text("Add".tl),
                ),
              ],
            );
          },
        );
      },
      // Covers every dismissal path: button, back gesture and barrier tap.
    ).then((_) => controller.dispose());
  }
}
