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
    super.initState();
  }

  @override
  void dispose() {
    LocalManager().removeListener(update);
    super.dispose();
  }

  void sort() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return ContentDialog(
            title: "Sort".tl,
            content: RadioGroup<LocalSortType>(
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
            actions: [
              FilledButton(
                onPressed: () {
                  appdata.implicitData["local_sort"] = sortType.value;
                  appdata.writeImplicitData();
                  Navigator.pop(context);
                  update();
                },
                child: Text("Confirm".tl),
              ),
            ],
          );
        });
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
        icon: HugeIcon(icon: HugeIcons.strokeRoundedHeartAdd, size: 18),
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

  @override
  Widget build(BuildContext context) {
    List<Widget> selectActions = [
      IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle01, size: 18),
          tooltip: "Select All".tl,
          onPressed: selectAll),
      IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedCancelCircle, size: 18),
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
            var result = await showModalBottomSheet(
              context: context,
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: HugeIcon(icon: HugeIcons.strokeRoundedArchive, size: 18),
                      title: Text("Import CBZ / ZIP / 7Z".tl),
                      onTap: () => Navigator.pop(ctx, 'cbz'),
                    ),
                    ListTile(
                      leading: HugeIcon(icon: HugeIcons.strokeRoundedFolderZip, size: 18),
                      title: Text("Import archives from folder".tl),
                      subtitle: Text("Batch import .cbz/.zip/.7z files".tl),
                      onTap: () => Navigator.pop(ctx, 'multiCbz'),
                    ),
                    ListTile(
                      leading: HugeIcon(icon: HugeIcons.strokeRoundedFolder01, size: 18),
                      title: Text("Import image folders".tl),
                      subtitle: Text("Import folders containing images as comics".tl),
                      onTap: () => Navigator.pop(ctx, 'folder'),
                    ),
                  ],
                ),
              ),
            );
            if (result == 'cbz') {
              await const ImportComic().cbz();
              setState(() {});
            } else if (result == 'multiCbz') {
              await const ImportComic().multipleCbz();
              setState(() {});
            } else if (result == 'folder') {
              await const ImportComic().directory(false);
              setState(() {});
            }
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
          PaginatedSliverGridComics(
            key: _gridKey,
            pageLoader: _loadPage,
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
                    LocalManager().find(c.id, ComicType.fromKey(c.sourceKey))!;
                comic.read();
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
    await showDialog(
      context: App.rootContext,
      builder: (context) {
        bool removeComicFile = false;
        bool removeFavoriteAndHistory = false;
        return StatefulBuilder(builder: (context, state) {
          return ContentDialog(
            title: "Delete".tl,
            content: Column(
              children: [
                CheckboxListTile(
                  title: Text("Remove local favorite and history".tl),
                  value: removeFavoriteAndHistory,
                  onChanged: (v) {
                    state(() {
                      removeFavoriteAndHistory = !removeFavoriteAndHistory;
                    });
                  },
                ),
                CheckboxListTile(
                  title: Text("Also remove files on disk".tl),
                  value: removeComicFile,
                  onChanged: (v) {
                    state(() {
                      removeComicFile = !removeComicFile;
                    });
                  },
                )
              ],
            ),
            actions: [
              if (comics.length == 1 && comics.first.hasChapters)
                TextButton(
                  child: Text("Delete Chapters".tl),
                  onPressed: () {
                    context.pop();
                    showDeleteChaptersPopWindow(context, comics.first);
                  },
                ),
              FilledButton(
                onPressed: () {
                  context.pop();
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
          );
        });
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
      context.showMessage(message: e.toString());
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
      App.rootContext.showMessage(message: "Failed to open folder: $e");
    }
  }
}

void showDeleteChaptersPopWindow(BuildContext context, LocalComic comic) {
  var chapters = <String>[];

  showPopUpWidget(
    context,
    PopUpWidgetScaffold(
      title: "Delete Chapters".tl,
      body: StatefulBuilder(builder: (context, setState) {
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: comic.downloadedChapters.length,
                itemBuilder: (context, index) {
                  var id = comic.downloadedChapters[index];
                  var chapter = comic.chapters![id] ?? "Unknown Chapter";
                  return CheckboxListTile(
                    title: Text(chapter),
                    value: chapters.contains(id),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          chapters.add(id);
                        } else {
                          chapters.remove(id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () {
                      Future.delayed(const Duration(milliseconds: 200), () {
                        LocalManager().deleteComicChapters(comic, chapters);
                      });
                      App.rootContext.pop();
                    },
                    child: Text("Submit".tl),
                  )
                ],
              ),
            )
          ],
        );
      }),
    ),
  );
}
