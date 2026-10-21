part of 'reader.dart';

class _ChaptersView extends StatefulWidget {
  const _ChaptersView(this.reader);

  final _ReaderState reader;

  @override
  State<_ChaptersView> createState() => _ChaptersViewState();
}

enum _ChapterDlFilter { all, downloaded, notDownloaded }

class _ChaptersViewState extends State<_ChaptersView> {
  bool desc = false;

  bool _searching = false;
  String _query = '';
  _ChapterDlFilter _dlFilter = _ChapterDlFilter.all;
  final TextEditingController _searchController = TextEditingController();

  late final ScrollController _scrollController;

  var downloaded = <String>[];

  @override
  void initState() {
    super.initState();
    int epIndex = widget.reader.chapter - 2;
    _scrollController = ScrollController(
      initialScrollOffset: (epIndex * 48.0 + 52).clamp(0, double.infinity),
    );
    var local = LocalManager().find(widget.reader.cid, widget.reader.type);
    if (local != null) {
      downloaded = local.downloadedChapters;
    }
  }

  void _setQuery(String v) {
    setState(() => _query = v);
    _scrollToTop();
  }

  void _setDlFilter(_ChapterDlFilter f) {
    setState(() => _dlFilter = f);
    _scrollToTop();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _exitSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final chapters = widget.reader.widget.chapters!;
    final current = widget.reader.chapter - 1;
    final all = chapters.allChapters.entries.toList();
    final q = _query.trim().toLowerCase();

    // 先按「搜索词 + 下载状态」筛出原始下标，再套用升/降序。
    var indices = <int>[];
    for (var i = 0; i < all.length; i++) {
      final id = all[i].key;
      final title = all[i].value;
      if (_query.isNotEmpty && !title.toLowerCase().contains(q)) continue;
      if (_dlFilter == _ChapterDlFilter.downloaded && !downloaded.contains(id)) {
        continue;
      }
      if (_dlFilter == _ChapterDlFilter.notDownloaded && downloaded.contains(id)) {
        continue;
      }
      indices.add(i);
    }
    if (desc) indices = indices.reversed.toList();

    final hasFilterRow = downloaded.isNotEmpty;

    return Scaffold(
      // 居中浮层卡片已经铺了 surfaceContainerHigh，Scaffold 再刷默认底色会把
      // 卡片色调盖掉。
      backgroundColor: Colors.transparent,
      body: SmoothCustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppbar(
            style: AppbarStyle.shadow,
            backgroundColor: cs.surfaceContainerHigh,
            leading: IconButton(
              icon: HugeIcon(
                icon: _searching
                    ? HugeIcons.strokeRoundedArrowLeft01
                    : HugeIcons.strokeRoundedCancel01,
                size: 18,
              ),
              onPressed: _searching ? _exitSearch : () => Navigator.maybePop(context),
            ),
            title: _searching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: TextStyle(fontSize: kcSubtitle),
                    decoration: InputDecoration.collapsed(
                      hintText: "Search chapters".tl,
                      hintStyle: TextStyle(fontSize: kcSubtitle).withColor(cs.onSurfaceVariant),
                    ),
                    onChanged: _setQuery,
                  )
                : Text("Chapters".tl),
            actions: [
              if (!_searching)
                IconButton(
                  tooltip: "Search".tl,
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedSearch02, size: 18),
                  onPressed: () => setState(() => _searching = true),
                ),
              Tooltip(
                message: "Click to change the order".tl,
                child: Button.text(
                  onPressed: () {
                    setState(() {
                      desc = !desc;
                    });
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      !desc ? HugeIcon(icon: HugeIcons.strokeRoundedArrowUp01, size: 18) : HugeIcon(icon: HugeIcons.strokeRoundedArrowDown01, size: 18),
                      const SizedBox(width: 6),
                      Text(!desc ? "Ascending".tl : "Descending".tl),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (hasFilterRow)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text("All".tl),
                      selectedColor: kcAccentSurface(context),
                      showCheckmark: false,
                      selected: _dlFilter == _ChapterDlFilter.all,
                      onSelected: (_) => _setDlFilter(_ChapterDlFilter.all),
                    ),
                    ChoiceChip(
                      label: Text("Downloaded".tl),
                      selectedColor: kcAccentSurface(context),
                      showCheckmark: false,
                      selected: _dlFilter == _ChapterDlFilter.downloaded,
                      onSelected: (_) => _setDlFilter(_ChapterDlFilter.downloaded),
                    ),
                    ChoiceChip(
                      label: Text("Not downloaded".tl),
                      selectedColor: kcAccentSurface(context),
                      showCheckmark: false,
                      selected: _dlFilter == _ChapterDlFilter.notDownloaded,
                      onSelected: (_) => _setDlFilter(_ChapterDlFilter.notDownloaded),
                    ),
                  ],
                ),
              ),
            ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final real = indices[index];
                final entry = all[real];
                return _ChapterListTile(
                  onTap: () {
                    widget.reader.toChapter(real + 1);
                    Navigator.of(context).pop();
                  },
                  title: entry.value,
                  isActive: current == real,
                  isDownloaded: downloaded.contains(entry.key),
                );
              },
              childCount: indices.length,
            ),
          ),
          if (indices.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    "No results".tl,
                    style: TextStyle(fontSize: kcBody).withColor(cs.onSurfaceVariant),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _GroupedChaptersView extends StatefulWidget {
  const _GroupedChaptersView(this.reader);

  final _ReaderState reader;

  @override
  State<_GroupedChaptersView> createState() => _GroupedChaptersViewState();
}

class _GroupedChaptersViewState extends State<_GroupedChaptersView>
    with SingleTickerProviderStateMixin {
  ComicChapters get chapters => widget.reader.widget.chapters!;

  late final TabController tabController;

  late final ScrollController _scrollController;

  late final String initialGroupName;

  var downloaded = <String>[];

  bool _searching = false;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final groups = chapters.groups;
    var chapter = widget.reader.chapter;
    if (chapter < 1) chapter = 1;
    int index = 0;
    int epIndex = chapter - 1;
    while (epIndex >= 0 && index < groups.length) {
      epIndex -= chapters.getGroupByIndex(index).length;
      index++;
    }
    index = index.clamp(1, groups.length);
    final safeIndex = (index - 1).clamp(0, groups.isEmpty ? 0 : groups.length - 1);
    tabController = TabController(
      length: groups.length,
      vsync: this,
      initialIndex: safeIndex,
    );
    initialGroupName = groups.isEmpty ? '' : groups.elementAt(safeIndex);
    var epIndexAtGroup = widget.reader.chapter - 1;
    for (var i = 0; i < index - 1; i++) {
      epIndexAtGroup -= chapters.getGroupByIndex(i).length;
    }
    _scrollController = ScrollController(
      initialScrollOffset: (epIndexAtGroup * 48.0).clamp(0, double.infinity),
    );
    var local = LocalManager().find(widget.reader.cid, widget.reader.type);
    if (local != null) {
      downloaded = local.downloadedChapters;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return Column(
      children: [
        Appbar(
          title: _searching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(fontSize: kcSubtitle),
                  decoration: InputDecoration.collapsed(
                    hintText: "Search chapters".tl,
                    hintStyle: TextStyle(fontSize: kcSubtitle).withColor(cs.onSurfaceVariant),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                )
              : Text("Chapters".tl),
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: HugeIcon(
              icon: _searching
                  ? HugeIcons.strokeRoundedArrowLeft01
                  : HugeIcons.strokeRoundedCancel01,
              size: 18,
            ),
            onPressed: _searching
                ? () {
                    _searchController.clear();
                    setState(() {
                      _query = '';
                      _searching = false;
                    });
                  }
                : () => Navigator.maybePop(context),
          ),
          actions: [
            if (!_searching)
              IconButton(
                tooltip: "Search".tl,
                icon: HugeIcon(icon: HugeIcons.strokeRoundedSearch02, size: 18),
                onPressed: () => setState(() => _searching = true),
              ),
          ],
        ),
        if (_searching)
          Expanded(child: _buildSearchResults())
        else
          AppTabBar(
            controller: tabController,
            tabs: chapters.groups.map((e) => Tab(text: e)).toList(),
          ),
        if (!_searching)
          Expanded(
            child: TabViewBody(
              controller: tabController,
              children: chapters.groups.map(buildGroup).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchResults() {
    final cs = context.colorScheme;
    // allChapters 已按分组顺序合并成扁平映射，下标 == toChapter 的全局下标，
    // 所以搜索结果与未分组视图共用同一套「下标 → 跳转」逻辑。
    final all = chapters.allChapters.entries.toList();
    final q = _query.trim().toLowerCase();
    final indices = <int>[];
    for (var i = 0; i < all.length; i++) {
      if (_query.isEmpty || all[i].value.toLowerCase().contains(q)) {
        indices.add(i);
      }
    }
    return SmoothCustomScrollView(
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final real = indices[index];
              final entry = all[real];
              return _ChapterListTile(
                onTap: () {
                  widget.reader.toChapter(real + 1);
                  context.pop();
                },
                title: entry.value,
                isActive: widget.reader.chapter - 1 == real,
                isDownloaded: downloaded.contains(entry.key),
              );
            },
            childCount: indices.length,
          ),
        ),
        if (indices.isEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 200,
              child: Center(
                child: Text(
                  "No results".tl,
                  style: TextStyle(fontSize: kcBody).withColor(cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget buildGroup(String groupName) {
    var group = chapters.getGroup(groupName);
    return SmoothCustomScrollView(
      controller: initialGroupName == groupName ? _scrollController : null,
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              var name = group.values.elementAt(index);
              var i = 0;
              for (var g in chapters.groups) {
                if (g == groupName) {
                  break;
                }
                i += chapters.getGroup(g).length;
              }
              i += index + 1;
              return _ChapterListTile(
                onTap: () {
                  widget.reader.toChapter(i);
                  context.pop();
                },
                title: name,
                isActive: widget.reader.chapter == i,
                isDownloaded: downloaded.contains(group.keys.elementAt(index)),
              );
            },
            childCount: group.length,
          ),
        ),
      ],
    );
  }
}

class _ChapterListTile extends StatelessWidget {
  const _ChapterListTile({
    required this.title,
    required this.isActive,
    required this.isDownloaded,
    required this.onTap,
  });

  final String title;

  final bool isActive;

  final bool isDownloaded;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    // 一章一行、几十上百行连排，逐行加 divider 会把这堆同质文本变成表格，
    // 扫描效率反而更低（Material 列表本来就用行高和留白分隔）。真正缺的是
    // 「哪一话是当前章」这一个状态要被一眼看出来。
    //
    // 旧版用贴边的 4dp 主色左边框：在居中浮层里它正好压在圆角上，被裁成
    // 一条悬在边缘的竖线，看着像溢出。改成整行浅主色底 + 内缩圆头色条，
    // 色条不再碰卡片边缘，行与行之间也有了「块」的区分。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: isActive
            // 深色/AMOLED 下 primary 贴近白色，同一透明度在纯黑底上的对比更弱，
            // 所以深色模式给得比浅色多一点。
            ? kcAccentColor(context).withValues(alpha: context.isDarkMode ? 0.14 : 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(kcRadius8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kcRadius8),
          child: Container(
            // 行高锁死 48：_ChaptersView / _GroupedChaptersView 用
            // `epIndex * 48.0` 预计算初始滚动位置，改这里必须同步改公式。
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                // 固定 3dp 槽位：当前章显示一条圆头色条，其余行留空，
                // 保证所有章名的左边缘严格对齐。
                Container(
                  width: 3,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isActive ? kcAccentColor(context) : Colors.transparent,
                    borderRadius: BorderRadius.circular(kcRadius3),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: isActive
                        ? TextStyle(fontSize: kcSubtitle, color: kcBrandAdaptive(context))
                            .bold
                        : TextStyle(fontSize: kcSubtitle),
                  ),
                ),
                if (isDownloaded)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedDownload04,
                      // 已下载只是辅助信息，不该用 secondary 抢当前章的主色。
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
