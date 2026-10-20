import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_type.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/pages/comic_details_page/comic_page.dart';
import 'package:kong_comic/pages/downloading_page.dart';
import 'package:kong_comic/pages/favorites/favorites_page.dart';
import 'package:kong_comic/utils/cbz.dart';
import 'package:kong_comic/utils/import_comic.dart';
import 'package:kong_comic/utils/epub.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:kong_comic/utils/pdf.dart';
import 'package:kong_comic/utils/translations.dart';
import 'package:zip_flutter/zip_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

class LocalComicsPage extends StatefulWidget {
  const LocalComicsPage({super.key});

  @override
  State<LocalComicsPage> createState() => _LocalComicsPageState();
}

class _LocalComicsPageState extends State<LocalComicsPage> {
  late LocalSortType sortType;

  String keyword = "";

  bool searchMode = false;

  bool multiSelectMode = false;

  Map<LocalComic, bool> selectedComics = {};

  /// Comics currently loaded by the paginated grid.
  /// Updated via [onLoadedComicsChanged] callback.
  List<LocalComic> _loadedComics = [];

  /// GlobalKey to access the paginated grid's state for refresh.
  final _gridKey = GlobalKey<PaginatedSliverGridComicsState>();

  /// Page loader for PaginatedSliverGridComics.
  Future<List<Comic>> _loadPage(int offset, int limit) async {
    if (keyword.isEmpty) {
      return LocalManager().getComicsPaginated(sortType,
          limit: limit, offset: offset);
    } else {
      return LocalManager().searchPaginated(keyword,
          limit: limit, offset: offset);
    }
  }

  void update() {
    _gridKey.currentState?.refresh();
  }

  @override
  void initState() {
    var sort = appdata.implicitData["local_sort"] ?? "name";
    sortType = LocalSortType.fromString(sort);
    LocalManager().addListener(update);
    LocalManager().addListener(_onDownloadListChanged);
    super.initState();
  }

  @override
  void dispose() {
    LocalManager().removeListener(update);
    LocalManager().removeListener(_onDownloadListChanged);
    super.dispose();
  }

  /// Refreshes the "下载管理" entry's live task count without reloading the
  /// comic grid.
  void _onDownloadListChanged() {
    if (mounted) setState(() {});
  }

