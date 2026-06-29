import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_type.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:kong_comic/utils/ext.dart';
import 'package:kong_comic/utils/translations.dart';
import 'cbz.dart';
import 'io.dart';

class ImportComic {
  final String? selectedFolder;
  final bool copyToLocal;

  const ImportComic({this.selectedFolder, this.copyToLocal = true});

  Future<bool> cbz() async {
    var file = await selectFile(ext: ['cbz', 'zip', '7z', 'cb7']);
    Map<String?, List<LocalComic>> imported = {};
    if (file == null) {
      return false;
    }
    var controller = showLoadingDialog(App.rootContext, allowCancel: false);
    try {
      var comic = await CBZ.import(File(file.path));
      imported[selectedFolder] = [comic];
    } catch (e, s) {
      Log.error("Import Comic", e.toString(), s);
      App.rootContext.showMessage(message: e.toString());
    }
    controller.close();
    return registerComics(imported, false);
  }

  Future<bool> multipleCbz() async {
    var picker = DirectoryPicker();
    var dir = await picker.pickDirectory(directAccess: true);
    if (dir != null) {
      var entries = await dir.list().toList();
      // Pre-filter valid archive files to know total count
      var validFiles = entries.whereType<File>().where((f) {
        var name = f.name.toLowerCase();
        return name.endsWith('.cbz') || name.endsWith('.zip') ||
            name.endsWith('.7z') || name.endsWith('.cb7');
      }).toList();
      Map<String?, List<LocalComic>> imported = {};
      var controller = showLoadingDialog(App.rootContext,
          allowCancel: false, withProgress: true);
      var comics = <LocalComic>[];
      var processed = 0;
      for (var entry in validFiles) {
        processed++;
        controller.setProgress(processed / validFiles.length);
        controller.setMessage(
            "${"Importing".tl} $processed/${validFiles.length}: ${entry.name}");
        try {
          var comic = await CBZ.import(entry);
          comics.add(comic);
        } catch (e, s) {
          Log.error("Import Comic", e.toString(), s);
        }
      }
      if (comics.isEmpty) {
        App.rootContext.showMessage(message: "No valid comics found".tl);
      }
      imported[selectedFolder] = comics;
      controller.close();
      return registerComics(imported, false);
    }
    return false;
  }

  Future<bool> ehViewer() async {
    var dbFile = await selectFile(ext: ['db']);
    final picker = DirectoryPicker();
    final comicSrc = await picker.pickDirectory();
    Map<String?, List<LocalComic>> imported = {};
    if (dbFile == null || comicSrc == null) {
      return false;
    }

    bool cancelled = false;
    var controller = showLoadingDialog(App.rootContext,
        onCancel: () {
          cancelled = true;
        }, withProgress: true);

    try {
      var db = sql.sqlite3.open(dbFile.path);

      var tags = <String>[""];
      tags.addAll(db.select("""
            SELECT * FROM DOWNLOAD_LABELS LB
            ORDER BY  LB.TIME DESC;
          """).map((r) => r['LABEL'] as String).toList());

      // Pre-collect all comic lists to know total count for progress
      var allComicData = <MapEntry<String, List<sql.Row>>>[];
      for (var tag in tags) {
        var folderName = tag == '' ? '(EhViewer)Default'.tl : '(EhViewer)$tag';
        var comicList = tag == ''
            ? db.select("""
              SELECT * 
              FROM DOWNLOAD_DIRNAME DN
              LEFT JOIN DOWNLOADS DL
              ON DL.GID = DN.GID
              WHERE DL.LABEL IS NULL AND DL.STATE = 3
              ORDER BY DL.TIME DESC
            """).toList()
            : db.select("""
              SELECT * 
              FROM DOWNLOAD_DIRNAME DN
              LEFT JOIN DOWNLOADS DL
              ON DL.GID = DN.GID
              WHERE DL.LABEL = ? AND DL.STATE = 3
              ORDER BY DL.TIME DESC
            """, [tag]).toList();
        allComicData.add(MapEntry(folderName, comicList));
      }

      int totalComics = allComicData.fold(0, (sum, e) => sum + e.value.length);
      int processed = 0;

      for (var entry in allComicData) {
        if (cancelled) {
          break;
        }
        var folderName = entry.key;
        var comicList = entry.value;
        var validComics = <LocalComic>[];
        for (var comic in comicList) {
          if (cancelled) {
            break;
          }
          processed++;
          controller.setProgress(totalComics > 0 ? processed / totalComics : null);
          controller.setMessage("${"Importing".tl}: $processed/$totalComics");
          var comicDir = Directory(
              FilePath.join(comicSrc.path, comic['DIRNAME'] as String));
          String titleJP =
              comic['TITLE_JPN'] == null ? "" : comic['TITLE_JPN'] as String;
          String title = titleJP == "" ? comic['TITLE'] as String : titleJP;
          int timeStamp = comic['TIME'] as int;
          DateTime downloadTime = timeStamp != 0
              ? DateTime.fromMillisecondsSinceEpoch(timeStamp)
              : DateTime.now();
          var comicObj = await _checkSingleComic(comicDir,
              title: title,
              tags: [
                //1 >> x
                [
                  "MISC",
                  "DOUJINSHI",
                  "MANGA",
                  "ARTISTCG",
                  "GAMECG",
                  "IMAGE SET",
                  "COSPLAY",
                  "ASIAN PORN",
                  "NON-H",
                  "WESTERN",
                ][(log(comic['CATEGORY'] as int) / ln2).floor()]
              ],
              createTime: downloadTime);
          if (comicObj == null) {
            continue;
          }
          validComics.add(comicObj);
        }
        imported[folderName] = validComics;
        if (validComics.isNotEmpty &&
            !LocalFavoritesManager().existsFolder(folderName)) {
          LocalFavoritesManager().createFolder(folderName);
        }
      }
      db.dispose();

      //Android specific
      var cache = FilePath.join(App.cachePath, dbFile.name);
      await File(cache).deleteIgnoreError();
    } catch (e, s) {
      Log.error("Import Comic", e.toString(), s);
      App.rootContext.showMessage(message: e.toString());
    }
    controller.close();
    if (cancelled) return false;
    return registerComics(imported, copyToLocal);
  }

