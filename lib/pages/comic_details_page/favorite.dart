part of 'comic_page.dart';

class _FavoritePanel extends StatefulWidget {
  const _FavoritePanel({
    required this.cid,
    required this.type,
    required this.isFavorite,
    required this.onFavorite,
    required this.favoriteItem,
    this.updateTime,
  });

  final String cid;

  final ComicType type;

  /// whether the comic is in the network favorite list
  ///
  /// if null, the comic source does not support favorite or support multiple favorite lists
  final bool? isFavorite;

  final void Function(bool?, bool?) onFavorite;

  final FavoriteItem favoriteItem;

  final String? updateTime;

  @override
  State<_FavoritePanel> createState() => _FavoritePanelState();
}

class _FavoritePanelState extends State<_FavoritePanel>
    with SingleTickerProviderStateMixin {
  late ComicSource comicSource;

  late bool hasNetwork;

  late List<String> localFolders;

  late List<String> added;

  @override
  void initState() {
    comicSource = widget.type.comicSource!;
    localFolders = LocalFavoritesManager().folderNames;
    added = LocalFavoritesManager().find(widget.cid, widget.type);
    hasNetwork = comicSource.favoriteData != null && comicSource.isLogged;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return _FavoriteList(
      cid: widget.cid,
      type: widget.type,
      isFavorite: widget.isFavorite,
      onFavorite: widget.onFavorite,
      favoriteItem: widget.favoriteItem,
      updateTime: widget.updateTime,
      comicSource: comicSource,
      hasNetwork: hasNetwork,
      localFolders: localFolders,
      added: added,
    );
  }
}

/// 漫画详情页「收藏」居中对话框。
///
/// 与收藏页 `_FolderSelectorDialog` 同源：不能用 Material 的 Dialog /
/// ContentDialog 包，它们内部 `IntrinsicWidth` 会向内容索要固有宽高，而列表
/// 视口（Viewport）不支持 intrinsic 查询 → 整张卡片布局断言失败、只剩遮罩。
/// 这里自绘 Material 卡片，高度由内容决定，上限屏高 82%，超出内部滚动。
class _FavoriteDialog extends StatelessWidget {
  const _FavoriteDialog({required this.panel});

  final _FavoritePanel panel;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screen = MediaQuery.sizeOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // 收窄 + 限高，避免近乎全屏的压迫感
            maxWidth: 380,
            maxHeight: math.min(screen.height * 0.72, 600),
          ),
          child: Material(
            color: scheme.surfaceContainerHigh,
            elevation: 4,
            shadowColor: scheme.shadow.withValues(alpha: 0.14),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kcSurfaceRadius),
              side: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部抓取条：精致 sheet 暗示
                const SizedBox(height: kcSpaceXxs),
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(kcPillRadius),
                    ),
                  ),
                ),
                const SizedBox(height: kcSpaceXxs),
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      const SizedBox(width: kcSpaceSm),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: kcSpaceXs),
                          child: Text(
                            'Favorite'.tl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedCancel01,
                          size: 18,
                        ),
                        color: scheme.onSurfaceVariant,
                        tooltip: 'Close'.tl,
                        onPressed: context.pop,
                      ),
                      const SizedBox(width: kcSpaceXs),
                    ],
                  ),
                ),
                Flexible(child: panel),
                const SizedBox(height: kcSpaceXxs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteList extends StatefulWidget {
  const _FavoriteList({
    required this.cid,
    required this.type,
    required this.isFavorite,
    required this.onFavorite,
    required this.favoriteItem,
    this.updateTime,
    required this.comicSource,
    required this.hasNetwork,
    required this.localFolders,
    required this.added,
  });

  final String cid;
  final ComicType type;
  final bool? isFavorite;
  final void Function(bool?, bool?) onFavorite;
  final FavoriteItem favoriteItem;
  final String? updateTime;
  final ComicSource comicSource;
  final bool hasNetwork;
  final List<String> localFolders;
  final List<String> added;

  @override
  State<_FavoriteList> createState() => _FavoriteListState();
}

class _FavoriteListState extends State<_FavoriteList> {
  @override
  Widget build(BuildContext context) {
    final localFavoritesFirst = appdata.settings['localFavoritesFirst'] ?? true;

    final localSection = _LocalSection(
      cid: widget.cid,
      type: widget.type,
      favoriteItem: widget.favoriteItem,
      updateTime: widget.updateTime,
      localFolders: widget.localFolders,
      added: widget.added,
      onFavorite: (local) {
        widget.onFavorite(local, null);
      },
    );

    final networkSection = widget.hasNetwork
        ? _NetworkSection(
            cid: widget.cid,
            comicSource: widget.comicSource,
            isFavorite: widget.isFavorite,
            onFavorite: (network) {
              widget.onFavorite(null, network);
            },
          )
        : null;

    final divider = widget.hasNetwork
        ? Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: context.colorScheme.outlineVariant.withValues(alpha: 0.3),
          )
        : null;

    return ListView(
      children: [
        if (localFavoritesFirst) ...[
          localSection,
          if (widget.hasNetwork) ...[divider!, networkSection!],
        ] else ...[
          if (widget.hasNetwork) ...[networkSection!, divider!],
          localSection,
        ],
      ],
    );
  }
}

