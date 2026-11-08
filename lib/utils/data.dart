import 'dart:convert';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_type.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/history.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/network/cookie_jar.dart';
import 'package:kong_comic/utils/ext.dart';
import 'package:zip_flutter/zip_flutter.dart';

import 'io.dart';

Future<File> exportAppData([bool sync = true]) async {
  var time = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  var cacheFilePath = FilePath.join(App.cachePath, '$time.kongcomic');
  var cacheFile = File(cacheFilePath);
  var dataPath = App.dataPath;
  if (await cacheFile.exists()) {
    await cacheFile.delete();
  }
  await Isolate.run(() {
    var zipFile = ZipFile.open(cacheFilePath);
    var historyFile = FilePath.join(dataPath, "history.db");
    var localFavoriteFile = FilePath.join(dataPath, "local_favorite.db");
    var appdata = FilePath.join(
      dataPath,
      sync ? "syncdata.json" : "appdata.json",
    );
    var cookies = FilePath.join(dataPath, "cookie.db");
    var coversDir = FilePath.join(dataPath, "covers");
    zipFile.addFile("history.db", historyFile);
    zipFile.addFile("local_favorite.db", localFavoriteFile);
    zipFile.addFile("appdata.json", appdata);
    zipFile.addFile("cookie.db", cookies);
    if (Directory(coversDir).existsSync()) {
      for (var file in Directory(coversDir).listSync()) {
        if (file is File) {
          zipFile.addFile("covers/${file.name}", file.path);
        }
      }
    }
    var comicSourceDir = FilePath.join(dataPath, "comic_source");
    if (Directory(comicSourceDir).existsSync()) {
      for (var file in Directory(comicSourceDir).listSync()) {
        if (file is File) {
          zipFile.addFile("comic_source/${file.name}", file.path);
        }
      }
    }
    // 备份 implicitData.json（自定义封面映射等隐式数据）
    var implicitDataFile = FilePath.join(dataPath, "implicitData.json");
    if (File(implicitDataFile).existsSync()) {
      zipFile.addFile("implicitData.json", implicitDataFile);
    }
    // 备份 local_path（自定义下载路径）
    var localPathFile = FilePath.join(dataPath, "local_path");
    if (File(localPathFile).existsSync()) {
      zipFile.addFile("local_path", localPathFile);
    }
    zipFile.close();
  });
  return cacheFile;
}

