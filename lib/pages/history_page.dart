import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/components/scroll_top_fab.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_type.dart';
import 'package:kong_comic/foundation/history.dart';
import 'package:kong_comic/foundation/listen_mixin.dart';
import 'package:kong_comic/pages/search_page.dart';
import 'package:kong_comic/pages/settings/settings_page.dart';
import 'package:kong_comic/utils/translations.dart';

/// 历史页：自绘整条顶栏（标题 + 工具胶囊条），故实现 [SelfTopBarPage]
/// 请求共享顶栏整体让位。此前靠 `main_page` 里硬编码的 `[1, 4]` 索引，
/// 底栏顺序一变就会指错页。
class HistoryPage extends StatefulWidget implements SelfTopBarPage {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with AutoListenMixin {
  @override
  void initState() {
    listen(HistoryManager(), onUpdate);
    // 自绘顶栏后，布局切换按钮（列表/网格）在历史页内部，需要跟着设置变化刷新图标。
    listen(appdata.settings, _onSettingsChanged);
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  /// 当前是否为详细列表模式（detailed）；否则为简洁网格（brief）。
  bool get _isDetailedLayout => appdata.settings['comicDisplayMode'] != 'brief';

  void _toggleLayout() {
    appdata.settings['comicDisplayMode'] = _isDetailedLayout
        ? 'brief'
        : 'detailed';
    appdata.saveData();
  }

  void onUpdate() {
    _gridKey.currentState?.refresh();
    if (multiSelectMode) {
      selectedComics.removeWhere((comic, _) => !_loadedComics.contains(comic));
      if (selectedComics.isEmpty) {
        setState(() {
          multiSelectMode = false;
        });
      }
    }
  }

  /// 退出搜索模式，恢复完整历史列表。
  void _exitSearch() {
    setState(() {
      searchMode = false;
      searchKeyword = '';
      searchController.clear();
    });
    _gridKey.currentState?.refresh();
  }

  /// 时间筛选选项与翻译标签
  static const _timeFilterList = ['all', 'today', '7d', '30d', 'earlier'];

  String _timeFilterLabel(String f) => switch (f) {
    'today' => "Today".tl,
    '7d' => "Last 7 days".tl,
    '30d' => "Last 30 days".tl,
    'earlier' => "Earlier".tl,
    _ => "All".tl,
  };

  void _showTimeFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: "Filter".tl,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            KcListTile(
              showDivider: false,
              title: Text("Time Range".tl),
              trailing: Select(
                minWidth: 120,
                current: _timeFilterLabel(_timeFilter),
                values: [for (var f in _timeFilterList) _timeFilterLabel(f)],
                onTap: (i) {
                  setState(() => _timeFilter = _timeFilterList[i]);
                  _gridKey.currentState?.refresh();
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Comics currently loaded by the paginated grid.
  List<History> _loadedComics = [];

  /// GlobalKey to access the paginated grid's state for refresh.
  final _gridKey = GlobalKey<PaginatedSliverGridComicsState>();

  /// Controls the scroll view so the FAB can scroll the list back to top.
  final ScrollController _scrollController = ScrollController();

  /// Page loader for PaginatedSliverGridComics.
  Future<List<Comic>> _loadPage(int offset, int limit) async {
    if (searchMode && searchKeyword.trim().isNotEmpty) {
      return HistoryManager().searchPaginated(
        searchKeyword.trim(),
        limit: limit,
        offset: offset,
      );
    }
    return HistoryManager().getAllPaginated(
      limit: limit,
      offset: offset,
      timeFilter: _timeFilter,
    );
  }

  /// 历史时间筛选：all/today/7d/30d/earlier
  String _timeFilter = 'all';

  bool multiSelectMode = false;

  /// 搜索模式与关键词
  bool searchMode = false;

  String searchKeyword = '';

  final searchController = TextEditingController();

  Map<History, bool> selectedComics = {};

  void selectAll() {
    // Load all history for selection (one-time operation).
    final allComics = HistoryManager().getAll();
    setState(() {
      selectedComics = allComics.asMap().map((k, v) => MapEntry(v, true));
    });
  }

  void deSelect() {
    setState(() {
      selectedComics.clear();
    });
  }

  void invertSelection() {
    setState(() {
      for (var v in _loadedComics) {
        if (selectedComics.containsKey(v)) {
          selectedComics.remove(v);
        } else {
          selectedComics[v] = true;
        }
      }
    });
  }

  void _removeHistory(History comic) {
    if (comic.sourceKey.startsWith("Unknown")) {
      HistoryManager().remove(
        comic.id,
        ComicType(
          int.tryParse(comic.sourceKey.split(':').elementAtOrNull(1) ?? '') ??
              0,
        ),
      );
    } else if (comic.sourceKey == 'local') {
      HistoryManager().remove(comic.id, ComicType.local);
    } else {
      HistoryManager().remove(comic.id, ComicType(comic.sourceKey.hashCode));
    }
  }

  void _refreshHistory(History comic) async {
    var result = await HistoryManager().refreshHistoryInfo(comic);
    if (result) {
      if (mounted) {
        App.rootContext.showMessage(message: "Refresh Success".tl);
      }
    } else {
      if (mounted) {
        App.rootContext.showMessage(message: "Refresh Failed".tl);
      }
    }
  }

  void _refreshAllHistories() async {
    bool isCanceled = false;
    void onCancel() {
      isCanceled = true;
    }

    var loadingController = showLoadingDialog(
      App.rootContext,
      withProgress: true,
      cancelButtonText: "Cancel".tl,
      onCancel: onCancel,
      message: "Refreshing Histories".tl,
    );

    int success = 0;
    int failed = 0;
    int skipped = 0;

    await for (var progress in HistoryManager().refreshAllHistoriesStream()) {
      if (isCanceled) {
        return;
      }
      if (progress.total > 0) {
        loadingController.setProgress(progress.current / progress.total);
      }
      success = progress.success;
      failed = progress.failed;
      skipped = progress.skipped;
    }

    loadingController.close();

    if (mounted) {
      App.rootContext.showMessage(
        message:
            "Refresh Completed: Success @success, Failed @failed, Skipped @skipped"
                .tlParams({
                  'success': success,
                  'failed': failed,
                  'skipped': skipped,
                }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !multiSelectMode && !searchMode,
      onPopInvokedWithResult: (didPop, result) {
        if (multiSelectMode) {
          setState(() {
            multiSelectMode = false;
            selectedComics.clear();
          });
        } else if (searchMode) {
          _exitSearch();
        }
      },
      child: Scaffold(
        body: SmoothCustomScrollView(
          controller: _scrollController,
          slivers: [
            // 历史页顶栏（标题 + 工具胶囊条）由本页自绘，与收藏页同一套外观。
            // 共享顶栏已通过 NaviPane.topBarHiddenPages 对历史页整条让位，
            // 因此标题也在这里承担，避免出现「两排工具栏」。
            SliverAppbar(
              title: multiSelectMode
                  ? Text(
                      "Selected @c comics".tlParams({
                        "c": selectedComics.length,
                      }),
                    )
                  : Text("History".tl),
              actions: multiSelectMode
                  ? _multiSelectActions()
                  : _normalActions(),
            ),
            PaginatedSliverGridComics(
              key: _gridKey,
              pageLoader: _loadPage,
              selections: selectedComics,
              showSourceOnCover: false,
              badgeAsTopLeftSource: true,
              onLoadedComicsChanged: (comics) {
                _loadedComics = comics.cast<History>();
              },
              onLongPressed: null,
              onTap: multiSelectMode
                  ? (c, heroID) {
                      setState(() {
                        if (selectedComics.containsKey(c as History)) {
                          selectedComics.remove(c);
                        } else {
                          selectedComics[c] = true;
                        }
                        if (selectedComics.isEmpty) {
                          multiSelectMode = false;
                        }
                      });
                    }
                  : null,
              badgeBuilder: (c) {
                return ComicSource.find(c.sourceKey)?.name;
              },
              badgeColorBuilder: (c) {
                final brightness = Theme.of(context).brightness;
                final amoled = appdata.isAmoledMode;
                return kcTagColor(
                  kcStableHash(c.sourceKey),
                  brightness,
                  amoled: amoled,
                );
              },
              menuBuilder: (c) {
                return [
                  MenuEntry(
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedRefresh,
                      size: 18,
                    ),
                    text: 'Refresh Info'.tl,
                    onClick: () {
                      _refreshHistory(c as History);
                    },
                  ),
                  MenuEntry(
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      size: 18,
                    ),
                    text: 'Remove'.tl,
                    color: context.colorScheme.error,
                    onClick: () {
                      _removeHistory(c as History);
                    },
                  ),
                ];
              },
            ),
          ],
        ),
        floatingActionButton: _buildScrollTopFab(),
      ),
    );
  }

  /// 正常模式操作：布局 / 筛选 / 多选 / 更多（刷新全部·清空历史）。
  /// 外观与收藏页完全一致（[ToolsPill]）：胶囊条 + 中性图标，红只用于「筛选已启用」。
  /// 共享顶栏已对历史页让位，所以「列表/网格切换」由这里承担；
  /// 清空/刷新是低频且危险/耗时的动作，收进「更多」菜单。
  List<Widget> _normalActions() => [
    const SizedBox(width: 12),
    ToolsPill(
      children: [
        // 布局切换做成双态分段：左侧「网格(简明)」、右侧「列表(详细)」，
        // 当前布局高亮 accent 红。比原来「单图标 + 图标随状态反转」直观得多。
        ToolsPillSegment(
          icons: const [
            HugeIcons.strokeRoundedGridView,
            HugeIcons.strokeRoundedListView,
          ],
          tooltips: ["Switch to grid view".tl, "Switch to list view".tl],
          selectedIndex: _isDetailedLayout ? 1 : 0,
          onSelected: (_) => _toggleLayout(),
        ),
        ToolsPillButton(
          icon: HugeIcons.strokeRoundedSortDescending,
          tooltip: "Filter".tl,
          active: _timeFilter != 'all',
          onPressed: _showTimeFilterDialog,
        ),
        ToolsPillButton(
          icon: HugeIcons.strokeRoundedCheckList,
          tooltip: "Multi-Select".tl,
          onPressed: () => setState(() => multiSelectMode = true),
        ),
        ToolsPillMoreButton(
          entries: [
            MenuEntry(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
              text: "Refresh All Histories".tl,
              onClick: _refreshAllHistories,
            ),
            MenuEntry(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
              text: "Clear History".tl,
              color: context.colorScheme.error,
              onClick: _confirmClearHistory,
            ),
            // 历史页自绘顶栏后，全局共享顶栏的「搜索 / 设置」入口随之让位；
            // 这两个是全局功能，不该在历史页彻底消失，收进「更多」兜底。
            MenuEntry(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedSearch02, size: 18),
              text: "Search".tl,
              onClick: () => context.to(() => const SearchPage()),
            ),
            MenuEntry(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings01, size: 18),
              text: "Settings".tl,
              onClick: () => context.to(() => const SettingsPage()),
            ),
          ],
        ),
      ],
    ),
  ];

  /// 多选模式操作：全选 / 删除 / 更多(反选·取消) / 退出。
  List<Widget> _multiSelectActions() => [
    const SizedBox(width: 12),
    ToolsPill(
      children: [
        ToolsPillButton(
          icon: HugeIcons.strokeRoundedCheckList,
          tooltip: "Select All".tl,
          onPressed: selectAll,
        ),
        ToolsPillButton(
          icon: HugeIcons.strokeRoundedDelete01,
          tooltip: "Delete".tl,
          color: context.colorScheme.error,
          onPressed: _deleteSelected,
        ),
        ToolsPillMoreButton(
          entries: [
            MenuEntry(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedFlipHorizontal,
                size: 18,
              ),
              text: "Invert Selection".tl,
              onClick: invertSelection,
            ),
            MenuEntry(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
              text: "Deselect".tl,
              onClick: deSelect,
            ),
          ],
        ),
        ToolsPillButton(
          icon: HugeIcons.strokeRoundedCancel01,
          tooltip: "Exit Multi-Select".tl,
          onPressed: () => setState(() {
            multiSelectMode = false;
            selectedComics.clear();
          }),
        ),
      ],
    ),
  ];

  /// Scroll-to-top FAB，样式与发现页完全一致（统一组件）。
  Widget _buildScrollTopFab() {
    return ScrollTopFab(
      avoidNavBar: true,
      heroTag: 'historyScrollTopFab',
      onPressed: () {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      },
    );
  }

  void _deleteSelected() {
    if (selectedComics.isEmpty) return;
    final comicsToDelete = List<History>.from(selectedComics.keys);
    setState(() {
      multiSelectMode = false;
      selectedComics.clear();
    });
    for (final comic in comicsToDelete) {
      _removeHistory(comic);
    }
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: 'Clear History'.tl,
        contentPadding: ContentDialog.hPadding,
        content: Text('Are you sure you want to clear your history?'.tl),
        actions: [
          Button.text(
            onPressed: () {
              HistoryManager().clearUnfavoritedHistory();
              Navigator.of(dialogContext).pop();
            },
            child: Text('Clear Unfavorited'.tl),
          ),
          Button.filled(
            onPressed: () {
              HistoryManager().clearHistory();
              Navigator.of(dialogContext).pop();
            },
            child: Text('Clear'.tl),
          ),
        ],
      ),
    );
  }

  String getDescription(History h) {
    var res = "";
    if (h.ep >= 1) {
      res += "Chapter @ep".tlParams({"ep": h.ep});
    }
    if (h.page >= 1) {
      if (h.ep >= 1) {
        res += " - ";
      }
      res += "Page @page".tlParams({"page": h.page});
    }
    return res;
  }
}
