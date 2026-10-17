part of 'favorites_page.dart';

/// 居中文件夹选择卡片。
///
/// 不能用 Material 的 Dialog / ContentDialog 包：它们内部有 IntrinsicWidth，
/// 会向内容索要固有宽高，而 ListView 的视口（Viewport）明确不支持 intrinsic
/// 查询，会让整张卡片布局断言失败 —— 表现就是「只有一层灰遮罩、卡片不出现」。
/// 这里自绘 Material 卡片：高度由内容决定，上限屏高 62%，超出则内部滚动。
class _FolderSelectorDialog extends StatelessWidget {
  const _FolderSelectorDialog({required this.favPage});

  final _FavoritesPageState favPage;

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
            // 收窄宽度 + 限制高度，让卡片更精致、不占满整屏
            maxWidth: 360,
            maxHeight: math.min(screen.height * 0.7, 560),
          ),
          child: Material(
            color: scheme.surfaceContainerHigh,
            // 降 elevation、柔化阴影，去掉厚重感
            elevation: 3,
            shadowColor: scheme.shadow.withValues(alpha: 0.12),
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
                // 顶部抓取条：精致 sheet 暗示，点遮罩 / 返回即可关闭
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
                            'Folders'.tl,
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
                Flexible(
                  child: _LeftBar(
                    favPage: favPage,
                    inDialog: true,
                    onSelected: () => context.pop(),
                  ),
                ),
                const SizedBox(height: kcSpaceXxs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeftBar extends StatefulWidget {
  const _LeftBar({
    this.favPage,
    this.onSelected,
    this.inDialog = false,
  });

  final _FavoritesPageState? favPage;

  final VoidCallback? onSelected;

  /// 是否作为居中对话框的内容（而非常驻侧栏/左滑抽屉）。
  /// 为 true 时去掉侧栏右描边，并不再额外加状态栏安全区 padding。
  final bool inDialog;

  @override
  State<_LeftBar> createState() => _LeftBarState();
}

class _LeftBarState extends State<_LeftBar> implements FolderList {
  late _FavoritesPageState favPage;

  var folders = <String>[];

  var networkFolders = <String>[];

  bool _hiddenExpanded = false;

  void findNetworkFolders() {
    networkFolders.clear();
    var all = ComicSource.enabled()
        .where((e) => e.favoriteData != null)
        .map((e) => e.favoriteData!.key)
        .toList();
    var settings = appdata.settings['favorites'] as List;
    for (var p in settings) {
      if (all.contains(p) && !networkFolders.contains(p)) {
        networkFolders.add(p);
      }
    }
  }

  @override
  void initState() {
    favPage = widget.favPage ??
        context.findAncestorStateOfType<_FavoritesPageState>()!;
    favPage.folderList = this;
    folders = LocalFavoritesManager().folderNames;
    findNetworkFolders();
    appdata.settings.addListener(updateFolders);
    LocalFavoritesManager().addListener(updateFolders);
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    appdata.settings.removeListener(updateFolders);
    LocalFavoritesManager().removeListener(updateFolders);
  }

  @override
  Widget build(BuildContext context) {
    final cats = BookshelfLayout.categories;
    final hidden = BookshelfLayout.hiddenFolders;

    final items = <Widget>[buildLocalTitle(), buildLocalFolder(_localAllFolderLabel)];

    for (var cat in cats) {
      final id = cat['id'];
      final name = cat['name'];
      if (id == null || name == null) continue;
      final catFolders = folders
          .where((f) =>
              !hidden.contains(f) && BookshelfLayout.categoryOf(f) == id)
          .toList();
      final count = catFolders.fold(
          0, (sum, f) => sum + LocalFavoritesManager().folderComics(f));
      items.add(_buildCategoryHeader(name, count, id));
      for (var f in catFolders) {
        items.add(buildLocalFolder(f));
      }
    }

    final uncat = folders
        .where((f) =>
            !hidden.contains(f) && BookshelfLayout.categoryOf(f) == null)
        .toList();
    if (uncat.isNotEmpty) {
      items.add(_buildGroupHeader('Uncategorized'.tl));
      for (var f in uncat) {
        items.add(buildLocalFolder(f));
      }
    }

    if (hidden.isNotEmpty) {
      items.add(_buildHiddenHeader());
      if (_hiddenExpanded) {
        for (var f in hidden) {
          if (folders.contains(f)) items.add(_buildHiddenFolderRow(f));
        }
      }
    }

    items.add(buildNetworkTitle());
    for (var f in networkFolders) {
      items.add(buildNetworkFolder(f));
    }

    return Container(
      width: double.infinity,
      // 对话框里按内容高度收缩（外层 ConstrainedBox 限高后内部滚动）；
      // 常驻侧栏/抽屉才撑满整屏。
      height: widget.inDialog ? null : double.infinity,
      decoration: widget.inDialog
          ? null
          : BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: context.colorScheme.outlineVariant,
                  width: 0.6,
                ),
              ),
            ),
      child: Column(
        mainAxisSize: widget.inDialog ? MainAxisSize.min : MainAxisSize.max,
        children: [
          widget.inDialog
              ? ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: items,
                )
              : Expanded(
                  child: ListView(
                    padding: EdgeInsets.only(
                      top: context.padding.top,
                      bottom: kcSpaceLg,
                    ),
                    children: items,
                  ),
                )
        ],
      ),
    );
  }

  /// 统一的选中/未选中文件夹行（本地与网络共用外观）。
  Widget _folderRow({
    required String label,
    required bool isSelected,
    required int count,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final scheme = context.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(kcRadius8),
      onTap: isSelected ? null : onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        margin: const EdgeInsets.symmetric(horizontal: kcSpaceSm, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: kcSpaceMd, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(kcRadius8),
        ),
        child: Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedFolder01,
              size: 20,
              color: isSelected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: kcSpaceMd),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: kcBody,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? scheme.onPrimaryContainer : scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: kcSpaceXs),
            _countChip(count, isSelected),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  /// 计数 chip：未选中=中性低对比胶囊；选中=叠在 primaryContainer 上的浅色胶囊。
  Widget _countChip(int count, bool selected) {
    final scheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: kcSpaceSm, vertical: 2),
      decoration: BoxDecoration(
        color: selected
            ? scheme.onPrimaryContainer.withValues(alpha: 0.14)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kcChipRadius),
      ),
      child: Text(
        count.toString(),
        style: TextStyle(
          fontSize: kcCaption,
          fontWeight: FontWeight.w500,
          color: selected
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 通用分区标题（Local / 分类 / 未分类 / 隐藏 / Network 共用一套排版）。
  Widget _sectionHeader(Widget leading, String label, {Widget? trailing}) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kcSpaceLg, 12, kcSpaceSm, 4),
      child: Row(
        children: [
          leading,
          const SizedBox(width: kcSpaceSm),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget buildLocalTitle() {
    return _sectionHeader(
      HugeIcon(
        icon: HugeIcons.strokeRoundedActivity01,
        size: 18,
        color: context.colorScheme.onSurfaceVariant,
      ),
      "Local".tl,
      trailing: MenuButton(
        entries: [
          MenuEntry(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedAddCircle, size: 18),
            text: 'Create Folder'.tl,
            onClick: () {
              newFolder().then((value) {
                setState(() {
                  folders = LocalFavoritesManager().folderNames;
                });
              });
            },
          ),
          MenuEntry(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedArrange, size: 18),
            text: 'Sort'.tl,
            onClick: () {
              sortFolders().then((value) {
                setState(() {
                  folders = LocalFavoritesManager().folderNames;
                });
              });
            },
          ),
          MenuEntry(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedFolder02, size: 18),
            text: 'New Category'.tl,
            onClick: () {
              showInputDialog(
                context: App.rootContext,
                title: 'New Category'.tl,
                hintText: 'Category Name'.tl,
                onConfirm: (value) {
                  if (value.isEmpty) {
                    return 'Name cannot be empty'.tl;
                  }
                  BookshelfLayout.createCategory(value);
                  return null;
                },
              );
            },
          ),
          MenuEntry(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings01, size: 18),
            text: 'Manage Categories'.tl,
            onClick: () {
              _manageCategoriesDialog();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryHeader(String name, int count, String id) {
    return _sectionHeader(
      HugeIcon(
        icon: HugeIcons.strokeRoundedFolder02,
        size: 18,
        color: context.colorScheme.onSurfaceVariant,
      ),
      name,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _countChip(count, false),
          MenuButton(
            entries: [
              MenuEntry(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedEdit01, size: 18),
                text: 'Rename'.tl,
                onClick: () {
                  showInputDialog(
                    context: App.rootContext,
                    title: 'Rename'.tl,
                    hintText: 'New Name'.tl,
                    onConfirm: (value) {
                      if (value.isEmpty) return 'Name cannot be empty'.tl;
                      BookshelfLayout.renameCategory(id, value);
                      return null;
                    },
                  );
                },
              ),
              MenuEntry(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
                text: 'Delete'.tl,
                onClick: () {
                  showConfirmDialog(
                    context: App.rootContext,
                    title: 'Delete category'.tl,
                    content:
                        'Folders in this category will become uncategorized.'.tl,
                    onConfirm: () {
                      BookshelfLayout.deleteCategory(id);
                    },
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupHeader(String title) {
    return _sectionHeader(
      HugeIcon(
        icon: HugeIcons.strokeRoundedFolder02,
        size: 18,
        color: context.colorScheme.onSurfaceVariant,
      ),
      title,
    );
  }

  Widget _buildHiddenHeader() {
    final scheme = context.colorScheme;
    return InkWell(
      onTap: () {
        setState(() {
          _hiddenExpanded = !_hiddenExpanded;
        });
      },
      child: _sectionHeader(
        HugeIcon(
          icon: HugeIcons.strokeRoundedViewOff,
          size: 18,
          color: context.colorScheme.onSurfaceVariant,
        ),
        'Hidden'.tl,
        trailing: HugeIcon(
          icon: _hiddenExpanded
              ? HugeIcons.strokeRoundedArrowUp01
              : HugeIcons.strokeRoundedArrowDown01,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildHiddenFolderRow(String name) {
    final scheme = context.colorScheme;
    return InkWell(
      onTap: () => BookshelfLayout.unhideFolder(name),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        margin: const EdgeInsets.symmetric(horizontal: kcSpaceSm, vertical: 2),
        padding: const EdgeInsets.only(left: 32, right: kcSpaceMd),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: TextStyle(fontSize: kcBody, color: scheme.onSurfaceVariant),
              ),
            ),
            IconButton(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedView,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              tooltip: 'Restore'.tl,
              onPressed: () => BookshelfLayout.unhideFolder(name),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildNetworkTitle() {
    final scheme = context.colorScheme;
    return _sectionHeader(
      HugeIcon(
        icon: HugeIcons.strokeRoundedCloud,
        size: 18,
        color: context.colorScheme.onSurfaceVariant,
      ),
      "Network".tl,
      trailing: IconButton(
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedSettings01,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        onPressed: () {
          showPopUpWidget(
            App.rootContext,
            setFavoritesPagesWidget(),
          );
        },
      ),
    );
  }

  Widget buildLocalFolder(String name) {
    final isSelected = name == favPage.folder && !favPage.isNetwork;
    final count = name == _localAllFolderLabel
        ? LocalFavoritesManager().totalComics
        : LocalFavoritesManager().folderComics(name);
    final folderName = name == _localAllFolderLabel
        ? "All".tl
        : getFavoriteDataOrNull(name)?.title ?? name;
    return _folderRow(
      label: folderName,
      isSelected: isSelected,
      count: count,
      onTap: () {
        favPage.setFolder(false, name);
        widget.onSelected?.call();
      },
      trailing: name != _localAllFolderLabel
          ? MenuButton(
              entries: [
                MenuEntry(
                  icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedFolder02, size: 18),
                  text: 'Set category'.tl,
                  onClick: () => _pickCategoryDialog(name),
                ),
                MenuEntry(
                  icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedViewOff, size: 18),
                  text: 'Hide'.tl,
                  onClick: () => BookshelfLayout.hideFolder(name),
                ),
              ],
            )
          : null,
    );
  }

  Widget buildNetworkFolder(String key) {
    final data = getFavoriteDataOrNull(key);
    if (data == null) {
      return const SizedBox();
    }
    final isSelected = key == favPage.folder && favPage.isNetwork;
    return _folderRow(
      label: data.title,
      isSelected: isSelected,
      count: 0,
      onTap: () {
        favPage.setFolder(true, key);
        widget.onSelected?.call();
      },
    );
  }

  void _pickCategoryDialog(String folder) {
    final cats = BookshelfLayout.categories;
    final current = BookshelfLayout.categoryOf(folder);
    showDialog(
      context: App.rootContext,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return ContentDialog(
            title: 'Set category'.tl,
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    title: Text('Uncategorized'.tl),
                    selected: current == null,
                    onTap: () {
                      BookshelfLayout.setCategory(folder, null);
                      context.pop();
                    },
                  ),
                  for (var cat in cats)
                    ListTile(
                      title: Text(cat['name'] ?? ''),
                      selected: current == cat['id'],
                      onTap: () {
                        BookshelfLayout.setCategory(folder, cat['id']);
                        context.pop();
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: context.pop,
                child: Text('Cancel'.tl),
              ),
            ],
          );
        });
      },
    );
  }

  void _manageCategoriesDialog() {
    final cats = List<Map<String, String>>.from(BookshelfLayout.categories);
    showDialog(
      context: App.rootContext,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return ContentDialog(
            title: 'Manage Categories'.tl,
            content: SizedBox(
              width: double.maxFinite,
              height: 360,
              child: cats.isEmpty
                  ? Center(child: Text('No categories yet'.tl))
                  : ReorderableListView.builder(
                      onReorderItem: (oldIndex, newIndex) {
                        setState(() {
                          final item = cats.removeAt(oldIndex);
                          cats.insert(newIndex, item);
                        });
                      },
                      itemCount: cats.length,
                      itemBuilder: (context, index) {
                        final cat = cats[index];
                        return ListTile(
                          key: ValueKey(cat['id']),
                          leading: HugeIcon(
                            icon: HugeIcons.strokeRoundedArrange,
                            size: 18,
                          ),
                          title: Text(cat['name'] ?? ''),
                        );
                      },
                    ),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  BookshelfLayout.reorderCategories(
                    cats.map((c) => c['id'] ?? '').toList(),
                  );
                  context.pop();
                },
                child: Text('Confirm'.tl),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  void update() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void updateFolders() {
    if (!mounted) return;
    setState(() {
      folders = LocalFavoritesManager().folderNames;
      findNetworkFolders();
    });
  }
}
