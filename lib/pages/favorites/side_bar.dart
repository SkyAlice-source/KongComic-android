part of 'favorites_page.dart';

class _LeftBar extends StatefulWidget {
  const _LeftBar({this.favPage, this.onSelected, this.withAppbar = false});

  final _FavoritesPageState? favPage;

  final VoidCallback? onSelected;

  final bool withAppbar;

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
      height: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: context.colorScheme.outlineVariant,
            width: 0.6,
          ),
        ),
      ),
      child: Column(
        children: [
          if (widget.withAppbar)
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  const CloseButton(),
                  const SizedBox(width: 8),
                  Text(
                    "Folders".tl,
                    style: ts.s18,
                  ),
                ],
              ),
            ).paddingTop(context.padding.top),
          Expanded(
            child: ListView(
              padding: widget.withAppbar
                  ? EdgeInsets.zero
                  : EdgeInsets.only(top: context.padding.top),
              children: items,
            ),
          )
        ],
      ),
    );
  }

  Widget buildLocalTitle() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedActivity01,
            size: 22,
            color: context.colorScheme.secondary,
          ),
          const SizedBox(width: 12),
          Text("Local".tl),
          const Spacer(),
          MenuButton(
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
        ],
      ).paddingHorizontal(16),
    );
  }

  Widget _buildCategoryHeader(String name, int count, String id) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.colorScheme.outlineVariant,
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedFolder02,
            size: 18,
            color: context.colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: ts.s16)),
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: context.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(kcRadius8),
            ),
            child: Text(count.toString()),
          ),
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
      ).paddingHorizontal(16),
    );
  }

  Widget _buildGroupHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.colorScheme.outlineVariant,
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedFolder02,
            size: 18,
            color: context.colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Text(title, style: ts.s16),
        ],
      ).paddingHorizontal(16),
    );
  }

  Widget _buildHiddenHeader() {
    return InkWell(
      onTap: () {
        setState(() {
          _hiddenExpanded = !_hiddenExpanded;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: context.colorScheme.outlineVariant,
              width: 0.6,
            ),
          ),
        ),
        child: Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedViewOff,
              size: 18,
              color: context.colorScheme.secondary,
            ),
            const SizedBox(width: 8),
            Text('Hidden'.tl, style: ts.s16),
            const Spacer(),
            Icon(_hiddenExpanded ? Icons.expand_less : Icons.expand_more),
          ],
        ).paddingHorizontal(16),
      ),
    );
  }

  Widget _buildHiddenFolderRow(String name) {
    return Container(
      height: 42,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 32),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: ts.s14.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedView, size: 18),
            tooltip: 'Restore'.tl,
            onPressed: () {
              BookshelfLayout.unhideFolder(name);
            },
          ),
        ],
      ),
    );
  }

  Widget buildNetworkTitle() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.colorScheme.outlineVariant,
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedCloud,
            size: 22,
            color: context.colorScheme.secondary,
          ),
          const SizedBox(width: 12),
          Text("Network".tl),
          const Spacer(),
          IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings01, size: 18),
            onPressed: () {
              showPopUpWidget(
                App.rootContext,
                setFavoritesPagesWidget(),
              );
            },
          ),
        ],
      ).paddingHorizontal(16),
    );
  }

  Widget buildLocalFolder(String name) {
    bool isSelected = name == favPage.folder && !favPage.isNetwork;
    int count = 0;
    if (name == _localAllFolderLabel) {
      count = LocalFavoritesManager().totalComics;
    } else {
      count = LocalFavoritesManager().folderComics(name);
    }
    var folderName = name == _localAllFolderLabel
        ? "All".tl
        : getFavoriteDataOrNull(name)?.title ?? name;
    return InkWell(
      onTap: () {
        if (isSelected) {
          return;
        }
        favPage.setFolder(false, name);
        widget.onSelected?.call();
      },
      child: Container(
        height: 42,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: isSelected
              ? context.colorScheme.primaryContainer.toOpacity(0.36)
              : null,
          border: Border(
            left: BorderSide(
              color:
                  isSelected ? context.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(folderName),
            ),
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: context.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(kcRadius8),
              ),
              child: Text(count.toString()),
            ),
            if (name != _localAllFolderLabel)
              MenuButton(
                entries: [
                  MenuEntry(
                    icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedFolder02, size: 18),
                    text: 'Set category'.tl,
                    onClick: () {
                      _pickCategoryDialog(name);
                    },
                  ),
                  MenuEntry(
                    icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedViewOff, size: 18),
                    text: 'Hide'.tl,
                    onClick: () {
                      BookshelfLayout.hideFolder(name);
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget buildNetworkFolder(String key) {
    var data = getFavoriteDataOrNull(key);
    if (data == null) {
      return const SizedBox();
    }
    bool isSelected = key == favPage.folder && favPage.isNetwork;
    return InkWell(
      onTap: () {
        if (isSelected) {
          return;
        }
        favPage.setFolder(true, key);
        widget.onSelected?.call();
      },
      child: Container(
        height: 42,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: isSelected
              ? context.colorScheme.primaryContainer.toOpacity(0.36)
              : null,
          border: Border(
            left: BorderSide(
              color:
                  isSelected ? context.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.only(left: 16),
        child: Text(data.title),
      ),
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
                      title: Text(cat['name']!),
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
                          title: Text(cat['name']!),
                        );
                      },
                    ),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  BookshelfLayout.reorderCategories(
                    cats.map((c) => c['id']!).toList(),
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
