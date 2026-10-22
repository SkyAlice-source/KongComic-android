part of 'comic_page.dart';

class _ComicChapters extends StatelessWidget {
  const _ComicChapters({this.history, required this.groupedMode});

  final History? history;

  final bool groupedMode;

  @override
  Widget build(BuildContext context) {
    return groupedMode
        ? _GroupedComicChapters(history)
        : _NormalComicChapters(history);
  }
}

class _NormalComicChapters extends StatefulWidget {
  const _NormalComicChapters(this.history);

  final History? history;

  @override
  State<_NormalComicChapters> createState() => _NormalComicChaptersState();
}

class _NormalComicChaptersState extends State<_NormalComicChapters> {
  late _ComicPageState state;

  late bool reverse;

  bool showAll = false;

  /// 章节标题行的定位锚点：切换顺序后要把这一行拉回视野，
  /// 否则列表翻了个个、滚动位置却没动，用户会停在一屏陌生的章节上。
  final _headerKey = GlobalKey();

  void _onOrderChanged(bool value) {
    if (value == reverse) return;
    setState(() => reverse = value);
    appdata.settings["reverseChapterOrder"] = value;
    appdata.saveData();
    _scrollBackToChapters();
  }

  void _scrollBackToChapters() {
    // 下一帧才完成重排，提前取 context 会拿到待布局的旧位置。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _headerKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        // 详情页顶栏会盖住视口最上面一段，留一点余量别顶到栏底下。
        alignment: 0.12,
      );
    });
  }

  late History? history;

  late ComicChapters chapters;

  /// 已下载章节 id 集合，用于章节格子右上角的下载状态标。
  /// 仅在漫画 id 变化时重新查库，避免每次 rebuild 都查 SQLite。
  Set<String> _downloadedKeys = const {};
  String? _downloadedComicId;

  void _syncDownloaded() {
    final id = state.comic.id;
    if (_downloadedComicId == id) return;
    _downloadedComicId = id;
    final local = LocalManager().find(id, state.comic.comicType);
    _downloadedKeys = local?.downloadedChapters.toSet() ?? const {};
  }

  @override
  void initState() {
    super.initState();
    reverse = appdata.settings["reverseChapterOrder"] ?? false;
    history = widget.history;
  }

  @override
  void didChangeDependencies() {
    state = context.findAncestorStateOfType<_ComicPageState>()!;
    chapters = state.comic.chapters!;
    _syncDownloaded();
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(covariant _NormalComicChapters oldWidget) {
    super.didUpdateWidget(oldWidget);
    setState(() {
      history = widget.history;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constrains) {
        int length = chapters.length;
        bool canShowAll = showAll;
        if (!showAll) {
          var width = constrains.crossAxisExtent - 16;
          var crossItems = width ~/ 200;
          if (width % 200 != 0) {
            crossItems += 1;
          }
          length = math.min(length, crossItems * 8);
          if (length == chapters.length) {
            canShowAll = true;
          }
        }

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: KcListTile(
                key: _headerKey,
                title: Text("Chapters".tl),
                trailing: _ChapterOrderToggle(
                  reverse: reverse,
                  onChanged: _onOrderChanged,
                ),
              ),
            ),
            SliverGrid(
              delegate: SliverChildBuilderDelegate(
                childCount: length,
                (context, i) {
                  if (reverse) {
                    i = chapters.length - i - 1;
                  }
                  var key = chapters.ids.elementAt(i);
                  var value = chapters[key]!;
                  bool visited = (history?.readEpisode ?? {}).contains(i + 1);
                  bool isCurrent = history != null && (i + 1) == history!.ep;
                  return _buildChapterTile(
                    context,
                    value: value,
                    visited: visited,
                    isCurrent: isCurrent,
                    downloaded: _downloadedKeys.contains(key),
                    onTap: () => state.read(i + 1),
                  );
                },
              ),
              gridDelegate: const SliverGridDelegateWithFixedHeight(
                maxCrossAxisExtent: 250,
                itemHeight: 48,
              ),
            ).sliverPadding(const EdgeInsets.symmetric(horizontal: 16)),
            if (!canShowAll)
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.center,
                  child: Button.text(
                    onPressed: () {
                      setState(() {
                        showAll = true;
                      });
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(icon: HugeIcons.strokeRoundedArrowDown01, size: 18),
                        const SizedBox(width: 6),
                        Text("${"Show all".tl} (${chapters.length})"),
                      ],
                    ),
                  ).paddingTop(12),
                ),
              ),
            const SliverToBoxAdapter(
              child: Divider(),
            ),
          ],
        );
      },
    );
  }
}

