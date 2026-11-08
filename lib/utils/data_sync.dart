import 'package:flutter/foundation.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/components/window_frame.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/foundation/res.dart';
import 'package:kong_comic/network/app_dio.dart';
import 'package:kong_comic/utils/data.dart';
import 'package:kong_comic/utils/ext.dart';
import 'package:webdav_client/webdav_client.dart' hide File;
import 'package:kong_comic/utils/translations.dart';

import 'io.dart';

class DataSync with ChangeNotifier {
  DataSync._() {
    if (isEnabled) {
      downloadData();
    }
    LocalFavoritesManager().addListener(onDataChanged);
    ComicSourceManager().addListener(onDataChanged);
    if (App.isDesktop) {
      Future.delayed(const Duration(seconds: 1), () {
        var controller = WindowFrame.of(App.rootContext);
        controller.addCloseListener(_handleWindowClose);
      });
    }
  }

  void onDataChanged() {
    if (!isEnabled) return;
    // 导入窗口内的 notify 绝大多数来自 importAppData 自身（mergeFrom /
    // reload / syncData），不能回传，否则多设备之间会「下载完立刻上传」乒乓。
    // 但也不能静默丢：窗口结束时由 downloadData 清掉自产生的那部分；窗口
    // 之外的真实改动仍会触发一次全量快照上传（快照是整包，不是增量 diff），
    // 导入期间新增的数据不会被永久丢云。
    if (_isImporting) {
      _pendingUpload = true;
      return;
    }
    // 上传或下载正在进行时，旧实现直接把这次改动丢掉；记一个待补传标记，
    // 等当前任务结束后统一补一次，而不是让改动永远不上云。
    if (_isDownloading || _isUploading || _haveWaitingTask) {
      _pendingUpload = true;
      return;
    }
    uploadData();
  }

  bool _handleWindowClose() {
    if (_isUploading) {
      _showWindowCloseDialog();
      return false;
    }
    return true;
  }

  void _showWindowCloseDialog() async {
    showLoadingDialog(
      App.rootContext,
      cancelButtonText: "Shut Down".tl,
      onCancel: () => exit(0),
      barrierDismissible: false,
      message: "Uploading data...".tl,
    );
    while (_isUploading) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    exit(0);
  }

  static DataSync? instance;

  factory DataSync() => instance ?? (instance = DataSync._());

  bool _isDownloading = false;

  bool get isDownloading => _isDownloading;

  bool _isUploading = false;

  bool get isUploading => _isUploading;

  /// 导入（WebDAV 下载后的合并）进行中。比 `_isDownloading` 覆盖范围更长：
  /// `importAppData` 触发的 notify 可能落在下载窗口之后的微任务里。
  bool _isImporting = false;

  bool _haveWaitingTask = false;

  /// 有改动在上传/下载期间发生，当前任务结束后补传一次。
  bool _pendingUpload = false;

  /// 下载请求因「已有任务在排队」被跳过时记下，任务结束后补跑下载。
  /// 以前这里错置 `_pendingUpload`，结果下载被静默吞掉、反倒多传一次。
  bool _pendingDownload = false;

  String? _lastError;

  String? get lastError => _lastError;

  /// 与 [_validateConfig] 用同一套校验：以前这里只判断「非空 List」，配置
  /// 写成 2 项或 4 项时 isEnabled 为真、实际上传/下载却每次都报非法配置。
  bool get isEnabled {
    var autoSync = appdata.implicitData['webdavAutoSync'] ?? false;
    if (autoSync != true) return false;
    var config = _validateConfig();
    return config != null && config.isNotEmpty;
  }

  List<String>? _validateConfig() {
    var config = appdata.settings['webdav'];
    if (config is! List) {
      return null;
    }
    if (config.isEmpty) {
      return [];
    }
    if (config.length != 3 || config.whereType<String>().length != 3) {
      return null;
    }
    return List.from(config);
  }