/// [syncAssets] 只由 WebDAV 自动同步传入：合并 DB 之后继续执行 settings /
/// cookie / 漫画源 / 自定义封面映射的同步；手动「合并导入」保持原语义（只合并
/// 收藏与历史、其余一律保留本地）。
Future<bool> importAppData(
  File file, [
  bool checkVersion = false,
  bool merge = false,
  bool syncAssets = false,
]) async {
  var needRestart = false;
  var cacheDirPath = FilePath.join(App.cachePath, 'temp_data');
  var cacheDir = Directory(cacheDirPath);
  if (cacheDir.existsSync()) {
    cacheDir.deleteSync(recursive: true);
  }
  cacheDir.createSync();
  try {
    await Isolate.run(() {
      ZipFile.openAndExtract(file.path, cacheDirPath);
    });
    var historyFile = cacheDir.joinFile("history.db");
    var localFavoriteFile = cacheDir.joinFile("local_favorite.db");
    var appdataFile = cacheDir.joinFile("appdata.json");
    var cookieFile = cacheDir.joinFile("cookie.db");
    if (checkVersion && appdataFile.existsSync()) {
      var data = jsonDecode(await appdataFile.readAsString());
      var version = data["settings"]["dataVersion"];
      if (version is int && version <= appdata.settings["dataVersion"]) {
        return false;
      }
    }
    if (merge) {
      // 合并模式：保留当前数据，仅把备份中缺失的部分追加进来。
      if (await localFavoriteFile.exists()) {
        LocalFavoritesManager().mergeFrom(localFavoriteFile.path);
      }
      if (await historyFile.exists()) {
        HistoryManager().mergeFrom(historyFile.path);
      }
      // 复制备份中缺失的封面，避免覆盖本地已有的自定义封面。
      var coversDir = FilePath.join(cacheDirPath, "covers");
      if (Directory(coversDir).existsSync()) {
        var targetCoversDir = FilePath.join(App.dataPath, "covers");
        if (!Directory(targetCoversDir).existsSync()) {
          Directory(targetCoversDir).createSync(recursive: true);
        }
        for (var file in Directory(coversDir).listSync()) {
          if (file is File) {
            var targetPath = FilePath.join(targetCoversDir, file.name);
            if (!File(targetPath).existsSync()) {
              await file.copy(targetPath);
            }
          }
        }
      }
      // 手动「合并导入」到此为止：保留当前设置、Cookies、隐式数据与下载路径。
      // WebDAV 自动同步（syncAssets）则继续往下，把允许跨设备的非 DB 资产
      // 也同步过来，否则收藏合上了却丢了设置 / 登录态 / 漫画源。
      if (!syncAssets) {
        return false;
      }
    } else {
      // 全量替换模式：删掉本机 DB 再换上备份。只有手动「覆盖导入」走这里，
      // WebDAV 已改走 merge，避免本机新增的收藏被远端快照整包覆盖。
      if (await historyFile.exists()) {
        HistoryManager().close();
        File(FilePath.join(App.dataPath, "history.db")).deleteIfExistsSync();
        historyFile.renameSync(FilePath.join(App.dataPath, "history.db"));
        HistoryManager().init();
      }
      if (await localFavoriteFile.exists()) {
        LocalFavoritesManager().close();
        File(
          FilePath.join(App.dataPath, "local_favorite.db"),
        ).deleteIfExistsSync();
        localFavoriteFile.renameSync(
          FilePath.join(App.dataPath, "local_favorite.db"),
        );
        LocalFavoritesManager().init();
      }
    }
    if (await appdataFile.exists()) {
      var content = await appdataFile.readAsString();
      var data = jsonDecode(content);
      // WebDAV 合并（syncAssets）不能在写回 settings 时又触发一次上传。
      appdata.syncData(data, !syncAssets);
    }
    if (await cookieFile.exists()) {
      final targetCookie = File(FilePath.join(App.dataPath, "cookie.db"));
      // merge 语义下不能整包替换：本机在远端快照之后新登录的站点 Cookie
      // 会被旧快照抹掉。只在本机还没有 cookie 库时补一份（新设备首同步）。
      final shouldReplace = !merge ||
          !targetCookie.existsSync() ||
          targetCookie.lengthSync() == 0;
      if (shouldReplace) {
        SingleInstanceCookieJar.instance?.dispose();
        targetCookie.deleteIfExistsSync();
        cookieFile.renameSync(FilePath.join(App.dataPath, "cookie.db"));
        SingleInstanceCookieJar.instance = SingleInstanceCookieJar(
          FilePath.join(App.dataPath, "cookie.db"),
        )..init();
      }
    }
    // 恢复自定义封面。merge 分支上面已经「只补缺失」，这里不能再次无条件
    // 覆盖，否则本机后来替换过的封面又会被远端旧图盖掉。
    if (!merge) {
      var coversDir = FilePath.join(cacheDirPath, "covers");
      if (Directory(coversDir).existsSync()) {
        var targetCoversDir = FilePath.join(App.dataPath, "covers");
        if (!Directory(targetCoversDir).existsSync()) {
          Directory(targetCoversDir).createSync();
        }
        for (var file in Directory(coversDir).listSync()) {
          if (file is File) {
            var targetPath = FilePath.join(targetCoversDir, file.name);
            await file.copy(targetPath);
          }
        }
      }
    }
    var comicSourceDir = FilePath.join(cacheDirPath, "comic_source");
    if (Directory(comicSourceDir).existsSync()) {
      final targetDir = Directory(FilePath.join(App.dataPath, "comic_source"));
      // merge 只补本机缺失的漫画源，绝不能先删目录：本机后来装的新源会被
      // 远端旧快照整包抹掉（手动「覆盖导入」才保留整包替换语义）。
      if (!merge) {
        targetDir.deleteIfExistsSync(recursive: true);
      }
      if (!targetDir.existsSync()) {
        targetDir.createSync(recursive: true);
      }
      var changed = false;
      for (var file in Directory(comicSourceDir).listSync()) {
        if (file is File) {
          var targetFile = FilePath.join(
            App.dataPath,
            "comic_source",
            file.name,
          );
          if (!merge || !File(targetFile).existsSync()) {
            await file.copy(targetFile);
            changed = true;
          }
        }
      }
      if (changed) {
        await ComicSourceManager().reload();
      }
    }
    // 恢复 implicitData.json（自定义封面映射等隐式数据）
    var implicitDataFile = cacheDir.joinFile("implicitData.json");
    if (await implicitDataFile.exists()) {
      if (merge) {
        // WebDAV 只合并真正跨设备共享的「自定义封面映射」。整包替换会把
        // webdavAutoSync（自动同步开关）、favoriteFolder、各类排序筛选等
        // 设备本地状态一起覆盖，甚至静默改变本机是否继续同步。
        try {
          var incoming = jsonDecode(await implicitDataFile.readAsString());
          var covers = incoming is Map ? incoming['customCovers'] : null;
          if (covers is Map) {
            var current = appdata.implicitData['customCovers'];
            if (current is Map && current.isNotEmpty) {
              var merged = Map<String, dynamic>.from(current);
              covers.forEach((key, value) {
                merged.putIfAbsent(key.toString(), () => value);
              });
              appdata.implicitData['customCovers'] = merged;
            } else {
              appdata.implicitData['customCovers'] =
                  Map<String, dynamic>.from(covers);
            }
            appdata.writeImplicitData();
          }
        } catch (e) {
          Log.error("Import Data", "Failed to merge implicit data: $e");
        }
      } else {
        File(
          FilePath.join(App.dataPath, "implicitData.json"),
        ).deleteIfExistsSync();
        implicitDataFile.renameSync(
          FilePath.join(App.dataPath, "implicitData.json"),
        );
        // 重新加载 implicitData 到内存
        try {
          appdata.implicitData = jsonDecode(
            await File(
              FilePath.join(App.dataPath, "implicitData.json"),
            ).readAsString(),
          );
        } catch (e) {
          Log.error("Import Data", "Failed to reload implicit data: $e");
        }
      }
    }
    // 恢复 local_path（自定义下载路径）：路径属于设备本地，自动同步不能带。
    if (!merge) {
      var localPathFile = cacheDir.joinFile("local_path");
      if (await localPathFile.exists()) {
        File(FilePath.join(App.dataPath, "local_path")).deleteIfExistsSync();
        localPathFile.renameSync(FilePath.join(App.dataPath, "local_path"));
        needRestart = true;
      }
    }
    return needRestart;
  } finally {
    cacheDir.deleteIgnoreError(recursive: true);
  }
}

