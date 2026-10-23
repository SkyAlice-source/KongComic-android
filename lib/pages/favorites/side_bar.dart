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
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      // 与收藏面板同款：标题左缩进对齐胶囊/分区标签，且不再放抓取条
                      //（居中卡片不可拖拽，那条小横线只会被当成毛刺）。
                      const SizedBox(width: kcSpaceLg),
                      Expanded(
                        child: Text(
                          'Folders'.tl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      // 分组切换胶囊已移到收藏正文顶部；这里只留文件夹管理菜单，
                      // 随当前分组在「本地管理 / 网络设置」之间切换。
                      favPage.isNetwork
                          ? _buildNetworkMenu(context)
                          : _buildLocalMenu(context),
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
                const SizedBox(height: kcSpace6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeftBar extends StatefulWidget {
  const _LeftBar({this.favPage, this.onSelected, this.inDialog = false});

  final _FavoritesPageState? favPage;

  final VoidCallback? onSelected;

  /// 是否作为居中对话框的内容（而非常驻侧栏/左滑抽屉）。
  /// 为 true 时去掉侧栏右描边，并不再额外加状态栏安全区 padding。
  final bool inDialog;

  @override
  State<_LeftBar> createState() => _LeftBarState();
}

class _LeftBarState extends State<_LeftBar>
    with AutoListenMixin
    implements FolderList {
  late _FavoritesPageState favPage;

  var folders = <String>[];

  var networkFolders = <String>[];

  bool _hiddenExpanded = false;

  void findNetworkFolders() {
    networkFolders.clear();
    // 与 favPage._computeNetworkFolders 同口径：只列已登录的源。
    // 网络收藏挂在账号下，未登录的源不可能有收藏；装源时会自动把
    // favoriteData.key 写进 settings['favorites']，不过滤就会出现
    // 一排点了只会报错的死入口。
    var all = ComicSource.enabled()
        .where((e) => e.favoriteData != null && e.isLogged)
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
    favPage =
        widget.favPage ??
        context.findAncestorStateOfType<_FavoritesPageState>()!;
    favPage.folderList = this;
    folders = LocalFavoritesManager().folderNames;
    findNetworkFolders();
    listen(appdata.settings, updateFolders);
    listen(LocalFavoritesManager(), updateFolders);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // 每次 build 重算：initState 时漫画源可能还没加载完，只算一次会让网络分组
    // 永久判空（胶囊被灰掉、列表也空）。这里只是遍历已启用的源，开销可忽略。
    findNetworkFolders();

    final cats = BookshelfLayout.categories;
    final hidden = BookshelfLayout.hiddenFolders;

    final isNetwork = favPage.isNetwork;

    // 胶囊在顶部当分组切换器，列表只渲染当前分组的条目 ——
    // 原来本地 / 网络两段一路排下来，只能靠缩进和图标分辨层级。
    final items = <Widget>[];

    if (isNetwork) {
      for (var f in networkFolders) {
        items.add(buildNetworkFolder(f));
      }
    } else {
      items.add(buildLocalFolder(_localAllFolderLabel));

      for (var cat in cats) {
        final id = cat['id'];
        final name = cat['name'];
        if (id == null || name == null) continue;
        final catFolders = folders
            .where(
              (f) =>
                  !hidden.contains(f) &&
                  f != kReadLaterFolder &&
                  BookshelfLayout.categoryOf(f) == id,
            )
            .toList();
        final count = catFolders.fold(
          0,
          (sum, f) => sum + LocalFavoritesManager().folderComics(f),
        );
        items.add(_buildCategoryHeader(name, count, id));
        for (var f in catFolders) {
          items.add(buildLocalFolder(f));
        }
      }

      final uncat = folders
          .where(
            (f) =>
                !hidden.contains(f) &&
                f != kReadLaterFolder &&
                BookshelfLayout.categoryOf(f) == null,
          )
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
            if (f == kReadLaterFolder) continue;
            if (folders.contains(f)) items.add(_buildHiddenFolderRow(f));
          }
        }
      }
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
      // 侧栏/弹窗只负责「当前分组下的文件夹列表」；分组切换胶囊已抽到
      // 收藏正文顶部（_GroupPills），单栏窄屏也能直接切分组，不必先点弹窗。
      child: widget.inDialog
          ? ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: items,
            )
          : ListView(
              padding: EdgeInsets.only(
                top: context.padding.top,
                bottom: kcSpaceLg,
              ),
              children: items,
            ),
    );
  }

  /// 统一的选中/未选中文件夹行（本地与网络共用外观）。
  ///
  /// 行本身做成「胶囊按钮」，与正文顶部的分组胶囊（_GroupPills）同一套语言：
  /// 圆角 999、选中 = accent 红底白字、未选中 = 透明底 + 细描边。
  /// 之前是 8dp 小圆角 + primaryContainer 的列表行样式，夹在一排红胶囊下面
  /// 明显不搭（同一处「选中」出现两种形状、两种红）。
  Widget _folderRow({
    required String label,
    required bool isSelected,
    required int count,
    required VoidCallback onTap,
    Widget? trailing,

    /// HugeIcons 常量本身是路径数据（`List<List<dynamic>>`），不是 IconData。
    List<List<dynamic>>? icon,
  }) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kcSpaceSm, vertical: 2),
      child: Material(
        color: isSelected ? kcAccentColor(context) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kcPillRadius),
          side: isSelected
              ? BorderSide.none
              : BorderSide(color: scheme.outlineVariant, width: 0.8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isSelected ? null : onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(
              horizontal: kcSpaceMd,
              vertical: 2,
            ),
            child: Row(
              children: [
                HugeIcon(
                  icon: icon ?? HugeIcons.strokeRoundedFolder01,
                  size: 19,
                  color: isSelected ? kcOnAccentColor : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: kcSpaceSm),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: kcBody,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isSelected ? kcOnAccentColor : scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: kcSpaceXs),
                _countChip(count, isSelected),
                if (trailing != null) ...[
                  const SizedBox(width: kcSpace6),
                  trailing,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 计数 chip：未选中=中性低对比胶囊；选中=红底上的白色薄片。
  Widget _countChip(int count, bool selected) {
    final scheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: kcSpaceSm, vertical: 2),
      decoration: BoxDecoration(
        color: selected
            ? kcOnAccentColor.withValues(alpha: 0.22)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kcPillRadius),
      ),
      child: Text(
        count.toString(),
        style: TextStyle(
          fontSize: kcCaption,
          fontWeight: FontWeight.w500,
          color: selected ? kcOnAccentColor : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 通用分区标题（Local / 分类 / 未分类 / 隐藏 / Network 共用一套排版）。
  Widget _sectionHeader(Widget leading, String label, {Widget? trailing}) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kcSpaceSm + kcSpaceMd,
        12,
        kcSpaceSm,
        4,
      ),
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
            color: context.colorScheme.onSurfaceVariant,
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
                        'Folders in this category will become uncategorized.'
                            .tl,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kcSpaceSm, vertical: 2),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kcPillRadius),
          side: BorderSide(color: scheme.outlineVariant, width: 0.8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => BookshelfLayout.unhideFolder(name),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.only(left: kcSpaceMd, right: kcSpaceXs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: kcBody,
                      color: scheme.onSurfaceVariant,
                    ),
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
        ),
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
              color: isSelected
                  ? kcOnAccentColor
                  : context.colorScheme.onSurfaceVariant,
              entries: [
                MenuEntry(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedFolder02,
                    size: 18,
                  ),
                  text: 'Set category'.tl,
                  onClick: () => _pickCategoryDialog(name),
                ),
                MenuEntry(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedViewOff,
                    size: 18,
                  ),
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
        return StatefulBuilder(
          builder: (context, setState) {
            return ContentDialog(
              title: 'Set category'.tl,
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    KcListTile(
                      title: Text('Uncategorized'.tl),
                      selected: current == null,
                      // 只有后面还有分类名时才需要分隔线。
                      showDivider: cats.isNotEmpty,
                      onTap: () {
                        BookshelfLayout.setCategory(folder, null);
                        context.pop();
                      },
                    ),
                    for (var cat in cats)
                      KcListTile(
                        title: Text(cat['name'] ?? ''),
                        selected: current == cat['id'],
                        showDivider: cat != cats.last,
                        onTap: () {
                          BookshelfLayout.setCategory(folder, cat['id']);
                          context.pop();
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                Button.text(onPressed: context.pop, child: Text('Cancel'.tl)),
              ],
            );
          },
        );
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

/// 收藏页顶部的文件夹胶囊条。
///
/// 取代原来的「本地 | 网络」两段等分胶囊 —— 那两个胶囊只表达顶层分组，
/// 真正的文件夹仍要点开左上角弹窗才看得到。现在把「全部 + 各本地文件夹 +
/// 各网络收藏源」平铺成一条可横滑的胶囊，一次点到位（Mihon / Kotatsu 的
/// 分类 tab 同范式）；配合 [_SliverFolderChipsHeader] 常驻在顶栏下方，
/// 滚到列表深处也不用滚回顶部才能换文件夹。
class _GroupPills extends StatefulWidget {
  const _GroupPills({required this.favPage});

  final _FavoritesPageState favPage;

  @override
  State<_GroupPills> createState() => _GroupPillsState();
}

class _GroupPillsState extends State<_GroupPills> with AutoListenMixin {
  final ScrollController _controller = ScrollController();

  /// 只挂在当前选中项上：切换后把它滚进视野中部。
  final GlobalKey _selectedKey = GlobalKey();

  var _localFolders = <String>[];
  var _networkFolders = <String>[];

  String? _lastFolder;
  bool _lastIsNetwork = false;

  @override
  void initState() {
    super.initState();
    _load();
    // 建 / 删文件夹、改分类、增删收藏源后，胶囊要跟着变。
    listen(LocalFavoritesManager(), _reload);
    listen(appdata.settings, _reload);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _load() {
    final hidden = BookshelfLayout.hiddenFolders;
    _localFolders =
        userFolderNames().where((f) => !hidden.contains(f)).toList();
    _networkFolders = widget.favPage._computeNetworkFolders();
  }

  void _reload() {
    if (!mounted) return;
    setState(_load);
  }

  String _displayName(String folder) =>
      getFavoriteDataOrNull(folder)?.title ?? folder;

  void _ensureSelectedVisible() {
    final ctx = _selectedKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: AppAnimations.duration(const Duration(milliseconds: 220)),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final fp = widget.favPage;

    // 只在选中项真正变化时滚一次：点已可见的胶囊不该出现无谓的居中跳动。
    if (_lastFolder != fp.folder || _lastIsNetwork != fp.isNetwork) {
      _lastFolder = fp.folder;
      _lastIsNetwork = fp.isNetwork;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureSelectedVisible();
      });
    }

    Widget cell({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      int? count,
      bool network = false,
    }) {
      return Material(
        // 选中的那颗挂 key，供切换后自动滚进视野。
        key: selected ? _selectedKey : null,
        color: selected ? kcAccentColor(context) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kcPillRadius),
          side: selected
              ? BorderSide.none
              : BorderSide(color: scheme.outlineVariant, width: 0.8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selected ? null : onTap,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: kcSpaceMd),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (network) ...[
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedGlobe02,
                    size: 13,
                    color:
                        selected ? kcOnAccentColor : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: kcCaption,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? kcOnAccentColor : scheme.onSurface,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: kcCaption,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? kcOnAccentColor.withValues(alpha: 0.8)
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final cells = <Widget>[];
    for (final f in _localFolders) {
      cells.add(
        cell(
          label: _displayName(f),
          selected: !fp.isNetwork && fp.folder == f,
          count: LocalFavoritesManager().folderComics(f),
          onTap: () => fp.setFolder(false, f),
        ),
      );
    }
    for (final k in _networkFolders) {
      cells.add(
        cell(
          label: _displayName(k),
          selected: fp.isNetwork && fp.folder == k,
          network: true,
          onTap: () => fp.setFolder(true, k),
        ),
      );
    }

    return Container(
      // 作为 pinned header 时会盖住滚动内容，底色必须与页面同源，否则封面透上来。
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: SingleChildScrollView(
        // 不用 PageStorageKey：横向滚动位置无需持久化，也避开与纵向列表共用
        // PageStorage 标识导致的 `as double?` 崩溃（见 1.5.x 修复记录）。
        key: const ValueKey('favoriteFolderChips'),
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg),
        child: Row(
          children: [
            // 「全部」钉在最前：最高频的落点，不该被文件夹挤到屏幕外。
            cell(
              label: "All".tl,
              selected: !fp.isNetwork && fp.folder == _localAllFolderLabel,
              count: LocalFavoritesManager().totalComics,
              onTap: () => fp.setFolder(false, _localAllFolderLabel),
            ),
            for (final c in cells) ...[
              const SizedBox(width: 8),
              c,
            ],
          ],
        ),
      ),
    );
  }
}

/// 把文件夹胶囊条钉在顶栏下方（pinned）。
///
/// 高度必须与 [_GroupPills] 的实际高度一致：4(top) + 32(胶囊) + 10(bottom)。
class _SliverFolderChipsHeader extends SliverPersistentHeaderDelegate {
  const _SliverFolderChipsHeader(this.child);

  final Widget child;

  static const double _height = 46;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      child;

  @override
  bool shouldRebuild(covariant _SliverFolderChipsHeader old) =>
      old.child != child;
}

/// 弹窗头部的「本地」文件夹管理菜单（创建文件夹 / 排序 / 分类）。
Widget _buildLocalMenu(BuildContext context) {
  return MenuButton(
    entries: [
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedAddCircle, size: 18),
        text: 'Create Folder'.tl,
        onClick: () {
          // 弹窗里的 _LeftBar 监听 LocalFavoritesManager，建完会自动刷新列表。
          newFolder();
        },
      ),
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedArrange, size: 18),
        text: 'Sort'.tl,
        onClick: () {
          sortFolders();
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
          _manageCategoriesDialog(context);
        },
      ),
    ],
  );
}

/// 弹窗头部的「网络」收藏源设置入口。
Widget _buildNetworkMenu(BuildContext context) {
  return Button.icon(
    icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings01, size: 18),
    color: context.colorScheme.onSurfaceVariant,
    tooltip: 'Settings'.tl,
    onPressed: () {
      showPopUpWidget(App.rootContext, setFavoritesPagesWidget());
    },
  );
}

/// 分类管理弹窗（重排 / 删除分类）。
void _manageCategoriesDialog(BuildContext context) {
  final cats = List<Map<String, String>>.from(BookshelfLayout.categories);
  showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
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
                      itemBuilder: (dialogContext, index) {
                        final cat = cats[index];
                        return KcListTile(
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
              Button.filled(
                onPressed: () {
                  BookshelfLayout.reorderCategories(
                    cats.map((c) => c['id'] ?? '').toList(),
                  );
                  dialogContext.pop();
                },
                child: Text('Confirm'.tl),
              ),
            ],
          );
        },
      );
    },
  );
}