  /// 快照文件名 `<天数>-<版本>.kongcomic`。旧版版本号不补零，字典序会把
  /// `-9` 排在 `-10` 之后：下载会取到较旧的快照，清理又会误删最新的一份。
  /// 统一解析成 (天数, 版本) 数值再比较，兼容服务器上的旧文件名。
  static int _compareSnapshots(String a, String b) {
    List<int> parse(String name) {
      var stem = name.endsWith('.kongcomic')
          ? name.substring(0, name.length - '.kongcomic'.length)
          : name;
      var parts = stem.split('-');
      return [
        int.tryParse(parts.first) ?? 0,
        parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      ];
    }

    var pa = parse(a);
    var pb = parse(b);
    var byDay = pa[0].compareTo(pb[0]);
    return byDay != 0 ? byDay : pa[1].compareTo(pb[1]);
  }

  /// 当前任务结束后，把「忙期间被记下的改动」和「被跳过的下载请求」补跑。
  /// 只排一个 microtask，不阻塞调用方，也不与刚结束的任务抢锁。
  void _flushPending() {
    if (_isImporting || _isDownloading || _isUploading || _haveWaitingTask) {
      return;
    }
    if (!_pendingUpload && !_pendingDownload) return;
    final upload = _pendingUpload;
    final download = _pendingDownload;
    _pendingUpload = false;
    _pendingDownload = false;
    if (!isEnabled) return;
    Future.microtask(() async {
      if (download) {
        await downloadData();
      }
      if (upload) {
        await uploadData();
      }
      // 补跑期间若又有改动被记下（或又走了提前 return 的路径），再排一轮，
      // 避免 pending 一直搁置到下一次无关的用户操作。
      if (_pendingUpload || _pendingDownload) {
        _flushPending();
      }
    });
  }

