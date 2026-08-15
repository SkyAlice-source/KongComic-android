part of 'favorites_page.dart';

Future<bool> _deleteComic(
  String cid,
  String? fid,
  String sourceKey,
  String? favId,
) async {
  var source = ComicSource.find(sourceKey);
  if (source == null) {
    return false;
  }

  var result = false;

  await showDialog(
    context: App.rootContext,
    builder: (context) {
      bool loading = false;
      return StatefulBuilder(builder: (context, setState) {
        return ContentDialog(
          title: "Remove".tl,
          content: Text("Remove comic from favorite?".tl).paddingHorizontal(16),
          actions: [
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
                if (res.success) {
                  // Invalidate network cache so next loads fetch fresh data
                  NetworkCacheManager().clear();
                  context.showMessage(message: "Deleted".tl);
                  result = true;
                  context.pop();
                } else {
                  setState(() {
                    loading = false;
                  });
                  context.showMessage(message: friendlyError(res.errorMessage!));
                }
              },
              child: Text("Confirm".tl),
            ),
          ],
        );
      });
    },
  );

  return result;
}

/// 收藏页内部栏的“文件夹”上下文：降级为次级 chip（不再作为第二根标题栏）。
/// 点击展开文件夹选择器，视觉权重明显低于全局主标题“收藏”。
Widget _folderChip(BuildContext context, String title, VoidCallback? onTap) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(kcChipRadius),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(kcChipRadius),
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedFolder01,
            size: 16,
            color: cs.primary,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.38,
            ),
            child: Text(
              title,
              style: const TextStyle(fontSize: kcFont13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          HugeIcon(
            icon: HugeIcons.strokeRoundedArrowDown01,
            size: 14,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    ),
  );
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
    return ComicList(
      key: comicListKey,
      controller: widget.controller,
      showSourceOnCover: false,
      showBottomSourceDate: true,
      openLocalIfAvailable: true,
      leadingSliver: SliverAppbar(
        style:
            context.width < changePoint ? AppbarStyle.shadow : AppbarStyle.blur,
        leading: Tooltip(
          message: "Folders".tl,
          child: context.width <= _kTwoPanelChangeWidth
              ? IconButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedMenu02, size: 18),
                  color: context.colorScheme.primary,
                  onPressed: showFolders,
                )
              : null,
        ),
        title: _folderChip(
          context,
          widget.data.title,
          context.width < _kTwoPanelChangeWidth ? showFolders : null,
        ),
        actions: [
          Tooltip(
            message: "Refresh".tl,
            child: IconButton(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
              onPressed: () {
                // Force refresh bypassing cache
                NetworkCacheManager().clear();
                comicListKey.currentState!.refresh();
              },
            ),
          ),
          MenuButton(entries: [
            MenuEntry(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
              text: "Convert to local".tl,
              onClick: () {
                importNetworkFolder(widget.data.key, 9999999, null, null);
              },
            )
          ]),
        ],
      ),
      errorLeading: Appbar(
        leading: Tooltip(
          message: "Folders".tl,
          child: context.width <= _kTwoPanelChangeWidth
              ? IconButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedMenu02, size: 18),
                  color: context.colorScheme.primary,
                  onPressed: context
                      .findAncestorStateOfType<_FavoritesPageState>()
                      ?.showFolderSelector,
                )
              : null,
        ),
        title: _folderChip(
          context,
          widget.data.title,
          context.width < _kTwoPanelChangeWidth ? showFolders : null,
        ),
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
              color: context.colorScheme.primary,
            ),
            color: context.colorScheme.primary,
            text: "Download".tl,
            onClick: () {
              var source = ComicSource.find(comic.sourceKey);
              if (source == null) {
                context.showMessage(message: "Source not found".tl);
                return;
              }
              if (LocalManager().isDownloaded(
                  comic.id, ComicType.fromKey(comic.sourceKey))) {
                context.showMessage(message: "Already downloaded".tl);
                return;
              }
              LocalManager().addTask(ImagesDownloadTask(
                source: source,
                comicId: comic.id,
                comicTitle: comic.title,
              ));
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

  void showFolders() {
    context
        .findAncestorStateOfType<_FavoritesPageState>()
        ?.showFolderSelector();
  }

  void loadPage() async {
    var res = await widget.data.loadFolders!();
    _loading = false;
    if (res.error) {
      setState(() {
        _errorMessage = res.errorMessage;
      });
    } else {
      setState(() {
        folders = res.data;
      });
    }
  }

  void openFolder(String key, String title) {
    context.to(() => _FavoriteFolder(widget.data, key, title));
  }

  @override
  Widget build(BuildContext context) {
    var sliverAppBar = SliverAppbar(
      style:
          context.width < changePoint ? AppbarStyle.shadow : AppbarStyle.blur,
      leading: Tooltip(
        message: "Folders".tl,
        child: context.width <= _kTwoPanelChangeWidth
            ? IconButton(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedMenu02, size: 18),
                color: context.colorScheme.primary,
                onPressed: showFolders,
              )
            : null,
      ),
      title: GestureDetector(
        onTap: context.width < _kTwoPanelChangeWidth ? showFolders : null,
        child: Text(widget.data.title),
      ),
    );

    var appBar = Appbar(
      leading: Tooltip(
        message: "Folders".tl,
        child: context.width <= _kTwoPanelChangeWidth
            ? IconButton(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedMenu02, size: 18),
                color: context.colorScheme.primary,
                onPressed: showFolders,
              )
            : null,
      ),
      title: GestureDetector(
        onTap: context.width < _kTwoPanelChangeWidth ? showFolders : null,
        child: Text(widget.data.title),
      ),
    );

    if (_loading) {
      loadPage();
      return Column(
        children: [
          appBar,
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      );
    } else if (_errorMessage != null) {
      return Column(
        children: [
          appBar,
          Expanded(
            child: NetworkError(
              message: friendlyError(_errorMessage!),
              withAppbar: false,
              retry: () {
                setState(() {
                  _loading = true;
                  _errorMessage = null;
                });
              },
            ),
          )
        ],
      );
    } else {
      var length = folders!.length;
      if (widget.data.allFavoritesId != null) length++;
      final keys = folders!.keys.toList();

      return SmoothCustomScrollView(
        controller: widget.controller,
        slivers: [
          sliverAppBar,
          SliverGridViewWithFixedItemHeight(
            delegate:
                SliverChildBuilderDelegate(childCount: length, (context, i) {
              if (widget.data.allFavoritesId != null) {
                if (i == 0) {
                  return _FolderTile(
                      name: "All".tl,
                      onTap: () =>
                          openFolder(widget.data.allFavoritesId!, "All".tl));
                } else {
                  i--;
                  return _FolderTile(
                    name: folders![keys[i]]!,
                    onTap: () => openFolder(keys[i], folders![keys[i]]!),
                    deleteFolder: widget.data.deleteFolder == null
                        ? null
                        : () => widget.data.deleteFolder!(keys[i]),
                    updateState: () => setState(() {
                      _loading = true;
                    }),
                  );
                }
              } else {
                return _FolderTile(
                  name: folders![keys[i]]!,
                  onTap: () => openFolder(keys[i], folders![keys[i]]!),
                  deleteFolder: widget.data.deleteFolder == null
                      ? null
                      : () => widget.data.deleteFolder!(keys[i]),
                  updateState: () => setState(() {
                    _loading = true;
                  }),
                );
              }
            }),
            maxCrossAxisExtent: 450,
            itemHeight: 52,
          ),
          if (widget.data.addFolder != null)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 60,
                width: double.infinity,
                child: Center(
                  child: TextButton(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Create a folder".tl),
                        HugeIcon(icon: 
                          HugeIcons.strokeRoundedAddCircle,
                          size: 18,
                        ),
                      ],
                    ),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return _CreateFolderDialog(
                            widget.data,
                            () => setState(() {
                              _loading = true;
                            }),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            )
        ],
      );
    }
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile(
      {required this.name,
      required this.onTap,
      this.deleteFolder,
      this.updateState});

  final String name;

  final Future<Res<bool>> Function()? deleteFolder;

  final void Function()? updateState;

  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              HugeIcon(icon: 
                HugeIcons.strokeRoundedFolder01,
                size: 28,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(
                width: 16,
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    name,
                    style: const TextStyle(
                        fontSize: kcSubtitle, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              if (deleteFolder != null)
                IconButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
                  onPressed: () => onDeleteFolder(context),
                )
              else
                HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: 18),
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
        return StatefulBuilder(builder: (context, setState) {
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
                  if (res.success) {
                    context.showMessage(message: "Deleted".tl);
                    context.pop();
                    updateState?.call();
                  } else {
                    setState(() {
                      loading = false;
                    });
                    context.showMessage(message: friendlyError(res.errorMessage!));
                  }
                },
                child: Text("Confirm".tl),
              ),
            ],
          );
        });
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: "name".tl,
              ),
            ),
          ),
          const SizedBox(
            height: 16
          ),
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
              if (b.error) {
                context.showMessage(message: friendlyError(b.errorMessage!));
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
        )
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
          MenuButton(entries: [
            MenuEntry(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
              text: "Convert to local".tl,
              onClick: () {
                importNetworkFolder(data.key, 9999999, title, folderID);
              },
            )
          ]),
        ],
      ),
      errorLeading: Appbar(
        title: Text(title),
      ),
      loadPage:
          data.loadComic == null ? null : (i) => data.loadComic!(i, folderID),
      loadNext: data.loadNext == null
          ? null
          : (next) => data.loadNext!(next, folderID),
      menuBuilder: (comic) {
        return [
          MenuEntry(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedDownload04,
              size: 18,
              color: context.colorScheme.primary,
            ),
            color: context.colorScheme.primary,
            text: "Download".tl,
            onClick: () {
              var source = ComicSource.find(comic.sourceKey);
              if (source == null) {
                context.showMessage(message: "Source not found".tl);
                return;
              }
              if (LocalManager().isDownloaded(
                  comic.id, ComicType.fromKey(comic.sourceKey))) {
                context.showMessage(message: "Already downloaded".tl);
                return;
              }
              LocalManager().addTask(ImagesDownloadTask(
                source: source,
                comicId: comic.id,
                comicTitle: comic.title,
              ));
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
