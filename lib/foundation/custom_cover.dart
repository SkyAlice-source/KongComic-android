import 'dart:io';
import 'dart:typed_data';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:path/path.dart' as p;

/// 自定义封面管理
///
/// 用户可为漫画手动替换本地封面图。
/// 数据存储在 appdata.implicitData["customCovers"] 中，
/// 图片文件复制到 {App.dataPath}/covers/ 目录下。
class CustomCoverManager {
  static const _key = 'customCovers';

  /// 封面存储目录
  static String get _coversDir => p.join(App.dataPath, 'covers');

  /// 获取所有自定义封面映射（sourceKey@id → 本地文件路径）
  static Map<String, String> _getAll() {
    final data = appdata.implicitData[_key];
    if (data is Map) {
      return Map<String, String>.from(data.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ));
    }
    return {};
  }

  /// 获取某部漫画的自定义封面路径，没有则返回 null
  static String? getCustomCoverPath(String sourceKey, String id) {
    final key = '$sourceKey@$id';
    return _getAll()[key];
  }

  /// 设置自定义封面（复制图片到应用目录并保存映射）
  static Future<bool> setCustomCover(String sourceKey, String id, String sourcePath) async {
    try {
      final dir = Directory(_coversDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final ext = p.extension(sourcePath).toLowerCase();
      final destPath = p.join(_coversDir, '${sourceKey}_$id$ext');

      // 复制文件到应用目录（保持持久性）
      await File(sourcePath).copy(destPath);

      final key = '$sourceKey@$id';
      final covers = _getAll();
      covers[key] = destPath;
      appdata.implicitData[_key] = covers;
      appdata.writeImplicitData();
      App.forceRebuild();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 设置自定义封面（从图片字节数据）
  static Future<bool> setCustomCoverFromData(String sourceKey, String id, Uint8List data) async {
    try {
      final dir = Directory(_coversDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 检测图片格式
      String ext = '.jpg';
      if (data.length >= 4) {
        if (data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) {
          ext = '.png';
        } else if (data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46) {
          ext = '.webp';
        }
      }

      final destPath = p.join(_coversDir, '${sourceKey}_$id$ext');
      await File(destPath).writeAsBytes(data);

      final key = '$sourceKey@$id';
      final covers = _getAll();
      // 删除旧封面文件（如果扩展名变了）
      final oldPath = covers[key];
      if (oldPath != null && oldPath != destPath) {
        try { await File(oldPath).delete(); } catch (_) {}
      }
      covers[key] = destPath;
      appdata.implicitData[_key] = covers;
      appdata.writeImplicitData();
      App.forceRebuild();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 移除自定义封面，恢复为源封面
  static Future<void> removeCustomCover(String sourceKey, String id) async {
    final key = '$sourceKey@$id';
    final covers = _getAll();
    final oldPath = covers.remove(key);
    if (oldPath != null) {
      try {
        await File(oldPath).delete();
      } catch (_) {}
    }
    appdata.implicitData[_key] = covers;
    appdata.writeImplicitData();
    App.forceRebuild();
  }

  /// 检查某部漫画是否有自定义封面
  static bool hasCustomCover(String sourceKey, String id) {
    final key = '$sourceKey@$id';
    return _getAll().containsKey(key);
  }
}