  Future<Res<bool>> uploadData() async {
    if (isDownloading || _isImporting) return const Res(true);
    if (_haveWaitingTask) {
      _pendingUpload = true;
      return const Res(true);
    }
    while (isUploading) {
      _haveWaitingTask = true;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _haveWaitingTask = false;
    // 等待期间可能插入了一次下载：不能再无条件开始导出，否则会与
    // importAppData 同时读写 history.db / local_favorite.db。
    if (isDownloading || _isImporting) {
      _pendingUpload = true;
      return const Res(true);
    }
    _isUploading = true;
    _lastError = null;
    notifyListeners();
    File? exported;
    try {
      var config = _validateConfig();
      if (config == null) {
        _lastError = 'Invalid WebDAV configuration';
        return const Res.error('Invalid WebDAV configuration');
      }
      if (config.isEmpty) {
        return const Res(true);
      }
      String url = config[0];
      String user = config[1];
      String pass = config[2];

      var client = newClient(
        url,
        user: user,
        password: pass,
        adapter: RHttpAdapter(),
      );

      try {
        // dataVersion 可能从旧备份 / 同步里被写成 double 或字符串，`++`
        // 会直接抛；统一归一化。
        var currentVersion = appdata.settings['dataVersion'];
        var local = currentVersion is num
            ? currentVersion.toInt()
            : int.tryParse(currentVersion.toString()) ?? 0;
        var nextVersion = local + 1;
        appdata.settings['dataVersion'] = nextVersion;
        await appdata.saveData(false);
        // 恒定打包脱敏快照 syncdata.json。以前用
        // `disableSyncFields.toString().isNotEmpty` 当开关，默认配置下会
        // 传 false → 把含 WebDAV 明文密码、proxy、deviceId 的 appdata.json
        // 整个传上服务器；`.toString()` 遇 null 还会指向一个没生成的文件。
        exported = await exportAppData(true);
        var time = (DateTime.now().millisecondsSinceEpoch ~/ 86400000)
            .toString();
        // 版本补零，保证字典序与数值序一致（旧文件由 _compareSnapshots 兼容）。
        var filename =
            '$time-${nextVersion.toString().padLeft(8, '0')}.kongcomic';
        var files = await client.readDir('/');
        // webdav_client 的 File.name 是 String?，某些服务器会返回无名条目。
        files = files.where((e) => e.name != null).toList();
        files = files.where((e) => e.name!.endsWith('.kongcomic')).toList();
        var old = files.firstWhereOrNull((e) => e.name!.startsWith("$time-"));
        if (old != null) {
          await client.remove(old.name!);
          files.remove(old);
        }
        // 保留 10 份：多设备同日上传时旧实现一次只删 1 个，文件数会单调增长。
        if (files.length >= 10) {
          files.sort((a, b) => _compareSnapshots(a.name!, b.name!));
          var overflow = files.length - 9;
          for (var i = 0; i < overflow; i++) {
            await client.remove(files[i].name!);
          }
        }
        await client.write(filename, await exported.readAsBytes());
        Log.info("Upload Data", "Data uploaded successfully");
        return const Res(true);
      } catch (e, s) {
        Log.error("Upload Data", e, s);
        _lastError = e.toString();
        return Res.error(e.toString());
      }
    } finally {
      _isUploading = false;
      // 导出临时 zip 无论成功失败都删掉；以前只在成功路径 fire-and-forget。
      if (exported != null) {
        await exported.deleteIgnoreError();
      }
      notifyListeners();
      _flushPending();
    }
  }

  Future<Res<bool>> downloadData() async {
    if (_isImporting) return const Res(true);
    if (_haveWaitingTask) {
      // 被跳过的是「下载」而不是上传：记下载标记，由 _flushPending 补跑，
      // 否则 UI 拿到 Res(true) 显示已保存，远端快照其实根本没拉下来。
      _pendingDownload = true;
      return const Res(true);
    }
    while (isDownloading || isUploading) {
      _haveWaitingTask = true;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _haveWaitingTask = false;
    _isDownloading = true;
    _lastError = null;
    notifyListeners();
    try {
      var config = _validateConfig();
      if (config == null) {
        _lastError = 'Invalid WebDAV configuration';
        return const Res.error('Invalid WebDAV configuration');
      }
      if (config.isEmpty) {
        return const Res(true);
      }
      String url = config[0];
      String user = config[1];
      String pass = config[2];

      var client = newClient(
        url,
        user: user,
        password: pass,
        adapter: RHttpAdapter(),
      );

      try {
        var files = await client.readDir('/');
        files = files
            .where((e) => e.name != null && e.name!.endsWith('.kongcomic'))
            .toList();
        // 按 (天数, 版本) 数值倒序取最新；纯字典序会在版本 ≥10 时取错。
        files.sort((a, b) => _compareSnapshots(b.name!, a.name!));
        var file = files.isEmpty ? null : files.first;
        if (file == null) {
          throw 'No data file found';
        }
        var version = file.name!
            .split('-')
            .elementAtOrNull(1)
            ?.split('.')
            .first;
        if (version != null && int.tryParse(version) != null) {
          var currentVersion = appdata.settings['dataVersion'];
          var local = currentVersion is num
              ? currentVersion.toInt()
              : int.tryParse(currentVersion.toString()) ?? 0;
          if (int.parse(version) <= local) {
            Log.info("Data Sync", 'No new data to download');
            return const Res(true);
          }
        }
        Log.info("Data Sync", "Downloading data from WebDAV server");
        var localFile = File(FilePath.join(App.cachePath, file.name!));
        try {
          await client.read2File(file.name!, localFile.path);
          _isImporting = true;
          try {
            // merge = true：把远端增量并进本机，而不是删掉本机 DB 整包替换
            // （旧实现会让「上次上传后本机新增的收藏/历史/图片收藏」全部丢失）。
            // syncAssets = true：合并之外仍同步允许跨设备的 settings、cookie、
            // 漫画源与自定义封面映射。版本判定只留上面按文件名做的这一处，
            // 不再让 importAppData 用包内 dataVersion 重复判一次。
            await importAppData(localFile, false, true, true);
          } finally {
            _isImporting = false;
            // 导入窗口内 mergeFrom / reload / syncData 产生的 notify 不该回传
            // （会把刚合并的快照立刻上传、dataVersion 虚涨，多设备互相乒乓）。
            // 窗口之外用户真实改动不会被清：uploadData 导出的是全量快照，
            // 下一次任意改动仍会把它带上云，不会永久丢数据。
            _pendingUpload = false;
          }
        } finally {
          await localFile.deleteIgnoreError();
        }
        Log.info("Data Sync", "Data downloaded and merged successfully");
        return const Res(true);
      } catch (e, s) {
        Log.error("Data Sync", e, s);
        _lastError = e.toString();
        return Res.error(e.toString());
      }
    } finally {
      _isDownloading = false;
      notifyListeners();
      _flushPending();
    }
  }
}
