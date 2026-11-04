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
import 'package:kong_comic/utils/power.dart';

part 'reader.dart';
part 'explore_settings.dart';
part 'setting_components.dart';
part 'appearance.dart';
part 'local_favorites.dart';
part 'app.dart';
part 'permissions.dart';
part 'about.dart';
part 'network.dart';
part 'download.dart';

class _SettingSearchEntry {
  final String title;
  final int category;
  final String? subtitle;
  final bool isCategory;

  /// 只参与匹配、不显示的补充词（英文选项名、同义词）。
  ///
  /// 标题与副标题在中文界面下只拿「译文」参与匹配，所以用户输入 `dark` /
  /// `AMOLED` 这类英文选项名时命不中一行叫「外观」的设置。这里显式登记这些
  /// 词，避免为了可搜索去改显示文案。
  final String? keywords;

  const _SettingSearchEntry(
    this.title,
    this.category, {
    this.subtitle,
    this.isCategory = false,
    this.keywords,
  });
}

/// 跨分类的设置项搜索索引。title / subtitle 为英文源串，运行时经 `.tl` 取本地化
/// 文本并同时用英文本体做匹配，保证中文界面下输入中文或英文都能命中。
const List<_SettingSearchEntry> _kSettingSearchIndex = [
  // 0 - Reading & images ／ 1 - Page & interface
  _SettingSearchEntry("Tap to turn Pages", 1),
  _SettingSearchEntry("Reverse tap to turn Pages", 1),
  _SettingSearchEntry("Tap Zone Layout", 1),
  _SettingSearchEntry("Page animation", 1),
  _SettingSearchEntry("Reading mode", 0),
  _SettingSearchEntry("Auto Webtoon detection", 0),
  _SettingSearchEntry("Auto page turning interval", 1),
  _SettingSearchEntry("Show single image on first page", 0),
  _SettingSearchEntry("Long press zoom position", 0),
  _SettingSearchEntry(
    "Double tap to zoom",
    0,
    keywords: "double tap zoom 双击 放大",
  ),
  _SettingSearchEntry(
    "Long press to zoom",
    0,
    keywords: "long press zoom 长按 放大",
  ),
  _SettingSearchEntry(
    "Image Fit Mode",
    0,
    keywords: "fit width height screen 适应 拉伸",
  ),
  _SettingSearchEntry(
    "Image display scale",
    0,
    keywords: "scale zoom percent 缩放 比例 显示大小",
  ),
  _SettingSearchEntry(
    "Limit image width",
    0,
    keywords: "limit width continuous 宽度 限制",
  ),
  _SettingSearchEntry(
    "Webtoon side margin",
    0,
    keywords: "webtoon margin padding 条漫 留白 边距",
  ),
  _SettingSearchEntry(
    "Turn page by volume keys",
    1,
    keywords: "volume key 音量键 翻页",
  ),
  _SettingSearchEntry("Display time & battery info in reader", 1),
  _SettingSearchEntry("Hide navigation while reading", 1),
  _SettingSearchEntry("Show system status bar", 1),
  _SettingSearchEntry("Keep screen on", 1),
  _SettingSearchEntry("Screen orientation", 1),
  _SettingSearchEntry("Quick collect image", 1),
  _SettingSearchEntry("Custom Image Processing", 0),
  _SettingSearchEntry(
    "Number of images preloaded",
    0,
    keywords: "preload cache 预加载 缓存图片",
  ),
  _SettingSearchEntry(
    "The number of pic in screen for landscape (Only Gallery Mode)",
    0,
    keywords: "gallery grid landscape 网格 横屏 每屏",
  ),
  _SettingSearchEntry(
    "The number of pic in screen for portrait (Only Gallery Mode)",
    0,
    keywords: "gallery grid portrait 网格 竖屏 每屏",
  ),
  _SettingSearchEntry("Show Page Number", 1),
  _SettingSearchEntry("Show Chapter Comments", 1),
  _SettingSearchEntry("Show Comments at Chapter End", 1),
  _SettingSearchEntry("Reverse default chapter order", 1),
  // 2 - Appearance（只有主题，语言在「应用与存储 → 语言与启动」）
  // 页内第一段就叫「主题模式」，索引也用它 —— 否则搜 dark / 深色 命中的是
  // 一条标题与分类名都叫「外观」的行，看不出它到底管什么。
  _SettingSearchEntry(
    "Theme Mode",
    2,
    subtitle: "Follow system, light, dark, AMOLED",
    keywords:
        "theme mode dark light amoled night black system 主题 外观 深色 浅色 暗色 夜间 纯黑",
  ),
  _SettingSearchEntry(
    "Theme Color",
    2,
    keywords: "color accent palette theme 颜色 配色 主题色",
  ),
  _SettingSearchEntry("Language", 8, keywords: "language locale 语言 語言 语言切换"),
  // 3 - Explore
  _SettingSearchEntry("Display mode of comic tile", 3),
  _SettingSearchEntry("Show recommendations on explore", 3),
  _SettingSearchEntry("Size of comic tile", 3),
  _SettingSearchEntry("Explore Pages", 3),
  _SettingSearchEntry("Category Pages", 3),
  _SettingSearchEntry("Network Favorite Pages", 3),
  _SettingSearchEntry("Search Sources", 3),
  _SettingSearchEntry("Show favorite status on comic tile", 3),
  _SettingSearchEntry("Show history on comic tile", 3),
  _SettingSearchEntry("Keyword blocking", 3),
  _SettingSearchEntry("Comment keyword blocking", 3),
  _SettingSearchEntry("Default Search Target", 3),
  _SettingSearchEntry("Auto Language Filters", 3),
  _SettingSearchEntry("Load mode of comic list", 3),
  // 4 - Local Favorites
  _SettingSearchEntry("Show local favorites before network favorites", 4),
  _SettingSearchEntry("Auto close favorite panel after operation", 4),
  _SettingSearchEntry("Add new favorite to", 4),
  _SettingSearchEntry("Move favorite after reading", 4),
  _SettingSearchEntry("Quick Favorite", 4),
  _SettingSearchEntry("Delete all unavailable local favorite items", 4),
  _SettingSearchEntry("Click favorite item", 4),
  _SettingSearchEntry("Home banner folders", 4),
  // 5 - Network
  _SettingSearchEntry("Proxy", 5, keywords: "proxy http socks 代理 代理服务器"),
  // 6 - Download & Import
  // 「CBZ 打包」「下载性能」两个小标题在合并时已并入「下载」组，索引里一并删掉，
  // 否则搜索结果会指向页面上早已不存在的小标题。
  _SettingSearchEntry(
    "Save chapters as CBZ",
    6,
    subtitle: "Package each chapter as .cbz file after download",
  ),
  _SettingSearchEntry(
    "Delete folder after CBZ packaging",
    6,
    subtitle: "Keep only the .cbz file, remove the original folder",
  ),
  _SettingSearchEntry("Download Threads", 6),
  _SettingSearchEntry("Import CBZ / ZIP / 7Z", 6),
  _SettingSearchEntry(
    "Import archives from folder",
    6,
    subtitle: "Batch import .cbz/.zip/.7z files",
  ),
  _SettingSearchEntry(
    "Import image folders",
    6,
    subtitle: "Import folders containing images as comics",
  ),
  // 7 - Data & backup ／ 8 - App & storage ／ 9 - Permissions
  _SettingSearchEntry("Move comics into storage path", 8),
  _SettingSearchEntry("Initial Page", 8),
  _SettingSearchEntry("Set New Storage Path", 8),
  _SettingSearchEntry("Move to Current Storage Path", 8),
  _SettingSearchEntry("All files access", 9),
  _SettingSearchEntry("Use Download/Comic", 9),
  _SettingSearchEntry("Notifications", 9),
  _SettingSearchEntry("Unrestricted battery usage", 9),
  _SettingSearchEntry("Install unknown apps", 9),
  _SettingSearchEntry("Clear Cache", 8),
  _SettingSearchEntry("Cache Limit", 8),
  _SettingSearchEntry("Export App Data", 7),
  _SettingSearchEntry("Import App Data", 7),
  _SettingSearchEntry(
    "Auto Backup",
    7,
    subtitle: "Periodically back up your data to the Download folder",
  ),
  _SettingSearchEntry("Auto-update comic sources", 7),
  _SettingSearchEntry("Backup Interval", 7),
  _SettingSearchEntry("Backup Retention", 7),
  _SettingSearchEntry("Back Up Now", 7),
  _SettingSearchEntry("Authorization Required", 7),
  _SettingSearchEntry(
    "Exit Confirmation",
    8,
    subtitle: "Ask before exiting via back gesture at root",
  ),
  _SettingSearchEntry("Webdav", 7, keywords: "webdav cloud sync 云同步 同步"),
  _SettingSearchEntry("Cloud Sync", 7, keywords: "webdav cloud sync 云同步 同步"),
  // 10 - About
  _SettingSearchEntry("Check for updates on startup", 10),
  _SettingSearchEntry("Mirror template", 10),
  _SettingSearchEntry("Download sources", 10),
];

