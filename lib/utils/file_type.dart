import 'package:mime/mime.dart';

class FileType {
  /// 带前导点的扩展名，例如 `.jpg`。
  final String ext;

  final String mime;

  const FileType(this.ext, this.mime);

  static FileType fromExtension(String ext) {
    if (ext.startsWith('.')) {
      ext = ext.substring(1);
    }
    if (ext.isEmpty) {
      return const FileType('', 'application/octet-stream');
    }
    var mime = lookupMimeType('no-file.$ext') ?? 'application/octet-stream';
    // Android doesn't support some mime types
    mime = switch (mime) {
      'text/javascript' => 'application/octet-stream',
      'application/x-cbr' => 'application/octet-stream',
      _ => mime,
    };
    return FileType(".$ext", mime);
  }
}

final _resolver = MimeTypeResolver()
  // zip
  ..addMagicNumber([0x50, 0x4B], 'application/zip')
  // 7z
  ..addMagicNumber([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C], 'application/x-7z-compressed')
  // rar
  ..addMagicNumber([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07], 'application/vnd.rar')
;

/// `mime` 包的扩展名表缺少部分格式（或给出无法用于分享的扩展名），这里补齐。
const _kExtOverrides = <String, String>{
  'image/jpeg': 'jpg',
  'image/avif': 'avif',
  'image/heic': 'heic',
  'image/heif': 'heif',
  'image/x-icon': 'ico',
};

/// ISO-BMFF（HEIF 家族）的 brand → 文件类型。
///
/// AVIF / HEIC 的头部是 `size(4) + "ftyp" + brand(4)`，其中 size 随文件而变，
/// `mime` 包那套固定 magic 表匹配不到 —— 这正是漫画图被判成
/// `application/octet-stream`、文件名丢掉扩展名、分享出去变成「文件」的根因。
const _kFtypBrands = <String, FileType>{
  'avif': FileType('.avif', 'image/avif'),
  'avis': FileType('.avif', 'image/avif'),
  'av01': FileType('.avif', 'image/avif'),
  'heic': FileType('.heic', 'image/heic'),
  'heix': FileType('.heic', 'image/heic'),
  'hevc': FileType('.heic', 'image/heic'),
  'hevx': FileType('.heic', 'image/heic'),
  'mif1': FileType('.heif', 'image/heif'),
  'msf1': FileType('.heif', 'image/heif'),
};

bool _startsWith(List<int> data, List<int> signature) {
  if (data.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (data[i] != signature[i]) return false;
  }
  return true;
}

bool _matchesAt(List<int> data, int offset, String ascii) {
  if (data.length < offset + ascii.length) return false;
  for (var i = 0; i < ascii.length; i++) {
    if (data[offset + i] != ascii.codeUnitAt(i)) return false;
  }
  return true;
}

/// 手写头部嗅探，覆盖 `mime` 包默认 magic 表漏掉的常见图片格式。
FileType? _sniffImageHeader(List<int> data) {
  if (_startsWith(data, [0xFF, 0xD8, 0xFF])) {
    return const FileType('.jpg', 'image/jpeg');
  }
  if (_startsWith(data, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return const FileType('.png', 'image/png');
  }
  if (_startsWith(data, [0x47, 0x49, 0x46, 0x38])) {
    return const FileType('.gif', 'image/gif');
  }
  if (data.length >= 12 &&
      _matchesAt(data, 0, 'RIFF') &&
      _matchesAt(data, 8, 'WEBP')) {
    return const FileType('.webp', 'image/webp');
  }
  if (_startsWith(data, [0x42, 0x4D])) {
    return const FileType('.bmp', 'image/bmp');
  }
  if (_startsWith(data, [0x49, 0x49, 0x2A, 0x00]) ||
      _startsWith(data, [0x4D, 0x4D, 0x00, 0x2A])) {
    return const FileType('.tiff', 'image/tiff');
  }
  if (_startsWith(data, [0x00, 0x00, 0x01, 0x00])) {
    return const FileType('.ico', 'image/x-icon');
  }
  // JPEG XL：裸码流 0xFF0A，或容器 `\x00\x00\x00\x0CJXL `
  if (_startsWith(data, [0xFF, 0x0A])) {
    return const FileType('.jxl', 'image/jxl');
  }
  if (_matchesAt(data, 4, 'JXL ')) {
    return const FileType('.jxl', 'image/jxl');
  }
  // ISO-BMFF：`ftyp` box 里的 major / compatible brand
  if (_matchesAt(data, 4, 'ftyp')) {
    for (var offset = 8; offset + 4 <= data.length && offset < 40; offset += 4) {
      final brand = String.fromCharCodes(data.sublist(offset, offset + 4));
      final type = _kFtypBrands[brand];
      if (type != null) return type;
    }
  }
  return null;
}

/// 从文件名 / URL 猜类型。部分 CDN 会在 URL 上写真实格式，比 magic 更好用。
FileType? _fromNameHint(String hint) {
  var name = hint;
  final query = name.indexOf('?');
  if (query >= 0) name = name.substring(0, query);
  final hash = name.indexOf('#');
  if (hash >= 0) name = name.substring(0, hash);
  final slash = name.lastIndexOf('/');
  if (slash >= 0) name = name.substring(slash + 1);
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  final ext = name.substring(dot + 1).toLowerCase();
  if (!RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext)) return null;
  final mime = lookupMimeType('no-file.$ext');
  if (mime == null || mime == 'application/octet-stream') return null;
  return FileType('.$ext', mime);
}

/// 判断字节内容对应的文件类型。
///
/// [nameHint] 是可选的文件名或 URL，仅在前两种方式都失败时作为兜底 ——
/// 有些源的图片没有可识别头部，但 URL 上的扩展名是可信的。
///
/// 无论识别结果如何，返回的 [FileType.ext] 都尽量不为空：调用方普遍按
/// `name + ext` 命名文件，空的扩展名会让分享出去的文件变成无名「文件」。
FileType detectFileType(List<int> data, {String? nameHint}) {
  final mime = _resolver.lookup('no-file', headerBytes: data);
  if (mime != null && mime != 'application/octet-stream') {
    var ext = extensionFromMime(mime) ?? _kExtOverrides[mime];
    if (ext == 'jpe') ext = 'jpg';
    if (ext != null && ext.isNotEmpty) return FileType('.$ext', mime);
    final override = _kExtOverrides[mime];
    if (override != null) return FileType('.$override', mime);
  }
  final sniffed = _sniffImageHeader(data);
  if (sniffed != null) return sniffed;
  if (nameHint != null) {
    final fromName = _fromNameHint(nameHint);
    if (fromName != null) return fromName;
  }
  return const FileType('.bin', 'application/octet-stream');
}