  Future<bool> directory(bool single) async {
    final picker = DirectoryPicker();
    final path = await picker.pickDirectory();
    if (path == null) {
      return false;
    }
    Map<String?, List<LocalComic>> imported = {selectedFolder: []};
    var controller = showLoadingDialog(App.rootContext,
        message: "Scanning comics...".tl, allowCancel: false, withProgress: true);
    try {
      if (single) {
        var result = await _checkSingleComic(path);
        if (result != null) {
          imported[selectedFolder]!.add(result);
        } else {
          App.rootContext.showMessage(message: "Invalid Comic".tl);
          controller.close();
          return false;
        }
      } else {
        List<FileSystemEntity> entries;
        try {
          entries = await path.list().toList();
        } catch (_) {
          controller.setMessage("Cannot access directory".tl);
          controller.close();
          return false;
        }
        var totalEntries = entries.length;
        var processed = 0;
        for (var entry in entries) {
          processed++;
          controller.setProgress(processed / totalEntries);
          if (entry is Directory) {
            controller.setMessage("${"Importing".tl}: ${entry.name}");
            var result = await _checkSingleComic(entry);
            if (result != null) {
              imported[selectedFolder]!.add(result);
            }
          }
        }
        controller.setProgress(null);
        // If no subdirectories found, try root folder itself
        if (imported[selectedFolder]!.isEmpty) {
          var result = await _checkSingleComic(path);
          if (result != null) {
            imported[selectedFolder]!.add(result);
          }
        }
        // If still nothing, show message
        if (imported[selectedFolder]!.isEmpty) {
          App.rootContext.showMessage(message: "No valid comics found".tl);
          controller.close();
          return false;
        }
      }
      controller.close();
      return registerComics(imported, false);
    } catch (e, s) {
      Log.error("Import Comic", e.toString(), s);
      App.rootContext.showMessage(message: e.toString());
      controller.close();
      return false;
    }
  }