/// 分类列表的三段分组，区间是半开区间 [start, end)。
///
/// 9 条分类平铺时只能靠顺序记忆；按「读的时候 / 存的时候 / 应用本身」切开后，
/// 段标题先给一个粗定位，再往下才是具体分类。分组只影响列表呈现，不改索引。
const List<(int, int, String)> _kCategorySections = [
  (0, 4, "Reading & display"),
  (4, 8, "Data & network"),
  (8, 11, "App & permissions"),
];

/// 分类列表的段标题。只承担「粗定位」，所以比分类行小一号、颜色更淡，
/// 不去和下面 9 条分类抢注意力；左右内缩与分类行的内容左缘对齐。
class _SettingSectionLabel extends StatelessWidget {
  const _SettingSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 3),
      child: Text(
        text,
        style: TextStyle(
          fontSize: kcCaption,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

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

  // 顺序必须与下面的 icons / _subtitles / _buildSettingsContent 完全一致。
  // 9 类：导入并入下载，语言并入 APP 的「通用」组。
  List<String> _categories() => [
    "Reading & images".tl,
    "Page & interface".tl,
    "Appearance".tl,
    "Explore".tl,
    "Local Favorites".tl,
    "Network".tl,
    "Download & Import".tl,
    "Data & backup".tl,
    "App & storage".tl,
    "Permissions".tl,
    "About".tl,
  ];

  final icons = <Widget>[
    HugeIcon(icon: HugeIcons.strokeRoundedBookOpen01, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedFlipHorizontal, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedColorPicker, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedCompass01, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedBookmark01, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedGlobe02, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedCloudBackup, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedAppStore, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedShieldKey, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, size: 24),
  ];

  List<String> _subtitles() => [
    "Reading mode, webtoon, image fit".tl,
    "Page turning, gestures, interface".tl,
    "Theme mode, theme color".tl,
    "Comic display, search sources, home".tl,
    "Local favorites management".tl,
    "Proxy server".tl,
    "Download tasks, CBZ, import".tl,
    "Backup & sync, account".tl,
    "Language, startup, storage, cache".tl,
    "Storage, notifications, background".tl,
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
      final kw = e.keywords?.toLowerCase() ?? '';
      if (t.contains(q) ||
          en.contains(q) ||
          sub.contains(q) ||
          kw.contains(q)) {
        out.add(e);
      }
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
          SizedBox(width: 280, height: double.infinity, child: buildLeft()),
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
          ),
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
          SizedBox(height: MediaQuery.of(context).padding.top),
          SizedBox(
            height: 56,
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
                    onPressed: context.pop,
                  ),
                ),
                const SizedBox(width: 16),
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
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
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
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: buildCategories()),
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
                color: selected
                    ? kcAccentColor(context).withValues(alpha: 0.3)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                HugeIcon(
                  icon: (icons[id] as HugeIcon).icon,
                  color: selected
                      ? kcBrandAdaptive(context)
                      : cs.onSurfaceVariant,
                  size: 24,
                ),
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
                  color: selected
                      ? kcBrandAdaptive(context)
                      : cs.onSurfaceVariant.withValues(alpha: 0.4),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final cats = _categories();
    final subs = _subtitles();
    final rows = <Widget>[];
    var covered = 0;
    for (final (start, end, label) in _kCategorySections) {
      rows.add(_SettingSectionLabel(label.tl));
      for (var i = start; i < end; i++) {
        rows.add(buildItem(cats[i], subs[i], i));
      }
      covered = end;
    }
    // 兜底：分段表写少了（新增分类却忘了改 _kCategorySections）时，剩下的
    // 分类仍然要出现 —— 否则那个页面会从根页静默消失，只能靠搜索才找得到。
    for (var i = covered; i < cats.length; i++) {
      rows.add(buildItem(cats[i], subs[i], i));
    }
    return ListView(
      padding: EdgeInsets.only(
        top: 4,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      children: rows,
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
      0 => const ReaderSettings(section: ReaderSettingsSection.reading),
      1 => const ReaderSettings(section: ReaderSettingsSection.turning),
      2 => const AppearanceSettings(),
      3 => const ExploreSettings(),
      4 => const LocalFavoritesSettings(),
      5 => const NetworkSettings(),
      6 => const DownloadSettings(),
      7 => const AppSettings(section: AppSettingsSection.data),
      8 => const AppSettings(section: AppSettingsSection.app),
      9 => const PermissionsSettings(),
      10 => const AboutSettings(),
      _ => throw UnimplementedError(),
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
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final e = results[index];
        final selected = !e.isCategory && currentPage == e.category;
        final mainText = e.title.tl;
        // 条目自带副标题时优先用它（如「外观」列出四个模式名）；
        // 没有才退回分类名。否则搜「外观」会出现标题与副标题同名的一行。
        final subText = e.isCategory
            ? subs[e.category].tl
            : (e.subtitle?.tl ?? cats[e.category].tl);
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
      0 => const ReaderSettings(section: ReaderSettingsSection.reading),
      1 => const ReaderSettings(section: ReaderSettingsSection.turning),
      2 => const AppearanceSettings(),
      3 => const ExploreSettings(),
      4 => const LocalFavoritesSettings(),
      5 => const NetworkSettings(),
      6 => const DownloadSettings(),
      7 => const AppSettings(section: AppSettingsSection.data),
      8 => const AppSettings(section: AppSettingsSection.app),
      9 => const PermissionsSettings(),
      10 => const AboutSettings(),
      _ => throw UnimplementedError(),
    };
  }
}