class _NetworkSection extends StatefulWidget {
  const _NetworkSection({
    required this.cid,
    required this.comicSource,
    required this.isFavorite,
    required this.onFavorite,
  });

  final String cid;
  final ComicSource comicSource;
  final bool? isFavorite;
  final void Function(bool) onFavorite;

  @override
  State<_NetworkSection> createState() => _NetworkSectionState();
}

class _NetworkSectionState extends State<_NetworkSection> {
  bool isLoading = false;
  Map<String, String>? folders;
  /// Set when `loadFolders()` fails. Without it `folders` stays null while
  /// `isLoadingFolders` is already false, and building the multi-folder panel
  /// would hit `folders!` and take the whole sheet down.
  String? foldersError;
  var addedFolders = <String>{};
  var isLoadingFolders = true;
  bool? localIsFavorite;
  final Map<String, bool> _itemLoading = {};
  late List<double> _skeletonWidths;

  @override
  void initState() {
    super.initState();
    localIsFavorite = widget.isFavorite;
    _skeletonWidths = List.generate(3, (_) => 0.3 + math.Random().nextDouble() * 0.5);
    if (widget.comicSource.favoriteData!.loadFolders != null) {
      loadFolders();
    } else {
      isLoadingFolders = false;
    }
  }

  void loadFolders() async {
    var res = await widget.comicSource.favoriteData!.loadFolders!(widget.cid);
    if (!mounted) return;
    if (res.error) {
      context.showMessage(message: friendlyError(res.errorMessage!));
      setState(() {
        isLoadingFolders = false;
        foldersError = res.errorMessage;
      });
    } else {
      folders = res.data;
      if (res.subData is List) {
        final list = List<String>.from(res.subData);
        if (list.isNotEmpty) {
          addedFolders = list.toSet();
          localIsFavorite = true;
        } else {
          addedFolders.clear();
          localIsFavorite = false;
        }
      } else {
        addedFolders.clear();
        localIsFavorite = false;
      }
      setState(() {
        isLoadingFolders = false;
      });
    }
  }

