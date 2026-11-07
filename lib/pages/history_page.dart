import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/components/quick_search.dart';
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
/// 注入本页专属操作与动态标题（多选态「已选 N 项」）。
///
/// 顶栏极简后：正常态右上角只有一枚**裸搜索**图标（不套 [ToolsPill]，因此
/// 没有胶囊外壳与发丝描边）。其余入口全部放到内容区且默认可见：
///   · 筛选状态 → 第一行常驻 chip 行（有文字证据 + 结果数/重置）
///   · 布局切换 → 第二行固定位 [ToolsPillLayoutButton]，与发现页右上角
///     那颗全站共用按钮同一个组件：点一下直接切换，不再另造弹窗 / 分段
///   · 第二行辅助操作 → 多选 / 刷新全部 / 清空历史 平铺成裸图标按钮
///     （位置够就不藏 ⋮；窄屏 / 大字号放不下时末尾几枚才收拢）
///   · 多选动作 → 贴底工具条；重载列表 → 下拉刷新
/// 多选态顶栏清空。全局 paneActions 隐藏（pageHideGlobalActions）。
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
    _paneIndex?.removeListener(_onPaneIndexChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void onUpdate() {
    _gridKey.currentState?.refresh();
    _invalidateGroups();
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

  /// 时间筛选选项与翻译标签
  static const _timeFilterList = ['all', 'today', '7d', '30d', 'earlier'];

  String _timeFilterLabel(String f) => switch (f) {
    'today' => "Today".tl,
    '7d' => "Last 7 days".tl,
    '30d' => "Last 30 days".tl,
    'earlier' => "Earlier".tl,
    _ => "All".tl,
  };

  /// 布局切换不再有第二个入口：辅助行固定位直接放 [ToolsPillLayoutButton]，
  /// 与发现页右上角那颗全站共用的是**同一个组件**，读同一个
  /// `appdata.settings['comicDisplayMode']`。图标表示当前布局，点一下直接
  /// 切成另一种，不用再点开「排列方式」弹窗选一次。
  ///
  /// 时间筛选是第一行常驻 chip，结果数与重置在辅助行左侧，布局不该和它们
  /// 混在一个面板里 —— 筛选状态只存一份，排列方式也只留一颗按钮。

  /// 内容区辅助行的**全部**动作：默认一枚枚平铺出来，不再藏进 ⋮ 菜单。
  /// 顺序即优先级 —— 宽度不够时末尾的破坏性动作先被收拢，不会退化成
  /// 「一排常驻红图标」；清空历史本身仍带二次确认弹窗。
  /// 「多选」恢复为可见入口，长按任意一条历史同样能进，是两条并行路径。
  List<KcToolbarAction> _actionItems() => [
    KcToolbarAction(
      icon: HugeIcons.strokeRoundedCheckList,
      label: "Multi-Select".tl,
      onTap: () => setState(() => multiSelectMode = true),
    ),
    KcToolbarAction(
      icon: HugeIcons.strokeRoundedRefresh,
      label: "Refresh All Histories".tl,
      onTap: _refreshAllHistories,
    ),
    KcToolbarAction(
      icon: HugeIcons.strokeRoundedDelete01,
      label: "Clear History".tl,
      color: context.colorScheme.error,
      onTap: _confirmClearHistory,
    ),
  ];

  void _pickTimeFilter(String f) {
    if (f == _timeFilter) return;
    _invalidateGroups();
    setState(() => _timeFilter = f);
    _gridKey.currentState?.refresh();
  }

  void _resetTimeFilter() {
    if (_timeFilter == 'all') return;
    _invalidateGroups();
    setState(() => _timeFilter = 'all');
    _gridKey.currentState?.refresh();
  }

  /// B · 内容区常驻的时间筛选 chip 行：当前筛选有文字证据，带结果数与重置。
  /// 第二行固定位是发现页同款的一键布局切换，其余 多选 / 刷新 / 清空历史
  /// 平铺成常驻按钮，只有窄屏 / 大字号放不下时末尾几枚才自动收进 ⋮。
  Widget _buildFilterChips() {
    return KcFilterChipRow(
      chips: [
        for (final f in _timeFilterList)
          KcFilterChipData(
            label: _timeFilterLabel(f),
            selected: _timeFilter == f,
            onTap: () => _pickTimeFilter(f),
          ),
      ],
      resultCount: _resultCount,
      onReset: _timeFilter == 'all' ? null : _resetTimeFilter,
      // 与发现页右上角完全同一个组件；高频且本身不需要 ⋮，固定占位不收拢。
      fixedActions: [const ToolsPillLayoutButton()],
      actions: _actionItems(),
    );
  }

  /// D · 长按任意一条历史进入多选，并顺手选中被按住的那条。
  void _enterMultiSelect(Comic c) {
    if (c is! History) return;
    setState(() {
      multiSelectMode = true;
      selectedComics[c] = true;
    });
  }

  /// D · 下拉刷新重载本地列表（快速、符合手势预期）。
  ///
  /// 「刷新全部历史」是逐条联网更新漫画信息的重操作，仍作为内容区辅助行
  /// 的常驻按钮可见，没有因为引入下拉手势就把功能藏起来。
  Future<void> _onPullRefresh() async {
    _invalidateGroups();
    _gridKey.currentState?.refresh();
    if (mounted) setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 220));
  }

  /// Comics currently loaded by the paginated grid.
  List<History> _loadedComics = [];

  /// GlobalKey to access the paginated grid's state for refresh.
  final _gridKey = GlobalKey<PaginatedSliverGridComicsState>();

  /// Controls the scroll view so the FAB can scroll the list back to top.
  final ScrollController _scrollController = ScrollController();

  /// Page loader for PaginatedSliverGridComics.
  Future<List<Comic>> _loadPage(int offset, int limit) async {
    return HistoryManager().getAllPaginated(
      limit: limit,
      offset: offset,
      timeFilter: _timeFilter,
    );
  }

  /// 历史时间筛选：all/today/7d/30d/earlier
  String _timeFilter = 'all';

  /// 分组列表缓存（见 [_groupHistories]）。数据或筛选变化时必须清空。
  List<(String, List<History>)>? _groupCache;

  /// 「显示 N 项」的结果数缓存：chip 行在 sliver 列表的最前面构建，那时
  /// 网格的 onLoadedComicsChanged 还没回来，直接读 [_loadedComics] 会先显示 0。
  /// 与分组缓存同源失效，避免为了一个数字每次 build 全量查 300 条。
  int? _countCache;

  int get _resultCount => _countCache ??= _fetchHistories().length;

  void _invalidateGroups() {
    _groupCache = null;
    _countCache = null;
  }

  bool multiSelectMode = false;

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
    final showHero = !multiSelectMode && _timeFilter == 'all';
    // 续读卡只要最近一条：limit 1 直接查，别为取头部去翻 300 行。
    final continueHistory = showHero
        ? _fetchHistories(limit: 1).firstOrNull
        : null;
    // 库页面不显示「已收藏」角标（见 FavoriteBadgeScope 文档）；
    // 阅读进度角标保留——历史页正需要它。
    return FavoriteBadgeScope.disabled(
      child: PopScope(
        canPop: !multiSelectMode,
        onPopInvokedWithResult: (didPop, result) {
          if (multiSelectMode) {
            setState(() {
              multiSelectMode = false;
              selectedComics.clear();
            });
          }
        },
        child: Scaffold(
          // 骨架归一：hero 与网格共用 900dp 内容列并居中，平板不再出现
          // 「7 列后孤行 + 右半空白」。手机宽度不足 900，等价于不约束。
          // 多选态把工具条贴到底部（浮岛 dock 上方），所以外层用 Stack。
          body: Stack(
            children: [
              KcPageContent(
                child: RefreshIndicator(
                  onRefresh: _onPullRefresh,
                  child: SmoothCustomScrollView(
                    controller: _scrollController,
                    // 下拉刷新在空历史 / 筛选无结果时也要能触发；末尾留白让
                    // 最后一行能滚到浮岛 dock（多选时还有贴底工具条）之上。
                    alwaysScrollable: true,
                    bottomPadding:
                        kcPageBottomInset(context) +
                        kcDockedToolbarLift +
                        (multiSelectMode ? kcMinTapTarget + kcSpaceMd : 0.0),
                    slivers: [
                      // 方案 A：续读英雄卡 —— 主页英雄卡语言的移植，取最近一条历史。
                      if (continueHistory != null)
                        SliverToBoxAdapter(
                          child: KcContinueHero(
                            history: continueHistory,
                            onOpen: () => _openComic(continueHistory, -1),
                          ),
                        ),
                      // 方案 B：筛选状态常驻内容区，选中态 + 结果数 + 重置
                      // 都有文字证据；多选态收起，把高度让给列表。
                      if (!multiSelectMode)
                        SliverToBoxAdapter(child: _buildFilterChips()),
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
                          // 方案 D：长按直接进入多选并选中该项；辅助行的
                          // 常驻「多选」按钮是另一条更显式的路径。
                          onLongPressed: (c, heroID) => _enterMultiSelect(c),
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
                ),
              ),
              if (multiSelectMode)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: kcPageBottomInset(context) + kcDockedToolbarLift,
                  child: KcDockedToolbar(
                    selectedCount: selectedComics.length,
                    actions: _multiSelectActions(),
                    onExit: _exitMultiSelect,
                  ),
                ),
            ],
          ),
          // 多选态隐藏回到顶部的 FAB，避免和贴底工具条/手势抢位置。
          floatingActionButton:
              multiSelectMode ? null : _buildScrollTopFab(),
        ),
      ),
    );
  }

  /// 取当前时间筛选下的历史（time DESC）。
  ///
  /// 默认上限 300 条（分组列表一次性渲染，sqlite 全量查询毫秒级；上限防极端大库）。
  /// 只要「最近一条」时必须显式传 `limit: 1` —— 否则每次 build 都会把 300 条
  /// 全查出来再 `firstOrNull`，而 [History.fromRow] 还要逐条解析 readEpisode。
  ///
  /// 页内关键词搜索已由速搜浮层取代（见 [showQuickSearch]），这里只剩时间筛选。
  List<History> _fetchHistories({int limit = 300}) {
    final res = HistoryManager().getAllPaginated(
      limit: limit,
      offset: 0,
      timeFilter: _timeFilter,
    );
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
  ///
  /// 结果缓存在 [_groupCache]：本方法每次 build 都要读 300 条历史并逐条解析
  /// readEpisode（见 [History.fromRow]），而多选态每点一张卡片就是一次 setState
  /// → 点一下等于一次 300 行全量查询。数据/筛选变化时由 [_invalidateGroups] 清掉。
  List<(String, List<History>)> _groupHistories() =>
      _groupCache ??= _computeGroups();

  List<(String, List<History>)> _computeGroups() {
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
                  // 多选态逐行卡片化：每本一圈独立描边 + 选中勾标，
                  // 与网格视图 / 收藏页的 _SelectableComicCell 一致。
                  showSelectionFrame: multiSelectMode,
                  timeLabel: _timeLabel(h.time),
                  onTap: () => _openComic(h, _heroIDCounter++),
                  // 方案 D：列表布局同样支持长按进入多选。
                  onLongPressed: () => _enterMultiSelect(h),
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
/// 操作正常态只留一枚裸搜索图标，多选态顶栏清空（动作移到贴底工具条）；
/// 同时隐藏共享 [paneActions]，避免顶栏再散出另一圈全局图标。
/// 发现页同款的一键布局切换 + 多选 / 刷新 / 清空历史放在内容区辅助行，
/// 重载走下拉手势。
  /// 本页在 NaviPane 底栏里的索引（首次 build 时记录）。用于判断本页是否处于
  /// 前台：切到别的 tab 后要把签名清空，否则切回来时签名仍命中、不会重新注入，
  /// 顶栏操作就丢了（[NaviPane.updatePage] 会在换页时把 notifier 重置为 null）。
  int? _myPageIndex;

  /// 上一次真正写进顶栏的组件实例。换 tab 时 [NaviPane.updatePage] 会把
  /// notifier 重置为 null，而本页未被销毁时签名仍在，仅靠签名早退会让
  /// 切回来的顶栏操作补不回来。除签名外再确认顶栏里仍是上次写入的实例。
  Widget? _injectedTitle;
  List<Widget>? _injectedActions;

  /// NaviPane 当前页索引通知（本页据此在「切回前台」时补注入顶栏）。
  NaviPaneState? _pane;
  ValueNotifier<int>? _paneIndex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pane = NaviPane.of(context);
    if (!identical(_pane, pane)) {
      _paneIndex?.removeListener(_onPaneIndexChanged);
      _pane = pane;
      _paneIndex = pane.pageIndexListenable;
      _paneIndex!.addListener(_onPaneIndexChanged);
    }
  }

  /// 换 tab 时 [NaviPaneState.updatePage] 会清空顶栏 notifier，而本页实例
  /// 未被销毁；根 Tab 的页面 widget 是同一个 const 实例，框架会跳过重建，
  /// [build] 不跑 → [_syncTopBar] 没机会补回，顶栏操作就永久消失。
  /// 切回前台时强制重建一次，让 [_syncTopBar] 的实例校验触发重新注入。
  void _onPaneIndexChanged() {
    if (!mounted || _pane == null) return;
    if (_pane!.currentPage != _myPageIndex) return;
    setState(() {});
  }

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
    final stillInjected =
        identical(pane.pageActionsNotifier.value, _injectedActions) &&
        identical(pane.pageTitleNotifier.value, _injectedTitle);
    if (_topBarSig == sig && stillInjected) return;
    _topBarSig = sig;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _myPageIndex == null) return;
      if (pane.currentPage != _myPageIndex) return;
      // 标题已升级为 Widget：多选态注入与共享栏样式一致的粗体文本。
      final title = multiSelectMode
          ? Text(
              "Selected @c comics".tlParams({'c': selectedComics.length}),
              style: TextStyle(
                fontSize: kcTitleMain,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            )
          : null;
      // 方案 C：多选态顶栏不留任何动作，全部交给贴底工具条（单手可达）。
      final actions = multiSelectMode
          ? const <Widget>[]
          : _normalActions();
      _injectedTitle = title;
      _injectedActions = actions;
      pane.pageTitleNotifier.value = title;
      // 顶栏只留本页那一枚裸搜索（_normalActions），全局 paneActions
      // （布局/搜索/设置）随之隐藏，避免旁边再散一圈图标。
      // 换 tab 时 updatePage 会把该开关复位为 false，无需清理。
      pane.pageHideGlobalActionsNotifier.value = true;
      pane.pageActionsNotifier.value = actions;
    });
  }

  /// 「更多」：裸图标按钮（无边框），菜单沿用全站 [showMenuX]。
  /// 普通态辅助行动作已全部平铺，这里只服务于多选态贴底工具条的
  /// 「反选 / 取消选择」；窄屏下辅助行自动收拢用的是组件自带的 ⋮。
  Widget _moreButton(List<MenuEntry> entries) {
    return Builder(
      builder: (ctx) => IconButton(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical, size: 22),
        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
        tooltip: "More".tl,
        constraints: const BoxConstraints(
          minWidth: kcMinTapTarget,
          minHeight: kcMinTapTarget,
        ),
        padding: EdgeInsets.zero,
        onPressed: () {
          final rb = ctx.findRenderObject() as RenderBox;
          showMenuX(ctx, rb.localToGlobal(Offset.zero), entries);
        },
      ),
    );
  }

  /// 正常模式顶栏操作：**只留一枚裸搜索**。
  ///
  /// 不套 [ToolsPill]，因此没有圆角胶囊外壳，也没有那圈发丝描边 —— 用户
  /// 要的「去掉边框」。按钮本身仍是 48dp 命中区 + onSurfaceVariant 中性色，
  /// 与共享顶栏其它图标按钮同款。发现页同款的一键布局切换固定在辅助行首位，
  /// 多选 / 刷新 / 清空历史平铺其后，筛选在第一行 chip，多选动作在贴底工具条，
  /// 重载走下拉刷新。
  List<Widget> _normalActions() => [
    ToolsPillButton(
      icon: HugeIcons.strokeRoundedSearch02,
      tooltip: "Search".tl,
      // 与收藏共用一个速搜浮层：搜的是「收藏 + 历史」整体，
      // 不再只覆盖当前这一页；网络搜索在浮层底部兜底。
      onPressed: () => showQuickSearch(context),
    ),
  ];

  /// 多选模式贴底工具条的动作槽：全选 / 删除 / 更多(反选·取消)。
  /// 「退出」由 [KcDockedToolbar.onExit] 统一提供，不再占一个坑位。
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
  ];

  void _exitMultiSelect() {
    setState(() {
      multiSelectMode = false;
      selectedComics.clear();
    });
  }

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