  /// Always-visible shortcut at the top of the 本地 page so users can find
  /// the download page without guessing. Shows a live count badge while
  /// downloads are active.
  Widget _buildDownloadEntry() {
    final cs = Theme.of(context).colorScheme;
    final count = LocalManager().downloadingTasks.length;
    // 做成主页「追更 / 本地」同款胶囊（填充 + 大圆角 + 发丝描边）：
    // 之前是一条裸行直接贴在网格上方，既没有边界，也不像可点的入口。
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kcRadius22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showPopUpWidget(context, const DownloadingPage()),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kcRadius22),
              border: Border.all(color: cs.outlineVariant, width: 0.6),
            ),
            child: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedDownload04,
                  size: 20,
                  color: kcBrandAdaptive(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Downloads".tl,
                    style: TextStyle(
                      fontSize: kcBody,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                if (count > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 22),
                    decoration: BoxDecoration(
                      color: kcAccentSurface(context),
                      borderRadius: BorderRadius.circular(kcPillRadius),
                    ),
                    child: Center(
                      child: Text(
                        count.toString(),
                        style: TextStyle(
                          fontSize: kcFont11,
                          fontWeight: FontWeight.w600,
                          color: kcBrandAdaptive(context),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowRight01,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void sort() {
    final scheme = context.colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = kcReduceMotion(context);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, __) {
        return StatefulBuilder(builder: (ctx, setState) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Material(
                  color: scheme.surfaceContainerHigh,
                  elevation: 3,
                  shadowColor: scheme.shadow.withValues(alpha: 0.18),
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 16, 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Sort".tl,
                            style: Theme.of(ctx)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      RadioGroup<LocalSortType>(
                        groupValue: sortType,
                        onChanged: (v) {
                          setState(() {
                            sortType = v ?? sortType;
                          });
                        },
                        child: Column(
                          children: [
                            RadioListTile<LocalSortType>(
                              title: Text("Name".tl),
                              value: LocalSortType.name,
                            ),
                            RadioListTile<LocalSortType>(
                              title: Text("Date".tl),
                              value: LocalSortType.timeAsc,
                            ),
                            RadioListTile<LocalSortType>(
                              title: Text("Date Desc".tl),
                              value: LocalSortType.timeDesc,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Button.filled(
                              onPressed: () {
                                appdata.implicitData["local_sort"] =
                                    sortType.value;
                                appdata.writeImplicitData();
                                ctx.pop();
                                update();
                              },
                              child: Text("Confirm".tl),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        });
      },
      transitionBuilder: (context, animation, _, child) {
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.93, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget buildMultiSelectMenu() {
    return MenuButton(entries: [
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
        text: "Delete".tl,
        onClick: () {
          deleteComics(selectedComics.keys.toList()).then((value) {
            if (value) {
              setState(() {
                multiSelectMode = false;
                selectedComics.clear();
              });
            }
          });
        },
      ),
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedFavourite, size: 18),
        text: "Add to favorites".tl,
        onClick: () {
          addFavorite(selectedComics.keys.toList());
        },
      ),
      if (selectedComics.length == 1)
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedFolderOpen, size: 18),
          text: "Open Folder".tl,
          onClick: () {
            openComicFolder(selectedComics.keys.first);
          },
        ),
      if (selectedComics.length == 1)
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedBook01, size: 18),
          text: "View Detail".tl,
          onClick: () {
            context.to(() => ComicPage(
                  id: selectedComics.keys.first.id,
                  sourceKey: selectedComics.keys.first.sourceKey,
                ));
          },
        ),
      if (selectedComics.isNotEmpty)
        ...exportActions(selectedComics.keys.toList()),
    ]);
  }

  void selectAll() {
    // Load all comics for selection. This is a one-time operation
    // triggered by the user, not in the scroll path.
    if (keyword.isEmpty) {
      final allComics = LocalManager().getComics(sortType);
      setState(() {
        selectedComics =
            allComics.asMap().map((k, v) => MapEntry(v, true));
      });
    } else {
      final allComics = LocalManager().search(keyword);
      setState(() {
        selectedComics =
            allComics.asMap().map((k, v) => MapEntry(v, true));
      });
    }
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

  /// 「导入」选择弹窗。
  ///
  /// 空目录页/工具栏的「+」都走这里，返回 `cbz` / `multiCbz` / `folder`（取消为 null）。
  ///
  /// 版式要点（2026-10-20 重做）：
  /// - 顶部改成「图标徽章 + 标题 + 说明」的富头部，不再放左上角 ×。纯选择弹窗里
  ///   点遮罩、按返回键都能退，× 只是第三个关闭入口，却把标题挤在左边、右侧空一片；
  ///   换成徽章后顶部有了视觉锚点，右侧由「取消」按钮收口。
  /// - 三个选项从裸 `ListTile` 改成带描边的卡片（图标块 + 主副标题 + 右箭头），
  ///   和「保存图片」「选择文件夹」等弹窗里的选项卡片语言一致，不再显得单薄。
  Future<String?> _showImportChooser() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: "Import".tl,
        subtitle: "Choose how to import".tl,
        headerIcon: HugeIcons.strokeRoundedFolderImport,
        showClose: false,
        // 顶部 4：紧跟富头部的 8dp 间隙，避免第一张卡片被推得离标题太远。
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ImportOptionTile(
              icon: HugeIcons.strokeRoundedArchive,
              title: "Import a CBZ / ZIP / 7Z file".tl,
              subtitle: "Add a single comic archive".tl,
              onTap: () => ctx.pop('cbz'),
            ),
            const SizedBox(height: kcSpaceSm),
            _ImportOptionTile(
              icon: HugeIcons.strokeRoundedFolderZip,
              title: "Import archives in a folder".tl,
              subtitle:
                  "Batch import .cbz/.zip/.7z/.cb7 files from a folder".tl,
              onTap: () => ctx.pop('multiCbz'),
            ),
            const SizedBox(height: kcSpaceSm),
            _ImportOptionTile(
              icon: HugeIcons.strokeRoundedFolder01,
              title: "Import image folders".tl,
              subtitle: "Each subfolder with images becomes a comic".tl,
              onTap: () => ctx.pop('folder'),
            ),
          ],
        ),
        actions: [
          Button.text(
            onPressed: () => ctx.pop(null),
            child: Text("Cancel".tl),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> selectActions = [
      IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle01, size: 18),
          tooltip: "Select All".tl,
          onPressed: selectAll),
      IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
          tooltip: "Deselect".tl,
          onPressed: deSelect),
      IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedFlipHorizontal, size: 18),
          tooltip: "Invert Selection".tl,
          onPressed: invertSelection),
      buildMultiSelectMenu(),
    ];

    List<Widget> normalActions = [
      Tooltip(
        message: "Search".tl,
        child: IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedSearch02, size: 18),
          onPressed: () {
            setState(() {
              searchMode = true;
            });
          },
        ),
      ),
      Tooltip(
        message: "Sort".tl,
        child: IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedSortDescending, size: 18),
          onPressed: sort,
        ),
      ),
      Tooltip(
        message: "Downloading".tl,
        child: IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 18),
          onPressed: () {
            showPopUpWidget(context, const DownloadingPage());
          },
        ),
      ),
      Tooltip(
        message: "Import".tl,
        child: IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedAddCircle, size: 18),
          onPressed: () async {
            final result = await _showImportChooser();
            if (result == null) return;
            if (result == 'cbz') {
              await const ImportComic().cbz();
            } else if (result == 'multiCbz') {
              await const ImportComic().multipleCbz();
            } else if (result == 'folder') {
              await const ImportComic().directory(false);
            }
            setState(() {});
          },
        ),
      ),
    ];

    var body = Scaffold(
      body: SmoothCustomScrollView(
        slivers: [
          if (!searchMode)
            SliverAppbar(
              leading: Tooltip(
                message: multiSelectMode ? "Cancel".tl : "Back".tl,
                child: IconButton(
                  onPressed: () {
                    if (multiSelectMode) {
                      setState(() {
                        multiSelectMode = false;
                        selectedComics.clear();
                      });
                    } else {
                      context.pop();
                    }
                  },
                  icon: multiSelectMode
                      ? HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18)
                      : HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, size: 18),
                ),
              ),
              title: multiSelectMode
                  ? Text(selectedComics.length.toString())
                  : Text("Local".tl),
              actions: multiSelectMode ? selectActions : normalActions,
            )
          else if (searchMode)
            SliverAppbar(
              leading: Tooltip(
                message: multiSelectMode ? "Cancel".tl : "Cancel".tl,
                child: IconButton(
                  icon: multiSelectMode
                      ? HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18)
                      : HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
                  onPressed: () {
                    if (multiSelectMode) {
                      setState(() {
                        multiSelectMode = false;
                        selectedComics.clear();
                      });
                    } else {
                      setState(() {
                        searchMode = false;
                        keyword = "";
                        update();
                      });
                    }
                  },
                ),
              ),
              title: multiSelectMode
                  ? Text(selectedComics.length.toString())
                  : TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: "Search".tl,
                        border: InputBorder.none,
                      ),
                      onChanged: (v) {
                        keyword = v;
                        update();
                      },
                    ),
              actions: multiSelectMode ? selectActions : null,
            ),
          if (!searchMode)
            SliverToBoxAdapter(
              child: _buildDownloadEntry(),
            ),
          PaginatedSliverGridComics(
            key: _gridKey,
            pageLoader: _loadPage,
            emptySubtitle: 'No local comics yet? Tap + at the top right to add a folder.'.tl,
            selections: selectedComics,
            onLoadedComicsChanged: (comics) {
              _loadedComics = comics.cast<LocalComic>();
            },
            onLongPressed: (c, heroID) {
              setState(() {
                multiSelectMode = true;
                selectedComics[c as LocalComic] = true;
              });
            },
            onTap: (c, heroID) {
              if (multiSelectMode) {
                setState(() {
                  if (selectedComics.containsKey(c as LocalComic)) {
                    selectedComics.remove(c);
                  } else {
                    selectedComics[c] = true;
                  }
                  if (selectedComics.isEmpty) {
                    multiSelectMode = false;
                  }
                });
              } else {
                // prevent dirty data
                var comic =
                    LocalManager().find(c.id, ComicType.fromKey(c.sourceKey));
                if (comic != null) {
                  comic.read();
                }
              }
            },
            menuBuilder: (c) {
              return [
                MenuEntry(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedFolderOpen, size: 18),
                  text: "Open Folder".tl,
                  onClick: () {
                    openComicFolder(c as LocalComic);
                  },
                ),
                MenuEntry(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
                  text: "Delete".tl,
                  onClick: () {
                    deleteComics([c as LocalComic]).then((value) {
                      if (value && multiSelectMode) {
                        setState(() {
                          multiSelectMode = false;
                          selectedComics.clear();
                        });
                      }
                    });
                  },
                ),
                ...exportActions([c as LocalComic]),
              ];
            },
          ),
        ],
      ),
    );

    return PopScope(
      canPop: !multiSelectMode && !searchMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (multiSelectMode) {
          setState(() {
            multiSelectMode = false;
            selectedComics.clear();
          });
        } else if (searchMode) {
          setState(() {
            searchMode = false;
            keyword = "";
            update();
          });
        }
      },
      child: body,
    );
  }

  Future<bool> deleteComics(List<LocalComic> comics) async {
    bool isDeleted = false;
    await showGeneralDialog(
      context: App.rootContext,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration:
          kcReduceMotion(App.rootContext) ? Duration.zero : const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, __) {
        bool removeComicFile = false;
        bool removeFavoriteAndHistory = false;
        return StatefulBuilder(builder: (ctx, state) {
          final scheme = Theme.of(ctx).colorScheme;
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Material(
                  color: scheme.surfaceContainerHigh,
                  elevation: 3,
                  shadowColor: scheme.shadow.withValues(alpha: 0.18),
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 16, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Delete".tl,
                            style: Theme.of(ctx)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      CheckboxListTile(
                        title: Text("Remove local favorite and history".tl),
                        value: removeFavoriteAndHistory,
                        onChanged: (v) {
                          state(() {
                            removeFavoriteAndHistory = !removeFavoriteAndHistory;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        title: Text("Also remove files on disk".tl),
                        value: removeComicFile,
                        onChanged: (v) {
                          state(() {
                            removeComicFile = !removeComicFile;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (comics.length == 1 && comics.first.hasChapters)
                              Button.text(
                                onPressed: () {
                                  ctx.pop();
                                  showDeleteChaptersPopWindow(App.rootContext, comics.first);
                                },
                                child: Text("Delete Chapters".tl),
                              ),
                            Button.filled(
                              onPressed: () {
                                ctx.pop();
                                LocalManager().batchDeleteComics(
                                  comics,
                                  removeComicFile,
                                  removeFavoriteAndHistory,
                                );
                                isDeleted = true;
                              },
                              child: Text("Confirm".tl),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        });
      },
      transitionBuilder: (context, animation, _, child) {
        if (kcReduceMotion(App.rootContext)) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.93, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    return isDeleted;
  }

  List<MenuEntry> exportActions(List<LocalComic> comics) {
    return [
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedUpload01, size: 18),
        text: "Export as cbz".tl,
        onClick: () {
          exportComics(comics, CBZ.export, ".cbz");
        },
      ),
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedFile01, size: 18),
        text: "Export as pdf".tl,
        onClick: () async {
          exportComics(comics, createPdfFromComicIsolate, ".pdf");
        },
      ),
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedAddressBook, size: 18),
        text: "Export as epub".tl,
        onClick: () async {
          exportComics(comics, createEpubWithLocalComic, ".epub");
        },
      )
    ];
  }

  /// Export given comics to a file
  void exportComics(
      List<LocalComic> comics, ExportComicFunc export, String ext) async {
    var current = 0;
    var cacheDir = FilePath.join(App.cachePath, 'comics_export');
    var outFile = FilePath.join(App.cachePath, 'comics_export.zip');
    bool canceled = false;
    if (Directory(cacheDir).existsSync()) {
      Directory(cacheDir).deleteSync(recursive: true);
    }
    Directory(cacheDir).createSync();
    var loadingController = showLoadingDialog(
      context,
      allowCancel: true,
      message: comics.length == 1
          ? "${"Exporting".tl}: ${comics.first.title}"
          : "${"Exporting".tl} 0/${comics.length}",
      withProgress: true,
      onCancel: () {
        canceled = true;
      },
    );
    try {
      var fileName = "";
      // For each comic, export it to a file
      for (var comic in comics) {
        fileName = FilePath.join(
          cacheDir,
          sanitizeFileName(comic.title, maxLength: 100) + ext,
        );
        await export(comic, fileName, onProgress: (imgCurrent, imgTotal) {
          if (comics.length == 1) {
            loadingController.setProgress(imgCurrent / imgTotal);
            loadingController.setMessage("${"Exporting".tl}: $imgCurrent/$imgTotal");
          } else {
            var overall = (current + imgCurrent / imgTotal) / comics.length;
            loadingController.setProgress(overall);
            loadingController.setMessage(
                "${"Exporting".tl} ${current + 1}/${comics.length}: $imgCurrent/$imgTotal");
          }
        }).timeout(
          const Duration(minutes: 5),
          onTimeout: () => throw Exception("Export timed out for: ${comic.title}"),
        );
        current++;
        if (comics.length > 1) {
          loadingController.setProgress(current / comics.length);
          loadingController.setMessage("${"Exporting".tl} $current/${comics.length}");
        }
        if (canceled) {
          return;
        }
      }
      // For single comic, just save the file
      if (comics.length == 1) {
        await saveFile(
          file: File(fileName),
          filename: File(fileName).name,
        );
        Directory(cacheDir).deleteSync(recursive: true);
        loadingController.close();
        return;
      }
      // For multiple comics, compress the folder
      loadingController.setProgress(null);
      loadingController.setMessage("Compressing".tl);
      await ZipFile.compressFolderAsync(cacheDir, outFile);
      if (canceled) {
        File(outFile).deleteIgnoreError();
        return;
      }
    } catch (e, s) {
      Log.error("Export Comics", e, s);
      context.showMessage(message: "Failed to export comics".tl);
      loadingController.close();
      return;
    } finally {
      Directory(cacheDir).deleteIgnoreError(recursive: true);
    }
    await saveFile(
      file: File(outFile),
      filename: "comics_export.zip",
    );
    loadingController.close();
    File(outFile).deleteIgnoreError();
  }
}

typedef ExportComicFunc = Future<File> Function(
    LocalComic comic, String outFilePath,
    {void Function(int current, int total)? onProgress});

/// Opens the folder containing the comic in the system file explorer
Future<void> openComicFolder(LocalComic comic) async {
  try {
    final folderPath = comic.baseDir;

    if (App.isAndroid) {
      App.rootContext.showMessage(message: "Not supported on this platform".tl);
      return;
    } else if (App.isWindows) {
      await Process.run('explorer', [folderPath]);
    } else if (App.isMacOS) {
      await Process.run('open', [folderPath]);
    } else if (App.isLinux) {
      // Try different file managers commonly found on Linux
      try {
        await Process.run('xdg-open', [folderPath]);
      } catch (e) {
        // Fallback to other common file managers
        try {
          await Process.run('nautilus', [folderPath]);
        } catch (e) {
          try {
            await Process.run('dolphin', [folderPath]);
          } catch (e) {
            try {
              await Process.run('thunar', [folderPath]);
            } catch (e) {
              // Last resort: use the URL launcher with file:// protocol
              await launchUrlString('file://$folderPath');
            }
          }
        }
      }
    } else {
      // For mobile platforms, use the URL launcher with file:// protocol
      await launchUrlString('file://$folderPath');
    }
  } catch (e, s) {
    Log.error("Open Folder", "Failed to open comic folder: $e", s);
    // Show error message to user
    if (App.rootContext.mounted) {
      App.rootContext.showMessage(message: "Failed to open folder: @e".tlParams({"e": e}));
    }
  }
}

class _DeleteChaptersDialog extends StatefulWidget {
  const _DeleteChaptersDialog({required this.comic});

  final LocalComic comic;

  @override
  State<_DeleteChaptersDialog> createState() => _DeleteChaptersDialogState();
}

class _DeleteChaptersDialogState extends State<_DeleteChaptersDialog> {
  final List<String> _chapters = [];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screen = MediaQuery.sizeOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 360,
            maxHeight: (screen.height * 0.72).clamp(240.0, 560.0),
          ),
          child: Material(
            color: scheme.surfaceContainerHigh,
            elevation: 3,
            shadowColor: scheme.shadow.withValues(alpha: 0.18),
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
                  height: 52,
                  child: Row(
                    children: [
                      const SizedBox(width: kcSpaceXs),
                      IconButton(
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedCancel01,
                          size: 18,
                        ),
                        color: scheme.onSurfaceVariant,
                        onPressed: () => context.pop(),
                      ),
                      const SizedBox(width: kcSpaceXs),
                      Expanded(
                        child: Text(
                          "Delete Chapters".tl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // 与 ContentDialog 标题同一档（22 / w700），避免这个
                          // 自绘弹窗的标题比标准弹窗小一号、层级倒挂。
                          style: const TextStyle(
                            fontSize: kcTitleLarge,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: kcSpaceMd),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    itemCount: widget.comic.downloadedChapters.length,
                    itemBuilder: (context, index) {
                      final id = widget.comic.downloadedChapters[index];
                      final chapter =
                          widget.comic.chapters![id] ?? "Unknown Chapter".tl;
                      return CheckboxListTile(
                        title: Text(chapter),
                        value: _chapters.contains(id),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _chapters.add(id);
                            } else {
                              _chapters.remove(id);
                            }
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Button.filled(
                        onPressed: () {
                          Future.delayed(const Duration(milliseconds: 200), () {
                            LocalManager().deleteComicChapters(
                                widget.comic, _chapters);
                          });
                          context.pop();
                        },
                        child: Text("Submit".tl),
                      ),
                    ],
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

void showDeleteChaptersPopWindow(BuildContext context, LocalComic comic) {
  final reduceMotion = kcReduceMotion(context);
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    transitionDuration:
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) => _DeleteChaptersDialog(comic: comic),
    transitionBuilder: (context, animation, _, child) {
      if (reduceMotion) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.93, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 「导入」弹窗里的单个卡片式选项：图标块 + 主标题 + 说明 + 右箭头。
///
/// 透明底 + `outlineVariant` 发丝描边，而不是填充色：填充底叠在弹窗面
/// （surfaceContainerHigh）上会浮出「盒中盒」，描边只勾边界，观感更平，
/// 与「保存图片」弹窗里的格式卡片是同一套语言。
class _ImportOptionTile extends StatelessWidget {
  const _ImportOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final List<List<dynamic>> icon;

  final String title;

  final String subtitle;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final radius = BorderRadius.circular(kcRadius16);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: kcSpaceMd,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: scheme.outlineVariant, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(kcRadius10),
                ),
                child: HugeIcon(
                  icon: icon,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: kcSpaceMd),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: kcBody,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: kcCaption,
                        height: 1.35,
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: kcSpaceSm),
              HugeIcon(
                icon: HugeIcons.strokeRoundedArrowRight01,
                size: 16,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