class _GroupedComicChapters extends StatefulWidget {
  const _GroupedComicChapters(this.history);

  final History? history;

  @override
  State<_GroupedComicChapters> createState() => _GroupedComicChaptersState();
}

class _GroupedComicChaptersState extends State<_GroupedComicChapters>
    with SingleTickerProviderStateMixin, AutoListenMixin {
  late _ComicPageState state;

  late bool reverse;

  bool showAll = false;

  late History? history;

  late ComicChapters chapters;

  late TabController tabController;

  late int index;

  /// 已下载章节 id 集合，用于章节格子右上角的下载状态标。
  Set<String> _downloadedKeys = const {};
  String? _downloadedComicId;

  /// 章节标题行的定位锚点 —— 见 [_NormalComicChaptersState._scrollBackToChapters]。
  final _headerKey = GlobalKey();

  void _onOrderChanged(bool value) {
    if (value == reverse) return;
    setState(() => reverse = value);
    appdata.settings["reverseChapterOrder"] = value;
    appdata.saveData();
    // 分组模式下翻顺序同样要把标题拉回视野：.Table 在下、格子在上，
    // 停在半山腰会看到别的分组的章节。
    _scrollBackToChapters();
  }

  void _scrollBackToChapters() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _headerKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.12,
      );
    });
  }

  void _syncDownloaded() {
    final id = state.comic.id;
    if (_downloadedComicId == id) return;
    _downloadedComicId = id;
    final local = LocalManager().find(id, state.comic.comicType);
    _downloadedKeys = local?.downloadedChapters.toSet() ?? const {};
  }

  @override
  void initState() {
    super.initState();
    reverse = appdata.settings["reverseChapterOrder"] ?? false;
    history = widget.history;
    if (history?.group != null) {
      index = history!.group! - 1;
    } else {
      index = 0;
    }
  }

  @override
  void didChangeDependencies() {
    state = context.findAncestorStateOfType<_ComicPageState>()!;
    chapters = state.comic.chapters!;
    _syncDownloaded();
    tabController = TabController(
      initialIndex: index,
      length: chapters.ids.length,
      vsync: this,
    );
    listen(tabController, onTabChange);
    super.didChangeDependencies();
  }

  void onTabChange() {
    if (index != tabController.index) {
      setState(() {
        index = tabController.index;
      });
    }
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _GroupedComicChapters oldWidget) {
    super.didUpdateWidget(oldWidget);
    setState(() {
      history = widget.history;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constrains) {
        var group = chapters.getGroupByIndex(index);
        int length = group.length;
        bool canShowAll = showAll;
        if (!showAll) {
          var width = constrains.crossAxisExtent - 16;
          var crossItems = width ~/ 200;
          if (width % 200 != 0) {
            crossItems += 1;
          }
          length = math.min(length, crossItems * 8);
          if (length == group.length) {
            canShowAll = true;
          }
        }

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: KcListTile(
                key: _headerKey,
                title: Text("Chapters".tl),
                trailing: _ChapterOrderToggle(
                  reverse: reverse,
                  onChanged: _onOrderChanged,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: AppTabBar(
                withUnderLine: false,
                controller: tabController,
                tabs: chapters.groups.map((e) => Tab(text: e)).toList(),
              ),
            ),
            SliverPadding(padding: const EdgeInsets.only(top: 8)),
            SliverGrid(
              delegate: SliverChildBuilderDelegate(
                childCount: length,
                (context, i) {
                  if (reverse) {
                    i = group.length - i - 1;
                  }
                  var key = group.keys.elementAt(i);
                  var value = group[key]!;
                  var chapterIndex = 0;
                  for (var j = 0; j < chapters.groupCount; j++) {
                    if (j == index) {
                      chapterIndex += i;
                      break;
                    }
                    chapterIndex += chapters.getGroupByIndex(j).length;
                  }
                  String rawIndex = (chapterIndex + 1).toString();
                  String groupedIndex = "${index + 1}-${i + 1}";
                  bool visited = false;
                  bool isCurrent = false;
                  if (history != null) {
                    visited = history!.readEpisode.contains(groupedIndex) ||
                        history!.readEpisode.contains(rawIndex);
                    isCurrent = (chapterIndex + 1) == history!.ep;
                  }
                  return _buildChapterTile(
                    context,
                    value: value,
                    visited: visited,
                    isCurrent: isCurrent,
                    downloaded: _downloadedKeys.contains(key),
                    onTap: () => state.read(chapterIndex + 1),
                  );
                },
              ),
              gridDelegate: const SliverGridDelegateWithFixedHeight(
                maxCrossAxisExtent: 250,
                itemHeight: 48,
              ),
            ).sliverPadding(const EdgeInsets.symmetric(horizontal: 16)),
            if (!canShowAll)
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.center,
                  child: Button.text(
                    onPressed: () {
                      setState(() {
                        showAll = true;
                      });
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(icon: HugeIcons.strokeRoundedArrowDown01, size: 18),
                        const SizedBox(width: 6),
                        Text("${"Show all".tl} (${group.length})"),
                      ],
                    ),
                  ).paddingTop(12),
                ),
              ),
            const SliverToBoxAdapter(
              child: Divider(),
            ),
          ],
        );
      },
    );
  }
}

