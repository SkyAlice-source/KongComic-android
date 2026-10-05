import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:flutter_saf/flutter_saf.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/utils/ext.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart' as s;
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:kong_comic/utils/file_type.dart';
import 'package:kong_comic/utils/translations.dart';

export 'dart:io';
export 'dart:typed_data';

class IO {
  /// A global flag used to indicate whether the app is selecting files.
  ///
  /// Select file and other similar file operations will launch external programs,
  /// causing the app to lose focus. AppLifecycleState will be set to paused.
  static bool get isSelectingFiles => _isSelectingFiles;

  static bool _isSelectingFiles = false;
}

class FilePath {
  const FilePath._();

  static String join(String path1, String path2,
      [String? path3, String? path4, String? path5]) {
    return p.join(path1, path2, path3, path4, path5);
  }
}

extension FileSystemEntityExt on FileSystemEntity {
  /// Get the base name of the file or directory.
  String get name {
    return p.basename(path);
  }

  /// Delete the file or directory and ignore errors.
  Future<void> deleteIgnoreError({bool recursive = false}) async {
    try {
      await delete(recursive: recursive);
    } catch (e) {
      // ignore
    }
  }

  /// Delete the file or directory if it exists.
  Future<void> deleteIfExists({bool recursive = false}) async {
    if (existsSync()) {
      await delete(recursive: recursive);
    }
  }

  /// Delete the file or directory if it exists.
  void deleteIfExistsSync({bool recursive = false}) {
    if (existsSync()) {
      deleteSync(recursive: recursive);
    }
  }
}

extension FileExtension on File {
  /// Get the file extension, not including the dot.
  String get extension => path.split('.').last;

  /// Copy the file to the specified path using memory.
  ///
  /// This method prevents errors caused by files from different file systems.
  Future<void> copyMem(String newPath) async {
    var newFile = File(newPath);
    // Stream is not usable since [AndroidFile] does not support [openRead].
    await newFile.writeAsBytes(await readAsBytes());
  }

  /// Get the base name of the file without the extension.
  String get basenameWithoutExt {
    return p.basenameWithoutExtension(path);
  }
}

extension DirectoryExtension on Directory {
  /// Calculate the size of the directory.
  Future<int> get size async {
    if (!existsSync()) return 0;
    int total = 0;
    for (var f in listSync(recursive: true)) {
      if (FileSystemEntity.typeSync(f.path) == FileSystemEntityType.file) {
        total += await File(f.path).length();
      }
    }
    return total;
  }

  /// Change the base name of the directory.
  Directory renameX(String newName) {
    newName = sanitizeFileName(newName);
    return renameSync(path.replaceLast(name, newName));
  }

  File joinFile(String name) {
    return File(FilePath.join(path, name));
  }

  /// Delete the contents of the directory.
  void deleteContentsSync({recursive = true}) {
    if (!existsSync()) return;
    for (var f in listSync()) {
      f.deleteIfExistsSync(recursive: recursive);
    }
  }

  /// Delete the contents of the directory.
  Future<void> deleteContents({recursive = true}) async {
    if (!existsSync()) return;
    for (var f in listSync()) {
      await f.deleteIfExists(recursive: recursive);
    }
  }

  /// Create the directory. If the directory already exists, delete it first.
  void forceCreateSync() {
    if (existsSync()) {
      deleteSync(recursive: true);
    }
    createSync(recursive: true);
  }
}

/// Sanitize the file name. Remove invalid characters and trim the file name.
String sanitizeFileName(String fileName, {String? dir, int? maxLength}) {
  while (fileName.endsWith('.')) {
    fileName = fileName.substring(0, fileName.length - 1);
  }
  var length = maxLength ?? 255;
  if (dir != null) {
    if (!dir.endsWith('/') && !dir.endsWith('\\')) {
      dir = "$dir/";
    }
    length -= dir.length;
  }
  final invalidChars = RegExp(r'[<>:"/\\|?*]');
  final sanitizedFileName = fileName.replaceAll(invalidChars, ' ');
  var trimmedFileName = sanitizedFileName.trim();
  if (trimmedFileName.isEmpty) {
    throw Exception('Invalid File Name: Empty length.');
  }
  if (length <= 0) {
    throw Exception('Invalid File Name: Max length is less than 0.');
  }
  if (trimmedFileName.length > length) {
    trimmedFileName = trimmedFileName.substring(0, length);
  }
  return trimmedFileName;
}

