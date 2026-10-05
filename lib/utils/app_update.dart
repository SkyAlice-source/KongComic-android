import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/foundation/update_mirror.dart';
import 'package:kong_comic/network/app_dio.dart';
import 'package:kong_comic/network/file_downloader.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:crypto/crypto.dart';
import 'package:kong_comic/utils/translations.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Raised when a download route stops delivering bytes.
///
/// This is not a user cancellation: nobody pressed anything. The pipeline
/// treats it as "this route is unusable, try the next one", which is what makes
/// automatic fallback off a blocked GitHub connection possible.
class UpdateStalledException implements Exception {
  const UpdateStalledException();

  @override
  String toString() => "Download stalled";
}

/// Thrown when every configured download route failed.
class UpdateAllSourcesFailedException implements Exception {
  const UpdateAllSourcesFailedException(this.detail);

  final String detail;

  @override
  String toString() => "All download sources failed: $detail";
}

/// Thrown when the APK could not be fetched. Almost always a network problem
/// (GitHub is slow or resets connections regularly from mainland China).
class UpdateDownloadException implements Exception {
  final String reason;

  const UpdateDownloadException(this.reason);

  @override
  String toString() => "Update download failed: $reason";
}

/// Thrown when the download finished but the resulting file is not a complete
/// APK. Retrying usually helps; the partial file is deleted beforehand.
class UpdateVerifyException implements Exception {
  const UpdateVerifyException();

  @override
  String toString() => "Downloaded APK is corrupted";
}

/// Thrown when the download finished and the file looks like a complete APK
/// (valid ZIP magic + EOCD) but its SHA-256 digest does not match the value
/// published alongside the release. Indicates a corrupted or tampered download
/// that slipped past the cheap structural check. Re-downloading usually fixes
/// it, so the UI treats this the same as a structural failure (verify stage).
class UpdateHashException implements Exception {
  final String expected;
  final String actual;

  const UpdateHashException(this.expected, this.actual);

  @override
  String toString() =>
      "APK SHA-256 mismatch (expected $expected, got $actual)";
}

/// Thrown when the APK is intact but the system installer refused to open it.
/// The download already succeeded, so retrying the download is pointless — the
/// UI offers a manual install path instead.
class UpdateInstallException implements Exception {
  final String reason;
  final String apkPath;

  const UpdateInstallException(this.reason, this.apkPath);

  /// The user still has to grant the "install unknown apps" permission for
  /// KongComic. Nothing is broken, they just need to flip a switch.
  bool get isPermissionIssue =>
      reason.contains("install_permission_required") ||
      reason.contains("Permission");

  @override
  String toString() => "Failed to launch the system installer: $reason";
}

/// The stage at which an in-app update failed.
///
/// Distinguishing these matters: "download" asks the user to retry or check
/// their network, while "install" means the APK is already sitting on disk and
/// re-downloading it accomplishes nothing. Merging them into a single "update
/// failed" message is what made a v1.3.3 install bug masquerade as broken
/// networking for weeks.
enum UpdateFailureStage { download, verify, install }

/// Map an update exception onto the [UpdateFailureStage] that produced it.
UpdateFailureStage updateFailureStage(Object e) {
  if (e is UpdateInstallException) return UpdateFailureStage.install;
  if (e is UpdateVerifyException || e is UpdateHashException) {
    return UpdateFailureStage.verify;
  }
  return UpdateFailureStage.download;
}

/// Describe the failure in the user's language, including what to do next.
String updateFailureMessage(Object e) {
  switch (updateFailureStage(e)) {
    case UpdateFailureStage.download:
      if (e is UpdateAllSourcesFailedException) {
        return "Every download source failed. Open the release page in your browser to update manually."
            .tl;
      }
      return "Download failed".tl;
    case UpdateFailureStage.verify:
      if (e is UpdateHashException) {
        return "The downloaded APK failed its security check (SHA-256 mismatch). Please download it again."
            .tl;
      }
      return "The downloaded file is incomplete. Please download it again.".tl;
    case UpdateFailureStage.install:
      final install = e is UpdateInstallException ? e : null;
      if (install != null && install.isPermissionIssue) {
        return "KongComic needs the 「Install unknown apps」 permission. Allow it on the next screen, then try again."
            .tl;
      }
      return "The update was downloaded but the system installer could not open it. Install it manually from the Download folder."
          .tl;
  }
}

