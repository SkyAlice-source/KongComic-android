import 'dart:io';

import 'package:path/path.dart' as p;

/// 纯 `dart:io` 的递归复制：把 [from] 目录里的**内容**复制到 [to]，返回实际
/// 复制成功的文件数。
///
/// 为什么不用项目里的 `_copyWithStrategy`（带 SAF 兼容层的那套）：
/// - 兼容层在目标写不进去时会**静默跳过**（`AndroidFile.fromPathSync` 返回
///   null 就 `?.writeAsBytesSync` 什么也不做），调用方只看「有没有抛异常」，
///   会把「目录建好、文件一个没进去」当成成功，随后清空源目录 —— 数据直接丢。
/// - 这里每复制一个文件都走 `copySync`，失败就抛异常；返回值再配合
///   [findMissingFiles] 做二次校验，不给静默失败留口子。
///
/// 只在源和目标**都能表示成普通文件系统路径**时使用（SAF 树请先折算成
/// `/storage/emulated/0/...`）。[overwrite] 为 false 时，目标已存在的同名
/// 文件会被跳过而不是覆盖 —— 搬旧目录时不该把用户新下载的内容顶掉。
int copyDirectoryContentsSync(
  String from,
  String to, {
  bool overwrite = false,
}) {
  var copied = 0;
  for (final entity in Directory(from).listSync(recursive: false)) {
    final target = p.join(to, p.basename(entity.path));
    if (entity is File) {
      final file = File(target);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      if (file.existsSync()) {
        if (!overwrite) continue;
        file.deleteSync();
      }
      entity.copySync(target);
      copied++;
    } else if (entity is Directory) {
      final dir = Directory(target);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      copied += copyDirectoryContentsSync(
        entity.path,
        target,
        overwrite: overwrite,
      );
    }
  }
  return copied;
}

/// 复制后校验：返回 [from] 里**没能**在 [to] 下找到副本的相对路径。
///
/// 不能用「这次写了几个」判成败：`overwrite == false` 时目标已存在的同名
/// 文件是**跳过**的（刻意不覆盖用户新下载的内容），跳过不等于失败。真正要
/// 回答的问题是「每个文件在目标里有没有一份」，所以按相对路径逐个核对 ——
/// 空列表才算复制完整。
List<String> findMissingFiles(String from, String to) {
  final missing = <String>[];

  void walk(Directory src, String rel) {
    for (final entity in src.listSync(recursive: false)) {
      final name = p.basename(entity.path);
      final relPath = rel.isEmpty ? name : p.join(rel, name);
      if (entity is Directory) {
        walk(entity, relPath);
      } else if (entity is File) {
        if (!File(p.join(to, relPath)).existsSync()) {
          missing.add(relPath);
        }
      }
    }
  }

  walk(Directory(from), "");
  return missing;
}

/// [from] 下的文件总数（递归）。给无法逐文件校验的目标（SAF 树）兜底：
/// 源里有文件、目标一个都没写进去，就绝不能把「没抛异常」当成功。
int countFilesSync(String from) {
  var count = 0;
  for (final entity in Directory(from).listSync(recursive: false)) {
    if (entity is File) {
      count++;
    } else if (entity is Directory) {
      count += countFilesSync(entity.path);
    }
  }
  return count;
}
