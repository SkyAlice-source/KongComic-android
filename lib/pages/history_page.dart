import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/components/scroll_top_fab.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_type.dart';
import 'package:kong_comic/foundation/history.dart';
import 'package:kong_comic/utils/translations.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  @override
  void initState() {
    HistoryManager().addListener(onUpdate);
    super.initState();
  }

  @override
  void dispose() {
    HistoryManager().removeListener(onUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void onUpdate() {
    _gridKey.currentState?.refresh();
    if (multiSelectMode) {
      selectedComics.removeWhere((comic, _) => !_loadedComics.contains(comic));
      if (selectedComics.isEmpty) {
        setState(() {
          multiSelectMode = false;
        });
      }
    }
  }

  /// Comics currently loaded by the paginated grid.
  List<History> _loadedComics = [];

  /// GlobalKey to access the paginated grid's state for refresh.
  final _gridKey = GlobalKey<PaginatedSliverGridComicsState>();

  /// Controls the scroll view so the FAB can scroll the list back to top.
  final ScrollController _scrollController = ScrollController();

  /// Page loader for PaginatedSliverGridComics.
  Future<List<Comic>> _loadPage(int offset, int limit) async {
    return HistoryManager().getAllPaginated(limit: limit, offset: offset);
  }

  bool multiSelectMode = false;
  Map<History, bool> selectedComics = {};

  void selectAll() {
    // Load all history for selection (one-time operation).
    final allComics = HistoryManager().getAll();
    setState(() {
      selectedComics =
          allComics.asMap().map((k, v) => MapEntry(v, true));
    });
  }

  void deSelect() {
    setState(() {
      selectedComics.clear();
    });
  }

  void invertSelection() {
    setState(() {
      for (var v in _loadedComics) {
        if (selectedComics.containsKey(v)) {
          selectedComics.remove(v);
        } else {
          selectedComics[v] = true;
        }
      }
    });
  }

  void _removeHistory(History comic) {
    if (comic.sourceKey.startsWith("Unknown")) {
      HistoryManager().remove(
        comic.id,
        ComicType(int.parse(comic.sourceKey.split(':')[1])),
      );
    } else if (comic.sourceKey == 'local') {
      HistoryManager().remove(
        comic.id,
        ComicType.local,
      );
    } else {
      HistoryManager().remove(
        comic.id,
        ComicType(comic.sourceKey.hashCode),
      );
    }
  }

  void _refreshHistory(History comic) async {
    var result = await HistoryManager().refreshHistoryInfo(comic);
    if (result) {
      if (mounted) {
        App.rootContext.showMessage(message: "Refresh Success".tl);
      }
    } else {
      if (mounted) {
        App.rootContext.showMessage(message: "Refresh Failed".tl);
      }
    }
  }

  void _refreshAllHistories() async {
    bool isCanceled = false;
    void onCancel() {
      isCanceled = true;
    }

    var loadingController = showLoadingDialog(
      App.rootContext,
      withProgress: true,
      cancelButtonText: "Cancel".tl,
      onCancel: onCancel,
      message: "Refreshing Histories".tl,
    );

    int success = 0;
    int failed = 0;
    int skipped = 0;

    await for (var progress
        in HistoryManager().refreshAllHistoriesStream()) {
      if (isCanceled) {
        return;
      }
      if (progress.total > 0) {
        loadingController.setProgress(progress.current / progress.total);
      }
      success = progress.success;
      failed = progress.failed;
      skipped = progress.skipped;
    }

    loadingController.close();

    if (mounted) {
      App.rootContext.showMessage(
        message:
            "Refresh Completed: Success @success, Failed @failed, Skipped @skipped"
                .tlParams({
          'success': success,
          'failed': failed,
          'skipped': skipped,
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !multiSelectMode,
      onPopInvokedWithResult: (didPop, result) {
        if (multiSelectMode) {
          setState(() {
            multiSelectMode = false;
            selectedComics.clear();
          });
        }
      },
      child: Scaffold(
        body: SmoothCustomScrollView(
          controller: _scrollController,
          slivers: [
            // 历史页操作承载在自身内部 SliverAppbar（pinned），与收藏页风格一致。
            // 正常模式标题交给全局顶栏（粗体"历史"），此处不再重复显示；
            // 仅多选模式在内部条显示"已选 N 部"，避免与全局标题重复。
            SliverAppbar(
              title: multiSelectMode
                  ? Text("Selected @c comics".tlParams({"c": selectedComics.length}))
                  : const SizedBox.shrink(),
              actions: multiSelectMode ? _multiSelectActions() : _normalActions(),
            ),
            PaginatedSliverGridComics(
              key: _gridKey,
              pageLoader: _loadPage,
              selections: selectedComics,
              onLoadedComicsChanged: (comics) {
                _loadedComics = comics.cast<History>();
              },
              onLongPressed: null,
              onTap: multiSelectMode
                  ? (c, heroID) {
                      setState(() {
                        if (selectedComics.containsKey(c as History)) {
                          selectedComics.remove(c);
                        } else {
                          selectedComics[c] = true;
                        }
                        if (selectedComics.isEmpty) {
                          multiSelectMode = false;
                        }
                      });
                    }
                  : null,
              badgeBuilder: (c) {
                return ComicSource.find(c.sourceKey)?.name;
              },
              menuBuilder: (c) {
                return [
                  MenuEntry(
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
                    text: 'Refresh Info'.tl,
                    onClick: () {
                      _refreshHistory(c as History);
                    },
                  ),
                  MenuEntry(
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedCancelCircle, size: 18),
                    text: 'Remove'.tl,
                    color: context.colorScheme.error,
                    onClick: () {
                      _removeHistory(c as History);
                    },
                  ),
                ];
              },
            ),
          ],
        ),
        floatingActionButton: _buildScrollTopFab(),
      ),
    );
  }

  /// 正常模式操作：多选 / 清空 / 刷新全部。
  List<Widget> _normalActions() => [
        Tooltip(
          message: "Multi-Select".tl,
          child: IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedCheckList, size: 20),
            onPressed: () => setState(() => multiSelectMode = true),
          ),
        ),
        Tooltip(
          message: "Clear History".tl,
          child: IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 20),
            onPressed: _confirmClearHistory,
          ),
        ),
        Tooltip(
          message: "Refresh All Histories".tl,
          child: IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 20),
            onPressed: _refreshAllHistories,
          ),
        ),
      ];

  /// 多选模式操作：全选 / 删除 / 更多(反选·取消) / 退出。
  List<Widget> _multiSelectActions() => [
        Tooltip(
          message: "Select All".tl,
          child: IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedCheckList, size: 20),
            onPressed: selectAll,
          ),
        ),
        Tooltip(
          message: "Delete".tl,
          child: IconButton(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedDelete01,
              size: 20,
              color: Theme.of(context).colorScheme.error,
            ),
            onPressed: _deleteSelected,
          ),
        ),
        MenuButton(
          entries: [
            MenuEntry(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedFlipHorizontal, size: 18),
              text: "Invert Selection".tl,
              onClick: invertSelection,
            ),
            MenuEntry(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedCancelCircle, size: 18),
              text: "Deselect".tl,
              onClick: deSelect,
            ),
          ],
        ),
        Tooltip(
          message: "Exit Multi-Select".tl,
          child: IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 20),
            onPressed: () => setState(() {
              multiSelectMode = false;
              selectedComics.clear();
            }),
          ),
        ),
      ];

  /// Scroll-to-top FAB，样式与发现页完全一致（统一组件）。
  Widget _buildScrollTopFab() {
    return ScrollTopFab(
      avoidNavBar: true,
      heroTag: 'historyScrollTopFab',
      onPressed: () {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      },
    );
  }
  void _deleteSelected() {
    if (selectedComics.isEmpty) return;
    final comicsToDelete = List<History>.from(selectedComics.keys);
    setState(() {
      multiSelectMode = false;
      selectedComics.clear();
    });
    for (final comic in comicsToDelete) {
      _removeHistory(comic);
    }
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Clear History'.tl),
        content: Text('Are you sure you want to clear your history?'.tl),
        actions: [
          TextButton(
            onPressed: () {
              HistoryManager().clearUnfavoritedHistory();
              Navigator.of(dialogContext).pop();
            },
            child: Text('Clear Unfavorited'.tl),
          ),
          FilledButton(
            onPressed: () {
              HistoryManager().clearHistory();
              Navigator.of(dialogContext).pop();
            },
            child: Text('Clear'.tl),
          ),
        ],
      ),
    );
  }

  String getDescription(History h) {
    var res = "";
    if (h.ep >= 1) {
      res += "Chapter @ep".tlParams({
        "ep": h.ep,
      });
    }
    if (h.page >= 1) {
      if (h.ep >= 1) {
        res += " - ";
      }
      res += "Page @page".tlParams({
        "page": h.page,
      });
    }
    return res;
  }
}