/// Copy the **contents** of the source directory to the destination directory.
Future<void> copyDirectory(Directory source, Directory destination) async {
  List<FileSystemEntity> contents = source.listSync();
  for (FileSystemEntity content in contents) {
    String newPath = FilePath.join(destination.path, content.name);

    if (content is File) {
      var resultFile = File(newPath);
      resultFile.createSync();
      var data = content.readAsBytesSync();
      resultFile.writeAsBytesSync(data);
    } else if (content is Directory) {
      Directory newDirectory = Directory(newPath);
      newDirectory.createSync();
      copyDirectory(content.absolute, newDirectory.absolute);
    }
  }
}

/// Copy the **contents** of the source directory to the destination directory.
/// This function is executed in an isolate to prevent the UI from freezing.
Future<void> copyDirectoryIsolate(
    Directory source, Directory destination) async {
  await Isolate.run(() => overrideIO(() => copyDirectory(source, destination)));
}



String findValidDirectoryName(String path, String directory) {
  var name = sanitizeFileName(directory);
  var dir = Directory("$path/$name");
  var i = 1;
  while (dir.existsSync() && dir.listSync().isNotEmpty) {
    name = sanitizeFileName("$directory($i)");
    dir = Directory("$path/$name");
    i++;
  }
  return name;
}

class DirectoryPicker {
  /// Pick a directory.
  ///
  /// The directory may not be usable after the instance is GCed.
  DirectoryPicker();

  static final _finalizer = Finalizer<String>((path) {
    if (path.startsWith(App.cachePath)) {
      Directory(path).deleteIgnoreError();
    }
    if (App.isIOS || App.isMacOS) {
      _methodChannel.invokeMethod("stopAccessingSecurityScopedResource");
    }
  });

  static const _methodChannel = MethodChannel("kong_comic/method_channel");

  Future<Directory?> pickDirectory({bool directAccess = false}) async {
    IO._isSelectingFiles = true;
    try {
      String? directory;
      if (App.isWindows || App.isLinux) {
        directory = await file_selector.getDirectoryPath();
      } else if (App.isAndroid) {
        directory = (await AndroidDirectory.pickDirectory())?.path;
        if (directory != null && directAccess) {
          // Native library does not have access to the directory. Copy it to cache.
          var cache = FilePath.join(App.cachePath, "selected_directory");
          if (Directory(cache).existsSync()) {
            Directory(cache).deleteSync(recursive: true);
          }
          Directory(cache).createSync();
          await copyDirectoryIsolate(Directory(directory), Directory(cache));
          directory = cache;
        }
      } else {
        // ios, macos
        directory =
            await _methodChannel.invokeMethod<String?>("getDirectoryPath");
      }
      if (directory == null) return null;
      _finalizer.attach(this, directory);
      return Directory(directory);
    } finally {
      Future.delayed(const Duration(milliseconds: 100), () {
        IO._isSelectingFiles = false;
      });
    }
  }
}

class IOSDirectoryPicker {
  static const MethodChannel _channel = MethodChannel("kong_comic/method_channel");

  // 调用 iOS 目录选择方法
  static Future<String?> selectDirectory() async {
    IO._isSelectingFiles = true;
    try {
      final String? path = await _channel.invokeMethod('selectDirectory');
      return path;
    } catch (e) {
      // 返回报错信息
      return e.toString();
    } finally {
      Future.delayed(const Duration(milliseconds: 100), () {
        IO._isSelectingFiles = false;
      });
    }
  }
}

Future<FileSelectResult?> selectFile({required List<String> ext}) async {
  IO._isSelectingFiles = true;
  try {
    var extensions = App.isMacOS || App.isIOS ? null : ext;
    file_selector.XTypeGroup typeGroup = file_selector.XTypeGroup(
      label: 'files',
      extensions: extensions,
    );
    FileSelectResult? file;
    if (App.isAndroid) {
      const selectFileChannel = MethodChannel("kong_comic/select_file");
      String mimeType = "*/*";
      if (ext.length == 1) {
        mimeType = FileType.fromExtension(ext[0]).mime;
        if (mimeType == "application/octet-stream") {
          mimeType = "*/*";
        }
      }
      var filePath = await selectFileChannel.invokeMethod(
        "selectFile",
        mimeType,
      );
      if (filePath == null) return null;
      file = FileSelectResult(filePath);
    } else {
      var xFile = await file_selector.openFile(
        acceptedTypeGroups: <file_selector.XTypeGroup>[typeGroup],
      );
      if (xFile == null) return null;
      file = FileSelectResult(xFile.path);
    }
    if (!ext.any((e) => file!.path.toLowerCase().endsWith(".$e"))) {
      App.rootContext.showMessage(
        message: "${"Invalid file type".tl}: ${file.path.split(".").last}",
      );
      return null;
    }
    return file;
  } finally {
    Future.delayed(const Duration(milliseconds: 100), () {
      IO._isSelectingFiles = false;
    });
  }
}