/// 章节顺序切换：胶囊按钮直接把「当前是升序还是降序」写出来。
///
/// 原先是一个笼统的「上下箭头」图标按钮 —— 既看不出当前是升序还是降序，
/// 也看不出点了会切成什么，只能靠列表内容自己反推。现在按钮上的箭头与
/// 文字都描述**当前状态**（↑ 降序 = 最新话在最上），tooltip 才提示「点了
/// 会变成什么」，两种信息不混在一处。
class _ChapterOrderToggle extends StatelessWidget {
  const _ChapterOrderToggle({required this.reverse, required this.onChanged});

  final bool reverse;

  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: (reverse ? "Ascending" : "Descending").tl,
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kcPillRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(kcPillRadius),
          onTap: () => onChanged(!reverse),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kcPillRadius),
              border: Border.all(color: cs.outlineVariant, width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HugeIcon(
                  // 箭头指向章节号的增长方向：升序向下、降序向上。
                  icon: reverse
                      ? HugeIcons.strokeRoundedArrowUp01
                      : HugeIcons.strokeRoundedArrowDown01,
                  size: 15,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  reverse ? "Descending".tl : "Ascending".tl,
                  style: TextStyle(
                    fontSize: kcCaption,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
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

/// 普通/分组章节共用的单格渲染：当前章节高亮、已读降透明度、点击跳转。
/// 抽取自 [_NormalComicChapters] 与 [_GroupedComicChapters] 的重复格子代码，
/// 保证两种模式的章节格子视觉完全一致。
Widget _buildChapterTile(
  BuildContext context, {
  required String value,
  required bool visited,
  required bool isCurrent,
  required bool downloaded,
  required VoidCallback onTap,
}) {
  final cs = context.colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  // 强调色跟着外观走：浅色 / 深色是品牌红，AMOLED 退化为中性灰。若深色仍用
  // 主题 primary，同一颗「当前章节」的描边会和阅读按钮分成两套颜色。
  final accent = kcAccentColor(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
    child: Material(
      color: isCurrent
          // 极淡红染而不是整块 primaryContainer：既点出「当前」，又不会在
          // 深色页面上糊成一块更亮的砖；亮色下用 7% 保持同样的轻量感。
          ? kcAccentSurface(context, alpha: isDark ? 0.12 : 0.07)
          : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(kcCardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kcCardRadius),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kcCardRadius),
                border: Border.all(
                  color: isCurrent
                      ? accent
                      : visited
                          ? cs.tertiary.withValues(alpha: 0.5)
                          : cs.outline.withValues(alpha: 0.3),
                  width: isCurrent ? 1.5 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Center(
                  child: Text(
                    value,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      // 当前章节文字保持高对比（暗色下是白字）：红字在纯黑底上
                      // 只有 4.1:1，13sp 小字读不清；「当前」交给红边+红底表达。
                      color: isCurrent
                          ? cs.onSurface
                          : visited
                              ? cs.onSurfaceVariant
                              : cs.onSurface,
                      fontWeight: isCurrent ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ),
            ),
            if (downloaded)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: kcAccentSurface(context),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedTick01,
                      size: 11,
                      color: kcBrandAdaptive(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
