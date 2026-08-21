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
  /// body. Kept concise and version-agnostic (real releases ship a curated
  /// bilingual changelog via `changelogs/<version>.md`).
  static const String _defaultReleaseNotes =
      "本次更新包含若干问题修复与使用体验优化。\n\n"
      "This update includes bug fixes and UX improvements.";

  /// Maximum number of retries for transient network failures.
  static const int _maxRetries = 2;

  /// Invisible per-language section delimiter used inside changelog files,
  /// e.g. `<!-- lang:zh -->`. Markdown renderers hide HTML comments, so the
  /// GitHub release web page still shows every section while the app only
  /// shows the one matching the device locale.
  static final _langMarker = RegExp(r'<!--\s*lang:(\w+)\s*-->');

  /// Split a changelog body into per-language blocks keyed by language code.
  /// Returns an empty map when the body has no language markers (legacy notes),
  /// in which case the caller should display the whole body.
  static Map<String, String> _extractLangBlocks(String body) {
    final matches = _langMarker.allMatches(body).toList();
    if (matches.isEmpty) return const {};
    final blocks = <String, String>{};
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final lang = m.group(1)!;
      final start = m.end;
      final end = i + 1 < matches.length ? matches[i + 1].start : body.length;
      blocks[lang] = _stripDetailsTags(body.substring(start, end));
    }
    return blocks;
  }

  /// Strip `<details>` / `</details>` / `<summary>…</summary>` folding tags
  /// from a changelog block. The GitHub release page uses these to collapse
  /// the Chinese / Japanese sections (English stays on top and expanded), but
  /// the in-app Markdown renderer would otherwise show the raw HTML tags.
  static String _stripDetailsTags(String s) {
    return s
        .replaceAll(RegExp(r'<details[^>]*>'), '')
        .replaceAll('</details>', '')
        .replaceAll(RegExp(r'<summary[^>]*>.*?</summary>', dotAll: true), '')
        .trim();
  }

  /// Pick the device locale's language code: zh / ja / else en.
  static String _targetLang() {
    final lc = App.locale.languageCode;
    if (lc == 'zh') return 'zh';
    if (lc == 'ja') return 'ja';
    return 'en';
  }

  /// Localize release notes to the device language. Falls back to English,
  /// then to the first non-empty block, then to the default notes.
  static String _localizeNotes(String body) {
    final blocks = _extractLangBlocks(body);
    if (blocks.isEmpty) {
      return body.trim().isEmpty ? _defaultReleaseNotes : body;
    }
    final target = _targetLang();
    final picked = blocks[target] ??
        blocks['en'] ??
        blocks.values.firstWhere(
          (s) => s.trim().isNotEmpty,
          orElse: () => '',
        );
    return picked.trim().isNotEmpty ? picked : _defaultReleaseNotes;
  }

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
    final releaseNotes = _localizeNotes(body);
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

  /// 已下载 APK 的保存目录。放在持久化 data 目录（而非 cache），
  /// 避免被系统清理，让"错过安装弹窗后重装"成为可能。
  static Directory get updateDir =>
      Directory(FilePath.join(App.dataPath, "update"));

  /// 指定版本的 APK 完整路径。
  static String apkPath(String version) =>
      FilePath.join(updateDir.path, "KongComic-$version.apk");

  /// 校验 APK 的完整性。除 ZIP 头 magic 外，还检查文件尾部是否存在
  /// End Of Central Directory (EOCD) 记录签名 `PK\x05\x06`。
  ///
  /// 仅靠 magic 头会在「下载失败残留的不完整 APK」上误判为有效
  /// （ZIP 头位于文件开头，部分下载的文件前 4 字节仍是 PK），导致二次
  /// 更新直接拿损坏文件去安装而必失败。EOCD 位于完整 ZIP 的尾部，
  /// 部分下载的文件必然缺失，因此能可靠区分「已下载完成」与「残留坏文件」。
  static bool _isValidApk(File apk) {
    if (!apk.existsSync()) return false;
    final size = apk.lengthSync();
    if (size < 4) return false;
    final raf = apk.openSync();
    try {
      final magic = raf.readSync(4);
      if (magic.length != 4 ||
          magic[0] != 0x50 ||
          magic[1] != 0x4B ||
          magic[2] != 0x03 ||
          magic[3] != 0x04) {
        return false;
      }
      // EOCD signature "PK\x05\x06" sits near the end of a complete ZIP/APK.
      const eocd = [0x50, 0x4B, 0x05, 0x06];
      final tailLen = size > 128 * 1024 ? 128 * 1024 : size;
      raf.setPositionSync(size - tailLen);
      final tail = raf.readSync(tailLen);
      for (var i = 0; i + 3 < tail.length; i++) {
        if (tail[i] == eocd[0] &&
            tail[i + 1] == eocd[1] &&
            tail[i + 2] == eocd[2] &&
            tail[i + 3] == eocd[3]) {
          return true;
        }
      }
      return false;
    } finally {
      raf.closeSync();
    }
  }

  /// 若本地已下载 [version] 的 APK（且校验通过），直接触发系统安装器。
  /// 返回 true 表示已触发安装；false 表示需要重新下载。
  ///
  /// 供两个入口复用：① 更新检查时跳过重复下载；② 更新完成通知被点击时
  /// 重新拉起安装器（解决"错过弹窗就得重下"的问题）。
  static Future<bool> tryInstallDownloaded(String version) async {
    final apk = File(apkPath(version));
    if (!_isValidApk(apk)) {
      // 清理损坏/残留的 APK，避免后续校验反复失败
      if (apk.existsSync()) {
        try {
          apk.deleteSync();
        } catch (_) {}
      }
      return false;
    }
    return App.installApk(apk.path);
  }

  /// Core download-and-install logic for the direct GitHub asset URL.
  static Future<void> _downloadAndInstallFromUrl(
    String url,
    String version, {
    required String? abi,
    void Function(double progress, int bytesPerSecond)? onProgress,
    FileDownloaderHandle? handle,
  }) async {
    final savePath = apkPath(version);
    // 注意：不在这里删除残留 APK / `.download` 断点状态文件。FileDownloader
    // 内部会自行处理——有效的断点状态用于断点续传（避免不稳网络反复从 0 重下），
    // 损坏或残缺的文件则由 `_prepareFile` + EOCD 守卫在下载前清理并全新下载。
    if (!updateDir.existsSync()) {
      updateDir.createSync(recursive: true);
    }

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
    if (!_isValidApk(apk)) {
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
    // 复用已下载的同版本 APK：错过安装弹窗后无需重复下载，直接再次拉起安装器。
    if (await tryInstallDownloaded(info.latestVersion)) {
      return;
    }
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
