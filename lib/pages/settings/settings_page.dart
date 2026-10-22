import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/cache_manager.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/js_engine.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/foundation/listen_mixin.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/foundation/update_mirror.dart';
import 'package:kong_comic/utils/data.dart';
import 'package:kong_comic/utils/data_sync.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:kong_comic/utils/translations.dart';
import 'package:kong_comic/utils/import_comic.dart';
import 'package:kong_comic/utils/app_update.dart';
import 'package:kong_comic/utils/auto_backup.dart';
import 'package:kong_comic/utils/notifications.dart';

part 'reader.dart';
part 'explore_settings.dart';
part 'setting_components.dart';
part 'appearance.dart';
part 'local_favorites.dart';
part 'app.dart';
part 'about.dart';
part 'network.dart';
part 'download.dart';
part 'import_settings.dart';

class _SettingSearchEntry {
  final String title;
  final int category;
  final String? subtitle;
  final bool isCategory;
  const _SettingSearchEntry(this.title, this.category,
      {this.subtitle, this.isCategory = false});
}

/// 跨分类的设置项搜索索引。title / subtitle 为英文源串，运行时经 `.tl` 取本地化
/// 文本并同时用英文本体做匹配，保证中文界面下输入中文或英文都能命中。
const List<_SettingSearchEntry> _kSettingSearchIndex = [
  // 0 - Reader
  _SettingSearchEntry("Tap to turn Pages", 0),
  _SettingSearchEntry("Reverse tap to turn Pages", 0),
  _SettingSearchEntry("Tap Zone Layout", 0),
  _SettingSearchEntry("Page animation", 0),
  _SettingSearchEntry("Reading mode", 0),
  _SettingSearchEntry("Auto page turning interval", 0),
  _SettingSearchEntry("Show single image on first page", 0),
  _SettingSearchEntry("Long press zoom position", 0),
  _SettingSearchEntry("Image Fit Mode", 0),
  _SettingSearchEntry("Display time & battery info in reader", 0),
  _SettingSearchEntry("Hide navigation while reading", 0),
  _SettingSearchEntry("Show system status bar", 0),
  _SettingSearchEntry("Keep screen on", 0),
  _SettingSearchEntry("Screen orientation", 0),
  _SettingSearchEntry("Quick collect image", 0),
  _SettingSearchEntry("Custom Image Processing", 0),
  _SettingSearchEntry("Number of images preloaded", 0),
  _SettingSearchEntry("Show Page Number", 0),
  _SettingSearchEntry("Show Chapter Comments", 0),
  _SettingSearchEntry("Show Comments at Chapter End", 0),
  _SettingSearchEntry("Reverse default chapter order", 0),
  // 1 - Appearance
  _SettingSearchEntry("Theme Color", 1),
  _SettingSearchEntry("Language", 1),
  // 2 - Explore
  _SettingSearchEntry("Display mode of comic tile", 2),
  _SettingSearchEntry("Show recommendations on explore", 2),
  _SettingSearchEntry("Size of comic tile", 2),
  _SettingSearchEntry("Explore Pages", 2),
  _SettingSearchEntry("Category Pages", 2),
  _SettingSearchEntry("Network Favorite Pages", 2),
  _SettingSearchEntry("Search Sources", 2),
  _SettingSearchEntry("Show favorite status on comic tile", 2),
  _SettingSearchEntry("Show history on comic tile", 2),
  _SettingSearchEntry("Keyword blocking", 2),
  _SettingSearchEntry("Comment keyword blocking", 2),
  _SettingSearchEntry("Default Search Target", 2),
  _SettingSearchEntry("Auto Language Filters", 2),
  _SettingSearchEntry("Load mode of comic list", 2),
  // 3 - Local Favorites
  _SettingSearchEntry("Show local favorites before network favorites", 3),
  _SettingSearchEntry("Auto close favorite panel after operation", 3),
  _SettingSearchEntry("Add new favorite to", 3),
  _SettingSearchEntry("Move favorite after reading", 3),
  _SettingSearchEntry("Quick Favorite", 3),
  _SettingSearchEntry("Delete all unavailable local favorite items", 3),
  _SettingSearchEntry("Click favorite item", 3),
  _SettingSearchEntry("Home banner folders", 3),
  // 4 - Network
  _SettingSearchEntry("Proxy", 4),
  _SettingSearchEntry("DNS Overrides", 4),
  _SettingSearchEntry("Enable DNS Overrides", 4),
  _SettingSearchEntry("Server Name Indication", 4),
  // 5 - Download
  _SettingSearchEntry("CBZ Packaging", 5),
  _SettingSearchEntry("Save chapters as CBZ", 5,
      subtitle: "Package each chapter as .cbz file after download"),
  _SettingSearchEntry("Delete folder after CBZ packaging", 5,
      subtitle: "Keep only the .cbz file, remove the original folder"),
  _SettingSearchEntry("Download Performance", 5),
  _SettingSearchEntry("Download Threads", 5),
  // 6 - Import
  _SettingSearchEntry("Import CBZ / ZIP / 7Z", 6),
  _SettingSearchEntry("Import archives from folder", 6,
      subtitle: "Batch import .cbz/.zip/.7z files"),
  _SettingSearchEntry("Import image folders", 6,
      subtitle: "Import folders containing images as comics"),
  // 7 - APP
  _SettingSearchEntry("Move comics into storage path", 7),
  _SettingSearchEntry("Initial Page", 7),
  _SettingSearchEntry("Set New Storage Path", 7),
  _SettingSearchEntry("Move to Current Storage Path", 7),
  _SettingSearchEntry("All files access", 7),
  _SettingSearchEntry("Use Download/Comic", 7),
  _SettingSearchEntry("Notifications", 7),
  _SettingSearchEntry("Clear Cache", 7),
  _SettingSearchEntry("Cache Limit", 7),
  _SettingSearchEntry("Export App Data", 7),
  _SettingSearchEntry("Import App Data", 7),
  _SettingSearchEntry("Auto Backup", 7,
      subtitle: "Periodically back up your data to the Download folder"),
  _SettingSearchEntry("Auto-update comic sources", 7),
  _SettingSearchEntry("Backup Interval", 7),
  _SettingSearchEntry("Backup Retention", 7),
  _SettingSearchEntry("Back Up Now", 7),
  _SettingSearchEntry("Authorization Required", 7),
  _SettingSearchEntry("Exit Confirmation", 7,
      subtitle: "Ask before exiting via back gesture at root"),
  _SettingSearchEntry("Webdav", 7),
  // 8 - About
  _SettingSearchEntry("Check for updates on startup", 8),
  _SettingSearchEntry("Mirror template", 8),
  _SettingSearchEntry("Download sources", 8),
];