  Future<bool> localDownloads() async {
    var localDir = LocalManager().directory;
    Map<String?, List<LocalComic>> imported = {null: []};
    bool cancelled = false;
    var controller = showLoadingDialog(App.rootContext,
        onCancel: () {
          cancelled = true;
        }, withProgress: true);
    try {
      if (!await localDir.exists()) {
        App.rootContext.showMessage(message: "Local path not found".tl);
        controller.close();
        return false;
      }
      var entries = await localDir.list().toList();
      var dirs = entries.whereType<Directory>().toList();
      var total = dirs.length;
      var processed = 0;
      for (var entry in dirs) {
        if (cancelled) {
          break;
        }
        processed++;
        controller.setProgress(total > 0 ? processed / total : null);
        controller.setMessage("${"Importing".tl}: $processed/$total");
        var stat = await entry.stat();
        var result = await _checkSingleComic(
          entry,
          createTime: stat.modified,
          useRelativePath: true,
        );
        if (result != null) {
          imported[null]!.add(result);
        }
      }
      if (!cancelled && imported[null]!.isEmpty) {
        App.rootContext.showMessage(message: "No valid comics found".tl);
      }
    } catch (e, s) {
      Log.error("Import Comic", e.toString(), s);
      App.rootContext.showMessage(message: e.toString());
    }
    controller.close();
    if (cancelled) return false;
    return registerComics(imported, false);
  }

  //Automatically search for cover image and chapters
  Future<LocalComic?> _checkSingleComic(Directory directory,
      {String? id,
      String? title,
      String? subtitle,
      List<String>? tags,
      DateTime? createTime,
      bool useRelativePath = false}) async {
    if (!(await directory.exists())) return null;
    var name = title ?? directory.name;
    if (LocalManager().findByName(name) != null) {
      Log.info("Import Comic", "Comic already exists: $name");
      return null;
    }
    bool hasChapters = false;
    var chapters = <String>[];
    var coverPath = ''; // relative path to the cover image
    var fileList = <String>[];
    List<FileSystemEntity> dirEntries;
    try {
      dirEntries = await directory.list().toList();
    } catch (_) {
      return null; // Cannot access directory
    }
    for (var entry in dirEntries) {
      if (entry is Directory) {
        hasChapters = true;
        chapters.add(entry.name);
                await _collectImagesRecursive(entry, fileList);
      } else if (entry is File) {
        const imageExtensions = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'jpe'];
        if (imageExtensions.contains(entry.extension)) {
          fileList.add(entry.name);
        }
      }
    }

    if (fileList.isEmpty) {
      return null;
    }

    fileList.sort();
    coverPath = fileList.firstWhereOrNull((l) => l.startsWith('cover')) ??
        fileList.first;

