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

  String keyword = "";
  bool searchHasUpper = false;

  bool searchMode = false;

  bool multiSelectMode = false;

  int? lastSelectedIndex;

  bool get isAllFolder => widget.folder == _localAllFolderLabel;

  /// Reused across flyout rebuilds so the select-page widget keeps its state.
  final _selectUpdatePageNumKey = GlobalKey<_SelectUpdatePageNumState>();

  LocalFavoritesManager get manager => LocalFavoritesManager();

  late String readFilterSelect;

  var searchResults = <FavoriteItem>[];

  /// GlobalKey for the paginated grid.
  final _gridKey = GlobalKey<PaginatedSliverGridComicsState>();

  /// Comics currently loaded by the paginated grid.
  List<FavoriteItem> _loadedComics = [];

  /// Whether to use pagination for the current view.
  /// Only paginates single-folder browsing with no search/filter.
  bool get _usePagination =>
      !searchMode && !isAllFolder && readFilterSelect == readFilterList[0];

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
  /// In search mode, this is the search results.
  /// Otherwise, this is the filtered comics list.
  List<FavoriteItem> get _activeComics => _usePagination
      ? _loadedComics
      : (searchMode ? searchResults : filterComics(comics));

  void updateSearchResult() {
    setState(() {
      if (keyword.trim().isEmpty) {
        searchResults = comics;
      } else {
        searchResults = [];
        for (var comic in comics) {
          if (matchKeyword(keyword, comic) ||
              matchKeywordT(keyword, comic) ||
              matchKeywordS(keyword, comic)) {
            searchResults.add(comic);
          }
        }
      }
    });
  }

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

  bool matchKeyword(String keyword, FavoriteItem comic) {
    var list = keyword.split(" ");
    for (var k in list) {
      if (k.isEmpty) continue;
      if (checkKeyWordMatch(k, comic.title, false)) {
        continue;
      } else if (comic.subtitle != null &&
          checkKeyWordMatch(k, comic.subtitle!, false)) {
        continue;
      } else if (comic.tags.any((tag) {
        if (checkKeyWordMatch(k, tag, true)) {
          return true;
        } else if (tag.contains(':') &&
            checkKeyWordMatch(k, tag.split(':')[1], true)) {
          return true;
        } else if (App.locale.languageCode == 'zh' &&
            checkKeyWordMatch(k, tag.translateTagsToCN, true)) {
          return true;
        }
        return false;
      })) {
        continue;
      } else if (checkKeyWordMatch(k, comic.author, true)) {
        continue;
      }
      return false;
    }
    return true;
  }

  bool checkKeyWordMatch(String keyword, String compare, bool needEqual) {
    String temp = compare;
    // 没有大写的话, 就转成小写比较, 避免搜索需要注意大小写
    if (!searchHasUpper) {
      temp = temp.toLowerCase();
    }
    if (needEqual) {
      return keyword == temp;
    }
    return temp.contains(keyword);
  }

  // Convert keyword to traditional Chinese to match comics
  bool matchKeywordT(String keyword, FavoriteItem comic) {
    if (!OpenCC.hasChineseSimplified(keyword)) {
      return false;
    }
    keyword = OpenCC.simplifiedToTraditional(keyword);
    return matchKeyword(keyword, comic);
  }

  // Convert keyword to simplified Chinese to match comics
  bool matchKeywordS(String keyword, FavoriteItem comic) {
    if (!OpenCC.hasChineseTraditional(keyword)) {
      return false;
    }
    keyword = OpenCC.traditionalToSimplified(keyword);
    return matchKeyword(keyword, comic);
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
      if (searchMode) {
        selectedComics = searchResults.asMap().map((k, v) => MapEntry(v, true));
      } else if (_usePagination) {
        // Load all comics from the folder for selection (one-time).
        final allComics = manager.getFolderComics(widget.folder);
        selectedComics = allComics.asMap().map((k, v) => MapEntry(v, true));
      } else {
        selectedComics = comics.asMap().map((k, v) => MapEntry(v, true));
      }
    });
  }

  void invertSelection() {
    setState(() {
      if (searchMode) {
        for (var c in searchResults) {
          if (selectedComics.containsKey(c)) {
            selectedComics.remove(c);
          } else {
            selectedComics[c] = true;
          }
        }
      } else if (_usePagination) {
        for (var c in _loadedComics) {
          if (selectedComics.containsKey(c)) {
            selectedComics.remove(c);
          } else {
            selectedComics[c] = true;
          }
        }
      } else {
        for (var c in comics) {
          if (selectedComics.containsKey(c)) {
            selectedComics.remove(c);
          } else {
            selectedComics[c] = true;
          }
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
      if (!isAllFolder)
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
          text: "Delete".tl,
          onClick: () {
            LocalFavoritesManager().deleteComicWithId(
              widget.folder,
              c.id,
              (c as FavoriteItem).type,
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
              MenuEntry(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedFavourite,
                  size: 18,
                ),
                text: "Remove from favorites".tl,
                onClick: () {
                  for (var c in selectedComics.keys) {
                    var fav = c as FavoriteItem;
                    if (isAllFolder) {
                      // In All view, find which folder the comic belongs to
                      for (var f in LocalFavoritesManager().folderNames) {
                        var folderComics = LocalFavoritesManager()
                            .getFolderComics(f);
                        if (folderComics.any(
                          (fc) =>
                              fc.id == fav.id &&
                              fc.type.value == fav.type.value,
                        )) {
                          LocalFavoritesManager().deleteComicWithId(
                            f,
                            fav.id,
                            fav.type,
                          );
                          break;
                        }
                      }
                    } else {
                      LocalFavoritesManager().deleteComicWithId(
                        widget.folder,
                        fav.id,
                        fav.type,
                      );
                    }
                  }
                  setState(() {
                    multiSelectMode = false;
                    selectedComics.clear();
                  });
                },
              ),
              if (!isAllFolder)
                MenuEntry(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedDelete01,
                    size: 18,
                  ),
                  text: "Delete Comic".tl,
                  color: context.colorScheme.error,
                  onClick: () {
                    showConfirmDialog(
                      context: context,
                      title: "Delete".tl,
                      content: "Delete @c comics?".tlParams({
                        "c": selectedComics.length,
                      }),
                      btnColor: context.colorScheme.error,
                      onConfirm: () {
                        _deleteComicWithId();
                      },
                    );
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
            ],
          ),
        ],
      ),
    ];
  }

  /// 搜索态注入共享顶栏：leading 取消 + 标题位直接放输入框
  ///（这就是 pageTitleNotifier 升级为 Widget 的原因）。
  List<Widget> _searchLeading() {
    return [
      Tooltip(
        message: "Cancel".tl,
        child: IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
          onPressed: () {
            setState(() {
              searchMode = false;
            });
          },
        ),
      ),
    ];
  }

  Widget _searchTitleField() {
    return TextField(
      autofocus: true,
      decoration: InputDecoration(
        hintText: "Search".tl,
        border: UnderlineInputBorder(),
      ),
      onChanged: (v) {
        keyword = v;
        searchHasUpper = keyword.contains(RegExp(r'[A-Z]'));
        updateSearchResult();
      },
    ).paddingBottom(8).paddingRight(8);
  }

  /// 把本页（普通 / 多选 / 搜索三态）的顶栏内容同步进 NaviPane 共享栏。
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
    } else if (searchMode) {
      sig = 'search';
      leading = _searchLeading().first;
      title = _searchTitleField();
    } else {
      sig = 'n_${readFilterSelect}_${networkSource ?? 'l'}';
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
      // 布局切换双态分段：左「网格(简明)」/ 右「列表(详细)」，当前态高亮
      // accent 红。与历史页同一套写法，翻的是全局 comicDisplayMode，
      // 下方 PaginatedSliverGridComics/SliverGridComics 经 AnimatedBuilder
      // 自动重建，无需手动刷新。
      ToolsPillSegment(
        icons: const [
          HugeIcons.strokeRoundedGridView,
          HugeIcons.strokeRoundedListView,
        ],
        tooltips: ["Switch to grid view".tl, "Switch to list view".tl],
        selectedIndex: appdata.settings['comicDisplayMode'] != 'brief' ? 1 : 0,
        onSelected: (_) {
          appdata.settings['comicDisplayMode'] =
              appdata.settings['comicDisplayMode'] != 'brief'
              ? 'brief'
              : 'detailed';
          appdata.saveData();
          setState(() {});
        },
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
      favPage._toolIconButton(
        context,
        icon: HugeIcons.strokeRoundedSearch02,
        tooltip: "Search".tl,
        onPressed: () {
          setState(() {
            keyword = "";
            searchMode = true;
            updateSearchResult();
          });
        },
      ),
      // 「更多」始终显示：排序/筛选也住在里面（原独立按钮已收编）。
      favPage._toolMoreButton(context, _buildMoreEntries()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // 顶栏已并入 NaviPane 共享栏：三种模式（普通 / 多选 / 搜索）各自注入
    // leading / 标题 / 工具，见 [_syncTopBar]。
    _syncTopBar();
    Widget body = SmoothCustomScrollView(
      controller: widget.controller,
      slivers: [
        // 文件夹胶囊条：常驻顶栏下方（pinned），滚到列表深处也能直接换文件夹。
        // 共享顶栏接管后它就是首个 sliver，自动贴在共享栏下面。
        if (!searchMode && !multiSelectMode)
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverFolderChipsHeader(_GroupPills(favPage: favPage)),
          ),
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
        else if (!searchMode &&
            !multiSelectMode &&
            filterComics(comics).isEmpty)
          SliverFillRemaining(child: _buildEmptyState())
        else
          SliverGridComics(
            comics: searchMode ? searchResults : filterComics(comics),
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
    return PopScope(
      // 收藏页是「货架总览 → 文件夹」两层：文件夹视图里返回键先退回总览，
      // 而不是直接弹「确认退出」（总览是 tab 根页，那才是该退出的位置）。
      // 多选 / 搜索优先吃掉返回，与之前一致。
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (multiSelectMode) {
          setState(() {
            multiSelectMode = false;
            selectedComics.clear();
          });
        } else if (searchMode) {
          setState(() {
            searchMode = false;
            keyword = "";
            updateComics();
          });
        } else {
          favPage.setFolder(false, null);
        }
      },
      child: body,
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

  void _deleteComicWithId() {
    var toBeDeleted = selectedComics.keys
        .map((e) => e as FavoriteItem)
        .toList();
    LocalFavoritesManager().batchDeleteComics(widget.folder, toBeDeleted);
    _cancel();
  }

  /// 「更多」菜单项：从原 MenuButton 的 entries 抽出，供工具胶囊条的更多按钮复用。
  /// 「更多」菜单项：排序组 + 筛选 + 文件夹管理（仅具体文件夹）+ 设置。
  /// 排序/筛选从独立胶囊按钮收编进来，给共享顶栏的标题腾宽度。
  List<MenuEntry> _buildMoreEntries() {
    final current = appdata.settings['favoriteSort'] as String?;
    Widget check(bool on) => HugeIcon(
      icon: on
          ? HugeIcons.strokeRoundedCheckmarkCircle02
          : HugeIcons.strokeRoundedCircle,
      size: 15,
      color: on
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return [
      // 排序：全局 favoriteSort 设置（manual/recent/name），单选打勾。
      // 总览货架与「全部」视图读同一份设置，即时同步。
      MenuEntry(
        text: "Manual order".tl,
        icon: check(current == 'manual'),
        onClick: () => _onSortSelected('manual'),
      ),
      MenuEntry(
        text: "Recently favorited".tl,
        icon: check(current == 'recent'),
        onClick: () => _onSortSelected('recent'),
      ),
      MenuEntry(
        text: "By title".tl,
        icon: check(current == 'name'),
        onClick: () => _onSortSelected('name'),
      ),
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
                BookshelfLayout.onFolderRenamed(widget.folder, value.toString());
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
            saveFile(data: utf8.encode(json), filename: "${widget.folder}.json");
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
                });
              }
            });
          },
        ),
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
      // 收藏页自绘顶栏后，全局共享顶栏的「设置」入口随之让位；
      // 设置是全局功能，不该在收藏页彻底消失，收进「更多」兜底。
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings01, size: 18),
        text: "Settings".tl,
        onClick: () => context.to(() => const SettingsPage()),
      ),
    ];
  }

  /// 空状态：当前文件夹没有收藏时，用文件夹插画 + 引导文案取代空白。
  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    // 过滤器生效时空态必须说清「是筛选没命中」。
    //
    // 阅读状态筛选会被持久化到 implicitData，下次进来依然生效；而侧栏文件夹上
    // 的数字是总数、不受筛选影响。于是「左边显示 2、右边一片空白」看起来就像
    // 收藏丢了 —— 之前这里只说「这个文件夹是空的，去发现页添加漫画」，
    // 完全没提筛选，用户根本想不到要点筛选按钮。
    final filterActive = readFilterSelect != readFilterList[0];
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedFolder01,
              size: 72,
              color: cs.onSurfaceVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              filterActive
                  ? "No comics match the current filter".tl
                  : "This folder is empty".tl,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: kcSubtitle,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filterActive
                  ? "Clear the filter to see every comic in this folder".tl
                  : "Add comics from the Discover page".tl,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: kcCaption,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            if (filterActive) ...[
              const SizedBox(height: 16),
              Button.filled(
                onPressed: () {
                  setState(() {
                    readFilterSelect = readFilterList[0];
                  });
                  appdata.implicitData["local_favorites_read_filter"] =
                      readFilterSelect;
                  appdata.writeImplicitData();
                },
                child: Text("Clear filter".tl),
              ),
            ],
          ],
        ),
      ),
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