class SettingsPage extends StatefulWidget {
  const SettingsPage({this.initialPage = -1, super.key});

  final int initialPage;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with AutoListenMixin {
  int currentPage = -1;

  ColorScheme get colors => Theme.of(context).colorScheme;

  bool get enableTwoViews => context.width > 720;

  List<String> _categories() => [
    "Reader Settings".tl,
    "Appearance".tl,
    "Explore".tl,
    "Local Favorites".tl,
    "Network".tl,
    "Download".tl,
    "Import".tl,
    "APP".tl,
    "About".tl
  ];

  final icons = <Widget>[
    HugeIcon(icon: HugeIcons.strokeRoundedBook01, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedColorPicker, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedCompass01, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedBookmark01, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedGlobe02, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedUpload01, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedAppStore, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, size: 24),
  ];

  List<String> _subtitles() => [
    "Reading mode, page turning, zoom".tl,
    "Theme, language".tl,
    "Comic display, search sources, home".tl,
    "Local favorites management".tl,
    "Proxy, DNS".tl,
    "Download tasks, CBZ packaging".tl,
    "Comic import".tl,
    "Data sync, auth, cache, storage".tl,
    "Version, update, GitHub".tl,
  ];

  bool _searchActive = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<_SettingSearchEntry> get _allSearchEntries {
    final cats = _categories();
    final subs = _subtitles();
    return <_SettingSearchEntry>[
      for (var i = 0; i < cats.length; i++)
        _SettingSearchEntry(cats[i], i, subtitle: subs[i], isCategory: true),
      ..._kSettingSearchIndex,
    ];
  }

  List<_SettingSearchEntry> _searchEntriesFor(String q) {
    q = q.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <_SettingSearchEntry>[];
    for (final e in _allSearchEntries) {
      final t = e.title.tl.toLowerCase();
      final en = e.title.toLowerCase();
      final sub = e.subtitle?.tl.toLowerCase() ?? '';
      if (t.contains(q) || en.contains(q) || sub.contains(q)) out.add(e);
    }
    return out;
  }

  void _openSearch() {
    setState(() => _searchActive = true);
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    setState(() {
      _searchActive = false;
      _searchController.clear();
    });
  }

  void _goToCategory(int cat) {
    setState(() {
      _searchActive = false;
      _searchController.clear();
    });
    if (enableTwoViews) {
      setState(() => currentPage = cat);
    } else {
      context.to(() => _SettingsDetailPage(pageIndex: cat));
    }
  }

  @override
  void initState() {
    currentPage = widget.initialPage;
    listen(appdata.settings, _onSettingsChange);
    super.initState();
  }


  void _onSettingsChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // 底色统一用 scaffoldBackgroundColor（浅色纯白），与玻璃顶栏的 tint 基色一致；
    // 之前用 colorScheme.surface（浅色下略带紫的 #FAF8FF），被顶栏的 66% 白叠加后
    // 提亮成 #FDFDFF，两者在交界处形成一条肉眼可见的分层色带。
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: buildBody(),
    );
  }

  Widget buildBody() {
    if (enableTwoViews) {
      return Row(
        children: [
          SizedBox(
            width: 280,
            height: double.infinity,
            child: buildLeft(),
          ),
          Container(
            height: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: context.colorScheme.outlineVariant,
                  width: 0.6,
                ),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return LayoutBuilder(
                  builder: (context, constrains) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) {
                        var width = constrains.maxWidth;
                        var value = animation.isForwardOrCompleted
                            ? 1 - animation.value
                            : 1;
                        var left = width * value;
                        return Stack(
                          children: [
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: left,
                              width: width,
                              child: child,
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
              child: buildRight(),
            ),
          )
        ],
      );
    } else {
      return buildLeft();
    }
  }

  Widget buildLeft() {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).padding.top,
          ),
          SizedBox(
            height: 56,
            child: Row(children: [
              const SizedBox(
                width: 8,
              ),
              Tooltip(
                message: "Back".tl,
                child: IconButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, size: 22),
                  onPressed: context.pop,
                ),
              ),
              const SizedBox(
                width: 16,
              ),
              Expanded(
                child: _searchActive
                    ? TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                        style: TextStyle(fontSize: kcSubtitle),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: "Search settings".tl,
                          hintStyle: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      )
                    : Text(
                        "Settings".tl,
                        style: TextStyle(fontSize: kcTitleMain),
                      ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: HugeIcon(
                  icon: _searchActive
                      ? HugeIcons.strokeRoundedCancel01
                      : HugeIcons.strokeRoundedSearch02,
                  size: 22,
                ),
                tooltip: _searchActive ? "Close".tl : "Search settings".tl,
                onPressed: _searchActive ? _closeSearch : _openSearch,
              ),
              const SizedBox(width: 8),
            ]),
          ),
          const SizedBox(
            height: 4,
          ),
          Expanded(
            child: buildCategories(),
          )
        ],
      ),
    );
  }

  Widget buildCategories() {
    if (_searchActive) {
      return _buildSearchResults();
    }
    Widget buildItem(String name, String subtitle, int id) {
      final bool selected = id == currentPage;
      final cs = Theme.of(context).colorScheme;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(kcCardRadius),
          onTap: () {
            if (enableTwoViews) {
              setState(() => currentPage = id);
            } else {
              context.to(() => _SettingsDetailPage(pageIndex: id));
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kcCardRadius),
              border: Border.all(
                color: selected ? kcAccentColor(context).withValues(alpha: 0.3) : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                HugeIcon(icon: (icons[id] as HugeIcon).icon, color: selected ? kcBrandAdaptive(context) : cs.onSurfaceVariant, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: kcSubtitle,
                          fontWeight: FontWeight.w600,
                          color: selected ? cs.onSurface : cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: kcCaption,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowRight01,
                  color: selected ? kcBrandAdaptive(context) : cs.onSurfaceVariant.withValues(alpha: 0.4),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.only(top: 8, bottom: MediaQuery.of(context).padding.bottom + 16),
      itemCount: _categories().length,
      itemBuilder: (context, index) => buildItem(_categories()[index], _subtitles()[index], index),
    );
  }

  Widget buildRight() {
    if (currentPage == -1) {
      return const SizedBox();
    }
    // Render the selected settings page directly. Sub-pages reach a 2nd/3rd
    // level via `context.to`, which now resolves to the main (per-tab)
    // navigator — keeping the back stack symmetric with the narrow-screen
    // flow and the rest of the app.
    //
    // A separate nested Navigator used to live here. Because it was a
    // different navigator from the per-tab one, the outer PopScope in
    // navigation_bar.dart intercepted the system / predictive back gesture and
    // popped the whole SettingsPage off the per-tab stack, skipping the
    // in-page level. Returning from a 2nd/3rd-level settings page therefore
    // required multiple back presses (the same class of bug as the earlier
    // comments-page fix).
    return _buildSettingsContent(currentPage);
  }

  Widget _buildSettingsContent(int pageIndex) {
    return switch (pageIndex) {
      0 => const ReaderSettings(),
      1 => const AppearanceSettings(),
      2 => const ExploreSettings(),
      3 => const LocalFavoritesSettings(),
      4 => const NetworkSettings(),
      5 => const DownloadSettings(),
      6 => const ImportSettings(),
      7 => const AppSettings(),
      8 => const AboutSettings(),
      _ => throw UnimplementedError()
    };
  }

  Widget _buildSearchResults() {
    final cs = Theme.of(context).colorScheme;
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "Search settings".tl,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    final results = _searchEntriesFor(q);
    final cats = _categories();
    final subs = _subtitles();
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "No results".tl,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(top: 8, bottom: MediaQuery.of(context).padding.bottom + 16),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final e = results[index];
        final selected = !e.isCategory && currentPage == e.category;
        final mainText = e.title.tl;
        final subText = e.isCategory ? subs[e.category].tl : cats[e.category].tl;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(kcCardRadius),
            onTap: () => _goToCategory(e.category),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kcCardRadius),
                border: Border.all(
                  color: selected
                      ? kcAccentColor(context).withValues(alpha: 0.3)
                      : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mainText,
                          style: TextStyle(
                            fontSize: kcSubtitle,
                            fontWeight: FontWeight.w600,
                            color: e.isCategory
                                ? kcAccentColor(context)
                                : cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subText,
                          style: TextStyle(
                            fontSize: kcCaption,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

}

class _SettingsDetailPage extends StatelessWidget {
  const _SettingsDetailPage({required this.pageIndex});

  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _buildPage(),
    );
  }

  Widget _buildPage() {
    return switch (pageIndex) {
      0 => const ReaderSettings(),
      1 => const AppearanceSettings(),
      2 => const ExploreSettings(),
      3 => const LocalFavoritesSettings(),
      4 => const NetworkSettings(),
      5 => const DownloadSettings(),
      6 => const ImportSettings(),
      7 => const AppSettings(),
      8 => const AboutSettings(),
      _ => throw UnimplementedError()
    };
  }
}
