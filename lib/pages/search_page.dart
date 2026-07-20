import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sliver_tools/sliver_tools.dart';
import 'package:kong_comic/components/components.dart';
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

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
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

  void search([String? text]) {
    final keyword = text ?? _searchTextController.text;

    // ID 直接跳转：仅当唯一匹配时直接跳转，多源匹配时由建议列表选择
    var matchedSources = <ComicSource>[];
    for (var source in ComicSource.all()) {
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
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  id,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...sources.map((source) {
                final colorIndex =
                    source.key.hashCode.abs() % sourceColors.length;
                final accentColor = sourceColors[colorIndex];
                return ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      source.name.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: sourceColor(colorIndex, cs.brightness),
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  title: Text(source.name),
                  subtitle: Text("Open comic".tl),
                  trailing: HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
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
    for (var source in ComicSource.all()) {
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

      for (var comicSource in ComicSource.all()) {
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
    appdata.settings.addListener(updateSearchSourcesIfNeeded);
    super.initState();
  }

  @override
  void dispose() {
    focusNode.dispose();
    _searchTextController.dispose();
    _debounceTimer?.cancel();
    appdata.settings.removeListener(updateSearchSourcesIfNeeded);
    super.dispose();
  }

  void findSearchSources() {
    var all = ComicSource.all()
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
              icon: HugeIcon(icon: HugeIcons.strokeRoundedSearch02, size: 18),
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
            icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings01, size: 18),
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
            _buildTopSearchBar(),
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
      yield SliverAnimatedPaintExtent(
        duration: const Duration(milliseconds: 200),
        child: buildSearchOptions(),
      );
      if (appdata.searchHistory.isNotEmpty) {
        yield _SearchHistory(search);
      } else {
        yield _EmptySearchHint();
      }
    }
  }

  Widget _buildSourceRow() {
    final sources = searchSources.map((e) => ComicSource.find(e)!).toList();
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // ALL 全选按钮
                GestureDetector(
                  onTap: () {
                    setState(() {
                      final allSelected = _selectedSources.length == searchSources.length;
                      if (allSelected) {
                        _selectedSources = {searchSources.first};
                      } else {
                        _selectedSources = searchSources.toSet();
                      }
                      useDefaultOptions();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _selectedSources.length == searchSources.length
                          ? cs.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _selectedSources.length == searchSources.length
                            ? cs.primary.withValues(alpha: 0.3)
                            : cs.outlineVariant,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(icon: HugeIcons.strokeRoundedArrowLeftRight, size: 14, color: _selectedSources.length == searchSources.length
                              ? cs.primary
                              : cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          "ALL".tl,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _selectedSources.length == searchSources.length
                                ? cs.onPrimaryContainer
                                : cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ...sources.map((source) {
                final isSelected = _selectedSources.contains(source.key);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
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
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSelected ? cs.primaryContainer : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? cs.primary.withValues(alpha: 0.3)
                            : cs.outlineVariant,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(icon: 
                          isSelected ? HugeIcons.strokeRoundedCheckmarkCircle01 : HugeIcons.strokeRoundedRadioButton,
                          size: 14,
                          color: isSelected ? cs.primary : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          source.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                            color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        Tooltip(
            message: "Manage Sources".tl,
            child: IconButton(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings01, size: 18),
              onPressed: manageSearchSources,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                minimumSize: const Size(32, 32),
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
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
              text.translateTagsToCN)) {
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
        return ListTile(
          leading: HugeIcon(icon: HugeIcons.strokeRoundedLink01, size: 18),
          title: Text("Open link".tl),
          subtitle: Text(
            _searchTextController.text,
            maxLines: 1,
            overflow: TextOverflow.fade,
          ),
          trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: 18),
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
        final colorIndex = key.hashCode.abs() % sourceColors.length;
        final accentColor = sourceColors[colorIndex];
        return ListTile(
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              comicSource.name.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: sourceColor(colorIndex, cs.brightness),
                fontWeight: FontWeight.w600,
                fontSize: 14,
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
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: 18),
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
      return ListTile(
        leading: Container(
          width: 6,
          height: 24,
          decoration: BoxDecoration(
            color: typeColor,
            borderRadius: BorderRadius.circular(3),
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
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
              )
          ],
        ),
        subtitle: (showMethod && showTranslation) ? Text(subTitle) : null,
        trailing: Text(
          value.right.name,
          style: TextStyle(
            fontSize: 12,
            color: typeColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        onTap: () => onSelected(value.left, value.right),
      );
    }

    return RepaintBoundary(
      child: SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: ListTile(
            leading: HugeIcon(icon: HugeIcons.strokeRoundedAiNetwork, size: 18),
            title: Text("Suggestions".tl),
            trailing: Tooltip(
              message: "Clear".tl,
              child: IconButton(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedCancelCircle, size: 18),
                onPressed: () {
                  suggestions.clear();
                  update();
                },
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
    ));
  }

  Widget _buildTopSearchBar() {
    final cs = Theme.of(context).colorScheme;
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 12 + topPad, 12, 8),
      decoration: BoxDecoration(
        color: cs.surface,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: cs.surfaceContainerLow,
              ),
              clipBehavior: Clip.antiAlias,
              child: TextField(
                focusNode: focusNode,
                controller: _searchTextController,
                decoration: InputDecoration(
                  hintText: 'Search'.tl,
                  hintStyle: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  suffixIcon: ListenableBuilder(
                    listenable: _searchTextController,
                    builder: (context, _) {
                      return _searchTextController.text.isNotEmpty
                          ? IconButton(
                              icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 16, color: cs.onSurfaceVariant),
                              onPressed: () {
                                _searchTextController.clear();
                                suggestions.clear();
                                setState(() {});
                              },
                              visualDensity: VisualDensity.compact,
                            )
                          : const SizedBox(width: 0);
                    },
                  ),
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface,
                ),
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
                  _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                    if (_searchTextController.text.isNotEmpty) {
                      findSuggestions();
                    } else {
                      suggestions.clear();
                      update();
                    }
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              final text = _searchTextController.text;
              if (text.isNotEmpty) {
                suggestions.clear();
                search(text);
              }
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: cs.primary,
              ),
              child: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: 18, color: cs.onPrimary),
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              option.label.ts(sourceKey),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          if (option.type == 'select' || option.type == 'multi-select')
            Wrap(
              runSpacing: 6,
              spacing: 6,
              children: option.options.entries.map((e) {
                final isSelected = option.type == 'select'
                    ? value == e.key
                    : (jsonDecode(value) as List).contains(e.key);
                return GestureDetector(
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
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSelected ? cs.primaryContainer : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? cs.primary.withValues(alpha: 0.3)
                            : cs.outlineVariant,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      e.value.ts(sourceKey),
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          if (option.type == 'dropdown')
            Select(
              current: option.options[value],
              values: option.options.values.toList(),
              onTap: (index) {
                onChanged(option.options.keys.elementAt(index));
              },
              minWidth: 96,
            )
        ],
      ),
    );
  }
}

class _SearchHistory extends StatelessWidget {
  const _SearchHistory(this.search);

  final void Function(String) search;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final history = appdata.searchHistory;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HugeIcon(icon: HugeIcons.strokeRoundedClock01, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  "Search History".tl,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (history.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      appdata.clearSearchHistory();
                    },
                    child: Text(
                      "Clear".tl,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: history.map((item) {
                return GestureDetector(
                  onTap: () => search(item),
                  onLongPress: () {
                    appdata.removeSearchHistory(item);
                    appdata.saveData();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: cs.outlineVariant, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            item,
                            style: TextStyle(fontSize: 13, color: cs.onSurface),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            appdata.removeSearchHistory(item);
                            appdata.saveData();
                          },
                          child: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 14, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySearchHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(icon: HugeIcons.strokeRoundedSearch02, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              "Start typing to search".tl,
              style: TextStyle(
                fontSize: 15,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
