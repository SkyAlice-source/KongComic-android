import 'dart:math';

import 'package:archive/archive.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:kong_comic/utils/follow_update_worker.dart';
import 'package:workmanager/workmanager.dart';

const String autoBackupTaskKey = "kongcomic_auto_backup";
const String autoBackupTaskName = "kongcomic_auto_backup_task";
const int autoBackupKeepCount = 10;

/// WorkManager 回调入口。运行在独立 isolate 中，必须标记为顶级函数。
///
/// 所有后台任务的**唯一**入口：按任务名分发（自动备份 / 后台追更检查）。
@pragma('vm:entry-point')
void appBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      switch (task) {
        case autoBackupTaskName:
          await performAutoBackup();
        case followUpdateTaskName:
          await runBackgroundFollowUpdateCheck();
      }
    } catch (e, s) {
      Log.error("BackgroundTask", "Task $task failed: $e\n$s");
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

  // 同一天多次备份：在「日期」与扩展名之间追加短随机后缀，避免覆盖已有文件。
  var fileName = "KongComic_auto_${dateStr}_${_randomSuffix()}.kongcomic";

  final outFile = await _writeBackup(zipBytes, fileName);
  Log.info("AutoBackup", "Backup written to ${outFile.path}");

  await _cleanupOldBackups(outFile.parent.path);
}

/// 备份目录候选，按「用户越容易找到越优先」排序。
///
/// 之前硬编码 `/storage/emulated/0/...`：多用户 / 应用分身 / 双开场景下那不是
/// 当前用户的存储根。公共根只能问原生要（[LocalManager.publicStorageRoot] →
/// `Environment.getExternalStorageDirectory()`）；拿不到就依次退到 App 专属
/// 外部存储、App 私有目录。
Future<List<String>> _backupDirCandidates() async {
  final candidates = <String>[];
  final root = await LocalManager.publicStorageRoot();
  if (root != null) {
    candidates.add(FilePath.join(root, "Download", "KongComic", "AutoBackup"));
  }
  final ext = App.externalStoragePath;
  if (ext != null) {
    candidates.add(FilePath.join(ext, "KongComicAutoBackup"));
  }
  candidates.add(FilePath.join(App.dataPath, "KongComicAutoBackup"));
  return candidates;
}

/// 依次把 [bytes] 写进候选目录，返回落盘的那个文件。
///
/// 关键：**目录建得成不等于写得进去**。未授予「所有文件访问」时
/// `create(recursive: true)` 可能成功，随后的写入却被 FUSE/SELinux 拒绝 ——
/// 之前只有 create 在 try 里、真正的 `writeAsBytes` 在 try 之外，于是每次备份
/// 都失败且没有二次回退。这里把「写」本身当作探测：写不进去就换下一个目录。
Future<File> _writeBackup(List<int> bytes, String fileName) async {
  Object? lastError;
  for (final dir in await _backupDirCandidates()) {
    try {
      final directory = Directory(dir);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      var out = File(FilePath.join(dir, fileName));
      // 极端情况下（同一秒跑两次）文件名仍可能撞车，顺手错开。
      var attempt = 0;
      while (await out.exists() && attempt < 20) {
        out = File(FilePath.join(
            dir,
            "KongComic_auto_${DateTime.now().millisecondsSinceEpoch}_"
                "${_randomSuffix()}.kongcomic"));
        attempt++;
      }
      await out.writeAsBytes(bytes, flush: true);
      return out;
    } catch (e) {
      lastError = e;
      Log.warning("AutoBackup", "Cannot write backup to $dir: $e");
    }
  }
  throw Exception("Failed to write backup file: $lastError");
}

/// 双维度清理，避免备份无限堆积：
/// 1) 时间维度 —— 删除早于保留天数的旧备份，让「保留多久」可预期；
/// 2) 数量维度 —— 剩余文件按修改时间排序，超出 [autoBackupKeepCount] 上限的
///    删最旧的，作为兜底（例如长期没打开 App、周期性任务没机会跑时）。
Future<void> _cleanupOldBackups(String backupDirPath) async {
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
