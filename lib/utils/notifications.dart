import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/network/download.dart';
import 'package:kong_comic/utils/translations.dart';
import 'package:kong_comic/pages/downloading_page.dart';

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
  if (response.payload != 'download') return;
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
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
    _initialized = true;
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
    );
  }

  static Future<void> showAppUpdateCheck() async {
    await init();
    await _plugin.show(
      _appUpdateNotificationId,
      "Checking for updates".tl,
      "Looking for the latest version...".tl,
      NotificationDetails(
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
      _appUpdateNotificationId,
      "Downloading update".tl,
      body,
      NotificationDetails(
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

  static Future<void> showAppUpdateComplete({String? error}) async {
    await init();
    if (error != null) {
      await _plugin.show(
        _appUpdateNotificationId,
        "Update failed".tl,
        error,
        NotificationDetails(
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
        _appUpdateNotificationId,
        "Update ready".tl,
        "Follow the system prompt to install.".tl,
        NotificationDetails(
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
      );
    }
  }

  static Future<void> cancelAppUpdate() async {
    await _plugin.cancel(_appUpdateNotificationId);
  }

  /// Notify the user that a comic-update check is running across folders.
  static Future<void> showComicUpdateCheck() async {
    await init();
    await _plugin.show(
      _comicUpdateNotificationId,
      "Checking comic updates".tl,
      "Looking for new chapters...".tl,
      NotificationDetails(
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
      _comicUpdateNotificationId,
      "Checking comic updates".tl,
      body,
      NotificationDetails(
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
      _comicUpdateNotificationId,
      "Comic update check complete".tl,
      body,
      NotificationDetails(
        android: _progressDetails(
          title: "Comic update check complete".tl,
          body: body,
          ongoing: false,
          autoCancel: true,
        ),
      ),
    );
  }

  static Future<void> cancelComicUpdate() async {
    await _plugin.cancel(_comicUpdateNotificationId);
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
    await _plugin.show(
      _downloadNotificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _downloadChannelId,
          _downloadChannelNameKey.tl,
          channelDescription: _downloadChannelDescKey.tl,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: !isError,
          autoCancel: false,
          showProgress: true,
          maxProgress: 100,
          progress: (progress * 100).round().clamp(0, 100),
          onlyAlertOnce: true,
          channelShowBadge: false,
          actions: actions,
        ),
      ),
      payload: 'download',
    );
  }

  static Future<void> cancelDownload() async {
    await _plugin.cancel(_downloadNotificationId);
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
      AppNotifications.cancelDownload();
      return;
    }
    if (!_permissionRequested) {
      _permissionRequested = true;
      // Fire-and-forget: prompts only on first download; silently no-ops if
      // already granted or on platforms without runtime permission.
      AppNotifications.requestPermission();
    }
    final first = tasks.first;
    AppNotifications.showDownload(
      title: first.title,
      body: first.message,
      progress: first.progress,
      isPaused: first.isPaused,
      isError: first.isError,
    );
  }
}