  Widget _buildLoadingSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            "Network Favorites".tl,
            style: ts.s14.copyWith(
              fontWeight: FontWeight.w600,
              color: context.colorScheme.primary,
            ),
          ),
        ),
        Shimmer(
          child: Column(
            children: List.generate(3, (index) {
              return ListTile(
                title: Container(
                  height: 20,
                  width: double.infinity,
                  margin: const EdgeInsets.only(right: 16),
                  child: FractionallySizedBox(
                    widthFactor: _skeletonWidths[index],
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(kcRadius4),
                      ),
                    ),
                  ),
                ),
                trailing: Container(
                  height: 28,
                  width: 60 + (index * 2),
                  decoration: BoxDecoration(
                    color: context.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(kcCardRadius),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoadingFolders) {
      return _buildLoadingSkeleton();
    }

    bool isMultiFolder = widget.comicSource.favoriteData!.loadFolders != null;

    if (isMultiFolder) {
      // `loadFolders` exists but may have failed, leaving `folders` null.
      if (folders == null) {
        return _buildFoldersErrorState();
      }
      return _buildMultiFolder();
    } else {
      return _buildSingleFolder();
    }
  }

  Widget _buildFoldersErrorState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            "Network Favorites".tl,
            style: ts.s14.copyWith(
              fontWeight: FontWeight.w600,
              color: context.colorScheme.primary,
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle, size: 40),
              const SizedBox(height: kcSpaceSm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg),
                child: Text(
                  foldersError ?? "Network error".tl,
                  textAlign: TextAlign.center,
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    foldersError = null;
                    isLoadingFolders = true;
                  });
                  loadFolders();
                },
                child: Text("Retry".tl),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSingleFolder() {
    final isFavorite = localIsFavorite ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            "Network Favorites".tl,
            style: ts.s14.copyWith(
              fontWeight: FontWeight.w600,
              color: context.colorScheme.primary,
            ),
          ),
        ),
        ListTile(
          onTap: isLoading
              ? null
              : () async {
                  setState(() => isLoading = true);
                  final res = await widget.comicSource.favoriteData!
                      .addOrDelFavorite!(widget.cid, '', !isFavorite, null);
                  if (!mounted) return;
                  if (res.success) {
                    setState(() => localIsFavorite = !isFavorite);
                    widget.onFavorite(!isFavorite);
                    App.rootContext.showMessage(
                      message: isFavorite ? "Removed".tl : "Added".tl,
                    );
                    if (appdata.settings['autoCloseFavoritePanel'] ?? false) {
                      context.pop();
                    }
                  } else {
                    context.showMessage(message: friendlyError(res.errorMessage!));
                  }
                  if (mounted) setState(() => isLoading = false);
                },
          title: Row(
            children: [
              Text("Network Favorites".tl),
              const SizedBox(width: 8),
              _addedChip(context, isFavorite),
            ],
          ),
          trailing: _FavoriteStatePill(isFavorite: isFavorite, isLoading: isLoading),
        ),
      ],
    );
  }

  Widget _buildMultiFolder() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            "Network Favorites".tl,
            style: ts.s14.copyWith(
              fontWeight: FontWeight.w600,
              color: context.colorScheme.primary,
            ),
          ),
        ),
        ...folders!.entries.map((entry) {
          final name = entry.value;
          final id = entry.key;
          final isAdded = addedFolders.contains(id);
          // When `singleFolderForSingleComic` is `false`, all add and remove buttons are clickable.
          // When `singleFolderForSingleComic` is `true`, the remove button is always clickable,
          // while the add button is only clickable if the comic has not been added to any list.
          final enabled = !(widget.comicSource.favoriteData!.singleFolderForSingleComic && addedFolders.isNotEmpty && !isAdded);

          return ListTile(
            onTap: enabled
                ? () async {
                    setState(() => _itemLoading[id] = true);
                    final res = await widget
                        .comicSource
                        .favoriteData!
                        .addOrDelFavorite!(widget.cid, id, !isAdded, null);
                    if (!mounted) return;
                    if (res.success) {
                      // Invalidate network cache so folders/pages reload with fresh data
                      NetworkCacheManager().clear();
                      setState(() {
                        if (isAdded) {
                          addedFolders.remove(id);
                        } else {
                          addedFolders.add(id);
                        }
                        // sync local flag for single-folder-per-comic logic and parent
                        localIsFavorite = addedFolders.isNotEmpty;
                      });
                      // notify parent so page state updates when closing and reopening panel
                      widget.onFavorite(addedFolders.isNotEmpty);
                      context.showMessage(message: "Success".tl);
                      if (appdata.settings['autoCloseFavoritePanel'] ?? false) {
                        context.pop();
                      }
                    } else {
                      context.showMessage(message: friendlyError(res.errorMessage!));
                    }
                    if (mounted) setState(() => _itemLoading[id] = false);
                  }
                : null,
            title: Row(
              children: [
                Text(name),
                const SizedBox(width: 8),
                _addedChip(context, isAdded),
              ],
            ),
            trailing: (_itemLoading[id] ?? false)
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _FavoriteStatePill(isFavorite: isAdded, enabled: enabled),
          );
        }),
      ],
    );
  }
}

