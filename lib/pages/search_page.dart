import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sliver_tools/sliver_tools.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/components/quick_search.dart';
import 'package:kong_comic/foundation/listen_mixin.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/colors.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/global_state.dart';
import 'package:kong_comic/pages/aggregated_search_page.dart';
import 'package:kong_comic/pages/search_result_page.dart';
import 'package:kong_comic/pages/settings/settings_page.dart';
import 'package:kong_comic/utils/app_links.dart';
import 'package:kong_comic/utils/ext.dart';
import 'package:kong_comic/utils/tags_translation.dart';
import 'package:kong_comic/utils/translations.dart';

import 'comic_details_page/comic_page.dart';
import 'comic_source_page.dart';

/// 页面统一横向栅格。
///
/// 直接用设置页那套 [kcRowInsetH]（20），不再自造 16：本页此前是 12（源胶囊）
/// / 14（本地入口）/ 16（区块标题）/ 38（搜索框）四套内缩混用，整页看着像被
/// 随手推了一把。收口成同一条竖线之后，搜索框、源胶囊、区块标题、入口行、
/// 检索选项的左边线全部落在 20 上，与设置页逐像素对齐。
const double _gutter = kcRowInsetH;

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.initialKeyword});

  /// 带词进入：速搜弹窗的「在网络上搜索」把本地搜到的关键词直接带过来，
  /// 落地即出结果，用户不用把同一个词再敲一遍。
  final String? initialKeyword;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with AutoListenMixin {
  late final SearchBarController controller;

  late List<String> searchSources;

  Set<String> _selectedSources = {};
  final _searchTextController = TextEditingController();
  Timer? _debounceTimer;

  bool get _isAggregated => _selectedSources.length > 1;

  SearchPageData get currentSearchPageData =>
      ComicSource.find(_selectedSources.first)!.searchPageData!;

  var focusNode = FocusNode();

  var options = <String>[];

  void update() {
    setState(() {});
  }

  /// [allowIdJump] 为 false 时跳过「ID 直接跳转」。
  ///
  /// 速搜浮层的「在网络上搜索」必须跳过：用户从本地库带过来的是一个**书名**，
  /// 不是要打开某个源的作品 ID；而源配置里的 idMatcher 普遍写得很宽（有的就是
  /// 一串字母），普通英文书名（实测 "catch"）会被误判成 ID，直接跳进一个解析
  /// 失败的详情页。手动输入时保留原来的 ID 直达，行为不变。
  void search([String? text, bool allowIdJump = true]) {
    final keyword = text ?? _searchTextController.text;

    // ID 直接跳转：仅当唯一匹配时直接跳转，多源匹配时由建议列表选择
    if (allowIdJump) {
      var matchedSources = <ComicSource>[];
      for (var source in ComicSource.enabled()) {
        if (source.idMatcher?.hasMatch(keyword) ?? false) {
          matchedSources.add(source);
        }
      }

      if (matchedSources.length == 1) {
        context.to(() => ComicPage(
          sourceKey: matchedSources.first.key,
          id: keyword,
        )).then((_) => update());
        return;
      }

      if (matchedSources.length > 1) {
        _showSourcePicker(matchedSources, keyword);
        return;
      }
    }

    if (_selectedSources.isEmpty) return;

    if (_isAggregated) {
      context
          .to(
            () => AggregatedSearchPage(
              keyword: keyword,
              sourceKeys: _selectedSources.toList(),
            )
          )
          .then((_) => update());
    } else {
      final singleSource = _selectedSources.first;
      context
          .to(
            () => SearchResultPage(
              text: keyword,
              sourceKey: singleSource,
              options: options,
            )
          )
          .then((_) => update());
    }
  }

  void _showSourcePicker(List<ComicSource> sources, String id) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kcSurfaceRadius)),
      ),
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  "Multiple sources matched".tl,
                  style: TextStyle(
                    fontSize: kcSubtitle,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  id,
                  style: TextStyle(
                    // 例外：monospace 展示 ID，等宽下 14 明显更占宽度，按令牌规则保留 kcFont13。
                    fontSize: kcFont13,
                    fontFamily: 'monospace',
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...sources.map((source) {
                final colorIndex =
                    kcStableHash(source.key) % sourceColors.length;
                final accentColor = sourceColors[colorIndex];
                return KcListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(kcRadius8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      source.name.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: sourceColor(colorIndex, cs.brightness),
                        fontWeight: FontWeight.w600,
                        fontSize: kcSubtitle,
                      ),
                    ),
                  ),
                  title: Text(source.name),
                  subtitle: Text("Open comic".tl),
                  chevron: true,
                  onTap: () {
                    Navigator.pop(context);
                    context.to(() => ComicPage(
                          sourceKey: source.key,
                          id: id,
                        )).then((_) => update());
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  var suggestions = <Pair<String, TranslationType>>[];

  bool canHandleUrl(String text) {
    if (!text.isURL) return false;
    for (var source in ComicSource.enabled()) {
      if (source.linkHandler != null) {
        var uri = Uri.parse(text);
        if (source.linkHandler!.domains.contains(uri.host)) {
          return true;
        }
      }
    }
    return false;
  }

  void findSuggestions() {
    var text = _searchTextController.text.split(" ").last;
    var suggestions = this.suggestions;

    suggestions.clear();

    if (canHandleUrl(_searchTextController.text)) {
      suggestions.add(Pair("**URL**", TranslationType.other));
    } else {
      var text = _searchTextController.text;

      for (var comicSource in ComicSource.enabled()) {
        if (comicSource.idMatcher?.hasMatch(text) ?? false) {
          suggestions.add(Pair(
            "**${comicSource.key}**",
            TranslationType.other,
          ));
        }
      }
    }

    if (!ComicSource.find(_selectedSources.first)!.enableTagsSuggestions) {
      update();
      return;
    }

    bool check(String text, String key, String value) {
      if (text.removeAllBlank == "") {
        return false;
      }
      if (key.length >= text.length && key.substring(0, text.length) == text ||
          (key.contains(" ") &&
              key.split(" ").last.length >= text.length &&
              key.split(" ").last.substring(0, text.length) == text)) {
        return true;
      } else if (value.length >= text.length && value.contains(text)) {
        return true;
      }
      return false;
    }

    void find(Map<String, String> map, TranslationType type) {
      for (var element in map.entries) {
        if (suggestions.length > 100) {
          break;
        }
        if (check(text, element.key, element.value)) {
          suggestions.add(Pair(element.key, type));
        }
      }
    }

    find(TagsTranslation.femaleTags, TranslationType.female);
    find(TagsTranslation.maleTags, TranslationType.male);
    find(TagsTranslation.parodyTags, TranslationType.parody);
    find(TagsTranslation.characterTranslations, TranslationType.character);
    find(TagsTranslation.otherTags, TranslationType.other);
    find(TagsTranslation.mixedTags, TranslationType.mixed);
    find(TagsTranslation.languageTranslations, TranslationType.language);
    find(TagsTranslation.artistTags, TranslationType.artist);
    find(TagsTranslation.groupTags, TranslationType.group);
    find(TagsTranslation.cosplayerTags, TranslationType.cosplayer);
    update();
  }

  @override
  void initState() {
    findSearchSources();
    _selectedSources = searchSources.take(1).toSet();
    var defaultSearchTarget = appdata.settings['defaultSearchTarget'];
    if (defaultSearchTarget is String && searchSources.contains(defaultSearchTarget)) {
      _selectedSources = {defaultSearchTarget};
    } else if (defaultSearchTarget == "_aggregated_") {
      _selectedSources = searchSources.toSet();
    }
    if (_selectedSources.isNotEmpty) {
      useDefaultOptions();
    }
    controller = SearchBarController(
      onSearch: search,
    );
    // 带词进入：首帧之后再发搜索——initState 里直接 push 结果页会和本页的
    // 入场动画抢路由。输入框同步填上，返回时能看到搜的是什么。
    final initialKeyword = widget.initialKeyword?.trim();
    if (initialKeyword != null && initialKeyword.isNotEmpty) {
      _searchTextController.text = initialKeyword;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) search(initialKeyword, false);
      });
    }
    listen(appdata.settings, updateSearchSourcesIfNeeded);
    super.initState();
  }

  @override
  void dispose() {
    focusNode.dispose();
    _searchTextController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void findSearchSources() {
    var all = ComicSource.enabled()
        .where((e) => e.searchPageData != null)
        .map((e) => e.key)
        .toList();
    var settings = appdata.settings['searchSources'] as List;
    var sources = <String>[];
    for (var source in settings) {
      if (all.contains(source)) {
        sources.add(source);
      }
    }
    searchSources = sources;
    // 移除不再存在的源
    _selectedSources.removeWhere((s) => !searchSources.contains(s));
    if (_selectedSources.isEmpty && searchSources.isNotEmpty) {
      _selectedSources = {searchSources.first};
    }
  }

  void updateSearchSourcesIfNeeded() {
    var old = searchSources;
    findSearchSources();
    if (old.isEqualTo(searchSources)) {
      return;
    }
    setState(() {});
  }

  void manageSearchSources() {
    showPopUpWidget(App.rootContext, setSearchSourcesWidget());
  }

  Widget buildEmpty() {
    if (ComicSource.isEmpty) {
      return Column(
        children: [
          const Appbar(title: Text("")),
          Expanded(
            child: EmptyState(
              title: "No Search Sources".tl,
              subtitle: "Please add some sources first".tl,
              actionLabel: "Manage".tl,
              onAction: () => context.to(() => const ComicSourcePage()),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        const Appbar(title: Text("")),
        Expanded(
          child: EmptyState(
            title: "No Search Sources".tl,
            subtitle: "Please check your settings".tl,
            actionLabel: "Manage".tl,
            onAction: manageSearchSources,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (searchSources.isEmpty) {
      return buildEmpty();
    }
    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: RepaintBoundary(
        child: Column(
          children: [
            _buildHeader(),
            _buildSourceRow(),
            Expanded(
              child: SmoothCustomScrollView(
                slivers: buildSlivers().toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Iterable<Widget> buildSlivers() sync* {
    if (suggestions.isNotEmpty) {
      yield buildSuggestions(context);
    } else {
      // 自上而下：最近搜过什么 → 换一种搜法（本地库）→ 当前源的检索选项。
      // 选项是「配置」不是「内容」，压到底部；本地搜索入口放在历史正下方，
      // 断网时第一屏就能看到它，而不是要滚到最后。
      if (appdata.searchHistory.isNotEmpty) {
        yield _SearchHistory(search);
      } else {
        yield _EmptySearchHint();
      }
      yield const _LocalSearchEntry();
      yield SliverAnimatedPaintExtent(
        duration: const Duration(milliseconds: 200),
        child: buildSearchOptions(),
      );
    }
  }

  /// 源选择：单行横向滚动的填充胶囊。
  ///
  /// 这里是「未对齐」观感的主要来源：源一多就 Wrap 成两三行，右边还挂着一颗
  /// 齿轮，齿轮既不跟任何一边对齐、又只有半行高，看起来像掉在角落的零件。
  /// 现在改成一行滚动条 + 齿轮上提到顶栏（和设置页的搜索图标同位置），
  /// 源再多也只有一行高，内容区不会再被推下去。
  Widget _buildSourceRow() {
    final sources = searchSources.map((e) => ComicSource.find(e)!).toList();
    final allSelected = _selectedSources.length == searchSources.length;
    final chips = <Widget>[
      _SearchChip(
        label: "ALL".tl,
        selected: allSelected,
        onTap: () {
          setState(() {
            _selectedSources = allSelected
                ? {searchSources.first}
                : searchSources.toSet();
            useDefaultOptions();
          });
        },
      ),
      ...sources.map((source) {
        final isSelected = _selectedSources.contains(source.key);
        return _SearchChip(
          label: source.name,
          selected: isSelected,
          onTap: () {
            setState(() {
              if (isSelected) {
                // 至少留一个源，否则 search() 会静默什么都不做。
                if (_selectedSources.length > 1) {
                  _selectedSources.remove(source.key);
                }
              } else {
                _selectedSources.add(source.key);
              }
              if (_selectedSources.length == 1) {
                useDefaultOptions();
              }
            });
          },
        );
      }),
    ];
    return SizedBox(
      height: 32,
      child: Stack(
        children: [
          ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _gutter),
            itemCount: chips.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => chips[i],
          ),
          // 右侧 24dp 渐隐：源多到装不下时，最后一个胶囊会在边缘被硬切一半，
          // 看着像排版出错；压一层同底色的透明渐变，切口变成「还有更多、可以
          // 往左滑」的提示。胶囊放得下时渐变盖在纯底色上，等于不可见。
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 24,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0),
                      Theme.of(context).colorScheme.surface,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void useDefaultOptions() {
    if (_selectedSources.isEmpty) {
      options = [];
      return;
    }
    final searchOptions = currentSearchPageData.searchOptions ?? [];
    options = searchOptions.map((e) => e.defaultValue).toList();
  }

  Widget buildSearchOptions() {
    if (_isAggregated || _selectedSources.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox());
    }

    var children = <Widget>[];

    final searchOptions = currentSearchPageData.searchOptions ?? [];
    if (searchOptions.length != options.length) {
      useDefaultOptions();
    }
    if (searchOptions.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox());
    }
    for (int i = 0; i < searchOptions.length; i++) {
      final option = searchOptions[i];
      children.add(SearchOptionWidget(
        option: option,
        value: options[i],
        onChanged: (value) {
          options[i] = value;
          update();
        },
        sourceKey: _selectedSources.first,
      ));
    }

    return SliverToBoxAdapter(
      child: Container(
        width: double.infinity,
        // 上 8 + 首组自带 16 = 24，与设置页分区标题的 18 / 6 节奏同量级；
        // 组间 16、标签到胶囊 8，形成「块松、组中、标签贴身」的三级节奏。
        padding: const EdgeInsets.fromLTRB(_gutter, 8, _gutter, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget buildSuggestions(BuildContext context) {
    bool check(String text, String key, String value) {
      if (text.removeAllBlank == "") {
        return false;
      }
      if (key.length >= text.length && key.substring(0, text.length) == text ||
          (key.contains(" ") &&
              key.split(" ").last.length >= text.length &&
              key.split(" ").last.substring(0, text.length) == text)) {
        return true;
      } else if (value.length >= text.length && value.contains(text)) {
        return true;
      }
      return false;
    }

    void onSelected(String text, TranslationType? type) {
      var words = _searchTextController.text.split(" ");
      if (words.length >= 2 &&
          check("${words[words.length - 2]} ${words[words.length - 1]}", text,
              text.translateTagIfNeed)) {
        _searchTextController.text = _searchTextController.text.replaceLast(
            "${words[words.length - 2]} ${words[words.length - 1]}", "");
      } else {
        _searchTextController.text =
            _searchTextController.text.replaceLast(words[words.length - 1], "");
      }
      final source = ComicSource.find(_selectedSources.first);
      String insert;
      if (source?.onTagSuggestionSelected != null) {
        insert = source!.onTagSuggestionSelected!(type?.name ?? '', text);
      } else {
        var t = text;
        if (t.contains(' ')) t = "'$t'";
        insert = type != null ? "${type.name}:$t" : t;
      }
      _searchTextController.text += "$insert ";
      suggestions.clear();
      update();
      focusNode.requestFocus();
    }

    bool showMethod = context.width < 600;
    bool showTranslation = App.locale.languageCode == "zh";
    Widget buildItem(Pair<String, TranslationType> value) {
      final cs = Theme.of(context).colorScheme;
      final typeColor = translationTypeColor(value.right, cs);
      if (value.left == "**URL**") {
        return KcListTile(
          leading: HugeIcon(icon: HugeIcons.strokeRoundedLink01, size: 18),
          title: Text("Open link".tl),
          subtitle: Text(
            _searchTextController.text,
            maxLines: 1,
            overflow: TextOverflow.fade,
          ),
          chevron: true,
          onTap: () {
            setState(() {
              suggestions.clear();
            });
            handleAppLink(Uri.parse(_searchTextController.text));
          },
        );
      }

      if (RegExp(r"^\*\*.*\*\*$").hasMatch(value.left)) {
        var key = value.left.substring(2, value.left.length - 2);
        var comicSource = ComicSource.find(key);
        if (comicSource == null) {
          return const SizedBox();
        }
        // 为每个源分配稳定的颜色标识
        final colorIndex = kcStableHash(key) % sourceColors.length;
        final accentColor = sourceColors[colorIndex];
        return KcListTile(
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(kcRadius8),
            ),
            alignment: Alignment.center,
            child: Text(
              comicSource.name.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: sourceColor(colorIndex, cs.brightness),
                fontWeight: FontWeight.w600,
                fontSize: kcBody,
              ),
            ),
          ),
          title: Text(
            "${"Open comic".tl}: ${comicSource.name}",
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            _searchTextController.text,
            maxLines: 1,
            overflow: TextOverflow.fade,
            style: const TextStyle(fontFamily: 'monospace', fontSize: kcCaption),
          ),
          chevron: true,
          onTap: () {
            context.to(
              () => ComicPage(
                sourceKey: key,
                id: _searchTextController.text,
              ),
            );
          },
        );
      }

      var subTitle = TagsTranslation.translationTagWithNamespace(
          value.left, value.right.name);
      return KcListTile(
        leading: Container(
          width: 6,
          height: 24,
          decoration: BoxDecoration(
            color: typeColor,
            borderRadius: BorderRadius.circular(kcRadius3),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(value.left, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (!showMethod)
              const SizedBox(
                width: 12,
              ),
            if (!showMethod && showTranslation)
              Text(
                subTitle,
                style: TextStyle(
                  fontSize: kcBody,
                  color: Theme.of(context).colorScheme.outline,
                ),
              )
          ],
        ),
        subtitle: (showMethod && showTranslation) ? Text(subTitle) : null,
        trailing: Text(
          value.right.name,
          style: TextStyle(
            fontSize: kcCaption,
            color: typeColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        onTap: () => onSelected(value.left, value.right),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          // 分区标题走设置页那套（原来用的是列表行，标题行和下面的建议行
          // 长得一模一样，分不出层级）。
          child: KcSectionHeader(
            title: "Suggestions".tl,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedAiNetwork, size: 16),
            trailing: GestureDetector(
              onTap: () {
                suggestions.clear();
                update();
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedCancel01,
                  size: 16,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              return buildItem(suggestions[index]);
            },
            childCount: suggestions.length,
          ),
        ),
      ],
    );
  }

  /// 顶栏：返回 + 页面标题 + 源管理，下面一行是搜索框。
  ///
  /// 抄的是设置页的顶栏节奏（左 8 起、返回 48 宽、标题 [kcTitleMain]、右侧
  /// 单颗图标、8 收尾），所以从设置页进来不会有「换了一套皮肤」的断裂感。
  /// 上一版把返回、搜索框、提交圆钮挤在同一行，返回键贴着屏幕边、搜索框左边
  /// 距 38、内容左边距 16 —— 三套内缩叠在一起，越看越歪。拆成两行之后，
  /// 搜索框和下面的胶囊、标题共用 16 这条竖线。
  Widget _buildHeader() {
    final cs = Theme.of(context).colorScheme;
    final topPad = MediaQuery.of(context).padding.top;
    return Column(
      children: [
        SizedBox(height: topPad),
        SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 8),
              Tooltip(
                message: "Back".tl,
                child: IconButton(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowLeft01,
                    size: 22,
                  ),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  "Search".tl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: kcTitleMain,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Tooltip(
                message: "Manage Sources".tl,
                child: IconButton(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedSettings01,
                    size: 22,
                    color: cs.onSurfaceVariant,
                  ),
                  onPressed: manageSearchSources,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        const SizedBox(height: 2),
        _buildSearchField(),
        const SizedBox(height: 12),
      ],
    );
  }

  /// 搜索框：整条胶囊铺满 16–16，提交键收进胶囊右侧做文字按钮。
  ///
  /// 上一版右边那颗 44 的实心圆是全页最重的元素：没字时是灰圆、有字时是红圆，
  /// 抢的注意力比搜索框本身还多，还把右边缘顶到 12。改成胶囊内的「搜索」文字
  /// 按钮后，左右边距都是 16，最重的元素回到输入内容本身。
  Widget _buildSearchField() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _gutter),
      child: ListenableBuilder(
        listenable: _searchTextController,
        builder: (context, _) {
          final hasText = _searchTextController.text.isNotEmpty;
          return Container(
            height: 44,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(kcRadius22),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                const SizedBox(width: 14),
                HugeIcon(
                  icon: HugeIcons.strokeRoundedSearch02,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    focusNode: focusNode,
                    controller: _searchTextController,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      // 提示词不用「搜索」：胶囊右侧已有一颗「搜索」按钮，
                      // 两个同词并排会被读成重复的标签而不是「提示 + 动作」。
                      hintText: 'Search comics, authors or links'.tl,
                      hintStyle: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        fontSize: kcBody,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: TextStyle(fontSize: kcBody, color: cs.onSurface),
                    textInputAction: TextInputAction.search,
                    keyboardType: TextInputType.text,
                    onSubmitted: (text) {
                      if (text.isNotEmpty) {
                        suggestions.clear();
                        search(text);
                      }
                    },
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        const Duration(milliseconds: 300),
                        () {
                          if (_searchTextController.text.isNotEmpty) {
                            findSuggestions();
                          } else {
                            suggestions.clear();
                            update();
                          }
                        },
                      );
                    },
                  ),
                ),
                if (hasText)
                  // 清除：只有在有字时才占位，空闲态右侧留给「搜索」。
                  GestureDetector(
                    onTap: () {
                      _searchTextController.clear();
                      suggestions.clear();
                      setState(() {});
                      focusNode.requestFocus();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 12,
                      ),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedCancel01,
                        size: 16,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: () {
                    if (!hasText) {
                      focusNode.requestFocus();
                      return;
                    }
                    suggestions.clear();
                    search(_searchTextController.text);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 14, 12),
                    child: Text(
                      "Search".tl,
                      style: TextStyle(
                        fontSize: kcBody,
                        fontWeight: FontWeight.w600,
                        // 没字时压成灰字：一眼能看出「现在还搜不了」，
                        // 又不像禁用按钮那样发白、刺眼。
                        color: hasText
                            ? kcBrandAdaptive(context)
                            : cs.onSurfaceVariant.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class SearchOptionWidget extends StatelessWidget {
  const SearchOptionWidget({
    super.key,
    required this.option,
    required this.value,
    required this.onChanged,
    required this.sourceKey,
  });

  final SearchOptions option;

  final String value;

  final void Function(String) onChanged;

  final String sourceKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      // 横向内缩由外层（`buildSearchOptions` 的 20）统一处理，这里只留纵向
      // 节奏 —— 之前两层各加 16/20，标签和胶囊比页面其它内容多缩进了 16。
      // 上 16 对应「组与组之间」，组内标签到胶囊固定 8。
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              option.label.ts(sourceKey),
              style: TextStyle(
                fontSize: kcCaption,
                // 与 KcSectionHeader 完全同款：同字号、同字重、同字距、同行高，
                // 让「检索选项」的组标题和页面里其它分区标题是同一套字。
                height: 1.35,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: cs.onSurfaceVariant.withValues(alpha: 0.75),
              ),
            ),
          ),
          if (option.type == 'select' || option.type == 'multi-select')
            Wrap(
              runSpacing: 8,
              spacing: 8,
              children: option.options.entries.map((e) {
                final isSelected = option.type == 'select'
                    ? value == e.key
                    : (jsonDecode(value) as List).contains(e.key);
                return _SearchChip(
                  label: e.value.ts(sourceKey),
                  selected: isSelected,
                  onTap: () {
                    if (option.type == 'select') {
                      onChanged(e.key);
                    } else {
                      var list = jsonDecode(value) as List;
                      if (list.contains(e.key)) {
                        list.remove(e.key);
                      } else {
                        list.add(e.key);
                      }
                      onChanged(jsonEncode(list));
                    }
                  },
                );
              }).toList(),
            ),
          if (option.type == 'dropdown')
            _OptionDropdown(
              current: option.options[value],
              values: option.options.values.toList(),
              onTap: (index) {
                onChanged(option.options.keys.elementAt(index));
              },
            )
        ],
      ),
    );
  }
}

/// 全页唯一的胶囊样式 —— 源选择、搜索历史、检索选项共用。
///
/// 之前源胶囊是纯填充、检索选项是描边，两种「按钮感」并存；统一成填充后，
/// 选中态只靠「浅品牌底 + 品牌字 + 加粗」区分，页面里只剩一种标签语言。
class _SearchChip extends StatelessWidget {
  const _SearchChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: kcReduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? kcAccentSurface(context, alpha: 0.18)
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(kcRadius22),
        ),
        // 宽度必须收到文字上。带 alignment 的 Container 在 Wrap（有界宽）里
        // 会拉满整行 —— 检索选项的 select / multi-select 就渲染成一排满宽
        // 长条，跟源胶囊（横向 ListView，无界宽）判若两物。
        // Center(widthFactor: 1) 只吃文字宽，同时在 32 高里垂直居中。
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: kcBody,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? kcBrandAdaptive(context) : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 检索选项里的下拉 —— 视觉与 [_SearchChip] 同族。
///
/// 原来这里用的是通用 `Select`（1dp 描边小方框 + 品牌红箭头）：同一块区域里
/// 一组是填充胶囊、一组是描边方框，两种「按钮感」并排，还都叫「选项」。
/// 现在换成同款填充胶囊，只在尾部多一颗下箭头表明「点了会弹菜单」；点开仍是
/// 原生弹出菜单，交互与原来一致。
class _OptionDropdown extends StatelessWidget {
  const _OptionDropdown({
    required this.current,
    required this.values,
    required this.onTap,
  });

  final String? current;

  final List<String> values;

  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 源给了 dropdown 类型但没填选项（配置写错）时，showMenu 会因 items 为空
    // 抛断言；这里直接不出这颗胶囊，比整页崩掉好。
    if (values.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final box = context.findRenderObject() as RenderBox;
        final offset = box.localToGlobal(Offset.zero);
        final size = box.size;
        // 菜单至少 160 宽，避免「全部」这种短值弹出一个只有两个字宽的面板。
        final width = size.width < 160 ? 160.0 : size.width;
        showMenu<int>(
          elevation: 3,
          // 用比页面更高一层的容器色：菜单底与页底同色时，弹出层看起来像
          // 「页面被裁了个洞」，而不是浮在内容之上。
          color: cs.surfaceContainerHigh,
          context: context,
          useRootNavigator: true,
          constraints: BoxConstraints(minWidth: width, maxWidth: width),
          position: RelativeRect.fromLTRB(
            offset.dx,
            offset.dy + size.height + 4,
            offset.dx + width,
            offset.dy,
          ),
          items: [
            for (int i = 0; i < values.length; i++)
              PopupMenuItem<int>(
                height: 46,
                value: i,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        values[i].tl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: kcBody,
                          fontWeight: values[i] == current
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: values[i] == current
                              ? kcBrandAdaptive(context)
                              : cs.onSurface,
                        ),
                      ),
                    ),
                    // 菜单里标出「现在选的是哪个」—— 原来只能靠记住胶囊上的
                    // 文字再回来比一遍。
                    if (values[i] == current)
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                        size: 16,
                        color: kcBrandAdaptive(context),
                      ),
                  ],
                ),
              ),
          ],
        ).then((index) {
          if (index != null) onTap(index);
        });
      },
      child: AnimatedContainer(
        duration: kcReduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        height: 32,
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(kcRadius22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              (current ?? '').tl,
              maxLines: 1,
              style: TextStyle(fontSize: kcBody, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            HugeIcon(
              icon: HugeIcons.strokeRoundedArrowDown01,
              size: 14,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchHistory extends StatefulWidget {
  const _SearchHistory(this.search);

  final void Function(String) search;

  @override
  State<_SearchHistory> createState() => _SearchHistoryState();
}

class _SearchHistoryState extends State<_SearchHistory> {
  void _remove(String item) {
    appdata.removeSearchHistory(item);
    appdata.saveData();
    // appdata 的变更不等于本页 rebuild（本页只监听 settings），手动刷一次，
    // 否则删掉的词要等下次进页面才消失。
    if (mounted) setState(() {});
  }

  void _clear() {
    appdata.clearSearchHistory();
    appdata.saveData();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final history = appdata.searchHistory;
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 与设置页同一个分区标题件（20 内缩、12sp w600、上 18 下 6 的呼吸）。
          KcSectionHeader(
            title: "Search History".tl,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedClock01, size: 16),
            trailing: history.isEmpty
                ? null
                : GestureDetector(
                    onTap: _clear,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 2,
                      ),
                      child: Text(
                        "Clear".tl,
                        style: TextStyle(
                          fontSize: kcCaption,
                          fontWeight: FontWeight.w500,
                          color: kcBrandAdaptive(context),
                        ),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _gutter),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: history
                  .map(
                    (item) => _HistoryChip(
                      item: item,
                      onTap: () => widget.search(item),
                      onRemove: () => _remove(item),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryChip extends StatelessWidget {
  const _HistoryChip({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  final String item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onRemove,
      child: Container(
        height: 32,
        padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(kcRadius22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                item,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: kcBody, color: cs.onSurface),
              ),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedCancel01,
                  size: 12,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空输入时的引导：一句话 + 没有大图标占位，把纵向空间让给下面的入口行。
class _EmptySearchHint extends StatelessWidget {
  const _EmptySearchHint();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_gutter, 20, _gutter, 0),
        child: Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedSearch02,
              size: 18,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Start typing to search".tl,
                style: TextStyle(
                  fontSize: kcBody,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 本地库搜索入口。
///
/// 网络搜索依赖源站，断网/源站抽风时这页什么也做不了；而用户的收藏和历史
/// 是完整存在本机的。把速搜浮层挂在这里，等于给搜索页一条离线兜底路径，
/// 也让两个搜索入口之间有了明确的先后关系：「找已经看过的」→ 本地，
/// 「找新的」→ 网络。
///
/// 版式按设置页的行来做：上方一条 16 缩进的发丝线，行内「图标 + 标题 + 副标题
/// + 右箭头」、无卡片底色。上一版是 surfaceContainerLow 圆角卡 + 34 的强调色
/// 方块图标，在这页里是第三套视觉（胶囊一套、卡片一套、卡片里的方块又一套），
/// 和刚统一好的栅格对不上。
class _LocalSearchEntry extends StatelessWidget {
  const _LocalSearchEntry();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      // 直接复用设置页的通用行：20 内缩、48 高点击区、发丝分隔线、
      // 无溅射水波。上一版是 surfaceContainerLow 圆角卡 + 34 的强调色方块
      // 图标，在这页里是第三套视觉（胶囊一套、卡片一套、卡片里的方块又一套），
      // 和刚统一的栅格对不上。
      child: KcListTile(
        leading: HugeIcon(
          icon: HugeIcons.strokeRoundedBookmark01,
          size: 20,
          color: cs.onSurfaceVariant,
        ),
        title: Text("Search favorites & history".tl),
        subtitle: Text("Works offline".tl),
        chevron: true,
        onTap: () => showQuickSearch(context),
      ),
    );
  }
}