/// 检测备份是否与当前数据存在重复（漫画源 + 名字）。
/// 用于导入时决定是否需要询问用户「覆盖」还是「合并」。
Future<bool> importHasDuplicates(File file) async {
  var cacheDirPath = FilePath.join(App.cachePath, 'temp_duplicate_check');
  var cacheDir = Directory(cacheDirPath);
  if (cacheDir.existsSync()) {
    cacheDir.deleteSync(recursive: true);
  }
  cacheDir.createSync();
  try {
    await Isolate.run(() {
      ZipFile.openAndExtract(file.path, cacheDirPath);
    });
    var localFavoriteFile = cacheDir.joinFile("local_favorite.db");
    var historyFile = cacheDir.joinFile("history.db");
    // 当前收藏的 (name|type) 集合
    var currentFav = <String>{};
    for (var comic in LocalFavoritesManager().allComics()) {
      currentFav.add("${comic.name}|${comic.type.value}");
    }
    if (await localFavoriteFile.exists()) {
      var db = sqlite3.open(localFavoriteFile.path);
      try {
        var tables = db
            .select("SELECT name FROM sqlite_master WHERE type='table';")
            .map((e) => e["name"] as String)
            .toList();
        tables.removeWhere((e) => e == "folder_order" || e == "folder_sync");
        for (var folder in tables) {
          for (var row in db.select('SELECT name, type FROM "$folder";')) {
            if (currentFav.contains("${row['name']}|${row['type']}")) {
              return true;
            }
          }
        }
      } finally {
        db.close();
      }
    }
    // 当前历史的 (title|type) 集合
    var currentHist = <String>{};
    for (var h in HistoryManager().getAll()) {
      currentHist.add("${h.title}|${h.type.value}");
    }
    if (await historyFile.exists()) {
      var db = sqlite3.open(historyFile.path);
      try {
        for (var row in db.select("SELECT title, type FROM history;")) {
          if (currentHist.contains("${row['title']}|${row['type']}")) {
            return true;
          }
        }
      } finally {
        db.close();
      }
    }
    return false;
  } finally {
    cacheDir.deleteIgnoreError(recursive: true);
  }
}