class _LocalSection extends StatefulWidget {
  const _LocalSection({
    required this.cid,
    required this.type,
    required this.favoriteItem,
    this.updateTime,
    required this.localFolders,
    required this.added,
    required this.onFavorite,
  });

  final String cid;
  final ComicType type;
  final FavoriteItem favoriteItem;
  final String? updateTime;
  final List<String> localFolders;
  final List<String> added;
  final void Function(bool) onFavorite;

  @override
  State<_LocalSection> createState() => _LocalSectionState();
}

class _LocalSectionState extends State<_LocalSection> {
  late List<String> localFolders;
  late Set<String> localAdded;

  @override
  void initState() {
    super.initState();
    localFolders = widget.localFolders;
    localAdded = widget.added.toSet();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            "Local Favorites".tl,
            style: ts.s14.copyWith(
              fontWeight: FontWeight.w600,
              color: context.colorScheme.primary,
            ),
          ),
        ),
        ...localFolders.map((folder) {
          final isAdded = localAdded.contains(folder);

          return ListTile(
            onTap: () {
              if (isAdded) {
                LocalFavoritesManager().deleteComicWithId(
                  folder,
                  widget.cid,
                  widget.type,
                );
                setState(() {
                  localAdded.remove(folder);
                });
              } else {
                LocalFavoritesManager().addComic(
                  folder,
                  widget.favoriteItem,
                  null,
                  widget.updateTime,
                );
                setState(() {
                  localAdded.add(folder);
                });
              }
              widget.onFavorite(localAdded.isNotEmpty);
              if (appdata.settings['autoCloseFavoritePanel'] ?? false) {
                context.pop();
              }
            },
            title: Row(
              children: [
                Text(folder),
                const SizedBox(width: 8),
                _addedChip(context, isAdded),
              ],
            ),
            trailing: _FavoriteStatePill(isFavorite: isAdded),
          );
        }),
        // New folder button
        ListTile(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedAddCircle, size: 20),
              const SizedBox(width: 4),
              Text("New Folder".tl),
            ],
          ),
          onTap: () {
            newFolder().then((v) {
              setState(() {
                localFolders = LocalFavoritesManager().folderNames;
              });
            });
          },
        ),
      ],
    );
  }
}

/// 收藏状态药丸（纯展示）：Add / Remove 两态，加载时显示转圈。
///
/// 点击由所在整行 ListTile 处理 —— 这样点按热区覆盖整行，既好点又不会
/// 误触小按钮；药丸只负责呈现状态并随状态平滑变色。
class _FavoriteStatePill extends StatelessWidget {
  const _FavoriteStatePill({
    required this.isFavorite,
    this.isLoading = false,
    this.enabled = true,
  });

  final bool isFavorite;
  final bool isLoading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final removeColor = context.colorScheme.error;
    final addColor = context.colorScheme.primary;
    final bg = isLoading
        ? (isFavorite ? removeColor : addColor)
        : (enabled ? (isFavorite ? removeColor : addColor) : context.colorScheme.surfaceContainerLow);
    return AnimatedContainer(
      duration: AppAnimations.duration(const Duration(milliseconds: 200)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(kcCardRadius),
      ),
      child: isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.colorScheme.onPrimary,
              ),
            )
          : Text(
              isFavorite ? "Remove".tl : "Add".tl,
              style: ts.s12.copyWith(
                color: enabled
                    ? context.colorScheme.onPrimary
                    : context.colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }
}

/// 行内「已添加」标签，状态切换时带缩放过渡，比生硬出现更精致。
Widget _addedChip(BuildContext context, bool added) {
  return AnimatedSwitcher(
    duration: const Duration(milliseconds: 180),
    transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
    child: added
        ? Container(
            key: const ValueKey(true),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: context.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(kcCardRadius),
            ),
            child: Text("Added".tl, style: ts.s12),
          )
        : const SizedBox.shrink(key: ValueKey(false)),
  );
}
