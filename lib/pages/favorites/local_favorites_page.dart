part of 'favorites_page.dart';

const _localAllFolderLabel = '^_^[%local_all%]^_^';

class _LocalFavoritesPage extends StatefulWidget {
  const _LocalFavoritesPage({
    required this.folder,
    required this.controller,
    super.key,
  });

  final String folder;

  final ScrollController controller;

  @override
  State<_LocalFavoritesPage> createState() => _LocalFavoritesPageState();
}

class _LocalFavoritesPageState extends State<_LocalFavoritesPage>
    with AutoListenMixin {
  late _FavoritesPageState favPage;

  late List<FavoriteItem> comics;

  String? networkSource;
  String? networkFolder;

  Map<Comic, bool> selectedComics = {};

  var selectedLocalFolders = <String>{};

  late List<String> added = [];

  bool multiSelectMode = false;

  int? lastSelectedIndex;

  bool get isAllFolder => widget.folder == _localAllFolderLabel;

  /// Reused across flyout rebuilds so the select-page widget keeps its state.
  final _selectUpdatePageNumKey = GlobalKey<_SelectUpdatePageNumState>();

  LocalFavoritesManager get manager => LocalFavoritesManager();

  late String readFilterSelect;

  /// GlobalKey for the paginated grid.
  final _gridKey = GlobalKey<PaginatedSliverGridComicsState>();

  /// Comics currently loaded by the paginated grid.
  List<FavoriteItem> _loadedComics = [];

  /// 过滤结果缓存。
  ///
  /// [filterComics] 会**批量查历史 + 逐本查下载状态**（后者每本一次 SQL /
  /// 文件系统检查），而多选态每点一下卡片都会 `setState` 整页 —— 不缓存的话
  /// 每次点选都在 UI 线程重跑一遍全量过滤。build 里原先还要判空一次、取列表
  /// 一次，等于每帧算两遍。这里只在数据源变化时重算。
  List<FavoriteItem> _visibleCache = const [];
  bool _visibleDirty = true;

  /// 当前应当展示的列表（已应用阅读状态筛选）。
  List<FavoriteItem> get _visibleComics {
    if (_visibleDirty) {
      _visibleCache = filterComics(comics);
      _visibleDirty = false;
    }
    return _visibleCache;
  }

  /// 数据源（comics / 筛选条件）变化后调用。
  void _invalidateVisible() => _visibleDirty = true;

  /// Whether to use pagination for the current view.
  /// Only paginates single-folder browsing with no filter.
  bool get _usePagination =>
      !isAllFolder && readFilterSelect == readFilterList[0];

  /// Page loader for PaginatedSliverGridComics.
  Future<List<Comic>> _loadPage(int offset, int limit) async {
    return manager.getFolderComicsPaginated(
      widget.folder,
      limit: limit,
      offset: offset,
      orderBy: LocalFavoritesManager.favoriteSortOrderBy(
        appdata.settings['favoriteSort'] as String?,
      ),
    );
  }

  /// The list of comics currently active for selection/indexing.
  /// In pagination mode, this is the loaded comics.
  /// Otherwise, this is the filtered list.
  List<FavoriteItem> get _activeComics =>
      _usePagination ? _loadedComics : _visibleComics;

  void updateComics() {
    // We are a listener of `LocalFavoritesManager`. When the currently open
    // folder is deleted, `deleteFolder()` drops the table *before* notifying,
    // so reaching `getFolderComics` below would throw SqliteException
    // "no such table" — and that exception propagates back out of
    // `deleteFolder`, aborting its remaining cleanup. Bail out instead.
    if (!isAllFolder && !manager.existsFolder(widget.folder)) {
      return;
    }
    // In pagination mode the grid (PaginatedSliverGridComics) now listens to
    // LocalFavoritesManager itself and reloads on changes, so we must NOT call
    // refresh() here: that would race with the grid's own listener and trigger
    // a redundant async reload. It also previously silently skipped the refresh
    // whenever `_gridKey.currentState` was null.
    if (_usePagination) {
      return;
    }
    if (isAllFolder) {
      comics = manager.getAllComics();
      // 「全部」是多表合并（无统一 display_order），排序设置在 Dart 侧做。
      _applyFavoriteSort(comics);
    } else {
      comics = manager.getFolderComics(
        widget.folder,
        orderBy: LocalFavoritesManager.favoriteSortOrderBy(
          appdata.settings['favoriteSort'] as String?,
        ),
      );
    }
    _invalidateVisible();
    setState(() {});
  }

  /// 「全部」视图的 Dart 侧排序（与 SQL 白名单同语义）。
  void _applyFavoriteSort(List<FavoriteItem> list) {
    switch (appdata.settings['favoriteSort'] as String?) {
      case 'recent':
        list.sort((a, b) => b.time.compareTo(a.time));
      case 'name':
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    }
  }

  void _onSortSelected(String sort) {
    appdata.settings['favoriteSort'] = sort;
    appdata.saveData();
    if (_usePagination) {
      _gridKey.currentState?.refresh();
    } else {
      updateComics();
    }
  }

  List<FavoriteItem> filterComics(List<FavoriteItem> curComics) {
    // 'All'：无需查询阅读状态，直接返回
    if (readFilterSelect == readFilterList[0]) {
      return curComics;
    }
    // 批量查询历史，避免逐本 SQL（收藏多时是 N 次查询 → 1 次）
    var histories = HistoryManager().findBatch(curComics.map((c) => c.id));
    return curComics.where((comic) {
      var history = histories[comic.id];
      // findBatch 按 id 查询，校验 type 防止混入其他源的记录
      if (history != null &&
          history.type != ComicType(comic.sourceKey.hashCode)) {
        history = null;
      }
      switch (readFilterSelect) {
        case "Unread":
          // 从未读过
          return history == null;
        case "UnCompleted":
          return history == null || history.page != history.maxPage;
        case "Completed":
          return history != null && history.page == history.maxPage;
        case "RecentlyUpdated":
          // 有更新标记（追更检查发现新章节）。本地收藏为普通 FavoriteItem，
          // 不携带更新信息，仅当实际为带更新信息的子类时才匹配。
          return comic is FavoriteItemWithUpdateInfo && comic.hasNewUpdate;
        case "NotDownloaded":
          // 本地未下载
          return !LocalManager().isDownloaded(
            comic.id,
            ComicType(comic.sourceKey.hashCode),
          );
      }
      return true;
    }).toList();
  }

  @override
  void initState() {
    readFilterSelect =
        appdata.implicitData["local_favorites_read_filter"] ??
        readFilterList[0];
    favPage = context.findAncestorStateOfType<_FavoritesPageState>()!;
    if (!isAllFolder) {
      var (a, b) = LocalFavoritesManager().findLinked(widget.folder);
      networkSource = a;
      networkFolder = b;
    } else {
      networkSource = null;
      networkFolder = null;
    }
    comics = [];
    updateComics();
    listen(LocalFavoritesManager(), updateComics);
    super.initState();
  }

  void selectAll() {
    setState(() {
      if (_usePagination) {
        // Load all comics from the folder for selection (one-time).
        final allComics = manager.getFolderComics(widget.folder);
        selectedComics = allComics.asMap().map((k, v) => MapEntry(v, true));
      } else {
        // 只选「当前可见」的：筛选/搜索生效时用户看到的是子集，
        // 全选却把不可见的也勾上会让人莫名其妙。
        selectedComics = _visibleComics.asMap().map(
          (k, v) => MapEntry(v, true),
        );
      }
    });
  }

  void invertSelection() {
    setState(() {
      for (var c in (_usePagination ? _loadedComics : _visibleComics)) {
        if (selectedComics.containsKey(c)) {
          selectedComics.remove(c);
        } else {
          selectedComics[c] = true;
        }
      }
    });
  }

  bool downloadComic(FavoriteItem c) {
    var source = c.type.comicSource;
    if (source != null) {
      bool isDownloaded = LocalManager().isDownloaded(c.id, (c).type);
      if (isDownloaded) {
        return false;
      }
      LocalManager().addTask(
        ImagesDownloadTask(source: source, comicId: c.id, comicTitle: c.title),
      );
      return true;
    }
    return false;
  }

  void downloadSelected() {
    int count = 0;
    for (var c in selectedComics.keys) {
      if (downloadComic(c as FavoriteItem)) {
        count++;
      }
    }
    if (count > 0) {
      context.showMessage(
        message: "Added @c comics to download queue.".tlParams({"c": count}),
      );
    }
  }

  /// Build menu entries for a comic tile.
  List<MenuEntry> _buildMenuEntries(Comic c) {
    return [
      // 取消收藏：危险操作一律带确认，避免误触把收藏删掉。
      // 文案用「取消收藏」而不是「删除」—— 这里只删收藏条目，不动已下载的文件，
      // 旧文案「Delete」会让人以为本地漫画也被删了。
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedFavourite, size: 18),
        text: "Remove from favorites".tl,
        color: context.colorScheme.error,
        onClick: () {
          showConfirmDialog(
            context: context,
            title: "Remove from favorites".tl,
            content: "Remove this comic from favorites?".tl,
            btnColor: context.colorScheme.error,
            onConfirm: () => LocalFavoritesManager().deleteComicWithId(
              // 「全部」视图下条目是 FavoriteItemWithFolderInfo，自带所属文件夹。
              c is FavoriteItemWithFolderInfo ? c.folder : widget.folder,
              c.id,
              (c as FavoriteItem).type,
            ),
          );
        },
      ),
      MenuEntry(
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedCheckmarkCircle01,
          size: 18,
        ),
        text: "Select".tl,
        onClick: () {
          setState(() {
            if (!multiSelectMode) {
              multiSelectMode = true;
            }
            if (selectedComics.containsKey(c as FavoriteItem)) {
              selectedComics.remove(c);
              _checkExitSelectMode();
            } else {
              selectedComics[c] = true;
            }
            lastSelectedIndex = _activeComics.indexOf(c);
          });
        },
      ),
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 18),
        text: "Download".tl,
        onClick: () {
          downloadComic(c as FavoriteItem);
          context.showMessage(message: "Download started".tl);
        },
      ),
      if (appdata.settings["onClickFavorite"] == "viewDetail")
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedBook01, size: 18),
          text: "Read".tl,
          onClick: () {
            App.mainNavigatorKey?.currentContext?.to(
              () => ReaderWithLoading(id: c.id, sourceKey: c.sourceKey),
            );
          },
        ),
    ];
  }

  /// Handle tap on a comic tile.
  void _handleTap(Comic c, int heroID) {
    if (multiSelectMode) {
      setState(() {
        if (selectedComics.containsKey(c as FavoriteItem)) {
          selectedComics.remove(c);
          _checkExitSelectMode();
        } else {
          selectedComics[c] = true;
        }
        lastSelectedIndex = _activeComics.indexOf(c);
      });
    } else if (appdata.settings["onClickFavorite"] == "viewDetail") {
      App.mainNavigatorKey?.currentContext?.to(
        () => ComicPage(
          id: c.id,
          sourceKey: c.sourceKey,
          cover: c.cover,
          title: c.title,
          heroID: heroID,
        ),
      );
    } else {
      App.mainNavigatorKey?.currentContext?.to(
        () => ReaderWithLoading(id: c.id, sourceKey: c.sourceKey),
      );
    }
  }

  /// Handle long press on a comic tile (enter multi-select or range select).
  void _handleLongPress(Comic c, int heroID) {
    setState(() {
      if (!multiSelectMode) {
        multiSelectMode = true;
        if (!selectedComics.containsKey(c as FavoriteItem)) {
          selectedComics[c] = true;
        }
        lastSelectedIndex = _activeComics.indexOf(c);
      } else {
        if (lastSelectedIndex != null) {
          int start = lastSelectedIndex!;
          int end = _activeComics.indexOf(c as FavoriteItem);
          if (start > end) {
            int temp = start;
            start = end;
            end = temp;
          }

          for (int i = start; i <= end; i++) {
            if (i == lastSelectedIndex) continue;

            var comic = _activeComics[i];
            if (selectedComics.containsKey(comic)) {
              selectedComics.remove(comic);
            } else {
              selectedComics[comic] = true;
            }
          }
        }
        lastSelectedIndex = _activeComics.indexOf(c as FavoriteItem);
      }
      _checkExitSelectMode();
    });
  }

  /// 多选态注入共享顶栏的工具（原多选 SliverAppbar 的 actions 原样迁移）。
  List<Widget> _multiSelectActions() {
    return [
      ToolsPill(
        children: [
          ToolsPillButton(
            icon: HugeIcons.strokeRoundedCheckmarkCircle01,
            tooltip: "Select All".tl,
            onPressed: selectAll,
          ),
          ToolsPillButton(
            icon: HugeIcons.strokeRoundedCancel01,
            tooltip: "Deselect".tl,
            onPressed: _cancel,
          ),
          ToolsPillMoreButton(
            entries: [
              // ── 整理：换文件夹 / 调整选择 ──
              if (!isAllFolder)
                MenuEntry(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedMove01, size: 18),
                  text: "Move to folder".tl,
                  onClick: () => favoriteOption('move'),
                ),
              if (!isAllFolder)
                MenuEntry(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 18),
                  text: "Copy to folder".tl,
                  onClick: () => favoriteOption('add'),
                ),
              MenuEntry(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedFlipHorizontal,
                  size: 18,
                ),
                text: "Invert Selection".tl,
                onClick: invertSelection,
              ),
              MenuEntry.divider(),
              // ── 单项动作：只在选中 1 本时才有意义，多选时整组隐去 ──
              if (selectedComics.length == 1)
                MenuEntry(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedBook01, size: 18),
                  text: "Read".tl,
                  onClick: () {
                    final c = selectedComics.keys.first as FavoriteItem;
                    // Push onto the main navigator so back returns to the
                    // local favorites page instead of the home page.
                    App.mainNavigatorKey?.currentContext?.to(
                      () => ReaderWithLoading(id: c.id, sourceKey: c.sourceKey),
                    );
                  },
                ),
              if (selectedComics.length == 1)
                MenuEntry(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    size: 18,
                  ),
                  text: "Jump to Detail".tl,
                  onClick: () {
                    final c = selectedComics.keys.first as FavoriteItem;
                    App.mainNavigatorKey?.currentContext?.to(
                      () => ComicPage(id: c.id, sourceKey: c.sourceKey),
                    );
                  },
                ),
              if (selectedComics.length == 1)
                MenuEntry(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 18),
                  text: "Copy Title".tl,
                  onClick: () {
                    Clipboard.setData(
                      ClipboardData(text: selectedComics.keys.first.title),
                    );
                    context.showMessage(message: "Copied".tl);
                  },
                ),
              MenuEntry(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedDownload04,
                  size: 18,
                ),
                text: "Download".tl,
                onClick: downloadSelected,
              ),
              MenuEntry.divider(),
              // ── 危险操作：取消收藏 ──
              // 原「Delete Comic」与「Remove from favorites」底层都是删收藏表里
              // 的行，只是后者不带确认 —— 合并成一项并统一加确认，同时避免
              // 「Delete Comic」被误解成连本地下载的文件一起删。
              MenuEntry(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedFavourite,
                  size: 18,
                ),
                text: "Remove from favorites".tl,
                color: context.colorScheme.error,
                onClick: () {
                  showConfirmDialog(
                    context: context,
                    title: "Remove from favorites".tl,
                    content: "Remove @c comics from favorites?".tlParams({
                      "c": selectedComics.length,
                    }),
                    btnColor: context.colorScheme.error,
                    onConfirm: _removeSelectedFromFavorites,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    ];
  }

  /// 把本页（普通 / 多选两态）的顶栏内容同步进 NaviPane 共享栏。
  /// 写值机制与历史页 _syncTopBar 相同：post-frame + 签名守卫 + 前台校验。
  void _syncTopBar() {
    String sig;
    Widget? leading;
    Widget? title;
    List<Widget>? actions;
    if (multiSelectMode) {
      sig = 'ms_${selectedComics.length}';
      leading = Tooltip(
        message: "Cancel".tl,
        child: IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
          onPressed: () {
            setState(() {
              multiSelectMode = false;
              selectedComics.clear();
            });
          },
        ),
      );
      title = Text("Selected @c comics".tlParams({"c": selectedComics.length}));
      actions = _multiSelectActions();
    } else {
      // 签名必须包含排序键：工具条上的「手动/最近/标题」是状态显示，
      // 漏掉它就会出现「列表已按新排序重排、标签还停在旧值」。
      sig = 'n_${readFilterSelect}_${networkSource ?? 'l'}_$_sortKey';
      leading = Tooltip(
        message: "Favorites".tl,
        child: IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, size: 18),
          onPressed: () => favPage.setFolder(false, null),
        ),
      );
      title = Text(
        "Favorites".tl,
        style: TextStyle(fontSize: kcTitleMain, fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
      );
      actions = [favPage._favToolsPill(context, _normalPillChildren())];
    }
    favPage.pushTopBar(
      sig: sig,
      leading: leading,
      title: title,
      actions: actions,
      // 内层（文件夹/多选/搜索）工具胶囊里已有夹内搜索，右上角不再重复
      // 全局搜索/设置入口 —— 全局入口留在总览层。
      hideGlobalActions: true,
    );
  }

  /// 普通态工具胶囊条内容（原普通 SliverAppbar 的 actions 原样迁移）。
  ///
  /// 精简后只保留高频直操：布局切换、（网络文件夹的）同步、搜索；
  /// 排序/筛选与文件夹管理一起收进「更多」菜单 —— 六个槽位在窄屏上
  /// 会把共享顶栏的标题挤没（448dp 实测）。
  List<Widget> _normalPillChildren() {
    return [
      // 布局切换单图标：形状即当前布局（2×2 方块 = 网格 / 左封面+三行 = 列表），
      // 点击在原位淡入切换成另一种，翻的是全局 comicDisplayMode。
      // 旧的双态分段要占两个槽位，窄屏上会和标题抢宽度。
      const ToolsPillLayoutButton(),
      // 排序直显：只写当前值（手动 / 最近 / 标题）+ 下拉箭头，点开三段切换。
      // 不再在前面塞排序图标 —— 那个图标是几根横线，跟左边布局图标的横线
      // 挨在一起像同一族；文字 + 箭头反而更像「当前状态」。
      ToolsPillValueChip(
        label: _sortLabel,
        tooltip: "Sort".tl,
        entries: [MenuEntry.custom(_sortSegmentRow(_sortKey))],
      ),
      if (networkSource != null && !isAllFolder)
        Tooltip(
          message: "Sync".tl,
          child: Flyout(
            flyoutBuilder: (context) {
              var updatePageWidget = _SelectUpdatePageNum(
                networkSource: networkSource!,
                networkFolder: networkFolder,
                key: _selectUpdatePageNumKey,
              );
              return FlyoutContent(
                title: "Sync".tl,
                content: updatePageWidget,
                actions: [
                  Button.filled(
                    child: Text("Update".tl),
                    onPressed: () {
                      context.pop();
                      importNetworkFolder(
                        networkSource!,
                        _selectUpdatePageNumKey.currentState!.updatePageNum,
                        widget.folder,
                        networkFolder!,
                      ).then((value) {
                        updateComics();
                      });
                    },
                  ),
                ],
              );
            },
            child: Builder(
              builder: (context) {
                return IconButton(
                  tooltip: "Update Info".tl,
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedRefresh,
                    size: 18,
                  ),
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  splashRadius: 20,
                  onPressed: () {
                    Flyout.of(context).show();
                  },
                );
              },
            ),
          ),
        ),
      // 搜索不再进「本页内联筛选」：改成居中速搜浮层，一次搜全部收藏 +
      // 历史（原先只能搜当前文件夹，换个文件夹就得退出去重搜）。
      favPage._toolIconButton(
        context,
        icon: HugeIcons.strokeRoundedSearch02,
        tooltip: "Search".tl,
        onPressed: () => showQuickSearch(context),
      ),
      // 「更多」始终显示：排序/筛选也住在里面（原独立按钮已收编）。
      favPage._toolMoreButton(context, _buildMoreEntries()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // 顶栏已并入 NaviPane 共享栏：两种模式（普通 / 多选）各自注入
    // leading / 标题 / 工具，见 [_syncTopBar]。
    _syncTopBar();
    // 空态判定与网格共用同一份列表：原实现在 build 里调了两次 filterComics，
    // 每次都批量查历史 + 逐本查下载状态（多选点一下 = 两轮全量 DB）。
    final visible = _usePagination ? const <FavoriteItem>[] : _visibleComics;
    Widget body = SmoothCustomScrollView(
      controller: widget.controller,
      slivers: [
        // 文件夹胶囊条：常驻顶栏下方（pinned），滚到列表深处也能直接换文件夹。
        // 共享顶栏接管后它就是首个 sliver，自动贴在共享栏下面。
        if (!multiSelectMode)
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverFolderChipsHeader(_GroupPills(favPage: favPage)),
          ),
        // 筛选提示条：筛选条件会持久化，下次进来依然生效，而侧栏文件夹上的
        // 数字是总数、不受筛选影响。没有这条提示时「明明有 20 本却只看到 3 本」
        // 会被当成丢数据。
        if (!multiSelectMode && readFilterSelect != readFilterList[0])
          SliverToBoxAdapter(child: _filterBanner()),
        // 方案 A 的「收藏空间导航」入口卡放在总览（favorites_page
        // _buildOverview）顶部；「全部」等具体文件夹视图直接进内容。
        if (_usePagination)
          PaginatedSliverGridComics(
            key: _gridKey,
            pageLoader: _loadPage,
            selections: selectedComics,
            showSourceOnCover: false,
            showBottomSourceDate: true,
            onLoadedComicsChanged: (loaded) {
              _loadedComics = loaded.cast<FavoriteItem>();
            },
            menuBuilder: (c) {
              return _buildMenuEntries(c);
            },
            onTap: (c, heroID) => _handleTap(c, heroID),
            onLongPressed: (c, heroID) => _handleLongPress(c, heroID),
          )
        else if (!multiSelectMode && visible.isEmpty)
          SliverFillRemaining(child: _buildEmptyState())
        else
          SliverGridComics(
            comics: visible,
            selections: selectedComics,
            showSourceOnCover: false,
            showBottomSourceDate: true,
            menuBuilder: (c) {
              return _buildMenuEntries(c);
            },
            onTap: (c, heroID) => _handleTap(c, heroID),
            onLongPressed: (c, heroID) => _handleLongPress(c, heroID),
          ),
      ],
    );
    body = AppScrollBar(
      topPadding: 48,
      controller: widget.controller,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: body,
      ),
    );
    // 库页面不显示「已收藏」角标（见 FavoriteBadgeScope 文档）。
    return FavoriteBadgeScope.disabled(
      child: PopScope(
        // 收藏页是「货架总览 → 文件夹」两层：文件夹视图里返回键先退回总览，
        // 而不是直接弹「确认退出」（总览是 tab 根页，那才是该退出的位置）。
        // 多选优先吃掉返回，与之前一致。
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (multiSelectMode) {
            setState(() {
              multiSelectMode = false;
              selectedComics.clear();
            });
          } else {
            favPage.setFolder(false, null);
          }
        },
        child: body,
      ),
    );
  }

  void favoriteOption(String option) {
    var targetFolders = userFolderNames()
        .where((folder) => folder != favPage.folder)
        .toList();

    showPopUpWidget(
      App.rootContext,
      StatefulBuilder(
        builder: (context, setState) {
          return PopUpWidgetScaffold(
            title: favPage.folder ?? "Unselected".tl,
            body: Padding(
              padding: EdgeInsets.only(bottom: context.padding.bottom + 16),
              child: Container(
                constraints: const BoxConstraints(
                  maxHeight: 700,
                  maxWidth: 500,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: targetFolders.length + 1,
                        itemBuilder: (context, index) {
                          if (index == targetFolders.length) {
                            return SizedBox(
                              height: 36,
                              child: Center(
                                child: Button.text(
                                  onPressed: () {
                                    newFolder().then((v) {
                                      setState(() {
                                        targetFolders = userFolderNames()
                                            .where(
                                              (folder) =>
                                                  folder != favPage.folder,
                                            )
                                            .toList();
                                      });
                                    });
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      HugeIcon(
                                        icon: HugeIcons.strokeRoundedAddCircle,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 4),
                                      Text("New Folder".tl),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                          var folder = targetFolders[index];
                          var disabled = false;
                          if (selectedLocalFolders.isNotEmpty) {
                            if (added.contains(folder) &&
                                !added.contains(selectedLocalFolders.first)) {
                              disabled = true;
                            } else if (!added.contains(folder) &&
                                added.contains(selectedLocalFolders.first)) {
                              disabled = true;
                            }
                          }
                          return CheckboxListTile(
                            title: Row(
                              children: [
                                Text(folder),
                                const SizedBox(width: 8),
                              ],
                            ),
                            value: selectedLocalFolders.contains(folder),
                            onChanged: disabled
                                ? null
                                : (v) {
                                    setState(() {
                                      if (v!) {
                                        selectedLocalFolders.add(folder);
                                      } else {
                                        selectedLocalFolders.remove(folder);
                                      }
                                    });
                                  },
                          );
                        },
                      ),
                    ),
                    Center(
                      child: Button.filled(
                        onPressed: () {
                          if (selectedLocalFolders.isEmpty) {
                            return;
                          }
                          if (option == 'move') {
                            var comics = selectedComics.keys
                                .map((e) => e as FavoriteItem)
                                .toList();
                            for (var f in selectedLocalFolders) {
                              LocalFavoritesManager().batchMoveFavorites(
                                favPage.folder as String,
                                f,
                                comics,
                              );
                            }
                          } else {
                            var comics = selectedComics.keys
                                .map((e) => e as FavoriteItem)
                                .toList();
                            for (var f in selectedLocalFolders) {
                              LocalFavoritesManager().batchCopyFavorites(
                                favPage.folder as String,
                                f,
                                comics,
                              );
                            }
                          }
                          App.rootContext.pop();
                          updateComics();
                          _cancel();
                        },
                        child: Text(option == 'move' ? "Move".tl : "Add".tl),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _checkExitSelectMode() {
    if (selectedComics.isEmpty) {
      setState(() {
        multiSelectMode = false;
      });
    }
  }

  void _cancel() {
    setState(() {
      selectedComics.clear();
      multiSelectMode = false;
    });
  }

  /// 取消收藏当前选中的全部条目。
  ///
  /// 「全部」是跨表虚拟视图，条目可能同时存在于多个文件夹（同一本书被收藏
  /// 到两个文件夹），取消收藏理应从所有文件夹移除。
  void _removeSelectedFromFavorites() {
    final items = selectedComics.keys.map((e) => e as FavoriteItem).toList();
    final manager = LocalFavoritesManager();
    if (isAllFolder) {
      // 原本逐条 [deleteComicWithId]：每本各自 notifyListeners 一次，于是
      // N 本 = N 轮全量 getAllComics()（O(N²)，删 20 本会明显卡顿）。
      // batchDeleteComicsInAllFolders 单事务删完只通知一次。
      manager.batchDeleteComicsInAllFolders(
        items.map((e) => ComicID(e.type, e.id)).toList(),
      );
    } else {
      manager.batchDeleteComics(widget.folder, items);
    }
    _cancel();
  }

  /// 「更多」菜单顶部的排序分段控件：一行三段替代原先 3 行「圆圈打勾」项。
  /// 排序是单选状态而非动作，分段控件才是它的正确形态；选中段用品牌色实底。
  Widget _sortSegmentRow(String current) {
    final cs = Theme.of(context).colorScheme;
    Widget seg(String value, String label) {
      final selected = current == value;
      return Expanded(
        child: Material(
          color: selected
              ? kcBrandAdaptive(context)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(kcRadius8),
          child: InkWell(
            borderRadius: BorderRadius.circular(kcRadius8),
            onTap: () {
              // 分段控件吃掉了手势，包裹层 MenuEntry.custom 的关闭逻辑不会触发；
              // 手动关掉菜单再应用排序（与其他菜单项行为一致）。
              Navigator.of(context, rootNavigator: true).pop();
              _onSortSelected(value);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: kcCaption,
                  fontWeight: FontWeight.w500,
                  height: 1.0,
                  color: selected ? kcOnAccentColor : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        seg('manual', "Manual order".tl),
        const SizedBox(width: 4),
        seg('recent', "Recently favorited".tl),
        const SizedBox(width: 4),
        seg('name', "By title".tl),
      ],
    );
  }

  /// 当前收藏排序键（manual / recent / name）。
  String get _sortKey => (appdata.settings['favoriteSort'] as String?) ?? 'recent';

  /// 工具条上的排序短标签：只显示当前值，避免长文案把胶囊撑宽。
  String get _sortLabel {
    switch (_sortKey) {
      case 'manual':
        return "Manual".tl;
      case 'name':
        return "Title".tl;
      default:
        return "Recent".tl;
    }
  }

  /// 「更多」菜单项：分组为「视图 → 文件夹管理 → 危险操作」，组间用分隔线隔开，
  /// 删除文件夹前后都有线隔离。
  ///
  /// 排序（单选状态）已从菜单移到工具条上的直显按钮，菜单里不再重复。
  List<MenuEntry> _buildMoreEntries() {
    return [
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedFilter, size: 18),
        text: "Filter".tl,
        onClick: () {
          showDialog(
            context: context,
            builder: (context) {
              return _LocalFavoritesFilterDialog(
                initReadFilterSelect: readFilterSelect,
                updateConfig: (readFilter) {
                  setState(() {
                    readFilterSelect = readFilter;
                  });
                  updateComics();
                },
              );
            },
          );
        },
      ),
      // 文件夹管理只在具体文件夹视图有意义；「全部」是跨表虚拟视图。
      if (!isAllFolder) ...[
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedEdit01, size: 18),
          text: "Rename".tl,
          onClick: () {
            showInputDialog(
              context: App.rootContext,
              title: "Rename".tl,
              hintText: "New Name".tl,
              onConfirm: (value) {
                var err = validateFolderName(value.toString());
                if (err != null) {
                  return err;
                }
                LocalFavoritesManager().rename(widget.folder, value.toString());
                BookshelfLayout.onFolderRenamed(
                  widget.folder,
                  value.toString(),
                );
                favPage.folderList?.updateFolders();
                favPage.setFolder(false, value.toString());
                return null;
              },
            );
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedArrange, size: 18),
          text: "Reorder".tl,
          onClick: () {
            context
                .to(
                  () => _ReorderComicsPage(widget.folder, (comics) {
                    this.comics = comics;
                    // 手动排序改了数据源，筛选缓存必须失效，
                    // 否则带筛选时看到的还是旧顺序。
                    _invalidateVisible();
                  }),
                )
                .then((value) {
                  if (mounted) {
                    setState(() {});
                  }
                });
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedUpload01, size: 18),
          text: "Export".tl,
          onClick: () {
            var json = LocalFavoritesManager().folderToJson(widget.folder);
            saveFile(
              data: utf8.encode(json),
              filename: "${widget.folder}.json",
            );
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
          text: "Update Comics Info".tl,
          onClick: () {
            updateComicsInfo(widget.folder).then((newComics) {
              if (mounted) {
                setState(() {
                  comics = newComics;
                  // 同上：数据源整体换了一份，筛选缓存要跟着重算。
                  _invalidateVisible();
                });
              }
            });
          },
        ),
        MenuEntry.divider(),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
          text: "Delete Folder".tl,
          color: context.colorScheme.error,
          onClick: () {
            showConfirmDialog(
              context: App.rootContext,
              title: "Delete".tl,
              content: "Delete folder '@f' ?".tlParams({"f": widget.folder}),
              btnColor: context.colorScheme.error,
              onConfirm: () {
                favPage.setFolder(false, null);
                LocalFavoritesManager().deleteFolder(widget.folder);
                favPage.folderList?.updateFolders();
              },
            );
          },
        ),
      ],
    ];
  }

  /// 清除阅读状态筛选（提示条 / 空态按钮共用）。
  void _clearFilter() {
    setState(() {
      readFilterSelect = readFilterList[0];
    });
    appdata.implicitData["local_favorites_read_filter"] = readFilterSelect;
    appdata.writeImplicitData();
    _invalidateVisible();
  }

  /// 筛选生效时贴在文件夹胶囊条下方的常驻提示条。
  ///
  /// 筛选条件会持久化（implicitData），下次进来依然生效；而胶囊条上的文件夹
  /// 数字是总数、不受筛选影响。只在空态解释「是筛掉了」不够——有结果时用户
  /// 同样不知道自己看到的是被裁剪过的子集。这条给出「当前筛选 = X」+ 一键清除。
  Widget _filterBanner() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kcSpaceLg, 4, kcSpaceSm, 0),
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedFilter,
            size: 14,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              "Filtered: @v".tlParams({"v": readFilterSelect.tl}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: kcCaption, color: cs.onSurfaceVariant),
            ),
          ),
          Button.text(
            onPressed: _clearFilter,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text("Clear".tl, style: TextStyle(fontSize: kcCaption)),
          ),
        ],
      ),
    );
  }

  /// 空状态：当前文件夹没有收藏时，用统一角色插画 + 引导文案取代空白。
  Widget _buildEmptyState() {
    // 过滤器生效时空态必须说清「是筛选没命中」。
    //
    // 阅读状态筛选会被持久化到 implicitData，下次进来依然生效；而侧栏文件夹上
    // 的数字是总数、不受筛选影响。于是「左边显示 2、右边一片空白」看起来就像
    // 收藏丢了 —— 之前这里只说「这个文件夹是空的，去发现页添加漫画」，
    // 完全没提筛选，用户根本想不到要点筛选按钮。
    final filterActive = readFilterSelect != readFilterList[0];
    return EmptyState(
      title: filterActive
          ? "No comics match the current filter".tl
          : "This folder is empty".tl,
      subtitle: filterActive
          ? "Clear the filter to see every comic in this folder".tl
          : "Add comics from the Discover page".tl,
      actionLabel: filterActive ? "Clear filter".tl : "Browse Discover".tl,
      onAction: filterActive
          ? _clearFilter
          : () => context.to(() => const ExplorePage()),
    );
  }
}

class _ReorderComicsPage extends StatefulWidget {
  const _ReorderComicsPage(this.name, this.onReorder);

  final String name;

  final void Function(List<FavoriteItem>) onReorder;

  @override
  State<_ReorderComicsPage> createState() => _ReorderComicsPageState();
}

class _ReorderComicsPageState extends State<_ReorderComicsPage> {
  final _key = GlobalKey();
  var reorderWidgetKey = UniqueKey();
  final _scrollController = ScrollController();
  late var comics = LocalFavoritesManager().getFolderComics(widget.name);
  bool changed = false;

  static int _floatToInt8(double x) {
    return (x * 255.0).round() & 0xff;
  }

  Color lightenColor(Color color, double lightenValue) {
    int red = (_floatToInt8(color.r) + ((255 - color.r) * lightenValue))
        .round();
    int green = (_floatToInt8(color.g) + ((255 - color.g) * lightenValue))
        .round();
    int blue = (_floatToInt8(color.b) + ((255 - color.b) * lightenValue))
        .round();

    return Color.fromARGB(_floatToInt8(color.a), red, green, blue);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    if (changed) {
      // Delay to ensure navigation is completed
      Future.delayed(const Duration(milliseconds: 200), () {
        LocalFavoritesManager().reorder(comics, widget.name);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var type = appdata.settings['comicDisplayMode'];
    var tiles = comics.map((e) {
      var comicSource = e.type.comicSource;
      return ComicTile(
        key: Key(e.hashCode.toString()),
        enableLongPressed: false,
        comic: Comic(
          e.name,
          e.coverPath,
          e.id,
          e.author,
          e.tags,
          type == 'detailed'
              ? "${e.time} | ${comicSource?.name ?? "Unknown"}"
              : "${e.type.comicSource?.name ?? "Unknown"} | ${e.time}",
          comicSource?.key ?? (e.type == ComicType.local ? "local" : "Unknown"),
          null,
          null,
        ),
      );
    }).toList();
    return Scaffold(
      appBar: Appbar(
        title: Text("Reorder".tl),
        actions: [
          Tooltip(
            message: "Information".tl,
            child: IconButton(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedInformationCircle,
                size: 18,
              ),
              onPressed: () {
                showInfoDialog(
                  context: context,
                  title: "Reorder".tl,
                  content: "Long press and drag to reorder.".tl,
                );
              },
            ),
          ),
          Tooltip(
            message: "Reverse".tl,
            child: IconButton(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedArrange, size: 18),
              onPressed: () {
                setState(() {
                  comics = comics.reversed.toList();
                  changed = true;
                });
              },
            ),
          ),
        ],
      ),
      body: ReorderableBuilder<FavoriteItem>(
        key: reorderWidgetKey,
        scrollController: _scrollController,
        longPressDelay: App.isDesktop
            ? const Duration(milliseconds: 100)
            : const Duration(milliseconds: 500),
        onReorder: (reorderFunc) {
          changed = true;
          setState(() {
            comics = reorderFunc(comics);
          });
          widget.onReorder(comics);
        },
        dragChildBoxDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kcRadius16),
          color: lightenColor(
            Theme.of(context).splashColor.withAlpha(255),
            0.2,
          ),
        ),
        builder: (children) {
          return AnimatedBuilder(
            animation: appdata.settings,
            builder: (context, _) => GridView(
              key: _key,
              controller: _scrollController,
              gridDelegate: SliverGridDelegateWithComics(),
              children: children,
            ),
          );
        },
        children: tiles,
      ),
    );
  }
}

class _SelectUpdatePageNum extends StatefulWidget {
  const _SelectUpdatePageNum({
    required this.networkSource,
    this.networkFolder,
    super.key,
  });

  final String? networkFolder;
  final String networkSource;

  @override
  State<_SelectUpdatePageNum> createState() => _SelectUpdatePageNumState();
}

class _SelectUpdatePageNumState extends State<_SelectUpdatePageNum> {
  int updatePageNum = 9999999;

  String get _allPageText => 'All'.tl;

  List<String> get pageNumList => [
    '1',
    '2',
    '3',
    '5',
    '10',
    '20',
    '50',
    '100',
    '200',
    _allPageText,
  ];

  @override
  void initState() {
    updatePageNum =
        appdata.implicitData["local_favorites_update_page_num"] ?? 9999999;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var source = ComicSource.find(widget.networkSource);
    var sourceName = source?.name ?? widget.networkSource;
    var text = "The folder is Linked to @source".tlParams({
      "source": sourceName,
    });
    if (widget.networkFolder != null && widget.networkFolder!.isNotEmpty) {
      text += "\n${"Source Folder".tl}: ${widget.networkFolder}";
    }

    return Column(
      children: [
        Row(children: [Text(text)]),
        Row(
          children: [
            Text("Update the page number by the latest collection".tl),
            Spacer(),
            Select(
              current: updatePageNum.toString() == '9999999'
                  ? _allPageText
                  : updatePageNum.toString(),
              values: pageNumList,
              minWidth: 48,
              onTap: (index) {
                setState(() {
                  updatePageNum = int.parse(
                    pageNumList[index] == _allPageText
                        ? '9999999'
                        : pageNumList[index],
                  );
                  appdata.implicitData["local_favorites_update_page_num"] =
                      updatePageNum;
                  appdata.writeImplicitData();
                });
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _LocalFavoritesFilterDialog extends StatefulWidget {
  const _LocalFavoritesFilterDialog({
    required this.initReadFilterSelect,
    required this.updateConfig,
  });

  final String initReadFilterSelect;
  final Function updateConfig;

  @override
  State<_LocalFavoritesFilterDialog> createState() =>
      _LocalFavoritesFilterDialogState();
}

const readFilterList = [
  'All',
  'Unread',
  'UnCompleted',
  'Completed',
  'RecentlyUpdated',
  'NotDownloaded',
];

class _LocalFavoritesFilterDialogState
    extends State<_LocalFavoritesFilterDialog> {
  late var readFilter = widget.initReadFilterSelect;

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: "Filter".tl,
      content: KcListTile(
        title: Text("Filter reading status".tl),
        trailing: Select(
          current: readFilter.tl,
          values: readFilterList.map((e) => e.tl).toList(),
          minWidth: 120,
          onTap: (index) {
            final picked = readFilterList[index];
            appdata.implicitData["local_favorites_read_filter"] = picked;
            appdata.writeImplicitData();
            Navigator.pop(context);
            widget.updateConfig(picked);
          },
        ),
      ),
    );
  }
}