Future<void> importPicaData(File file) async {
  var cacheDirPath = FilePath.join(App.cachePath, 'temp_data');
  var cacheDir = Directory(cacheDirPath);
  if (cacheDir.existsSync()) {
    cacheDir.deleteSync(recursive: true);
  }
  cacheDir.createSync();
  try {
    await Isolate.run(() {
      ZipFile.openAndExtract(file.path, cacheDirPath);
    });
    var localFavoriteFile = cacheDir.joinFile("local_favorite.db");
    if (localFavoriteFile.existsSync()) {
      var db = sqlite3.open(localFavoriteFile.path);
      try {
        var folderNames = db
            .select("SELECT name FROM sqlite_master WHERE type='table';")
            .map((e) => e["name"] as String)
            .toList();
        folderNames.removeWhere(
          (e) => e == "folder_order" || e == "folder_sync",
        );
        for (var folderSyncValue in db.select("SELECT * FROM folder_sync;")) {
          var folderName = folderSyncValue["folder_name"];
          String sourceKey = folderSyncValue["key"];
          sourceKey = sourceKey.toLowerCase() == "htmanga"
              ? "wnacg"
              : sourceKey;
          // 有值就跳过
          if (LocalFavoritesManager().findLinked(folderName).$1 != null) {
            continue;
          }
          try {
            LocalFavoritesManager().linkFolderToNetwork(
              folderName,
              sourceKey,
              jsonDecode(folderSyncValue["sync_data"])["folderId"],
            );
          } catch (e, stack) {
            Log.error(e.toString(), stack);
          }
        }
        for (var folderName in folderNames) {
          if (!LocalFavoritesManager().existsFolder(folderName)) {
            LocalFavoritesManager().createFolder(folderName);
          }
          for (var comic in db.select("SELECT * FROM \"$folderName\";")) {
            LocalFavoritesManager().addComic(
              folderName,
              FavoriteItem(
                id: comic['target'],
                name: comic['name'],
                coverPath: comic['cover_path'],
                author: comic['author'],
                type: ComicType(switch (comic['type']) {
                  0 => 'picacg'.hashCode,
                  1 => 'ehentai'.hashCode,
                  2 => 'jm'.hashCode,
                  3 => 'hitomi'.hashCode,
                  4 => 'wnacg'.hashCode,
                  6 => 'nhentai'.hashCode,
                  _ => comic['type'],
                }),
                tags: comic['tags'].split(','),
              ),
            );
          }
        }
      } catch (e) {
        Log.error("Import Data", "Failed to import local favorite: $e");
      } finally {
        db.close();
      }
    }
    var historyFile = cacheDir.joinFile("history.db");
    if (historyFile.existsSync()) {
      var db = sqlite3.open(historyFile.path);
      try {
        for (var comic in db.select("SELECT * FROM history;")) {
          HistoryManager().addHistory(
            History.fromMap({
              "type": switch (comic['type']) {
                0 => 'picacg'.hashCode,
                1 => 'ehentai'.hashCode,
                2 => 'jm'.hashCode,
                3 => 'hitomi'.hashCode,
                4 => 'wnacg'.hashCode,
                5 => 'nhentai'.hashCode,
                _ => comic['type'],
              },
              "id": comic['target'],
              "max_page": comic["max_page"],
              "ep": comic["ep"],
              "page": comic["page"],
              "time": comic["time"],
              "title": comic["title"],
              "subtitle": comic["subtitle"],
              "cover": comic["cover"],
              "readEpisode": [comic["ep"]],
            }),
          );
        }
        List<ImageFavoritesComic> imageFavoritesComicList =
            ImageFavoriteManager().comics;
        for (var comic in db.select("SELECT * FROM image_favorites;")) {
          String sourceKey = comic["id"].split("-")[0];
          // 换名字了, 绅士漫画
          if (sourceKey.toLowerCase() == "htmanga") {
            sourceKey = "wnacg";
          }
          if (ComicSource.find(sourceKey) == null) {
            continue;
          }
          String id = comic["id"].split("-")[1];
          int page = comic["page"];
          // 章节和page是从1开始的, pica 可能有从 0 开始的, 得转一下
          int ep = comic["ep"] == 0 ? 1 : comic["ep"];
          String title = comic["title"];
          String epName = "";
          ImageFavoritesComic? tempComic = imageFavoritesComicList
              .firstWhereOrNull((e) => e.id == id && e.sourceKey == sourceKey);
          ImageFavorite curImageFavorite = ImageFavorite(
            page,
            "",
            null,
            "",
            id,
            ep,
            sourceKey,
            epName,
          );
          if (tempComic == null) {
            tempComic = ImageFavoritesComic(
              id,
              [],
              title,
              sourceKey,
              [],
              [],
              DateTime.now(),
              "",
              {},
              "",
              1,
            );
            tempComic.imageFavoritesEp = [
              ImageFavoritesEp("", ep, [curImageFavorite], epName, 1),
            ];
            imageFavoritesComicList.add(tempComic);
          } else {
            ImageFavoritesEp? tempEp = tempComic.imageFavoritesEp
                .firstWhereOrNull((e) => e.ep == ep);
            if (tempEp == null) {
              tempComic.imageFavoritesEp.add(
                ImageFavoritesEp("", ep, [curImageFavorite], epName, 1),
              );
            } else {
              // 如果已经有这个page了, 就不添加了
              if (tempEp.imageFavorites.firstWhereOrNull(
                    (e) => e.page == page,
                  ) ==
                  null) {
                tempEp.imageFavorites.add(curImageFavorite);
              }
            }
          }
        }
        for (var temp in imageFavoritesComicList) {
          ImageFavoriteManager().addOrUpdateOrDelete(
            temp,
            temp == imageFavoritesComicList.last,
          );
        }
      } catch (e, stack) {
        Log.error("Import Data", "Failed to import history: $e", stack);
      } finally {
        db.close();
      }
    }
  } finally {
    cacheDir.deleteIgnoreError(recursive: true);
  }
}
