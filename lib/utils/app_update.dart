import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/network/app_dio.dart';
import 'package:kong_comic/network/file_downloader.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Information about an available update.
class AppUpdateInfo {
  final String latestVersion;
  final String releaseNotes;
  final Map<String, String> abiDownloads;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.releaseNotes,
    required this.abiDownloads,
  });

  /// Pick the download URL matching the current device ABI.
  /// Falls back to the first available asset if no exact ABI match.
  String? pickUrlForCurrentDevice(String? abi) {
    if (abiDownloads.isEmpty) return null;
    if (abi != null && abiDownloads.containsKey(abi)) {
      return abiDownloads[abi];
    }
    return abiDownloads.values.first;
  }
}

class AppUpdate {
  static const _releasesUrl =
      "https://api.github.com/repos/SkyAlice-source/KongComic-android/releases/latest";

  /// Fallback release notes shown when a GitHub release has no description
  /// body. Kept concise and accurate to recent changes.
  static const String _defaultReleaseNotes =
      "本次更新包含：发现、收藏、历史页面新增列表 / 网格布局切换；"
      "默认主题改为跟随系统；亮色主题色彩更鲜明；"
      "并修复若干问题、优化使用体验。";

  /// Maximum number of retries for transient network failures.
  static const int _maxRetries = 2;