Future<String?> selectDirectory() async {
  IO._isSelectingFiles = true;
  try {
    var path = await file_selector.getDirectoryPath();
    return path;
  } finally {
    Future.delayed(const Duration(milliseconds: 100), () {
      IO._isSelectingFiles = false;
    });
  }
}

// selectDirectoryIOS
Future<String?> selectDirectoryIOS() async {
  return IOSDirectoryPicker.selectDirectory();
}

Future<void> saveFile(
    {Uint8List? data, required String filename, File? file}) async {
  if (data == null && file == null) {
    throw Exception("data and file cannot be null at the same time");
  }
  IO._isSelectingFiles = true;
  try {
    if (data != null) {
      var cache = FilePath.join(App.cachePath, filename);
      if (File(cache).existsSync()) {
        File(cache).deleteSync();
      }
      await File(cache).writeAsBytes(data);
      file = File(cache);
    }
    if (App.isMobile) {
      final params = SaveFileDialogParams(sourceFilePath: file!.path);
      await FlutterFileDialog.saveFile(params: params);
    } else {
      final result = await file_selector.getSaveLocation(
        suggestedName: filename,
      );
      if (result != null) {
        var xFile = file_selector.XFile(file!.path);
        await xFile.saveTo(result.path);
      }
    }
  } finally {
    Future.delayed(const Duration(milliseconds: 100), () {
      IO._isSelectingFiles = false;
    });
  }
}

final class _IOOverrides extends IOOverrides {
  @override
  Directory createDirectory(String path) {
    if (App.isAndroid) {
      var dir = AndroidDirectory.fromPathSync(path);
      if (dir == null) {
        return super.createDirectory(path);
      }
      return dir;
    } else {
      return super.createDirectory(path);
    }
  }

  @override
  File createFile(String path) {
    if (path.startsWith("file://")) {
      path = path.substring(7);
    }
    if (App.isAndroid) {
      var f = AndroidFile.fromPathSync(path);
      if (f == null) {
        return super.createFile(path);
      }
      return f;
    } else {
      return super.createFile(path);
    }
  }
}

T overrideIO<T>(T Function() f) {
  return IOOverrides.runWithIOOverrides<T>(
    f,
    _IOOverrides(),
  );
}

/// 把漫画名等用户可控文本转成安全的文件名。
///
/// 漫画名里出现 `/`、`:` 之类的字符很常见，直接拼进路径会让写文件抛异常，
/// 分享/保存整段失败；过长还会撞上文件系统的 255 字节单段名限制。
String safeShareFileName(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'^\.+'), '')
      .trim();
  if (cleaned.isEmpty) return 'image';
  return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
}

/// 一张待分享的图片：原始字节 + 文件名 + mime。
class ShareImageData {
  final Uint8List data;

  /// 带扩展名的文件名，例如 `海贼王_EP3_P12.png`。
  final String filename;

  final String mime;

  const ShareImageData({
    required this.data,
    required this.filename,
    required this.mime,
  });
}

class Share {
  /// 接收方（微信 / QQ / 相册等）普遍直接认得的图片格式。
  ///
  /// 其余格式（AVIF / HEIC / JXL…）即便 mime 标对了，接收方也常当成「文件」
  /// 处理，所以分享前先重编码为 PNG。
  static const _kWidelySupportedImageMimes = {
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
  };

  /// 把任意 Flutter 能解码的图片重新编码成 PNG；解码失败返回 null。
  static Future<Uint8List?> transcodeToPng(Uint8List data) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  /// 分享一组图片：必要时先转成 PNG，再一次性交给系统分享面板。
  ///
  /// 关键是给每个 [s.XFile] 显式带上 mimeType —— share_plus 只有在 XFile
  /// 没有 mime 时才按文件名猜，猜不到就退化成 `application/octet-stream`，
  /// 接收方会把图片显示成「文件」（这正是之前「分享不是图片」的原因）。
  static Future<void> shareImages(List<ShareImageData> images) async {
    final files = <s.XFile>[];
    for (final image in images) {
      var data = image.data;
      var filename = image.filename;
      var mime = image.mime;
      if (!_kWidelySupportedImageMimes.contains(mime)) {
        final png = await transcodeToPng(data);
        if (png != null) {
          data = png;
          filename = '${_withoutExtension(filename)}.png';
          mime = 'image/png';
        } else if (!mime.startsWith('image/')) {
          // 既不是可直接分享的格式，又无法解码成图片：跳过，
          // 避免把一段没法看的字节当成图片分享出去。
          continue;
        }
      }
      files.add(s.XFile.fromData(data, name: filename, mimeType: mime));
    }
    if (files.isEmpty) return;
    await s.SharePlus.instance.share(s.ShareParams(files: files));
  }

