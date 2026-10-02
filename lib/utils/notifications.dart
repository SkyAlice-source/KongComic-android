import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/network/download.dart';
import 'package:kong_comic/utils/app_update.dart';
import 'package:kong_comic/utils/translations.dart';
import 'package:kong_comic/pages/downloading_page.dart';
import 'package:kong_comic/pages/follow_updates_page.dart';
import 'package:kong_comic/pages/local_comics_page.dart';

const _updateChannelId = 'kongcomic_updates';
const _updateChannelNameKey = 'Updates';
const _updateChannelDescKey = 'Comic update checks and app update downloads';

// Dedicated, higher-priority channel for the user-initiated app-update
// download so its progress reliably appears in the status bar (instead of
// being collapsed like the low-importance comic-update checks).
const _appUpdateChannelId = 'kongcomic_app_update';
const _appUpdateChannelNameKey = 'App Update';
const _appUpdateChannelDescKey = 'App update downloads';

const _appUpdateNotificationId = 10001;
const _comicUpdateNotificationId = 20000;

// Dedicated channel for comic downloads. Shows an ongoing, low-priority
// progress notification with pause/resume/cancel action buttons so the user
// can control downloads from the system notification shade.
const _downloadChannelId = 'kongcomic_download';
const _downloadChannelNameKey = 'Downloads';
const _downloadChannelDescKey = 'Comic downloads';
const _downloadNotificationId = 30000;

/// Handles notification taps and action-button presses. Routes download
/// actions (pause/resume/cancel) to the active download task. The payload
/// discriminates our download notification from the app-update / comic-update
/// notifications, which we leave to their own flows.
@pragma('vm:entry-point')
void _onNotificationResponse(NotificationResponse response) {
  final payload = response.payload;
  // 更新完成通知点击 → 重新拉起安装器（错过弹窗后无需重下）
  if (payload != null && payload.startsWith('app_update:')) {
    _retryInstall(payload.substring('app_update:'.length));
    return;
  }
  // 漫画更新完成通知点击 → 跳转追更页查看更新结果
  if (payload == 'comic_update') {
    _openFollowUpdatesPage();
    return;
  }
  // Download finished: jump to the local library where the new comic landed.
  if (payload == 'download_complete') {
    _openLocalComicsPage();
    return;
  }
  if (payload != 'download') return;
  // Tapping the notification body (not an action button) jumps straight to
  // the download page so the user can see/manage active downloads.
  if (response.actionId == null) {
    _openDownloadPage();
    return;
  }
  final tasks = LocalManager().downloadingTasks;
  if (tasks.isEmpty) return;
  final task = tasks.first;
  switch (response.actionId) {
    case 'pause':
      task.pause();
    case 'resume':
      task.resume();
    case 'cancel':
      task.cancel();
  }
}

/// Re-open the installer for an APK that is already on disk (the update
/// completion notification stays tappable after the dialog is dismissed).
///
/// If the private-directory installer is blocked on this device, retry from
/// the public Download folder before giving up. Nothing here is actionable by
/// the user if both paths fail, so failures are swallowed rather than leaking
/// into the zone.
Future<void> _retryInstall(String version) async {
  try {
    await AppUpdate.tryInstallDownloaded(version);
  } on UpdateInstallException catch (_) {
    // The private-directory installer is blocked on this device; retry through
    // the public Download folder. Also guard this hop: the caller runs us
    // fire-and-forget, so a throw here would surface as an unhandled async
    // error with nothing actionable for the user.
    try {
      await AppUpdate.installFromDownloads(version);
    } catch (e) {
      Log.warning("AppUpdate", "Manual install failed: $e");
    }
  } catch (_) {
    // Already reported when the download ran.
  }
}

/// Navigate to the download page. Only meaningful while the app is alive
/// (foreground or background) — which is always the case while a download
/// notification is visible, since downloads don't run after the app is killed.
void _openDownloadPage() {
  try {
    final context = App.mainNavigatorKey?.currentContext;
    if (context != null) {
      context.to(() => const DownloadingPage());
    }
  } catch (_) {
    // App not in a navigable state (e.g. fully terminated). The download page
    // is still reachable from 本地 → 下载管理.
  }
}

/// Navigate to the local comics page after a download finished, so the user
/// lands on the comic they just downloaded instead of an empty queue.
void _openLocalComicsPage() {
  try {
    final context = App.mainNavigatorKey?.currentContext;
    if (context != null) {
      context.to(() => const LocalComicsPage());
    }
  } catch (_) {
    // App not in a navigable state; the page remains reachable from the 本地 tab.
  }
}

