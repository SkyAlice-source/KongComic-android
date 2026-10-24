import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/components/scroll_top_fab.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_type.dart';
import 'package:kong_comic/foundation/history.dart';
import 'package:kong_comic/foundation/listen_mixin.dart';
import 'package:kong_comic/pages/comic_details_page/comic_page.dart';
import 'package:kong_comic/pages/favorites/favorites_page.dart';
import 'package:kong_comic/utils/translations.dart';

/// 历史页：顶栏改用 NaviPane 共享顶栏（[NaviPane.buildTop]），不再自绘
/// SliverAppbar。页面通过 [NaviPane.pageActionsNotifier] / [NaviPane.pageTitleNotifier]
/// 注入本页专属操作（筛选 / 多选 / 更多）与动态标题（多选态「已选 N 项」），
/// 全局操作（布局切换 / 搜索 / 设置）由共享 [paneActions] 提供，避免重复。
class HistoryPage extends StatefulWidget {
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

  void onUpdate() {
    _gridKey.currentState?.refresh();
    // 分组列表的数据在 build 里现算，数据变化靠 setState 重建。
    if (mounted) setState(() {});
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
    // 把本页顶栏操作 / 标题同步进 NaviPane 共享顶栏（带签名守卫，避免成环）。
    _syncTopBar();
    final useBriefGrid = appdata.settings['comicDisplayMode'] == 'brief';
    final showHero =
        !multiSelectMode && !searchMode && _timeFilter == 'all';
    final continueHistory = showHero ? _fetchHistories().firstOrNull : null;
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
            // 方案 A：续读英雄卡 —— 主页英雄卡语言的移植，取最近一条历史。
            if (continueHistory != null)
              SliverToBoxAdapter(
                child: KcContinueHero(
                  history: continueHistory,
                  onOpen: () => _openComic(continueHistory, -1),
                ),
              ),
            if (useBriefGrid)
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
                menuBuilder: (c) => _tileMenu(c as History),
              )
            else
              ..._groupedSlivers(),
          ],
        ),
        floatingActionButton: _buildScrollTopFab(),
      ),
    );
  }

  /// 取当前筛选 / 搜索下的历史（time DESC），上限 300 条（分组列表一次性
  /// 渲染，sqlite 全量查询毫秒级；上限防极端大库）。
  List<History> _fetchHistories() {
    List<History> res;
    if (searchMode && searchKeyword.trim().isNotEmpty) {
      res = HistoryManager().searchPaginated(
        searchKeyword.trim(),
        limit: 300,
        offset: 0,
      );
    } else {
      res = HistoryManager().getAllPaginated(
        limit: 300,
        offset: 0,
        timeFilter: _timeFilter,
      );
    }
    return res;
  }

  int _heroIDCounter = 0;

  void _openComic(History h, int heroID) {
    if (multiSelectMode) {
      setState(() {
        if (selectedComics.containsKey(h)) {
          selectedComics.remove(h);
        } else {
          selectedComics[h] = true;
        }
        if (selectedComics.isEmpty) {
          multiSelectMode = false;
        }
      });
      return;
    }
    App.mainNavigatorKey?.currentContext?.to(
      () => ComicPage(
        id: h.id,
        sourceKey: h.sourceKey,
        cover: h.cover,
        title: h.title,
        heroID: heroID,
      ),
    );
  }

  List<MenuEntry> _tileMenu(History h) {
    return [
      // 高频动作置顶：看到想收的漫画直接收藏，不用绕进详情页。
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedFavourite, size: 18),
        text: "Add to favorites".tl,
        onClick: () => addFavorite([h]),
      ),
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
        text: 'Refresh Info'.tl,
        onClick: () => _refreshHistory(h),
      ),
      // 破坏性操作用分隔线隔离，避免和普通动作连排误触。
      MenuEntry.divider(),
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
        text: 'Remove'.tl,
        color: context.colorScheme.error,
        onClick: () => _removeHistory(h),
      ),
    ];
  }

  /// 时间分组：今天 / 昨天 / 本周（近 7 天，不含今昨）/ 更早。
  List<(String, List<History>)> _groupHistories() {
    final all = _fetchHistories();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final todayList = <History>[];
    final yesterdayList = <History>[];
    final weekList = <History>[];
    final earlierList = <History>[];
    for (final h in all) {
      final day = DateTime(h.time.year, h.time.month, h.time.day);
      if (!day.isBefore(today)) {
        todayList.add(h);
      } else if (!day.isBefore(yesterday)) {
        yesterdayList.add(h);
      } else if (!day.isBefore(weekAgo)) {
        weekList.add(h);
      } else {
        earlierList.add(h);
      }
    }
    return [
      if (todayList.isNotEmpty) ("Today".tl, todayList),
      if (yesterdayList.isNotEmpty) ("Yesterday".tl, yesterdayList),
      if (weekList.isNotEmpty) ("This week".tl, weekList),
      if (earlierList.isNotEmpty) ("Earlier".tl, earlierList),
    ];
  }

  /// 相对时间标签：今天=时刻，昨天/更早=日期（无需 i18n）。
  String _timeLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    if (!day.isBefore(today)) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    final diffDays = today.difference(day).inDays;
    if (diffDays == 1) return "Yesterday".tl;
    if (t.year == now.year) {
      return '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    }
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  /// 方案 A：时间分组流 —— 每组「吸顶胶囊组头 + 紧凑历史行」。
  List<Widget> _groupedSlivers() {
    final groups = _groupHistories();
    if (groups.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedClock01, size: 18),
            title: 'No comics'.tl,
            subtitle:
                "No comics yet? Add a comic source or favorite some comics.".tl,
          ),
        ),
      ];
    }
    _loadedComics = [for (final g in groups) ...g.$2];
    return [
      for (final g in groups)
        SliverMainAxisGroup(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: KcGroupHeaderDelegate(label: g.$1, count: g.$2.length),
            ),
            SliverList.builder(
              itemCount: g.$2.length,
              itemBuilder: (context, i) {
                final h = g.$2[i];
                return KcHistoryTile(
                  history: h,
                  selected: selectedComics[h] ?? false,
                  timeLabel: _timeLabel(h.time),
                  onTap: () => _openComic(h, _heroIDCounter++),
                  menuOptions: multiSelectMode ? null : _tileMenu(h),
                );
              },
            ),
          ],
        ),
    ];
  }

  /// 顶栏同步签名：仅当「模式 / 筛选 / 选中数」变化时写 notifier，避免每次
  /// build 都触发 NaviPane 重建（NaviPane 重建又会让本页 rebuild，靠守卫切断成环）。
  String? _topBarSig;

  /// 把本页顶栏标题 / 操作同步进 NaviPane 共享顶栏（[NaviPane.buildTop]）。
  ///
  /// 历史页不再自绘 SliverAppbar，改用共享顶栏后必须主动注入。正常态标题为
  /// null（回退到共享栏的「History」静态标签）；多选态显示「已选 N 项」。
  /// 操作正常态为 [筛选 / 多选 / 更多]，多选态为 [全选 / 删除 / 更多 / 退出]；
  /// 布局切换 / 搜索 / 设置由共享 [paneActions] 提供，这里不再重复。
  /// 本页在 NaviPane 底栏里的索引（首次 build 时记录）。用于判断本页是否处于
  /// 前台：切到别的 tab 后要把签名清空，否则切回来时签名仍命中、不会重新注入，
  /// 顶栏操作就丢了（[NaviPane.updatePage] 会在换页时把 notifier 重置为 null）。
  int? _myPageIndex;

  /// 把本页顶栏标题 / 操作同步进 NaviPane 共享顶栏（[NaviPane.buildTop]）。
  ///
  /// 关键：不能在 [build] 阶段直接写 notifier —— 写值会同步触发监听器的
  /// `setState`，而此时 [NaviPane] 自身正在 build，等于「build 期间 setState」，
  /// 框架会丢弃这次重建，导致顶栏操作永远不出现。所以实际写值延迟到本帧结束
  /// 后（post-frame），那时再触发 [NaviPane] 重建就安全了。写之前再校验仍在本页，
  /// 防止「刚切走、残留的回调」把历史页操作污染到别的 tab 顶栏。
  void _syncTopBar() {
    final pane = NaviPane.of(context);
    _myPageIndex ??= pane.currentPage;
    if (pane.currentPage != _myPageIndex) {
      // 本页不在前台：清空签名，下次切回能重新注入。
      _topBarSig = null;
      return;
    }
    final sig =
        '${multiSelectMode ? 'ms' : 'n'}_${_timeFilter}_${selectedComics.length}';
    if (_topBarSig == sig) return;
    _topBarSig = sig;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _myPageIndex == null) return;
      if (pane.currentPage != _myPageIndex) return;
      // 标题已升级为 Widget：多选态注入与共享栏样式一致的粗体文本。
      pane.pageTitleNotifier.value = multiSelectMode
          ? Text(
              "Selected @c comics".tlParams({'c': selectedComics.length}),
              style: TextStyle(
                fontSize: kcTitleMain,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            )
          : null;
      pane.pageActionsNotifier.value =
          multiSelectMode ? _multiSelectActions() : _normalActions();
    });
  }

  /// 右上角「更多」：图标按钮样式与共享顶栏一致，菜单沿用全站 [showMenuX]。
  Widget _moreButton(List<MenuEntry> entries) {
    return Builder(
      builder: (ctx) => IconButton(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical, size: 22),
        tooltip: "More".tl,
        onPressed: () {
          final rb = ctx.findRenderObject() as RenderBox;
          showMenuX(ctx, rb.localToGlobal(Offset.zero), entries);
        },
      ),
    );
  }

  /// 正常模式操作：筛选 / 更多（多选·刷新全部·清空历史）。
  ///
  /// 外观与共享顶栏一致 —— 平铺的 [IconButton]，不再套「工具胶囊条」容器：
  /// 胶囊条是列表内的临时工具栏，出现在根 tab 的 20pt 粗体标题旁边，会让历史页
  /// 在几个 tab 之间显得不是一套。红只用于「状态」（筛选非默认时点亮）。
  /// 布局切换 / 搜索 / 设置由共享 [paneActions] 提供，这里不再重复。
  /// 多选是低频动作，收进「更多」菜单，普通态只留两个图标。
  List<Widget> _normalActions() => [
    IconButton(
      icon: HugeIcon(icon: HugeIcons.strokeRoundedFilter, size: 22),
      color: _timeFilter != 'all' ? kcAccentColor(context) : null,
      tooltip: "Filter".tl,
      onPressed: _showTimeFilterDialog,
    ),
    _moreButton([
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedCheckList, size: 18),
        text: "Multi-Select".tl,
        onClick: () => setState(() => multiSelectMode = true),
      ),
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
        text: "Refresh All Histories".tl,
        onClick: _refreshAllHistories,
      ),
      // 破坏性操作用分隔线隔离。
      MenuEntry.divider(),
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
        text: "Clear History".tl,
        color: context.colorScheme.error,
        onClick: _confirmClearHistory,
      ),
    ]),
  ];

  /// 多选模式操作：全选 / 删除 / 更多(反选·取消) / 退出。
  List<Widget> _multiSelectActions() => [
    IconButton(
      icon: HugeIcon(icon: HugeIcons.strokeRoundedCheckList, size: 22),
      tooltip: "Select All".tl,
      onPressed: selectAll,
    ),
    IconButton(
      icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 22),
      color: context.colorScheme.error,
      tooltip: "Delete".tl,
      onPressed: _deleteSelected,
    ),
    _moreButton([
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedFlipHorizontal, size: 18),
        text: "Invert Selection".tl,
        onClick: invertSelection,
      ),
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
        text: "Deselect".tl,
        onClick: deSelect,
      ),
    ]),
    IconButton(
      icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 22),
      tooltip: "Exit Multi-Select".tl,
      onPressed: () => setState(() {
        multiSelectMode = false;
        selectedComics.clear();
      }),
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
