part of 'favorites_page.dart';

/// 网络收藏子页统一拦返回：先退回货架总览，而不是直接弹「确认退出」。
///
/// 这几个页面自身没有多选 / 搜索态（选择集由外部传入），返回键可以一路
/// 交给总览；真正需要先吃掉返回的弹层都是独立 route，会先于这里处理。
Widget _withBackToOverview(_FavoritesPageState favPage, Widget child) {
  return PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) return;
      favPage.setFolder(false, null);
    },
    child: child,
  );
}

Future<bool> _deleteComic(
  String cid,
  String? fid,
  String sourceKey,
  String? favId, {
  /// 撤销成功后重新拉一次列表（调用方持有 ComicListState 的 key）。
  VoidCallback? onRefresh,
}) async {
  var source = ComicSource.find(sourceKey);
  if (source == null) {
    return false;
  }

  var result = false;

  await showDialog(
    context: App.rootContext,
    builder: (context) {
      bool loading = false;
      return StatefulBuilder(
        builder: (context, setState) {
          return ContentDialog(
            title: "Remove".tl,
            content: Text(
              "Remove comic from favorite?".tl,
            ).paddingHorizontal(16),
            actions: [
              Button.text(
                onPressed: context.pop,
                child: Text("Cancel".tl),
              ),
              Button.filled(
                isLoading: loading,
                color: context.colorScheme.error,
                onPressed: () async {
                  setState(() {
                    loading = true;
                  });
                  var res = await source.favoriteData!.addOrDelFavorite!(
                    cid,
                    fid ?? '',
                    false,
                    favId,
                  );
                  if (!context.mounted) return;
                  if (res.success) {
                    // Invalidate network cache so next loads fetch fresh data
                    NetworkCacheManager().clear();
                    result = true;
                    context.pop();
                    // 删除是远端写操作，误删后重新搜索很贵：给 5 秒反悔窗口。
                    // 撤销重新调用同一接口把收藏加回，成功后只刷新列表做
                    // 界面内反馈；失败才提示错误（showUndoMessage 内部用
                    // App.rootContext，不依赖已 pop 的 dialog context）。
                    showUndoMessage(
                      message: "Deleted".tl,
                      onUndo: () async {
                        final undo = await source.favoriteData!
                            .addOrDelFavorite!(cid, fid ?? '', true, favId);
                        if (!undo.success) {
                          App.rootContext.showMessage(
                            message: friendlySourceError(undo.errorMessage),
                          );
                          return;
                        }
                        NetworkCacheManager().clear();
                        onRefresh?.call();
                      },
                    );
                  } else {
                    setState(() {
                      loading = false;
                    });
                    context.showMessage(
                      message: friendlySourceError(res.errorMessage),
                    );
                  }
                },
                child: Text("Confirm".tl),
              ),
            ],
          );
        },
      );
    },
  );

  return result;
}

class NetworkFavoritePage extends StatelessWidget {
  const NetworkFavoritePage(this.data, {this.controller, super.key});

  final FavoriteData data;

  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return data.multiFolder
        ? _MultiFolderFavoritesPage(data, controller)
        : _NormalFavoritePage(data, controller);
  }
}

class _NormalFavoritePage extends StatefulWidget {
  const _NormalFavoritePage(this.data, this.controller);

  final FavoriteData data;

  final ScrollController? controller;

  @override
  State<_NormalFavoritePage> createState() => _NormalFavoritePageState();
}

class _NormalFavoritePageState extends State<_NormalFavoritePage> {
  final comicListKey = GlobalKey<ComicListState>();

  void showFolders() {
    context
        .findAncestorStateOfType<_FavoritesPageState>()
        ?.showFolderSelector();
  }

