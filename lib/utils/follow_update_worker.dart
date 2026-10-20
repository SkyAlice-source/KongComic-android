import 'package:flutter/widgets.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/follow_updates.dart';
import 'package:kong_comic/foundation/js_engine.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/utils/notifications.dart';
import 'package:kong_comic/utils/translations.dart';
import 'package:workmanager/workmanager.dart';

/// WorkManager 任务唯一名（用于 isScheduled / cancel）。
const String followUpdateTaskKey = "kongcomic_follow_update";

/// 传给 Dart 回调的任务名。
const String followUpdateTaskName = "kongcomic_follow_update_task";

/// 上一次成功登记的「检查间隔」签名，避免每次启动都重置 WorkManager 计时器
/// （否则天天开 App 会让周期任务永远等不到触发点）。
const String _scheduledSignatureKey = "followUpdateScheduledSignature";

/// 登记 / 更新 / 取消「后台追更检查」周期任务。
///
/// 频率跟随追更检查间隔（1/3/7 天），只在配置了追更文件夹时启用。
/// 与自动备份一样，只在签名（是否启用 + 间隔）变化时才重新注册。
Future<void> initFollowUpdateWorker() async {
  if (!App.isAndroid) return;
  try {
    final enabled = getEffectiveFollowFolders().isNotEmpty;
    if (!enabled) {
      await Workmanager().cancelByUniqueName(followUpdateTaskKey);
      if (appdata.implicitData[_scheduledSignatureKey] != null) {
        appdata.implicitData.remove(_scheduledSignatureKey);
        appdata.writeImplicitData();
      }
      return;
    }
    final days = followUpdateIntervalDays;
    final signature = "$days";
    final alreadyScheduled =
        await Workmanager().isScheduledByUniqueName(followUpdateTaskKey);
    if (alreadyScheduled &&
        appdata.implicitData[_scheduledSignatureKey] == signature) {
      return;
    }
    await Workmanager().registerPeriodicTask(
      followUpdateTaskKey,
      followUpdateTaskName,
      frequency: Duration(days: days),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
    appdata.implicitData[_scheduledSignatureKey] = signature;
    appdata.writeImplicitData();
    Log.info("FollowUpdates",
        "Scheduled background follow-up check every $days day(s)");
  } catch (e, s) {
    Log.error("FollowUpdates", "Failed to schedule background check: $e\n$s");
  }
}

bool _runtimeReady = false;

/// 后台 isolate 的最小运行时：路径、收藏库、翻译、JS 引擎与漫画源。
///
/// 后台 isolate 是全新的 Dart 环境，主 isolate 里 init() 干过的活这里一件都
/// 没干过；少一样都会在 updateComic 里抛「Comic source not found」。
Future<void> _ensureRuntime() async {
  if (_runtimeReady) return;
  WidgetsFlutterBinding.ensureInitialized();
  if (!App.isInitialized) {
    await App.init();
  }
  // 收藏库（追更数据都在里面）+ JS 引擎（漫画源脚本）+ 源管理器。
  await App.initComponents();
  await AppTranslation.init();
  await JsEngine().init();
  await ComicSourceManager().init();
  _runtimeReady = true;
}

/// WorkManager 回调里执行的后台检查。
///
/// 与前台 [FollowUpdatesService] 的区别：没有 UI、不能请求权限、不能取消，
/// 只做「到期的漫画检查一遍 + 贴完成通知」。任何一步失败都只记日志，不抛出，
/// 以免 WorkManager 反复重试。
Future<void> runBackgroundFollowUpdateCheck() async {
  try {
    await _ensureRuntime();
    final folders = getEffectiveFollowFolders();
    if (folders.isEmpty) return;
    // 没有到期该查的漫画就什么都不做（连通知都不贴）。
    if (countDueUpdates(folders) == 0) return;

    // 后台不允许弹权限申请，只能查现状；没权限就静默检查，不贴进度通知。
    var canNotify = false;
    try {
      canNotify = await AppNotifications.isAllowed;
    } catch (e) {
      Log.warning("FollowUpdates", "Notification availability check failed: $e");
    }

    int? session;
    int updated = 0;
    int errors = 0;
    if (canNotify) {
      session = await AppNotifications.showComicUpdateCheck();
    }
    try {
      await for (final progress in updateFolders(folders, false)) {
        updated = progress.updated;
        errors = progress.errors;
        if (session != null) {
          await AppNotifications.showComicUpdateProgress(
            session: session,
            current: progress.current,
            total: progress.total,
            updated: progress.updated,
            errors: progress.errors,
          );
        }
      }
    } finally {
      if (session != null) {
        await AppNotifications.showComicUpdateComplete(
          session: session,
          updated: updated,
          errors: errors,
        );
      }
    }
    Log.info("FollowUpdates",
        "Background check finished: $updated updated, $errors errors");
  } catch (e, s) {
    Log.error("FollowUpdates", "Background check failed: $e\n$s");
  }
}