/// Navigate to the follow-updates page so the user can review the results of
/// a comic-update check triggered from the notification shade.
void _openFollowUpdatesPage() {
  try {
    final context = App.mainNavigatorKey?.currentContext;
    if (context != null) {
      context.to(() => const FollowUpdatesPage());
    }
  } catch (_) {
    // App not in a navigable state; the page remains reachable from the
    // 追更 tab.
  }
}

class AppNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: darwin);
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
    await _migrateDownloadChannel();
    _initialized = true;
  }

  /// Whether the download channel has already been rebuilt once (see
  /// [_migrateDownloadChannel]).
  static const _downloadChannelResetKey = 'downloadChannelReset';

  /// 重建下载通知渠道（**仅一次**）。
  ///
  /// v1.3.4 之前下载通知用的是 `IMPORTANCE_LOW`，Android 会把它塞进「静默通知」
  /// 折叠区，进度条和暂停/继续按钮基本看不见 —— 表现就像通知消失了。而**已存在
  /// 的通知渠道，其 importance 应用内无法修改**，改代码对老用户不生效，只能删掉
  /// 渠道让下一次 show 以新的 importance 重建。
  ///
  /// 只重建一次：每启动都删会反复抹掉用户对该渠道的自定义设置（例如自己调回去
  /// 静音），并丢掉该渠道里残留的通知。
  static Future<void> _migrateDownloadChannel() async {
    if (!App.isAndroid) return;
    if (appdata.settings[_downloadChannelResetKey] == true) return;
    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.deleteNotificationChannel(
          channelId: _downloadChannelId);
      appdata.settings[_downloadChannelResetKey] = true;
      await appdata.saveData(false);
    } catch (e) {
      // 渠道不存在 / 平台未实现删除：忽略，至少不阻塞启动。下次启动再试。
      Log.warning("Notification", "Failed to reset download channel: $e");
    }
  }

  static Future<bool> requestPermission() async {
    if (!App.isAndroid) return false;
    await init();
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await androidPlugin?.requestNotificationsPermission();
    return granted ?? false;
  }

  static Future<bool> get isAllowed async {
    if (!App.isAndroid) return false;
    await init();
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final enabled = await androidPlugin?.areNotificationsEnabled();
    return enabled ?? false;
  }

  static AndroidNotificationDetails _progressDetails({
    required String title,
    required String body,
    int? progress,
    int? maxProgress,
    bool indeterminate = false,
    bool ongoing = true,
    bool autoCancel = false,
    String channelId = _updateChannelId,
    String channelNameKey = _updateChannelNameKey,
    String channelDescKey = _updateChannelDescKey,
    Importance importance = Importance.low,
    Priority priority = Priority.low,
  }) {
    return AndroidNotificationDetails(
      channelId,
      channelNameKey.tl,
      channelDescription: channelDescKey.tl,
      importance: importance,
      priority: priority,
      showProgress: progress != null && maxProgress != null && maxProgress > 0,
      maxProgress: maxProgress ?? 0,
      progress: progress ?? 0,
      indeterminate: indeterminate,
      ongoing: ongoing,
      autoCancel: autoCancel,
      onlyAlertOnce: true,
      channelShowBadge: false,
      // Progress notifications are refreshed every second; never play the
      // default sound or they would chime on every update.
      playSound: false,
      enableVibration: false,
    );
  }

  static Future<void> showAppUpdateCheck() async {
    await init();
    await _plugin.show(
      id: _appUpdateNotificationId,
      title: "Checking for updates".tl,
      body: "Looking for the latest version...".tl,
      notificationDetails: NotificationDetails(
        android: _progressDetails(
          title: "Checking for updates".tl,
          body: "Looking for the latest version...".tl,
          indeterminate: true,
          channelId: _appUpdateChannelId,
          channelNameKey: _appUpdateChannelNameKey,
          channelDescKey: _appUpdateChannelDescKey,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  static Future<void> showAppUpdateDownload({
    required int progress,
    required int maxProgress,
    required int bytesPerSecond,
  }) async {
    await init();
    final percent = maxProgress > 0 ? (progress * 100 ~/ maxProgress) : 0;
    final speed = _formatSpeed(bytesPerSecond);
    final body = "@percent%  @speed".tlParams({
      "percent": percent.toString(),
      "speed": speed,
    });
    await _plugin.show(
      id: _appUpdateNotificationId,
      title: "Downloading update".tl,
      body: body,
      notificationDetails: NotificationDetails(
        android: _progressDetails(
          title: "Downloading update".tl,
          body: body,
          progress: progress,
          maxProgress: maxProgress,
          channelId: _appUpdateChannelId,
          channelNameKey: _appUpdateChannelNameKey,
          channelDescKey: _appUpdateChannelDescKey,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  static Future<void> showAppUpdateComplete({String? error, String? version}) async {
    await init();
    if (error != null) {
      await _plugin.show(
        id: _appUpdateNotificationId,
        title: "Update failed".tl,
        body: error,
        notificationDetails: NotificationDetails(
          android: _progressDetails(
            title: "Update failed".tl,
            body: error,
            ongoing: false,
            autoCancel: true,
            channelId: _appUpdateChannelId,
            channelNameKey: _appUpdateChannelNameKey,
            channelDescKey: _appUpdateChannelDescKey,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
    } else {
      await _plugin.show(
        id: _appUpdateNotificationId,
        title: "Update ready".tl,
        body: "Follow the system prompt to install.".tl,
        notificationDetails: NotificationDetails(
          android: _progressDetails(
            title: "Update ready".tl,
            body: "Follow the system prompt to install.".tl,
            ongoing: false,
            autoCancel: true,
            channelId: _appUpdateChannelId,
            channelNameKey: _appUpdateChannelNameKey,
            channelDescKey: _appUpdateChannelDescKey,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        payload: version != null ? 'app_update:$version' : null,
      );
    }
  }

  static Future<void> cancelAppUpdate() async {
    await _plugin.cancel(id: _appUpdateNotificationId);
  }

  /// Notify the user that a comic-update check is running across folders.
  static Future<void> showComicUpdateCheck() async {
    await init();
    await _plugin.show(
      id: _comicUpdateNotificationId,
      title: "Checking comic updates".tl,
      body: "Looking for new chapters...".tl,
      notificationDetails: NotificationDetails(
        android: _progressDetails(
          title: "Checking comic updates".tl,
          body: "Looking for new chapters...".tl,
          indeterminate: true,
        ),
      ),
    );
  }

  static Future<void> showComicUpdateProgress({
    required int current,
    required int total,
    int updated = 0,
    int errors = 0,
  }) async {
    await init();
    final percent = total > 0 ? (current * 100 ~/ total) : 0;
    final body = "@current / @total  (@percent%)".tlParams({
      "current": current.toString(),
      "total": total.toString(),
      "percent": percent.toString(),
    });
    await _plugin.show(
      id: _comicUpdateNotificationId,
      title: "Checking comic updates".tl,
      body: body,
      notificationDetails: NotificationDetails(
        android: _progressDetails(
          title: "Checking comic updates".tl,
          body: body,
          progress: current,
          maxProgress: total,
        ),
      ),
    );
  }

  static Future<void> showComicUpdateComplete({
    int updated = 0,
    int errors = 0,
  }) async {
    await init();
    String body;
    if (errors > 0) {
      body = "@updated updated, @errors errors".tlParams({
        "updated": updated.toString(),
        "errors": errors.toString(),
      });
    } else if (updated > 0) {
      body = "@c comics have new updates".tlParams({"c": updated.toString()});
    } else {
      body = "No new updates".tl;
    }
    await _plugin.show(
      id: _comicUpdateNotificationId,
      title: "Comic update check complete".tl,
      body: body,
      notificationDetails: NotificationDetails(
        android: _progressDetails(
          title: "Comic update check complete".tl,
          body: body,
          ongoing: false,
          autoCancel: true,
        ),
      ),
      payload: 'comic_update',
    );
  }

  static Future<void> cancelComicUpdate() async {
    await _plugin.cancel(id: _comicUpdateNotificationId);
  }

  /// Show or update the ongoing comic-download notification.
  ///
  /// Displays the active (first) download's progress and exposes
  /// pause/resume/cancel action buttons so the user can control the download
  /// straight from the system notification shade.
  static Future<void> showDownload({
    required String title,
    required String body,
    required double progress,
    required bool isPaused,
    required bool isError,
  }) async {
    await init();
    final actions = <AndroidNotificationAction>[
      AndroidNotificationAction(
        isPaused ? 'resume' : 'pause',
        (isPaused ? 'Resume' : 'Pause').tl,
      ),
      AndroidNotificationAction('cancel', 'Cancel'.tl),
    ];
    final percent = (progress * 100).round().clamp(0, 100);
    await _plugin.show(
      id: _downloadNotificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _downloadChannelId,
          _downloadChannelNameKey.tl,
          channelDescription: _downloadChannelDescKey.tl,
          // IMPORTANCE_LOW lands in the "silent notifications" section, which
          // Android collapses — the progress bar and action buttons were
          // effectively invisible. Use default importance (no sound) instead.
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          ongoing: !isError,
          autoCancel: false,
          showProgress: true,
          maxProgress: 100,
          progress: percent,
          // Nothing downloaded yet: the task is still fetching comic info /
          // cover / image list, so there is no total to divide by and a
          // determinate bar just sits at 0% looking frozen.
          indeterminate: !isError && !isPaused && percent <= 0,
          onlyAlertOnce: true,
          channelShowBadge: false,
          playSound: false,
          enableVibration: false,
          actions: actions,
        ),
      ),
      payload: 'download',
    );
  }

  static Future<void> cancelDownload() async {
    await _plugin.cancel(id: _downloadNotificationId);
  }

  /// Tell the user the download queue has drained. Without this the ongoing
  /// progress notification simply vanishes, which reads as "the download
  /// died" rather than "it finished".
  static Future<void> showDownloadComplete() async {
    await init();
    await _plugin.show(
      id: _downloadNotificationId,
      title: "Download complete".tl,
      body: "All downloads have finished.".tl,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _downloadChannelId,
          _downloadChannelNameKey.tl,
          channelDescription: _downloadChannelDescKey.tl,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          ongoing: false,
          autoCancel: true,
          showProgress: false,
          onlyAlertOnce: true,
          channelShowBadge: false,
        ),
      ),
      payload: 'download_complete',
    );
  }

  static String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond <= 0) return "";
    if (bytesPerSecond < 1024) return "$bytesPerSecond B/s";
    if (bytesPerSecond < 1024 * 1024) {
      return "${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s";
    }
    return "${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s";
  }
}

/// Keeps the comic-download notification in sync with [LocalManager].
///
/// Subscribes to the manager (so it learns about new/cancelled/completed
/// tasks) and to the active task (so it refreshes on every progress tick).
/// Shows an ongoing progress notification with pause/resume/cancel actions,
/// and removes it once the queue is empty.
class DownloadNotifier {
  static DownloadTask? _tracked;
  static bool _started = false;
  static bool _permissionRequested = false;

  /// Signature of the last posted notification. Used to skip redundant
  /// reposts: the active task notifies every second, and re-posting an
  /// identical notification would (a) waste a platform-channel round trip
  /// and (b) resurrect notifications the user just dismissed — notably the
  /// error one, which is not ongoing and can be swiped away.
  static String? _lastSignature;

  static void start() {
    if (_started) return;
    _started = true;
    LocalManager().addListener(_onListChanged);
    _attach(LocalManager().downloadingTasks.isEmpty
        ? null
        : LocalManager().downloadingTasks.first);
    _update();
  }

  static void _onListChanged() {
    _attach(LocalManager().downloadingTasks.isEmpty
        ? null
        : LocalManager().downloadingTasks.first);
    _update();
  }

  static void _attach(DownloadTask? task) {
    if (_tracked == task) return;
    _tracked?.removeListener(_update);
    _tracked = task;
    _tracked?.addListener(_update);
  }

  static void _update() {
    final tasks = LocalManager().downloadingTasks;
    if (tasks.isEmpty) {
      _lastSignature = null;
      // The queue drained: either everything finished or the user cancelled
      // the last task. Only announce the former.
      if (LocalManager().lastTaskCompleted) {
        LocalManager().lastTaskCompleted = false;
        AppNotifications.showDownloadComplete();
      } else {
        AppNotifications.cancelDownload();
      }
      return;
    }
    if (!_permissionRequested) {
      _permissionRequested = true;
      // Fire-and-forget: prompts only on first download; silently no-ops if
      // already granted or on platforms without runtime permission.
      AppNotifications.requestPermission();
    }
    final first = tasks.first;
    final signature = '${first.title}|${first.message}|'
        '${(first.progress * 100).round()}|${first.isPaused}|${first.isError}';
    if (signature == _lastSignature) return;
    _lastSignature = signature;
    AppNotifications.showDownload(
      title: first.title,
      body: first.message,
      progress: first.progress,
      isPaused: first.isPaused,
      isError: first.isError,
    );
  }
}