  @override
  Widget build(BuildContext context) {
    final favPage = context.findAncestorStateOfType<_FavoritesPageState>()!;
    // 顶栏已并入 NaviPane 共享栏：正常 / 错误 / 未登录态共用同一注入
    //（build 是三态的共同入口）。
    favPage.pushTopBar(
      sig: 'net_${widget.data.key}',
      leading: Tooltip(
        message: "Favorites".tl,
        child: IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, size: 18),
          onPressed: () => favPage.setFolder(false, null),
        ),
      ),
      title: Text(
        widget.data.title,
        style: TextStyle(fontSize: kcTitleMain, fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
      ),
      actions: [favPage._favToolsPill(context, _pillChildren(favPage))],
      // 内层工具胶囊已有夹内搜索，右上角不重复全局搜索/设置入口。
      hideGlobalActions: true,
    );
    // 库页面不显示「已收藏」角标（见 FavoriteBadgeScope 文档）。
    return FavoriteBadgeScope.disabled(
      child: _withBackToOverview(favPage, _buildList(favPage)),
    );
  }

  /// 网络收藏页工具胶囊条内容（原 SliverAppbar 的 actions 原样迁移）。
  List<Widget> _pillChildren(_FavoritesPageState favPage) {
    return [
      // 布局切换单图标：与「本地」收藏、历史页同一套（形状即当前布局）。
      const ToolsPillLayoutButton(),
      favPage._toolIconButton(
        context,
        icon: HugeIcons.strokeRoundedRefresh,
        tooltip: "Refresh".tl,
        onPressed: () {
          // Force refresh bypassing cache
          NetworkCacheManager().clear();
          comicListKey.currentState!.refresh();
        },
      ),
      favPage._toolMoreButton(context, [
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
          text: "Convert to local".tl,
          onClick: () {
            importNetworkFolder(widget.data.key, 9999999, null, null);
          },
        ),
      ]),
    ];
  }

  Widget _buildList(_FavoritesPageState favPage) {
    return ComicList(
      key: comicListKey,
      controller: widget.controller,
      showSourceOnCover: false,
      showBottomSourceDate: true,
      openLocalIfAvailable: true,
      leadingSliver: MultiSliver(
        children: [
          // 文件夹胶囊条常驻顶栏下方（pinned，不随列表滚走）。
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverFolderChipsHeader(_GroupPills(favPage: favPage)),
          ),
        ],
      ),
      // 错误 / 未登录态不能用 leadingSliver，胶囊单独补在共享顶栏下方，
      // 否则会卡在网络源错误页里没有分组切换入口（顶栏本身由共享栏提供）。
      errorLeading: Column(
        mainAxisSize: MainAxisSize.min,
        // stretch 让胶囊与正常态一样左对齐、占满整行，而不是被 Column 居中。
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_GroupPills(favPage: favPage)],
      ),
      loadPage: widget.data.loadComic == null
          ? null
          : (i) => widget.data.loadComic!(i),
      loadNext: widget.data.loadNext == null
          ? null
          : (next) => widget.data.loadNext!(next),
      menuBuilder: (comic) {
        return [
          MenuEntry(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedDownload04,
              size: 18,
              color: context.colorScheme.onSurfaceVariant,
            ),
            color: context.colorScheme.onSurfaceVariant,
            text: "Download".tl,
            onClick: () {
              var source = ComicSource.find(comic.sourceKey);
              if (source == null) {
                context.showMessage(message: "Source not found".tl);
                return;
              }
              if (LocalManager().isDownloaded(
                comic.id,
                ComicType.fromKey(comic.sourceKey),
              )) {
                context.showMessage(message: "Already downloaded".tl);
                return;
              }
              LocalManager().addTask(
                ImagesDownloadTask(
                  source: source,
                  comicId: comic.id,
                  comicTitle: comic.title,
                ),
              );
              context.showMessage(message: "Download started".tl);
            },
          ),
          MenuEntry(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
            text: "Remove".tl,
            onClick: () async {
              var res = await _deleteComic(
                comic.id,
                null,
                comic.sourceKey,
                comic.favoriteId,
                onRefresh: () {
                  comicListKey.currentState?.refresh();
                },
              );
              if (res) {
                comicListKey.currentState!.remove(comic);
              }
            },
          ),
        ];
      },
      enablePageStorage: true,
    );
  }
}

class _MultiFolderFavoritesPage extends StatefulWidget {
  const _MultiFolderFavoritesPage(this.data, this.controller);

  final FavoriteData data;

  final ScrollController? controller;

  @override
  State<_MultiFolderFavoritesPage> createState() =>
      _MultiFolderFavoritesPageState();
}

class _MultiFolderFavoritesPageState extends State<_MultiFolderFavoritesPage> {
  bool _loading = true;

  String? _errorMessage;

  Map<String, String>? folders;

  @override
  void initState() {
    super.initState();
    // Loading used to be kicked off from `build()` behind an `if (_loading)`,
    // which re-fired the request on every rebuild and left no way to recover
    // when `loadFolders` threw instead of returning an error.
    loadPage();
  }

  void showFolders() {
    context
        .findAncestorStateOfType<_FavoritesPageState>()
        ?.showFolderSelector();
  }

