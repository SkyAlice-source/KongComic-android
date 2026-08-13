import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/utils/translations.dart';

const _updateChannelId = 'kongcomic_updates';
const _updateChannelNameKey = 'Updates';
const _updateChannelDescKey = 'Comic update checks and app update downloads';

const _appUpdateNotificationId = 10001;
const _comicUpdateNotificationId = 20000;

class AppNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: darwin);
    await _plugin.initialize(settings);
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
  }) {
    return AndroidNotificationDetails(
      _updateChannelId,
      _updateChannelNameKey.tl,
      channelDescription: _updateChannelDescKey.tl,
      importance: Importance.low,
      priority: Priority.low,
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

  static String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond <= 0) return "";
    if (bytesPerSecond < 1024) return "$bytesPerSecond B/s";
    if (bytesPerSecond < 1024 * 1024) {
      return "${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s";
    }
    return "${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s";
  }
}
