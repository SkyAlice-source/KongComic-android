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
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      // 与下方 _sectionHeader 的 kcSpaceLg 左缩进对齐，标题不再比分区名凸出 4px。
                      const SizedBox(width: kcSpaceLg),
                      Expanded(
                        child: Text(
                          'Favorite'.tl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
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
                const SizedBox(height: kcSpace6),
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

    // 与本地分区内的分组线同一套（0.6 发丝 + 16 缩进），避免两处粗细/缩进不一。
    final divider = widget.hasNetwork ? _sectionDivider(context) : null;

    // shrinkWrap：内容少时让对话框贴着内容收口，不再在底部留一大片空白；
    // 内容超过上限高度时仍然可滚（外层 Flexible 给的是有限约束）。
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
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
    _skeletonWidths = List.generate(
      3,
      (_) => 0.3 + math.Random().nextDouble() * 0.5,
    );
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
        _sectionHeader(context, "Network".tl),
        Shimmer(
          child: Column(
            children: List.generate(3, (index) {
              return KcListTile(
                // 占位图标：真实行都有 leading，骨架若没有，加载完成后文字会横向跳一下。
                leading: SizedBox(
                  width: 24,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: context.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(kcRadius4),
                    ),
                  ),
                ),
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
        _sectionHeader(context, "Network".tl),
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
              Button.text(
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
        _sectionHeader(context, "Network".tl),
        KcListTile(
          onTap: isLoading
              ? null
              : () async {
                  setState(() => isLoading = true);
                  final res = await widget
                      .comicSource
                      .favoriteData!
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
                    context.showMessage(
                      message: friendlyError(res.errorMessage!),
                    );
                  }
                  if (mounted) setState(() => isLoading = false);
                },
          leading: _rowIcon(context, HugeIcons.strokeRoundedCloud),
          title: Text("Network Favorites".tl),
          showDivider: false,
          trailing: _FavoriteStatePill(
            isFavorite: isFavorite,
            isLoading: isLoading,
          ),
        ),
      ],
    );
  }

  Widget _buildMultiFolder() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, "Network".tl),
        ...folders!.entries.map((entry) {
          final name = entry.value;
          final id = entry.key;
          final isAdded = addedFolders.contains(id);
          // When `singleFolderForSingleComic` is `false`, all add and remove buttons are clickable.
          // When `singleFolderForSingleComic` is `true`, the remove button is always clickable,
          // while the add button is only clickable if the comic has not been added to any list.
          final enabled =
              !(widget.comicSource.favoriteData!.singleFolderForSingleComic &&
                  addedFolders.isNotEmpty &&
                  !isAdded);

          return KcListTile(
            // 列表末行不画分隔线：否则线贴在最下方，像多了一条边框。
            showDivider: entry.key != folders!.entries.last.key,
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
                      context.showMessage(
                        message: friendlyError(res.errorMessage!),
                      );
                    }
                    if (mounted) setState(() => _itemLoading[id] = false);
                  }
                : null,
            leading: _rowIcon(context, HugeIcons.strokeRoundedFolder01),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    localAdded = widget.added.where((f) => f != kReadLaterFolder).toSet();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, "Local".tl),
        _sectionDivider(context),
        ...localFolders.where((f) => f != kReadLaterFolder).map((folder) {
          final isAdded = localAdded.contains(folder);

          return KcListTile(
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
            // 每行都给 leading：没有图标时文字会贴在左边缘，与置顶行错位。
            leading: _rowIcon(context, HugeIcons.strokeRoundedFolder01),
            title: Text(folder, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: _FavoriteStatePill(isFavorite: isAdded),
          );
        }),
        // 与上方文件夹行拉开一点距离：这是「动作」，不是又一个文件夹。
        const SizedBox(height: kcSpaceXs),
        KcListTile(
          leading: _rowIcon(context, HugeIcons.strokeRoundedAddCircle),
          title: Text(
            "New Folder".tl,
            style: TextStyle(color: context.colorScheme.onSurfaceVariant),
          ),
          onTap: () {
            newFolder().then((v) {
              setState(() {
                localFolders = LocalFavoritesManager().folderNames;
              });
            });
          },
        ),
        // 末尾不再加间距：dense 行自带的上下留白 + 对话框底部 4，已与顶部对称。
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
    final scheme = context.colorScheme;
    // 未添加 = 描边胶囊（安静，不跟已添加态抢眼）；已添加 = 浅染胶囊 + 勾。
    // 旧实现两个状态都是实心高饱和色，一行行排下来像一排警告按钮。
    final fg = !enabled
        ? scheme.onSurfaceVariant
        : (isFavorite ? scheme.onErrorContainer : kcBrandAdaptive(context));
    final bg = !enabled
        ? Colors.transparent
        : (isFavorite ? scheme.errorContainer : Colors.transparent);
    return AnimatedContainer(
      duration: AppAnimations.duration(const Duration(milliseconds: 200)),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isLoading ? scheme.surfaceContainerHighest : bg,
        borderRadius: BorderRadius.circular(kcPillRadius),
        border: (isLoading || isFavorite)
            ? null
            : Border.all(
                color: enabled
                    ? scheme.outlineVariant
                    : scheme.outlineVariant.withValues(alpha: 0.5),
                width: 1,
              ),
      ),
      child: isLoading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: kcBrandAdaptive(context),
              ),
            )
          : Text(
              isFavorite ? "Remove".tl : "Add".tl,
              style: TextStyle(
                fontSize: kcCaption,
                fontWeight: FontWeight.w500,
                // 中文默认行高比字形高，胶囊里视觉会偏下；锁 1.0 让文字真正居中。
                height: 1.0,
                color: fg,
              ),
            ),
    );
  }
}

/// 分区标题：小号 caption + 次要色，替代原来「正文大小 + 品牌红」的写法。
///
/// 对话框里标题若用品牌红，会和右侧一排操作胶囊抢注意力；这里降级为
/// 安静的分组标签，让「文件夹行」本身成为唯一的视觉主体。
Widget _sectionHeader(BuildContext context, String title) {
  final scheme = context.colorScheme;
  return Padding(
    // 底部不再留白：dense 行本身自带内边距，标题贴近所属分组才不会「悬空」。
    padding: const EdgeInsets.fromLTRB(kcSpaceLg, kcSpaceMd, kcSpaceLg, 0),
    child: Text(
      title,
      style: TextStyle(
        fontSize: kcCaption,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: scheme.onSurfaceVariant,
      ),
    ),
  );
}

/// 分组之间的发丝线（缩进对齐文字左边缘）。
Widget _sectionDivider(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg),
    child: Divider(
      height: kcSpaceMd,
      thickness: 0.6,
      // 不叠 alpha：0.6dp 的发丝线再降到 0.7 透明度，在白底上基本看不见，
      // 分组就白做了。用 outlineVariant 原色，细而可辨。
      color: context.colorScheme.outlineVariant,
    ),
  );
}

/// 行首图标：固定 24 宽，保证有图标 / 无图标行、本地行 / 网络行文字全部左对齐。
Widget _rowIcon(
  BuildContext context,
  List<List<dynamic>> icon, {
  Color? color,
}) {
  return SizedBox(
    width: 24,
    child: HugeIcon(
      icon: icon,
      size: 20,
      color: color ?? context.colorScheme.onSurfaceVariant,
    ),
  );
}
