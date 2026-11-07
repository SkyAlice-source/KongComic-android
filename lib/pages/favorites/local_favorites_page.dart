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
    // 布局切换与排序都写 appdata.settings，而顶栏不再有全局按钮（布局切换
    // 改放内容区辅助行固定位），页面自己必须跟着重建，否则点了切换按钮
    // 图标变了、下面的网格还停在旧布局。
    listen(appdata.settings, () {
      if (mounted) setState(() {});
    });
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
            onConfirm: () {
              final manager = LocalFavoritesManager();
              // 「全部」视图下条目是 FavoriteItemWithFolderInfo，自带所属文件夹。
              final folder = c is FavoriteItemWithFolderInfo
                  ? c.folder
                  : widget.folder;
              final item = c as FavoriteItem;
              manager.deleteComicWithId(folder, item.id, item.type);
              // 撤销用这份内存快照原样加回：deleteComicWithId 只按 id/type
              // 删，事后没法从数据库还原作者 / 封面 / 标签。
              showUndoMessage(
                message: "Deleted".tl,
                onUndo: () {
                  if (manager.existsFolder(folder)) {
                    manager.addComic(folder, item);
                  }
                },
              );
            },
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

  /// 多选态贴底工具条的动作槽（方案 C）：顶栏清空，动作落在下半屏，
  /// 退出由 [KcDockedToolbar.onExit] 统一提供。
  List<Widget> _multiSelectActions() {
    return [
      IconButton(
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedCheckmarkCircle01,
          size: 20,
        ),
        tooltip: "Select All".tl,
        constraints: const BoxConstraints(
          minWidth: kcMinTapTarget,
          minHeight: kcMinTapTarget,
        ),
        padding: EdgeInsets.zero,
        onPressed: selectAll,
      ),
      IconButton(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 20),
        tooltip: "Deselect".tl,
        constraints: const BoxConstraints(
          minWidth: kcMinTapTarget,
          minHeight: kcMinTapTarget,
        ),
        padding: EdgeInsets.zero,
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
      // 方案 C：多选态顶栏不留动作，全部交给贴底工具条；leading 的取消
      // 按钮仍保留，作为「退出多选」的第二条可见路径。
      actions = const <Widget>[];
    } else {
      // 标题写当前文件夹名，而不是一律「收藏」。
      //
      // 顶栏是所有子页面共用的同一块区域，用户靠它认位置：进到「Reading」
      // 里标题还写「收藏」，除了下面的胶囊条没有任何「我在哪」的锚点，多
      // 文件夹来回切时尤其容易迷路。『全部』是跨表虚拟视图，用它的正式名字。
      final titleText = isAllFolder
          ? "All Favorites".tl
          : (getFavoriteDataOrNull(widget.folder)?.title ?? widget.folder);
      // 签名必须包含排序键：工具条上的「手动/最近/标题」是状态显示，
      // 漏掉它就会出现「列表已按新排序重排、标签还停在旧值」。
      // 也必须包含文件夹名，否则换个文件夹进来标题不更新。
      sig =
          'n_${widget.folder}_${readFilterSelect}_${networkSource ?? 'l'}_$_sortKey';
      leading = Tooltip(
        message: "Favorites".tl,
        child: IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, size: 18),
          onPressed: () => favPage.setFolder(false, null),
        ),
      );
      title = Text(
        titleText,
        style: TextStyle(fontSize: kcTitleMain, fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
      );
      // 顶栏只留一枚**裸搜索**：不套 [ToolsPill]，所以没有胶囊外壳，
      // 也没有那圈发丝描边。其余入口按用途分置：
      //   · 布局切换(发现页同款) / 同步(网络文件夹) → 辅助行固定位
      //   · 多选 / 管理 / 删除 → 辅助行平铺 [_actionItems]（窄屏可收拢）
      //   · 筛选 / 排序状态 → chip 行本身（有文字证据 + 结果数/重置）
      //   · 进入多选 → 辅助行常驻按钮 / 长按任意漫画；动作 → 贴底工具条
      //   · 重载当前文件夹 → 下拉刷新
      actions = [
        favPage._toolIconButton(
          context,
          icon: HugeIcons.strokeRoundedSearch02,
          tooltip: "Search".tl,
          onPressed: () => showQuickSearch(context),
        ),
      ];
    }
    favPage.pushTopBar(
      sig: sig,
      leading: leading,
      title: title,
      actions: actions,
      // 顶栏已有本页搜索，右上角不再重复全局搜索/设置入口 —— 全局入口
      // 留在总览层；多选态更是连搜索一起清空，交给贴底工具条。
      hideGlobalActions: true,
    );
  }

  /// 内容区辅助行里**不参与收拢**的固定按钮：
  ///   · [ToolsPillLayoutButton] —— 发现页右上角那颗全站共用的布局切换。
  ///     图标表示当前布局、点一下即切换，高频且不必进 ⋮，固定占首位；
  ///   · 「同步」(仅网络收藏文件夹) —— 要选同步页数，必须留在自带 context
  ///     的 Flyout 里；菜单行放不下 Flyout，`context.pop()` 也不适合弹窗。
  /// 其余普通动作全部走 [_actionItems] 平铺 / 窄屏收拢。
  List<Widget> _fixedChipRowActions() {
    return [
      const ToolsPillLayoutButton(),
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
                    minWidth: kcMinTapTarget,
                    minHeight: kcMinTapTarget,
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
    ];
  }

  /// 内容区辅助行的**全部**动作：默认一枚枚平铺成常驻裸图标按钮，
  /// 不再藏进 ⋮ 菜单。顺序即优先级 —— 窄屏 / 大字号放不下时末尾的
  /// 破坏性动作先被收拢，不会变成一排常驻红图标。
  ///
  /// 「全部收藏」是跨文件夹的虚拟视图，没有可管理 / 可删除的文件夹，
  /// 这两枚不再按条件隐藏，而是置灰常驻：位置够就别藏，动作数量也
  /// 不会随状态忽有忽无。筛选相关操作全部归第一行 chip 与「重置」。
  List<KcToolbarAction> _actionItems() => [
    KcToolbarAction(
      icon: HugeIcons.strokeRoundedCheckList,
      label: "Multi-Select".tl,
      onTap: () => setState(() => multiSelectMode = true),
    ),
    KcToolbarAction(
      icon: HugeIcons.strokeRoundedFolder01,
      label: "Manage Folder".tl,
      enabled: !isAllFolder,
      onTap: _showFolderManageDialog,
    ),
    // 「清除筛选」不放这里：辅助行左侧的「重置」文字按钮与它完全等价，
    // 而且只在真的有筛选时出现，再摆一枚常驻漏斗图标是重复 + 误导。
    KcToolbarAction(
      icon: HugeIcons.strokeRoundedDelete01,
      label: "Delete Folder".tl,
      enabled: !isAllFolder,
      color: context.colorScheme.error,
      onTap: _deleteFolder,
    ),
  ];

  /// 布局切换不再有第二个入口：辅助行固定位直接复用发现页右上角那颗全站
  /// 共用的 [ToolsPillLayoutButton]，读同一个
  /// `appdata.settings['comicDisplayMode']`，点一下即切换，不再弹窗选择。
  /// 阅读状态筛选、排序归第一行 chip，结果数与重置归辅助行左侧。

  /// 「显示 N 项」：分页视图查文件夹总数，其余视图用过滤后的全量。
  ///
  /// 分页时不能用 [_loadedComics] 的长度 —— 那是「已经滚动加载了几页」，
  /// 首屏会显示 0、往下滚才慢慢涨，而 chip 行的语义是当前条件下的结果总数。
  /// `getFolderComicCount` 是一条 `SELECT COUNT(*)`，比遍历廉价。
  int get _visibleCount {
    if (!_usePagination) return _visibleComics.length;
    try {
      return manager.getFolderComicCount(widget.folder);
    } catch (_) {
      // 网络文件夹 / 文件夹刚被删除时表可能还没建好，退回已加载数。
      return _loadedComics.length;
    }
  }

  /// B · 排序独立成 chip 点开的单选弹窗（Sort is not a filter）。
  void _showSortDialog() {
    showKcRadioDialog<String>(
      context: context,
      title: "Sort".tl,
      initial: _sortKey,
      options: [
        (value: 'manual', label: "Manual order".tl),
        (value: 'recent', label: "Recently favorited".tl),
        (value: 'name', label: "By title".tl),
      ],
    ).then((picked) {
      if (picked == null || !mounted) return;
      _onSortSelected(picked);
      // 分页模式下 _onSortSelected 只让网格自己刷新，不会重建本页；
      // chip 上的当前排序标签必须跟着改。
      setState(() {});
    });
  }

  /// B · 第一行：阅读状态筛选常驻 + 独立的排序 chip + 结果数/重置。
  /// 第二行右侧：发现页同款的一键布局切换固定在首位，多选 / 管理文件夹 /
  /// 删除文件夹平铺成常驻按钮（+ 网络文件夹的同步 Flyout），不再藏在 ⋮
  /// 里；筛选交给第一行 chip 与「重置」。
  Widget _buildFilterChips() {
    return KcFilterChipRow(
      chips: [
        for (final f in readFilterList)
          KcFilterChipData(
            label: f.tl,
            selected: readFilterSelect == f,
            onTap: () => _pickReadFilter(f),
          ),
        KcFilterChipData(
          label: _sortLabel(_sortKey),
          selected: false,
          showArrow: true,
          onTap: _showSortDialog,
        ),
      ],
      resultCount: _visibleCount,
      onReset: readFilterSelect == readFilterList[0] ? null : _clearFilter,
      actions: _actionItems(),
      fixedActions: _fixedChipRowActions(),
    );
  }

  String _sortLabel(String key) => switch (key) {
    'manual' => "Manual order".tl,
    'name' => "By title".tl,
    _ => "Recently favorited".tl,
  };

  void _pickReadFilter(String f) {
    if (f == readFilterSelect) return;
    setState(() => readFilterSelect = f);
    appdata.implicitData["local_favorites_read_filter"] = f;
    appdata.writeImplicitData();
    _invalidateVisible();
    // 从「全部」切到带筛选会让 _usePagination 翻转：分页模式里 comics 是空的
    // （initState 的 updateComics 会提前返回），必须按新视图重新加载全量；
    // 反向切回「全部」则让分页网格自己重载。
    if (_usePagination) {
      _gridKey.currentState?.refresh();
    } else {
      updateComics();
    }
  }

  /// 阅读状态筛选的单选弹窗：chip 行之外的备用路径，确认才落盘、可反悔。
  /// D · 下拉刷新：重载当前文件夹数据（原先「更新漫画信息」在管理弹窗里
  /// 仍有可见入口，没有因为加了手势就把它藏掉）。
  Future<void> _onPullRefresh() async {
    updateComics();
    _invalidateVisible();
    if (mounted) setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 220));
  }

  void _exitMultiSelect() {
    setState(() {
      multiSelectMode = false;
      selectedComics.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 顶栏已并入 NaviPane 共享栏：两种模式（普通 / 多选）各自注入
    // leading / 标题 / 工具，见 [_syncTopBar]。
    _syncTopBar();
    // 空态判定与网格共用同一份列表：原实现在 build 里调了两次 filterComics，
    // 每次都批量查历史 + 逐本查下载状态（多选点一下 = 两轮全量 DB）。
    final visible = _usePagination ? const <FavoriteItem>[] : _visibleComics;
    // 方案 D：下拉刷新重载当前文件夹；「更新漫画信息」仍留在管理弹窗里，
    // 不因为加了手势就把重操作藏起来。
    Widget body = RefreshIndicator(
      onRefresh: _onPullRefresh,
      child: SmoothCustomScrollView(
      controller: widget.controller,
      // 空文件夹也要能下拉刷新；末尾留白避开浮岛 dock 与多选贴底工具条。
      alwaysScrollable: true,
      bottomPadding:
          kcPageBottomInset(context) +
          kcDockedToolbarLift +
          (multiSelectMode ? kcMinTapTarget + kcSpaceMd : 0.0),
      slivers: [
        // 文件夹胶囊条：常驻顶栏下方（pinned），滚到列表深处也能直接换文件夹。
        // 共享顶栏接管后它就是首个 sliver，自动贴在共享栏下面。
        if (!multiSelectMode)
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverFolderChipsHeader(_GroupPills(favPage: favPage)),
          ),
        // 方案 B：筛选状态常驻的 chip 行（选中态 + 结果数 + 重置），取代
        // 原来只在筛选生效时才出现的单行提示条 —— 提示条只说「正在筛选」，
        // 不说「按什么筛」，关掉弹窗后当前条件仍然没有文字证据。
        if (!multiSelectMode)
          SliverToBoxAdapter(child: _buildFilterChips()),
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
      ),
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
        child: Stack(
          children: [
            body,
            // 方案 C：多选态动作不再挂在右上角，改为贴底工具条（浮岛 dock
            // 上方），与历史页同一套语言。
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
              padding: EdgeInsets.only(bottom: context.padding.bottom + kcSpaceLg),
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

  /// 当前收藏排序键（manual / recent / name）。
  String get _sortKey =>
      (appdata.settings['favoriteSort'] as String?) ?? 'recent';

  /// 文件夹管理子页（弹窗形态）：重命名 / 手动排序 / 导出 / 更新信息 / 删除。
  /// 用 ContentDialog + KcListTile，与「导入方式」等选择弹窗同一套语言；
  /// 点任一项先关弹窗再执行，避免重命名 / 删除的确认框叠在本弹窗上面。
  void _showFolderManageDialog() {
    showDialog(
      context: context,
      builder: (ctx) => ContentDialog(
        title: "Manage Folder".tl,
        subtitle: widget.folder,
        headerIcon: HugeIcons.strokeRoundedFolder01,
        showClose: false,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _folderManageTile(
              icon: HugeIcons.strokeRoundedEdit01,
              title: "Rename".tl,
              onTap: _renameFolder,
            ),
            _folderManageTile(
              icon: HugeIcons.strokeRoundedArrange,
              title: "Reorder".tl,
              onTap: _reorderFolderComics,
            ),
            _folderManageTile(
              icon: HugeIcons.strokeRoundedUpload01,
              title: "Export".tl,
              onTap: _exportFolder,
            ),
            _folderManageTile(
              icon: HugeIcons.strokeRoundedRefresh,
              title: "Update Comics Info".tl,
              onTap: _refreshFolderComicsInfo,
            ),
            const KcRowDivider(),
            _folderManageTile(
              icon: HugeIcons.strokeRoundedDelete01,
              title: "Delete Folder".tl,
              color: context.colorScheme.error,
              onTap: _deleteFolder,
            ),
          ],
        ),
        actions: [
          Button.text(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text("Cancel".tl),
          ),
        ],
      ),
    );
  }

  Widget _folderManageTile({
    required List<List<dynamic>> icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return KcListTile(
      leading: HugeIcon(icon: icon, size: 18, color: color),
      title: Text(
        title,
        style: TextStyle(fontSize: kcBody, color: color),
      ),
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      showDivider: false,
    );
  }

  void _renameFolder() {
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
        BookshelfLayout.onFolderRenamed(widget.folder, value.toString());
        favPage.folderList?.updateFolders();
        favPage.setFolder(false, value.toString());
        return null;
      },
    );
  }

  void _reorderFolderComics() {
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
  }

  void _exportFolder() {
    var json = LocalFavoritesManager().folderToJson(widget.folder);
    saveFile(data: utf8.encode(json), filename: "${widget.folder}.json");
  }

  void _refreshFolderComicsInfo() {
    updateComicsInfo(widget.folder).then((newComics) {
      if (mounted) {
        setState(() {
          comics = newComics;
          // 数据源整体换了一份，筛选缓存要跟着重算。
          _invalidateVisible();
        });
      }
    });
  }

  void _deleteFolder() {
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
  }

  /// 清除阅读状态筛选（辅助行「重置」/ 空态按钮共用）。
  void _clearFilter() {
    setState(() {
      readFilterSelect = readFilterList[0];
    });
    appdata.implicitData["local_favorites_read_filter"] = readFilterSelect;
    appdata.writeImplicitData();
    _invalidateVisible();
    // 切回「全部」会翻回分页视图，网格要自己重载一次。
    if (_usePagination) _gridKey.currentState?.refresh();
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
              gridDelegate: SliverGridDelegateWithComics(
                textScale:
                    MediaQuery.textScalerOf(context).scale(kcBody) / kcBody,
              ),
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

/// 阅读状态筛选的可选值（chip 行的唯一数据源）。
const readFilterList = [
  'All',
  'Unread',
  'UnCompleted',
  'Completed',
  'RecentlyUpdated',
  'NotDownloaded',
];
