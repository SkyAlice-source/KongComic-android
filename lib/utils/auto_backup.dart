import 'dart:math';

import 'package:archive/archive.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:workmanager/workmanager.dart';

const String autoBackupTaskKey = "kongcomic_auto_backup";
const String autoBackupTaskName = "kongcomic_auto_backup_task";
const int autoBackupKeepCount = 10;

/// WorkManager 回调入口。运行在独立 isolate 中，必须标记为顶级函数。
@pragma('vm:entry-point')
void backupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == autoBackupTaskName) {
      try {
        await performAutoBackup();
      } catch (e, s) {
        Log.error("AutoBackup", "Background backup failed: $e\n$s");
      }
    }
    return Future.value(true);
  });
}

/// 初始化自动备份调度。根据设置启用/禁用 WorkManager 周期任务。
///
/// 仅当任务尚未调度或备份间隔发生变化时才重新注册，避免每次启动应用都重置
/// WorkManager 计时器（否则天天打开 App 会让周期任务永远不触发）。
Future<void> initAutoBackup() async {
  if (!App.isAndroid) return;
  try {
    final enabled = appdata.settings['autoBackupEnabled'] == true;
    final interval = _readInterval();
    if (enabled) {
      final alreadyScheduled =
          await Workmanager().isScheduledByUniqueName(autoBackupTaskKey);
      final lastScheduled =
          appdata.implicitData['autoBackupScheduledInterval'];
      if (!alreadyScheduled || lastScheduled != interval) {
        await Workmanager().registerPeriodicTask(
          autoBackupTaskKey,
          autoBackupTaskName,
          frequency: Duration(days: interval),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        );
        appdata.implicitData['autoBackupScheduledInterval'] = interval;
        appdata.writeImplicitData();
        Log.info(
            "AutoBackup", "Scheduled periodic backup every $interval days");
      }
    } else {
      await Workmanager().cancelByUniqueName(autoBackupTaskKey);
      appdata.implicitData.remove('autoBackupScheduledInterval');
      appdata.writeImplicitData();
    }
  } catch (e, s) {
    Log.error("AutoBackup", "Failed to init: $e\n$s");
  }
}

int _readInterval() {
  final v = appdata.settings['autoBackupInterval'];
  if (v is int) return v.clamp(1, 365);
  if (v is String) return int.tryParse(v) ?? 7;
  return 7;
}

/// 备份保留天数：超过该时长的旧备份在每次备份后被清理。
///
/// 与 [autoBackupKeepCount] 的数量上限叠加——时间维度让「保留多久」可预期，
/// 数量维度做兜底，避免极端情况下（如长期未打开 App）备份无限堆积。
int _readRetentionDays() {
  final v = appdata.settings['autoBackupRetentionDays'];
  if (v is int) return v.clamp(1, 3650);
  if (v is String) return int.tryParse(v) ?? 30;
  return 30;
}

const _suffixChars = "abcdefghijklmnopqrstuvwxyz0123456789";

String _randomSuffix() {
  final rand = Random.secure();
  return List.generate(6, (_) => _suffixChars[rand.nextInt(_suffixChars.length)]).join();
}

/// 执行一次完整备份，写入「下载/KongComic/AutoBackup」目录。
///
/// 可在主 isolate（手动「立即备份」）或 WorkManager 后台 isolate 中调用。
/// 后台 isolate 中 App 尚未初始化，这里会按需初始化路径与插件注册。
Future<void> performAutoBackup() async {
  if (!App.isInitialized) {
    await App.init();
  }
  final dataPath = App.dataPath;
  final now = DateTime.now();
  final dateStr =
      "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  final archive = Archive();

  void addFile(String relative, String absolute) {
    final f = File(absolute);
    if (f.existsSync()) {
      final bytes = f.readAsBytesSync();
      archive.addFile(ArchiveFile(relative, bytes.length, bytes));
    }
  }

  void addDir(String relative, String absolute) {
    final dir = Directory(absolute);
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        final rel =
            entity.path.substring(absolute.length).replaceFirst('/', '');
        addFile("$relative/$rel", entity.path);
      }
    }
  }

  addFile("history.db", FilePath.join(dataPath, "history.db"));
  addFile("local_favorite.db", FilePath.join(dataPath, "local_favorite.db"));
  addFile("appdata.json", FilePath.join(dataPath, "appdata.json"));
  addFile("cookie.db", FilePath.join(dataPath, "cookie.db"));
  addDir("covers", FilePath.join(dataPath, "covers"));
  addDir("comic_source", FilePath.join(dataPath, "comic_source"));
  addFile("implicitData.json", FilePath.join(dataPath, "implicitData.json"));
  addFile("local_path", FilePath.join(dataPath, "local_path"));

  if (archive.files.isEmpty) {
    Log.warning("AutoBackup", "Nothing to back up");
    return;
  }

  final zipBytes = ZipEncoder().encode(archive);

  // 优先写入用户下载目录；若权限不足（如未授予管理外部存储），回退到应用外部存储目录。
  String backupDirPath;
  try {
    backupDirPath = "/storage/emulated/0/Download/KongComic/AutoBackup";
    await Directory(backupDirPath).create(recursive: true);
  } catch (e) {
    Log.warning("AutoBackup", "Cannot write to Download, fallback: $e");
    backupDirPath = FilePath.join(
        App.externalStoragePath ?? dataPath, "KongComicAutoBackup");
    await Directory(backupDirPath).create(recursive: true);
  }

  // 同一天多次备份：在「日期」与扩展名之间追加短随机后缀，避免覆盖已有文件。
  var fileName = "KongComic_auto_${dateStr}_${_randomSuffix()}.kongcomic";
  while (File(FilePath.join(backupDirPath, fileName)).existsSync()) {
    fileName = "KongComic_auto_${dateStr}_${_randomSuffix()}.kongcomic";
  }

  final outFile = File(FilePath.join(backupDirPath, fileName));
  await outFile.writeAsBytes(zipBytes);
  Log.info("AutoBackup", "Backup written to ${outFile.path}");

  // 双维度清理，避免备份无限堆积：
  // 1) 时间维度 —— 删除早于保留天数的旧备份，让「保留多久」可预期；
  // 2) 数量维度 —— 剩余文件按修改时间排序，超出 [autoBackupKeepCount] 上限的
  //    删最旧的，作为兜底（例如长期没打开 App、周期性任务没机会跑时）。
  try {
    final dir = Directory(backupDirPath);
    if (!dir.existsSync()) return;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.name.endsWith('.kongcomic'))
        .toList();
    // 1) 时间维度
    final retentionDays = _readRetentionDays();
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
    for (final f in files) {
      try {
        if (f.lastModifiedSync().isBefore(cutoff)) f.deleteSync();
      } catch (_) {
        // 单文件删除失败不应中断整批清理。
      }
    }
    // 2) 数量维度（兜底）
    final remaining = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.name.endsWith('.kongcomic'))
        .toList()
      ..sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    while (remaining.length > autoBackupKeepCount) {
      try {
        remaining.first.deleteSync();
      } catch (_) {}
      remaining.removeAt(0);
    }
  } catch (e) {
    Log.warning("AutoBackup", "Cleanup old backups failed: $e");
  }
}
