import 'dart:async';
import 'dart:convert';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/utils/channel.dart';

class ComicUpdateResult {
  final bool updated;
  final String? errorMessage;

  ComicUpdateResult(this.updated, this.errorMessage);
}

Future<ComicUpdateResult> updateComic(
    FavoriteItemWithUpdateInfo c, String folder) async {
  int retries = 3;
  while (true) {
    try {
      var comicSource = c.type.comicSource;
      if (comicSource == null) {
        return ComicUpdateResult(false, "Comic source not found");
      }
      var newInfo = (await comicSource.loadComicInfo!(c.id)).data;

      var newTags = <String>[];
      for (var entry in newInfo.tags.entries) {
        const shouldIgnore = ['author', 'artist', 'time'];
        var namespace = entry.key;
        if (shouldIgnore.contains(namespace.toLowerCase())) {
          continue;
        }
        for (var tag in entry.value) {
          newTags.add("$namespace:$tag");
        }
      }

      var item = FavoriteItem(
        id: c.id,
        name: newInfo.title,
        coverPath: newInfo.cover,
        author: newInfo.subTitle ??
            newInfo.tags['author']?.firstOrNull ??
            c.author,
        type: c.type,
        tags: newTags,
      );

      LocalFavoritesManager().updateInfo(folder, item, false);

      var updated = false;
      var updateTime = newInfo.findUpdateTime();
      if (updateTime != null && updateTime != c.updateTime) {
        LocalFavoritesManager().updateUpdateTime(
          folder,
          c.id,
          c.type,
          updateTime,
        );
        updated = true;
      } else {
        LocalFavoritesManager().updateCheckTime(folder, c.id, c.type);
      }
      return ComicUpdateResult(updated, null);
    } catch (e, s) {
      Log.error("Check Updates", e, s);
      await Future.delayed(const Duration(seconds: 2));
      retries--;
      if (retries == 0) {
        return ComicUpdateResult(false, e.toString());
      }
    }
  }
}

class UpdateProgress {
  final int total;
  final int current;
  final int errors;
  final int updated;
  final FavoriteItemWithUpdateInfo? comic;
  final String? errorMessage;

  UpdateProgress(this.total, this.current, this.errors, this.updated,
      [this.comic, this.errorMessage]);
}

/// A single comic-to-update task bound to the folder it lives in.
class _UpdateTask {
  final FavoriteItemWithUpdateInfo comic;
  final String folder;
  _UpdateTask(this.comic, this.folder);
}

/// Core update engine shared by [updateFolder] and [updateFolders].
/// Iterates over [items], applying the once-a-day check-time rule unless
/// [ignoreCheckTime] is set, then runs the producer/consumer pipeline with a
/// global monotonic progress counter.
void _updateItemsBase(
  List<_UpdateTask> items,
  StreamController<UpdateProgress> stream,
  bool ignoreCheckTime,
) async {
  int total = items.length;
  int current = 0;
  int errors = 0;
  int updated = 0;

  stream.add(UpdateProgress(total, current, errors, updated));

  var toUpdate = <_UpdateTask>[];

  for (var t in items) {
    if (!ignoreCheckTime) {
      var lastCheckTime = t.comic.lastCheckTime;
      if (lastCheckTime != null &&
          DateTime.now().difference(lastCheckTime).inDays < 1) {
        current++;
        stream.add(UpdateProgress(total, current, errors, updated));
        continue;
      }
    }
    toUpdate.add(t);
  }

  total = toUpdate.length;
  current = 0;
  stream.add(UpdateProgress(total, current, errors, updated));

  var channel = Channel<_UpdateTask>(10);

  // Producer
  () async {
    var c = 0;
    for (var t in toUpdate) {
      await channel.push(t);
      c++;
      // Throttle
      if (c % 5 == 0) {
        var delay = c % 100 + 1;
        if (delay > 10) {
          delay = 10;
        }
        await Future.delayed(Duration(seconds: delay));
      }
    }
    channel.close();
  }();

  // Consumers
  var updateFutures = <Future>[];
  for (var i = 0; i < 5; i++) {
    var f = () async {
      while (true) {
        var t = await channel.pop();
        if (t == null) {
          break;
        }
        var result = await updateComic(t.comic, t.folder);
        current++;
        if (result.updated) {
          updated++;
        }
        if (result.errorMessage != null) {
          errors++;
        }
        stream.add(UpdateProgress(
          total,
          current,
          errors,
          updated,
          t.comic,
          result.errorMessage,
        ));
      }
    }();
    updateFutures.add(f);
  }

  await Future.wait(updateFutures);

  if (updated > 0) {
    LocalFavoritesManager().notifyChanges();
  }

  stream.close();
}

Stream<UpdateProgress> updateFolder(String folder, bool ignoreCheckTime) {
  var comics = LocalFavoritesManager().getComicsWithUpdatesInfo(folder);
  var stream = StreamController<UpdateProgress>();
  _updateItemsBase(
    comics.map((c) => _UpdateTask(c, folder)).toList(),
    stream,
    ignoreCheckTime,
  );
  return stream.stream;
}

/// Update comics across multiple folders with a single aggregated progress
/// stream. [folders] is the resolved list of folder names.
Stream<UpdateProgress> updateFolders(
    List<String> folders, bool ignoreCheckTime) {
  var items = <_UpdateTask>[];
  for (var folder in folders) {
    for (var c in LocalFavoritesManager().getComicsWithUpdatesInfo(folder)) {
      items.add(_UpdateTask(c, folder));
    }
  }
  var stream = StreamController<UpdateProgress>();
  _updateItemsBase(items, stream, ignoreCheckTime);
  return stream.stream;
}

/// Resolve the effective list of folders configured for follow-updates.
/// Returns [] when disabled, all folders when the list contains the '*'
/// sentinel, otherwise the list of still-existing selected folders.
List<String> getEffectiveFollowFolders() {
  final raw = appdata.settings['followUpdatesFolders'];
  if (raw is! List || raw.isEmpty) return [];
  if (raw.contains('*')) {
    return LocalFavoritesManager().folderNames;
  }
  return raw
      .whereType<String>()
      .where((f) => LocalFavoritesManager().folderNames.contains(f))
      .toList();
}

Future<String> getUpdatedComicsAsJson(String folder) async {
  var comics = LocalFavoritesManager().getComicsWithUpdatesInfo(folder);
  var updatedComics = comics.where((c) => c.hasNewUpdate).toList();
  var jsonList = updatedComics.map((c) => {
    'id': c.id,
    'name': c.name,
    'coverUrl': c.coverPath,
    'author': c.author,
    'type': c.type.sourceKey,
    'updateTime': c.updateTime,
    'tags': c.tags,
  }).toList();
  return jsonEncode(jsonList);
}