/// Information about an available update.
class AppUpdateInfo {
  final String latestVersion;
  final String releaseNotes;
  final Map<String, String> abiDownloads;

  /// Expected SHA-256 (lowercase hex) per ABI key, published in the release
  /// notes as a hidden `<!-- sha256 ... -->` block by CI. Null for legacy
  /// releases that predate hash publishing; in that case verification is
  /// skipped so older updates keep working.
  final Map<String, String>? sha256;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.releaseNotes,
    required this.abiDownloads,
    this.sha256,
  });

  /// Pick the download URL matching the current device ABI.
  /// Falls back to the first available asset if no exact ABI match.
  String? pickUrlForCurrentDevice(String? abi) {
    if (abiDownloads.isEmpty) return null;
    if (abi != null && abiDownloads.containsKey(abi)) {
      return abiDownloads[abi];
    }
    // Prefer the universal build over an arbitrary per-ABI one when the
    // device ABI has no matching asset (e.g. a release where split APKs
    // failed to upload).
    return abiDownloads['universal'] ?? abiDownloads.values.first;
  }

  /// Like [pickUrlForCurrentDevice] but returns the ABI key that was chosen
  /// (e.g. `arm64-v8a` or `universal`) so callers can look up the expected
  /// SHA-256. Returns null when no asset is available.
  String? pickAbiKeyForCurrentDevice(String? abi) {
    if (abiDownloads.isEmpty) return null;
    if (abi != null && abiDownloads.containsKey(abi)) return abi;
    if (abiDownloads.containsKey('universal')) return 'universal';
    return abiDownloads.keys.first;
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

  /// How long a download may go without delivering anything before the
  /// pipeline gives up on the current route and hands over to the next mirror.
  ///
  /// A throttled GitHub connection often answers quickly and then crawls or
  /// freezes. Waiting for the socket timeout would burn minutes per route; this
  /// keeps each hopeless route to a few seconds.
  static const Duration kStallTimeout = Duration(seconds: 15);

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

  /// Extract published SHA-256 digests from the release body. CI appends a
  /// hidden HTML comment block (`<!-- sha256 ... -->`) listing one `<abi> <hex>`
  /// pair per asset. Parsing is independent of the localized changelog blocks
  /// so it never affects what the user sees in the update dialog.
  static Map<String, String>? _extractSha256(String body) {
    final m = RegExp(r'<!--\s*sha256\s*\n([\s\S]*?)-->').firstMatch(body);
    if (m == null) return null;
    final map = <String, String>{};
    for (final line in m.group(1)!.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length == 2 &&
          RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(parts[1])) {
        map[parts[0]] = parts[1].toLowerCase();
      }
    }
    return map.isEmpty ? null : map;
  }

  /// Remove the hidden `<!-- sha256 ... -->` block from a body so it never
  /// shows up in the in-app update notes (only matters for legacy changelogs
  /// that lack per-language markers; localized ones drop it already).
  static String _stripSha256(String body) => body
      .replaceAll(RegExp(r'<!--\s*sha256\s*[\s\S]*?-->', dotAll: true), '')
      .trim();

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
    final cleaned = _stripSha256(body);
    final blocks = _extractLangBlocks(cleaned);
    if (blocks.isEmpty) {
      return cleaned.trim().isEmpty ? _defaultReleaseNotes : cleaned;
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
    String? universalUrl;
    for (final a in assets) {
      if (a is! Map) continue;
      final name = (a["name"] as String?) ?? "";
      final url = (a["browser_download_url"] as String?) ?? "";
      if (name.isEmpty || url.isEmpty) continue;
      if (!name.endsWith(".apk")) continue;
      var matchedAbi = false;
      for (final abi in const [
        "arm64-v8a",
        "armeabi-v7a",
        "x86_64",
      ]) {
        if (name.contains(abi)) {
          downloads[abi] = url;
          matchedAbi = true;
          break;
        }
      }
      // Keep the universal APK as a fallback for devices whose ABI has no
      // dedicated asset.
      if (!matchedAbi && name.toLowerCase().contains("universal")) {
        universalUrl ??= url;
      }
    }
    if (universalUrl != null) {
      downloads['universal'] = universalUrl;
    }
    // Published integrity digests (null for legacy releases without them).
    final shaMap = _extractSha256(body);
    return AppUpdateInfo(
      latestVersion: coreVersion,
      releaseNotes: releaseNotes,
      abiDownloads: downloads,
      sha256: shaMap,
    );
  }

  /// 已下载 APK 的保存目录。放在持久化 data 目录（而非 cache），
  /// 避免被系统清理，让"错过安装弹窗后重装"成为可能。
  static Directory get updateDir =>
      Directory(FilePath.join(App.dataPath, "update"));

  /// 指定版本的 APK 完整路径。
  static String apkPath(String version) =>
      FilePath.join(updateDir.path, "KongComic-$version.apk");

  /// Stream-compute the SHA-256 of [file] without loading it fully into memory
  /// (release APKs are ~40 MB). Uses `package:crypto`.
  static Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

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
  /// 返回 true 表示已触发安装；false 表示没有可用 APK，需要重新下载。
  ///
  /// 供两个入口复用：① 更新检查时跳过重复下载；② 更新完成通知被点击时
  /// 重新拉起安装器（解决"错过弹窗就得重下"的问题）。
  ///
  /// 抛 [UpdateInstallException] 表示 APK 完好但拉不起安装器 —— 这种情况下
  /// 重新下载毫无意义，必须让调用方知道失败发生在安装阶段。
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
    final error = await App.installApk(apk.path);
    if (error != null) {
      throw UpdateInstallException(error, apk.path);
    }
    return true;
  }

  /// Manual escape hatch: copy the already-downloaded APK into the public
  /// Download folder and ask the system to install it from there. Used when
  /// [tryInstallDownloaded] fails, e.g. because a ROM blocks installs from an
  /// app-private directory.
  ///
  /// Returns `null` on success, otherwise the platform reason.
  static Future<String?> installFromDownloads(String version) async {
    final apk = File(apkPath(version));
    if (!_isValidApk(apk)) {
      throw const UpdateVerifyException();
    }
    return App.installApkFromDownloads(
      apk.path,
      "KongComic-$version.apk",
    );
  }

  /// Core download-and-install logic for the direct GitHub asset URL.
  static Future<void> _downloadAndInstallFromUrl(
    String url,
    String version, {
    required String? abi,
    String? expectedSha256,
    bool singleStream = false,
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

    final downloader = FileDownloader(
      url,
      savePath,
      singleStream: singleStream,
    );
    handle?.resetStall();
    if (handle != null) {
      handle._attach(downloader);
    }
    final completer = Completer<void>();
    final stream = downloader.start();
    StreamSubscription<DownloadingStatus>? sub;
    bool finished = false;
    // Fail fast instead of hanging: a route that stops delivering bytes (very
    // common when GitHub is throttled) must hand over to the next mirror rather
    // than sit at the same progress until the socket times out.
    var lastActivity = DateTime.now();
    void touch() => lastActivity = DateTime.now();
    touch();
    final watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (completer.isCompleted) return;
      if (DateTime.now().difference(lastActivity) > kStallTimeout) {
        handle?.stall();
      }
    });
    try {
      sub = stream.listen(
        (status) {
          touch();
          if (handle != null && (handle._canceled || handle._stalled)) {
            downloader.stop();
            if (!completer.isCompleted) {
              completer.completeError(
                handle._canceled
                    ? StateError("Download canceled by user")
                    : const UpdateStalledException(),
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
            finished = true;
            if (!completer.isCompleted) completer.complete();
          }
        },
        onError: (e, s) {
          if (!completer.isCompleted) completer.completeError(e, s);
        },
        onDone: () {
          // The stream can close without any status event (the downloader was
          // stopped before it emitted anything). Never wait forever on it.
          if (completer.isCompleted) return;
          if (finished) {
            completer.complete();
          } else if (handle != null && handle._stalled) {
            completer.completeError(const UpdateStalledException());
          } else if (handle != null && handle._canceled) {
            completer.completeError(
              StateError("Download canceled by user"),
            );
          } else {
            completer.completeError(
              Exception("Download stopped unexpectedly"),
            );
          }
        },
      );
      await completer.future;
    } on StateError {
      // User-initiated cancellation is not a failure.
      rethrow;
    } on UpdateStalledException {
      // Different route next time, please.
      rethrow;
    } catch (e) {
      throw UpdateDownloadException(e.toString());
    } finally {
      watchdog.cancel();
      await sub?.cancel();
    }

    final apk = File(savePath);
    if (!_isValidApk(apk)) {
      throw const UpdateVerifyException();
    }
    if (expectedSha256 != null) {
      final actual = await _sha256OfFile(apk);
      final expected = expectedSha256.toLowerCase();
      if (actual != expected) {
        // The structural check passed but the digest does not, so the file is
        // corrupt/tampered. Delete it so a retry re-downloads cleanly instead
        // of re-verifying the same bad bytes.
        try {
          await apk.delete();
        } catch (_) {}
        throw UpdateHashException(expected, actual);
      }
    }
    final error = await App.installApk(savePath);
    if (error != null) {
      throw UpdateInstallException(error, savePath);
    }
  }

  /// Drop APKs left over from earlier versions.
  ///
  /// Each installed update leaves a ~40 MB file behind and nothing ever removed
  /// them, so a long-lived install accumulated hundreds of megabytes of dead
  /// APKs. Called before a new download starts; the version being downloaded is
  /// never touched (its partial state may still be resumable).
  static Future<void> _cleanupOldApks(String keepVersion) async {
    // Cleanup is best-effort: it must never be the reason an update fails.
    try {
      if (!await updateDir.exists()) return;
      final keepName = "KongComic-$keepVersion.apk";
      final stale = <File>[];
      await for (final entity in updateDir.list()) {
        if (entity is! File) continue;
        final name = entity.name;
        if (!name.startsWith("KongComic-") ||
            !name.endsWith(".apk") ||
            name == keepName) {
          continue;
        }
        stale.add(entity);
      }
      for (final file in stale) {
        await file.deleteIgnoreError();
        await File("${file.path}.download").deleteIgnoreError();
      }
    } catch (e) {
      Log.error("AppUpdate", "Failed to clean up old APKs: $e", null);
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
    void Function(String mirrorName)? onMirrorChanged,
    FileDownloaderHandle? handle,
  }) async {
    // 复用已下载的同版本 APK：错过安装弹窗后无需重复下载，直接再次拉起安装器。
    if (await tryInstallDownloaded(info.latestVersion)) {
      return;
    }
    await _cleanupOldApks(info.latestVersion);
    final url = info.pickUrlForCurrentDevice(abi);
    if (url == null) {
      throw Exception("No APK asset found in the latest release");
    }
    // Verify the downloaded bytes against the digest published with the release
    // (null for legacy releases → skip). Keyed by the ABI we actually chose.
    final key = info.pickAbiKeyForCurrentDevice(abi);
    String? expected;
    if (key != null) {
      final map = info.sha256;
      if (map != null) expected = map[key];
    }

    final routes = UpdateMirrorPreference.rotation();
    // The background (notification driven) path downloads without a UI to cancel
    // it, so it hands over no handle. The stall watchdog still needs one to stop
    // a dead route, otherwise it could never move on from it.
    final effectiveHandle = handle ?? FileDownloaderHandle();
    Object? lastError;
    String? lastDetail;

    for (final mirror in routes) {
      if (effectiveHandle.isCanceled) {
        throw StateError("Download canceled by user");
      }
      onMirrorChanged?.call(mirror.name);
      final target = mirror.apply(url);
      try {
        final probe = await probeMirror(mirror, url);
        if (!probe.ok) {
          throw UpdateDownloadException(probe.error ?? "Unreachable");
        }
        // A previous route may have left bytes behind. Its resume state is not
        // valid for a different server (different chunk size, different
        // content-length), so start this route from a clean slate.
        if (lastError != null) {
          await _resetPartial(info.latestVersion);
        }
        await _downloadAndInstallFromUrl(
          target,
          info.latestVersion,
          abi: abi,
          expectedSha256: expected,
          singleStream: !probe.supportsRange,
          onProgress: onProgress,
          handle: effectiveHandle,
        );
        UpdateMirrorPreference.markWorking(mirror.id);
        return;
      } catch (e, s) {
        if (effectiveHandle.isCanceled) rethrow;
        // The APK was fully downloaded *and* passed its SHA-256 check through
        // this route — only the system installer refused to open it. The route
        // itself is fine, so remember it and let the UI offer manual install
        // instead of redownloading the same bytes from another mirror.
        if (e is UpdateInstallException) {
          UpdateMirrorPreference.markWorking(mirror.id);
          rethrow;
        }
        lastError = e;
        lastDetail = "$mirror: $e";
        if (kDebugMode) {
          Log.error("AppUpdate", "Update via ${mirror.name} failed: $e", s);
        }
      }
    }

    if (routes.length <= 1 && lastError != null) {
      // A pinned route must surface its own failure (including cancellations
      // and stalls), otherwise the UI cannot tell "user pressed stop" from
      // "network died".
      throw lastError is UpdateDownloadException
          ? lastError
          : UpdateDownloadException(lastError.toString());
    }
    throw UpdateAllSourcesFailedException(lastDetail ?? "unknown error");
  }

  /// Delete the partially downloaded APK and its resume state.
  static Future<void> _resetPartial(String version) async {
    final apk = File(apkPath(version));
    await apk.deleteIgnoreError();
    await File("${apk.path}.download").deleteIgnoreError();
  }

  /// The APK asset URL of the newest release, regardless of whether it is an
  /// update for this install. Used by the mirror tester, which needs a real
  /// file to fetch but has no pending update to hang it on.
  static Future<String?> latestAssetUrl() async {
    final data = await _fetchWithRetry(
      _releasesUrl,
      timeout: const Duration(seconds: 8),
    );
    final assets = (data["assets"] as List?) ?? const [];
    for (final a in assets) {
      if (a is! Map) continue;
      final url = (a["browser_download_url"] as String?) ?? "";
      final name = (a["name"] as String?) ?? "";
      if (name.endsWith(".apk") && url.isNotEmpty) return url;
    }
    return null;
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

  /// Set by the pipeline's stall watchdog, not by the user. A stalled download
  /// must not be reported as a cancellation: nobody pressed stop, the route
  /// simply stopped delivering bytes.
  bool _stalled = false;

  bool get isCanceled => _canceled;

  bool get isStalled => _stalled;

  void _attach(FileDownloader downloader) {
    _downloader = downloader;
  }

  /// Stop the in-flight download. Safe to call multiple times.
  void cancel() {
    if (_canceled) return;
    _canceled = true;
    _downloader?.stop();
  }

  /// Abandon the current download so the next mirror can take over. Unlike
  /// [cancel] this leaves [isCanceled] false, so the UI keeps showing progress
  /// instead of silently closing.
  void stall() {
    if (_canceled || _stalled) return;
    _stalled = true;
    _downloader?.stop();
  }

  /// Clear the stalled flag before a new route starts.
  void resetStall() {
    _stalled = false;
  }
}