  /// Helper: GET with simple retry for transient failures (timeout, 5xx).
  /// Dio throws [DioException] on timeout; we catch it and retry.
  static Future<Map<String, dynamic>> _fetchWithRetry(
    String url, {
    Duration timeout = const Duration(seconds: 10),
    int maxRetries = _maxRetries,
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final res = await AppDio().get(
          url,
          options: Options(
            responseType: ResponseType.json,
            receiveTimeout: timeout,
            sendTimeout: timeout,
          ),
        );
        if (res.statusCode == 200 && res.data is Map) {
          return res.data as Map<String, dynamic>;
        }
        // Non-retryable status codes (client errors: 4xx)
        if (res.statusCode != null &&
            res.statusCode! >= 400 &&
            res.statusCode! < 500) {
          throw DioException(
            requestOptions: res.requestOptions,
            response: res,
            type: DioExceptionType.badResponse,
            message: "HTTP ${res.statusCode}",
          );
        }
        // Retry on 5xx
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 1 << attempt)); // 1s, 2s
          continue;
        }
        throw DioException(
          requestOptions: res.requestOptions,
          response: res,
          type: DioExceptionType.badResponse,
          message: "HTTP ${res.statusCode} after $maxRetries retries",
        );
      } on DioException catch (e) {
        // Retry on timeout and connection errors; rethrow others immediately.
        final retryable = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.unknown;
        if (retryable && attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 1 << attempt));
          continue;
        }
        rethrow;
      }
    }
    // Unreachable
    throw DioException(
      requestOptions: RequestOptions(path: url),
      type: DioExceptionType.unknown,
      message: "Request failed after $maxRetries retries",
    );
  }

  /// Ping the GitHub Releases API. Returns null if the network is reachable
  /// but there is no update, [AppUpdateInfo] if there is, or throws if the
  /// network itself is unavailable.
  ///
  /// The caller can use `try/catch` to distinguish "network unreachable"
  /// from "no update available" — that's how the UI decides between in-app
  /// download and falling back to the browser.
  static Future<AppUpdateInfo?> check() async {
    final data = await _fetchWithRetry(
      _releasesUrl,
      timeout: const Duration(seconds: 8),
    );
    return _parseRelease(data);
  }

  static bool _isNewerVersion(String candidate, String current) {
    final a = candidate.split(".");
    final b = current.split(".");
    for (var i = 0; i < a.length && i < b.length; i++) {
      final ai = int.tryParse(a[i]) ?? 0;
      final bi = int.tryParse(b[i]) ?? 0;
      if (ai > bi) return true;
      if (ai < bi) return false;
    }
    return false;
  }

  /// Shared release data parser used by [check].
  static AppUpdateInfo? _parseRelease(Map<String, dynamic> data) {
    final tag = (data["tag_name"] as String?) ?? "";
    final version = tag.startsWith("v") ? tag.substring(1) : tag;
    if (version.isEmpty) {
      throw Exception("Empty tag_name in release");
    }
    // Strip pre-release (-beta, -rc.1) and build metadata (+build123)
    final coreVersion = version.split(RegExp(r'[-+]')).first;
    if (!_isNewerVersion(coreVersion, App.appVersion)) {
      return null;
    }
    final body = (data["body"] as String?) ?? "";
    final releaseNotes = body.trim().isEmpty ? _defaultReleaseNotes : body;
    final assets = (data["assets"] as List?) ?? const [];
    final downloads = <String, String>{};
    for (final a in assets) {
      if (a is! Map) continue;
      final name = (a["name"] as String?) ?? "";
      final url = (a["browser_download_url"] as String?) ?? "";
      if (name.isEmpty || url.isEmpty) continue;
      if (!name.endsWith(".apk")) continue;
      for (final abi in const [
        "arm64-v8a",
        "armeabi-v7a",
        "x86_64",
      ]) {
        if (name.contains(abi)) {
          downloads[abi] = url;
          break;
        }
      }
    }
    return AppUpdateInfo(
      latestVersion: coreVersion,
      releaseNotes: releaseNotes,
      abiDownloads: downloads,
    );
  }

  /// Core download-and-install logic for the direct GitHub asset URL.
  static Future<void> _downloadAndInstallFromUrl(
    String url,
    String version, {
    required String? abi,
    void Function(double progress, int bytesPerSecond)? onProgress,
    FileDownloaderHandle? handle,
  }) async {
    final cacheDir = Directory(FilePath.join(App.cachePath, "update"));
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    final filename = "KongComic-$version.apk";
    final savePath = FilePath.join(cacheDir.path, filename);

    final downloader = FileDownloader(url, savePath);
    if (handle != null) {
      handle._attach(downloader);
    }
    final completer = Completer<void>();
    final stream = downloader.start();
    StreamSubscription<DownloadingStatus>? sub;
    try {
      sub = stream.listen(
        (status) {
          if (handle != null && handle._canceled) {
            downloader.stop();
            if (!completer.isCompleted) {
              completer.completeError(
                StateError("Download canceled by user"),
              );
            }
            return;
          }
          if (status.totalBytes > 0 && onProgress != null) {
            onProgress(
              status.downloadedBytes / status.totalBytes,
              status.bytesPerSecond,
            );
          }
          if (status.isFinished) {
            if (!completer.isCompleted) completer.complete();
          }
        },
        onError: (e, s) {
          if (!completer.isCompleted) completer.completeError(e, s);
        },
      );
      await completer.future;
      await sub.cancel();
    } catch (e) {
      await sub?.cancel();
      rethrow;
    }

    final apk = File(savePath);
    if (!apk.existsSync() || apk.lengthSync() == 0) {
      throw Exception("Downloaded APK is missing or empty");
    }
    // Lightweight integrity check: verify the APK's ZIP magic header.
    final raf = apk.openSync();
    final magic = raf.readSync(4);
    raf.closeSync();
    if (magic.length < 4 ||
        magic[0] != 0x50 ||
        magic[1] != 0x4B ||
        magic[2] != 0x03 ||
        magic[3] != 0x04) {
      throw Exception("Downloaded APK is corrupted");
    }
    final ok = await App.installApk(savePath);
    if (!ok) {
      throw Exception("Failed to launch the system installer");
    }
  }

  /// Download the APK in [info] matching [abi] and trigger the system
  /// installer. Reports progress via [onProgress]. Returns when the install
  /// intent has been dispatched.
  ///
  /// Throws if no download URL is available, the download itself fails, or
  /// the install intent cannot be launched.
  static Future<void> downloadAndInstall(
    AppUpdateInfo info, {
    required String? abi,
    void Function(double progress, int bytesPerSecond)? onProgress,
    FileDownloaderHandle? handle,
  }) async {
    final url = info.pickUrlForCurrentDevice(abi);
    if (url == null) {
      throw Exception("No APK asset found in the latest release");
    }
    await _downloadAndInstallFromUrl(
      url,
      info.latestVersion,
      abi: abi,
      onProgress: onProgress,
      handle: handle,
    );
  }

  /// Open the releases page in the user's default browser. Used as the
  /// fallback path when the GitHub API is unreachable from the user's
  /// network.
  static Future<void> openReleasePageInBrowser() async {
    final url = "https://github.com/SkyAlice-source/KongComic-android/releases";
    if (!await launchUrlString(url, mode: LaunchMode.externalApplication)) {
      throw Exception("Could not open $url");
    }
  }

  /// Quietly swallow exceptions and only log them — useful for fire-and-forget
  /// side effects from UI callbacks.
  static void safeLog(Object error, [StackTrace? stack]) {
    if (kDebugMode) {
      Log.error("AppUpdate", error.toString(), stack);
    }
  }
}

/// A lightweight handle that lets the UI cancel an in-flight download.
/// Pass an instance into [AppUpdate.downloadAndInstall] and call [cancel]
/// when the user dismisses the dialog.
class FileDownloaderHandle {
  FileDownloader? _downloader;
  bool _canceled = false;

  bool get isCanceled => _canceled;

  void _attach(FileDownloader downloader) {
    _downloader = downloader;
  }

  /// Stop the in-flight download. Safe to call multiple times.
  void cancel() {
    if (_canceled) return;
    _canceled = true;
    _downloader?.stop();
  }
}