  static String _withoutExtension(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot > 0 ? filename.substring(0, dot) : filename;
  }

  static Future<void> shareFile({
    required Uint8List data,
    required String filename,
    String? mime,
  }) async {
    await shareImages([
      ShareImageData(
        data: data,
        filename: filename,
        mime: mime ?? detectFileType(data, nameHint: filename).mime,
      ),
    ]);
  }

  static Future<void> shareText(String text) async {
    await s.SharePlus.instance.share(s.ShareParams(text: text));
  }

  /// Share multiple files at once (e.g. all pages of a chapter).
  ///
  /// [mimeTypes] 与 [paths] 一一对应（可选）；缺失时会按文件内容推断。
  static Future<void> shareFiles({
    required List<String> paths,
    List<String>? mimeTypes,
  }) async {
    final payloads = <ShareImageData>[];
    for (var i = 0; i < paths.length; i++) {
      try {
        final path = paths[i];
        final data = await File(path).readAsBytes();
        final name = path.split(Platform.pathSeparator).last;
        final declared = (mimeTypes != null &&
                i < mimeTypes.length &&
                mimeTypes[i].isNotEmpty)
            ? mimeTypes[i]
            : null;
        payloads.add(ShareImageData(
          data: data,
          filename: name,
          mime: declared ?? detectFileType(data, nameHint: name).mime,
        ));
      } catch (_) {
        // 单个文件读失败不影响其余图片
      }
    }
    await shareImages(payloads);
  }
}

/// Compares two strings using "natural" ordering: runs of digits are compared
/// by their numeric value instead of character by character.
///
/// Plain string sorting puts `page_10` before `page_2`, which breaks reading
/// order for imported/downloaded chapters. With natural ordering
/// `page_2 < page_10`, and pure numeric names (`1.jpg`, `10.jpg`) still work.
int compareNatural(String a, String b) {
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);
    final aDigit = ca >= 48 && ca <= 57;
    final bDigit = cb >= 48 && cb <= 57;
    if (aDigit && bDigit) {
      final startA = i;
      final startB = j;
      var na = 0;
      var nb = 0;
      // Guard against overflow: fall back to length-then-lexicographic for
      // digit runs longer than what int can hold.
      final lenA = _digitRunLength(a, i);
      final lenB = _digitRunLength(b, j);
      final fits = lenA <= 18 && lenB <= 18;
      while (i < a.length && _isDigit(a.codeUnitAt(i))) {
        if (fits) na = na * 10 + (a.codeUnitAt(i) - 48);
        i++;
      }
      while (j < b.length && _isDigit(b.codeUnitAt(j))) {
        if (fits) nb = nb * 10 + (b.codeUnitAt(j) - 48);
        j++;
      }
      if (na != nb && fits) return na.compareTo(nb);
      // Same value but different padding ("007" vs "7") or overflowed:
      // shorter run first, then plain comparison for a stable order.
      if (lenA != lenB) return lenA.compareTo(lenB);
      if (!fits) {
        final cmp = a.substring(startA, i).compareTo(b.substring(startB, j));
        if (cmp != 0) return cmp;
      }
    } else {
      if (ca != cb) return ca.compareTo(cb);
      i++;
      j++;
    }
  }
  return (a.length - i).compareTo(b.length - j);
}

bool _isDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

int _digitRunLength(String s, int start) {
  var n = 0;
  while (start + n < s.length && _isDigit(s.codeUnitAt(start + n))) {
    n++;
  }
  return n;
}

String bytesToReadableString(int bytes) {
  if (bytes < 1024) {
    return "$bytes B";
  } else if (bytes < 1024 * 1024) {
    return "${(bytes / 1024).toStringAsFixed(2)} KB";
  } else if (bytes < 1024 * 1024 * 1024) {
    return "${(bytes / 1024 / 1024).toStringAsFixed(2)} MB";
  } else {
    return "${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB";
  }
}

class FileSelectResult {
  final String path;

  static final _finalizer = Finalizer<String>((path) {
    if (path.startsWith(App.cachePath)) {
      File(path).deleteIgnoreError();
    }
  });

  FileSelectResult(this.path) {
    _finalizer.attach(this, path);
  }

  Future<void> saveTo(String path) async {
    await File(this.path).copy(path);
  }

  Future<Uint8List> readAsBytes() {
    return File(path).readAsBytes();
  }

  String get name => File(path).name;
}