  void loadPage() async {
    Map<String, String>? loadedFolders;
    String? error;
    try {
      final res = await widget.data.loadFolders!();
      if (res.error) {
        error = res.errorMessage;
      } else {
        loadedFolders = res.data;
      }
    } catch (e) {
      error = e.toString();
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _errorMessage = error;
      if (error == null) {
        folders = loadedFolders;
      }
    });
  }

  void retry() {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    loadPage();
  }

  void openFolder(String key, String title) {
    context.to(() => _FavoriteFolder(widget.data, key, title));
  }

  @override
  Widget build(BuildContext context) {
    final favPage = context.findAncestorStateOfType<_FavoritesPageState>()!;
    // multiFolder 子页此前不注入共享顶栏：总览注入的「收藏」栏会残留，
    // 页面自己又画一条 SliverAppbar → 顶栏双层、标题与当前视图不符。
    // 与 _NormalFavoritePage 对齐，统一走 pushTopBar、去掉自绘栏。
    favPage.pushTopBar(
      sig: 'netMulti_${widget.data.key}',
      leading: Tooltip(
        message: "Favorites".tl,
        child: IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, size: 18),
          onPressed: () => favPage.setFolder(false, null),
        ),
      ),
      title: GestureDetector(
        onTap: showFolders,
        child: Text(
          widget.data.title,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      hideGlobalActions: true,
    );
    return _withBackToOverview(favPage, _buildBody(context));
  }

  Widget _buildBody(BuildContext context) {
    final favPage = context.findAncestorStateOfType<_FavoritesPageState>()!;
    // 文件夹行是按 1.0 字号的 52dp 定高的；系统字号放大后文字会换行把
    // 固定行格撑破。行格随 textScaler 一起放大，名称仍强制单行省略。
    final rowScale =
        MediaQuery.textScalerOf(context).scale(kcSubtitle) / kcSubtitle;

    if (_loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupPills(favPage: favPage),
          const Expanded(child: KcPageLoading()),
        ],
      );
    } else if (_errorMessage != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupPills(favPage: favPage),
          Expanded(
            child: NetworkError(
              message: friendlyError(_errorMessage!),
              withAppbar: false,
              retry: retry,
            ),
          ),
        ],
      );
    } else if (folders != null) {
      var length = folders!.length;
      if (widget.data.allFavoritesId != null) length++;
      final keys = folders!.keys.toList();

      return SmoothCustomScrollView(
        controller: widget.controller,
        slivers: [
          // 文件夹胶囊条常驻顶栏下方（pinned，不随列表滚走）。
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverFolderChipsHeader(_GroupPills(favPage: favPage)),
          ),
          SliverGridViewWithFixedItemHeight(
            delegate: SliverChildBuilderDelegate(childCount: length, (
              context,
              i,
            ) {
              if (widget.data.allFavoritesId != null) {
                if (i == 0) {
                  return _FolderTile(
                    name: "All".tl,
                    onTap: () =>
                        openFolder(widget.data.allFavoritesId!, "All".tl),
                  );
                } else {
                  i--;
                  return _FolderTile(
                    name: folders![keys[i]]!,
                    onTap: () => openFolder(keys[i], folders![keys[i]]!),
                    deleteFolder: widget.data.deleteFolder == null
                        ? null
                        : () => widget.data.deleteFolder!(keys[i]),
                    updateState: retry,
                  );
                }
              } else {
                return _FolderTile(
                  name: folders![keys[i]]!,
                  onTap: () => openFolder(keys[i], folders![keys[i]]!),
                  deleteFolder: widget.data.deleteFolder == null
                      ? null
                      : () => widget.data.deleteFolder!(keys[i]),
                  updateState: retry,
                );
              }
            }),
            maxCrossAxisExtent: 450,
            itemHeight: 52 * rowScale,
          ),
          if (widget.data.addFolder != null)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 60,
                width: double.infinity,
                child: Center(
                  child: Button.text(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Create a folder".tl),
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedAddCircle,
                          size: 18,
                        ),
                      ],
                    ),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return _CreateFolderDialog(widget.data, retry);
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      );
    } else {
      // Loaded successfully but the source returned no folder map. Reaching
      // this used to be impossible to distinguish from a crash on `folders!`.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupPills(favPage: favPage),
          Expanded(child: Center(child: Text("No folders".tl))),
        ],
      );
    }
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.name,
    required this.onTap,
    this.deleteFolder,
    this.updateState,
  });

  final String name;

  final Future<Res<bool>> Function()? deleteFolder;

  final void Function()? updateState;

  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(kcRadius8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kcSpaceLg, 10, kcSpaceLg, 10),
          child: Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedFolder01,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: kcSpaceMd),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: kcSubtitle,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (deleteFolder != null)
                IconButton(
                  tooltip: "Delete".tl,
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedDelete01,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  onPressed: () => onDeleteFolder(context),
                )
              else
                HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowRight01,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void onDeleteFolder(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        bool loading = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return ContentDialog(
              title: "Delete".tl,
              content: Text("Delete folder?".tl).paddingHorizontal(16),
              actions: [
                Button.filled(
                  isLoading: loading,
                  color: context.colorScheme.error,
                  onPressed: () async {
                    setState(() {
                      loading = true;
                    });
                    var res = await deleteFolder!();
                    if (!context.mounted) return;
                    if (res.success) {
                      context.showMessage(message: "Deleted".tl);
                      context.pop();
                      updateState?.call();
                    } else {
                      setState(() {
                        loading = false;
                      });
                      context.showMessage(
                        message: friendlySourceError(res.errorMessage),
                      );
                    }
                  },
                  child: Text("Confirm".tl),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _CreateFolderDialog extends StatefulWidget {
  const _CreateFolderDialog(this.data, this.updateState);

  final FavoriteData data;

  final void Function() updateState;

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  var controller = TextEditingController();
  bool loading = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: "Create a folder".tl,
      content: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(kcSpaceLg, 0, kcSpaceLg, 0),
            child: TextField(
              controller: controller,
              decoration: kcInputDecoration(context, labelText: "name".tl),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      actions: [
        Button.filled(
          isLoading: loading,
          onPressed: () {
            setState(() {
              loading = true;
            });
            widget.data.addFolder!(controller.text).then((b) {
              // 请求在飞时用户可点遮罩关掉弹窗（barrierDismissible）：
              // 对已卸载的 dialog context pop 会把底下的网络收藏页弹掉。
              if (!context.mounted) return;
              if (b.error) {
                context.showMessage(
                  message: friendlySourceError(b.errorMessage),
                );
                setState(() {
                  loading = false;
                });
              } else {
                context.pop();
                context.showMessage(message: "Created successfully".tl);
                widget.updateState();
              }
            });
          },
          child: Text("Submit".tl),
        ),
      ],
    );
  }
}

class _FavoriteFolder extends StatelessWidget {
  _FavoriteFolder(this.data, this.folderID, this.title);

  final FavoriteData data;

  final String folderID;

  final String title;

  final comicListKey = GlobalKey<ComicListState>();

  @override
  Widget build(BuildContext context) {
    return ComicList(
      key: comicListKey,
      enablePageStorage: true,
      allFavorite: true,
      showSourceOnCover: false,
      showBottomSourceDate: true,
      openLocalIfAvailable: true,
      leadingSliver: SliverAppbar(
        title: Text(title),
        actions: [
          MenuButton(
            entries: [
              MenuEntry(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
                text: "Convert to local".tl,
                onClick: () {
                  importNetworkFolder(data.key, 9999999, title, folderID);
                },
              ),
            ],
          ),
        ],
      ),
      errorLeading: Appbar(title: Text(title)),
      loadPage: data.loadComic == null
          ? null
          : (i) => data.loadComic!(i, folderID),
      loadNext: data.loadNext == null
          ? null
          : (next) => data.loadNext!(next, folderID),
      menuBuilder: (comic) {
        return [
          MenuEntry(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedDownload04,
              size: 18,
              color: context.colorScheme.onSurfaceVariant,
            ),
            color: context.colorScheme.onSurfaceVariant,
            text: "Download".tl,
            onClick: () {
              var source = ComicSource.find(comic.sourceKey);
              if (source == null) {
                context.showMessage(message: "Source not found".tl);
                return;
              }
              if (LocalManager().isDownloaded(
                comic.id,
                ComicType.fromKey(comic.sourceKey),
              )) {
                context.showMessage(message: "Already downloaded".tl);
                return;
              }
              LocalManager().addTask(
                ImagesDownloadTask(
                  source: source,
                  comicId: comic.id,
                  comicTitle: comic.title,
                ),
              );
              context.showMessage(message: "Download started".tl);
            },
          ),
          MenuEntry(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
            text: "Remove".tl,
            onClick: () async {
              var res = await _deleteComic(
                comic.id,
                null,
                comic.sourceKey,
                comic.favoriteId,
                onRefresh: () {
                  comicListKey.currentState?.refresh();
                },
              );
              if (res) {
                comicListKey.currentState!.remove(comic);
              }
            },
          ),
        ];
      },
    );
  }
}
