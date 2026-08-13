import 'dart:async' show Future, StreamController;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/cache_manager.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_type.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/network/images.dart';
import 'package:kong_comic/utils/io.dart';
import '../history.dart';
import 'base_image_provider.dart';
import 'image_favorites_provider.dart' as image_provider;

class ImageFavoritesProvider
    extends BaseImageProvider<image_provider.ImageFavoritesProvider> {
  /// Image provider for imageFavorites
  const ImageFavoritesProvider(this.imageFavorite);

  final ImageFavorite imageFavorite;

  int get page => imageFavorite.page;

  String get sourceKey => imageFavorite.sourceKey;

  String get cid => imageFavorite.id;

  String get eid => imageFavorite.eid;

  @override
  Future<Uint8List> load(
    StreamController<ImageChunkEvent>? chunkEvents,
    void Function()? checkStop,
  ) async {
    // 1. Persistent offline copy (single image). Lives under App.dataPath so
    //    it survives app restarts and is not trimmed by the system cache.
    final localFile = localImageFile(imageFavorite);
    if (localFile.existsSync()) {
      return await localFile.readAsBytes();
    }
    var imageKey = imageFavorite.imageKey;
    var localImage = await getImageFromLocal();
    checkStop?.call();
    if (localImage != null) {
      return localImage;
    }
    var cacheImage = await readFromCache();
    checkStop?.call();
    if (cacheImage != null) {
      return cacheImage;
    }
    var gotImageKey = false;
    if (imageKey == "") {
      imageKey = await getImageKey();
      checkStop?.call();
      gotImageKey = true;
    }
    Uint8List image;
    try {
      image = await getImageFromNetwork(imageKey, chunkEvents, checkStop);
    } catch (e) {
      if (gotImageKey) {
        rethrow;
      } else {
        imageKey = await getImageKey();
        image = await getImageFromNetwork(imageKey, chunkEvents, checkStop);
      }
    }
    await writeToCache(image);
    return image;
  }

  Future<void> writeToCache(Uint8List image) async {
    var fileName = md5.convert(key.codeUnits).toString();
    var file = File(FilePath.join(App.cachePath, 'image_favorites', fileName));
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    await file.writeAsBytes(image);
  }

  Future<Uint8List?> readFromCache() async {
    var fileName = md5.convert(key.codeUnits).toString();
    var file = File(FilePath.join(App.cachePath, 'image_favorites', fileName));
    if (!file.existsSync()) {
      return null;
    }
    return await file.readAsBytes();
  }

  /// Delete a image favorite cache
  static Future<void> deleteFromCache(ImageFavorite imageFavorite) async {
    var fileName = md5.convert(imageFavorite.imageKey.codeUnits).toString();
    var file = File(FilePath.join(App.cachePath, 'image_favorites', fileName));
    if (file.existsSync()) {
      await file.delete();
    }
    // also drop the persistent offline copy if present
    final local = localImageFile(imageFavorite);
    if (local.existsSync()) {
      await local.delete();
    }
  }

  /// Persistent local file for a single favorited image, keyed by stable
  /// identifiers (id + sourceKey + eid + page) so it does not depend on the
  /// network image key.
  static File localImageFile(ImageFavorite f) {
    return File(FilePath.join(
      App.dataPath,
      'image_favorites_local',
      '${f.id}_${f.sourceKey}_${f.eid}_${f.page}',
    ));
  }

  /// Download and persist a single favorited image to [localImageFile] so it
  /// can be viewed offline later. Returns true on success.
  static Future<bool> cacheImage(ImageFavorite f) async {
    try {
      final provider = ImageFavoritesProvider(f);
      var key = f.imageKey;
      if (key.isEmpty) {
        key = await provider.getImageKey();
      }
      final data = await provider.getImageFromNetwork(key, null, null);
      final file = localImageFile(f);
      if (!file.existsSync()) {
        file.createSync(recursive: true);
      }
      await file.writeAsBytes(data);
      // Mirror into the app image cache so the reader (which is CacheManager
      // first) can serve this cached favorite offline without further change.
      // The cache key matches ImageDownloader._loadComicImage's key.
      try {
        await CacheManager().writeCache(
          "${f.imageKey}@${f.sourceKey}@${f.id}@${f.eid}",
          data,
        );
      } catch (_) {
        // Non-fatal: the persistent localImageFile copy is still available.
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Uint8List?> getImageFromLocal() async {
    var localComic =
        LocalManager().find(sourceKey, ComicType.fromKey(sourceKey));
    if (localComic == null) {
      return null;
    }
    var epIndex = localComic.chapters?.ids.toList().indexOf(eid) ?? -1;
    if (epIndex == -1 && localComic.hasChapters) {
      return null;
    }
    var images = await LocalManager().getImages(
      sourceKey,
      ComicType.fromKey(sourceKey),
      epIndex,
    );
    var data = await File(images[page]).readAsBytes();
    return data;
  }

  Future<Uint8List> getImageFromNetwork(
    String imageKey,
    StreamController<ImageChunkEvent>? chunkEvents,
    void Function()? checkStop,
  ) async {
    await for (var progress
        in ImageDownloader.loadComicImage(imageKey, sourceKey, cid, eid)) {
      checkStop?.call();
      if (chunkEvents != null) {
        chunkEvents.add(ImageChunkEvent(
          cumulativeBytesLoaded: progress.currentBytes,
          expectedTotalBytes: progress.totalBytes,
        ));
      }
      if (progress.imageBytes != null) {
        return progress.imageBytes!;
      }
    }
    throw "Error: Empty response body.";
  }

  Future<String> getImageKey() async {
    String sourceKey = imageFavorite.sourceKey;
    String cid = imageFavorite.id;
    String eid = imageFavorite.eid;
    var page = imageFavorite.page;
    var comicSource = ComicSource.find(sourceKey);
    if (comicSource == null) {
      throw "Error: Comic source not found.";
    }
    var res = await comicSource.loadComicPages!(cid, eid);
    return res.data[page - 1];
  }

  @override
  Future<ImageFavoritesProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  String get key =>
      "ImageFavorites ${imageFavorite.imageKey}@${imageFavorite.sourceKey}@${imageFavorite.id}@${imageFavorite.eid}";
}