    chapters.sort();
    if (hasChapters && coverPath == '') {
      // use the first image in the first chapter as the cover
      var firstChapter = Directory('${directory.path}/${chapters.first}');
      await for (var entry in firstChapter.list()) {
        if (entry is File) {
          coverPath = entry.name;
          break;
        }
      }
    }
    if (coverPath == '') {
      Log.info("Import Comic", "Invalid Comic: $name\nNo cover image found.");
      return null;
    }
    var directoryPath = useRelativePath ? directory.name : directory.path;
    return LocalComic(
      id: id ?? '0',
      title: name,
      subtitle: subtitle ?? '',
      tags: tags ?? [],
      directory: directoryPath,
      chapters: hasChapters
          ? ComicChapters(Map.fromIterables(chapters, chapters))
          : null,
      cover: coverPath,
      comicType: ComicType.local,
      downloadedChapters: chapters,
      createdAt: createTime ?? DateTime.now(),
    );
  }

  static Future<Map<String, String>> _copyDirectories(
      Map<String, dynamic> data) async {
    return overrideIO(() async {
      var toBeCopied = data['toBeCopied'] as List<String>;
      var destination = data['destination'] as String;
      Map<String, String> result = {};
      for (var dir in toBeCopied) {
        var source = Directory(dir);
        var dest = Directory("$destination/${source.name}");
        if (dest.existsSync()) {
          // The destination directory already exists, and it is not managed by the app.
          // Rename the old directory to avoid conflicts.
          Log.info("Import Comic",
              "Directory already exists: ${source.name}\nRenaming the old directory.");
          dest.renameSync(
              findValidDirectoryName(dest.parent.path, "${dest.path}_old"));
        }
        dest.createSync();
        await copyDirectory(source, dest);
        result[source.path] = dest.path;
      }
      return result;
    });
  }

  Future<Map<String?, List<LocalComic>>> _copyComicsToLocalDir(
      Map<String?, List<LocalComic>> comics) async {
    var destPath = LocalManager().path;
    Map<String?, List<LocalComic>> result = {};
    for (var favoriteFolder in comics.keys) {
      result[favoriteFolder] = comics[favoriteFolder]!
          .where((c) => c.directory.startsWith(destPath))
          .toList();
      comics[favoriteFolder]!
          .removeWhere((c) => c.directory.startsWith(destPath));

      if (comics[favoriteFolder]!.isEmpty) {
        continue;
      }

      try {
        // copy the comics to the local directory
        var pathMap = await compute<Map<String, dynamic>, Map<String, String>>(
            _copyDirectories, {
          'toBeCopied':
              comics[favoriteFolder]!.map((e) => e.directory).toList(),
          'destination': destPath,
        });
        //Construct a new object since LocalComic.directory is a final String
        for (var c in comics[favoriteFolder]!) {
          result[favoriteFolder]!.add(LocalComic(
            id: c.id,
            title: c.title,
            subtitle: c.subtitle,
            tags: c.tags,
            directory: pathMap[c.directory]!,
            chapters: c.chapters,
            cover: c.cover,
            comicType: c.comicType,
            downloadedChapters: c.downloadedChapters,
            createdAt: c.createdAt,
          ));
        }
      } catch (e, s) {
        App.rootContext.showMessage(message: "Failed to copy comics".tl);
        Log.error("Import Comic", e.toString(), s);
        return result;
      }
    }
    return result;
  }

  /// Recursively collect image files from a directory (including subdirectories)
  Future<void> _collectImagesRecursive(Directory dir, List<String> fileList) async {
    const imageExtensions = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'jpe'];
    try {
      await for (var entry in dir.list()) {
        if (entry is File) {
          if (imageExtensions.contains(entry.extension)) {
            fileList.add(entry.name);
          }
        } else if (entry is Directory) {
          await _collectImagesRecursive(entry, fileList);
        }
      }
    } catch (_) {
      // Skip directories that can't be listed
    }
  }

  Future<bool> registerComics(
      Map<String?, List<LocalComic>> importedComics, bool copy) async {
    try {
      if (copy) {
        importedComics = await _copyComicsToLocalDir(importedComics);
      }
      int importedCount = 0;
      int updatedCount = 0;
      int skippedCount = 0;
      final resolver = LocalManager();
      for (var folder in importedComics.keys) {
        for (var comic in importedComics[folder]!) {
          // Dedup by absolute directory path. Re-importing the same file
          // (or a CBZ exported back over the same path) should update the
          // existing row instead of producing a new one with a fresh id.
          final existing = resolver.findByDirectory(comic.directory);
          if (existing != null) {
            final merged = comic.copyWith(
              id: existing.id,
              downloadedChapters: {
                ...existing.downloadedChapters,
                ...comic.downloadedChapters,
              }.toList(),
              createdAt: existing.createdAt,
              cover: existing.cover,
            );
            // `add` uses INSERT OR REPLACE keyed on id — passing the
            // existing id replaces the old row in place.
            resolver.add(merged, existing.id);
            updatedCount++;
          } else {
            var id = resolver.findValidId(ComicType.local);
            resolver.add(comic, id);
            importedCount++;
          }
          if (folder != null) {
            final existingByDir = resolver.findByDirectory(comic.directory);
            final id = existingByDir?.id ?? comic.id;
            // Only add to the named favorite folder once per directory.
            final alreadyInFolder = LocalFavoritesManager()
                .find(id, ComicType.local)
                .contains(folder);
            if (!alreadyInFolder) {
              LocalFavoritesManager().addComic(
                  folder,
                  FavoriteItem(
                      id: id,
                      name: comic.title,
                      coverPath: comic.cover,
                      author: comic.subtitle,
                      type: comic.comicType,
                      tags: comic.tags,
                      favoriteTime: comic.createdAt));
            } else {
              skippedCount++;
            }
          }
        }
      }
      if (importedCount > 0) {
        App.rootContext.showMessage(
            message: "Imported @a comics".tlParams({'a': importedCount}));
      } else if (updatedCount > 0) {
        App.rootContext.showMessage(
            message: "Updated @a comics".tlParams({'a': updatedCount}));
      } else if (skippedCount > 0) {
        App.rootContext.showMessage(
            message: "No new comics".tlParams({'a': skippedCount}));
      }
      App.forceRebuild();
    } catch (e, s) {
      App.rootContext.showMessage(message: "Failed to register comics".tl);
      Log.error("Import Comic", e.toString(), s);
      return false;
    }
    return true;
  }
}
