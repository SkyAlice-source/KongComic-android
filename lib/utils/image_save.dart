import 'dart:isolate';

import 'package:image/image.dart' as img;

import 'file_type.dart';
import 'io.dart';

/// 保存图片时可选的输出格式。
enum ImageSaveFormat {
  /// 保持原图格式（不做任何转码，质量零损失，速度最快）。
  original,

  /// 转成 PNG：无损、保留透明通道，但文件通常比 JPG 大。
  png,

  /// 转成 JPG：有损（quality 可调）、体积小、兼容性最好，透明区域会铺白底。
  jpg,
}

extension ImageSaveFormatLabel on ImageSaveFormat {
  String get label => switch (this) {
        ImageSaveFormat.original => 'Original',
        ImageSaveFormat.png => 'PNG',
        ImageSaveFormat.jpg => 'JPG',
      };

  /// 该格式对应的扩展名（自带前导点）。
  ///
  /// `original` 没有固定扩展名（取决于原图），返回空串，由调用方用嗅探结果补齐。
  String get ext => switch (this) {
        ImageSaveFormat.original => '',
        ImageSaveFormat.png => '.png',
        ImageSaveFormat.jpg => '.jpg',
      };

  String get description => switch (this) {
        ImageSaveFormat.original => 'Keep the original format',
        ImageSaveFormat.png => 'Lossless, keeps transparency',
        ImageSaveFormat.jpg => 'Smaller file, best compatibility',
      };
}

/// 生成「漫画名_EP{话数}_P{页码}」形式的保存文件名（**不含扩展名**）。
///
/// 例：`海贼王_EP3_P12`。漫画名会过一遍 [safeShareFileName]，把 `/`、`:` 一类
/// 不能进文件名的字符换成 `_`，并截断到安全长度，避免写盘直接失败。
///
/// - [ep] 为话序号（1-based），传 `null` 时省略话数段（如本地漫画没有话的概念）。
/// - [page] 为页码（1-based），与阅读器右下角显示的页码一致。
String buildImageSaveName({
  required String comicTitle,
  required int page,
  int? ep,
}) {
  final title = comicTitle.trim().isEmpty ? 'image' : comicTitle.trim();
  final parts = <String>[safeShareFileName(title)];
  if (ep != null) {
    parts.add('EP$ep');
  }
  parts.add('P$page');
  return parts.join('_');
}

/// 嗅探原图的扩展名（含前导点，如 `.webp`）。
///
/// 保存对话框里「原格式」选项要靠它把最终文件名显示完整，否则用户只能看到
/// 文件名却不知道会存成什么后缀。[nameHint] 传入图片 URL 作为兜底：极少数
/// 图片没有可识别的文件头，但 URL 上的扩展名可信。
String detectImageExt(Uint8List data, {String? nameHint}) =>
    detectFileType(data, nameHint: nameHint).ext;

/// 转换结果：可直接写盘的字节 + 对应文件类型（含扩展名 / MIME）。
class ImageSaveResult {
  const ImageSaveResult(this.data, this.type, {this.converted = false});

  final Uint8List data;
  final FileType type;

  /// 是否真的发生了转码（false 表示按原格式输出，含解码失败后的回退）。
  final bool converted;
}

/// 把 [data] 转成 [format] 指定的格式，供「保存图片」使用。
///
/// - [ImageSaveFormat.original]：原样返回，并用 [nameHint] 嗅探真实类型。
/// - PNG / JPG：在后台 isolate 里解码再重新编码，避免阻塞 UI。
/// - 解码失败（AVIF / HEIC / JXL 等 `image` 包不支持的格式）时会**回退成原格式**，
///   保证图片仍能存下来，而不是弹个错误什么也拿不到。
Future<ImageSaveResult> prepareImageForSave(
  Uint8List data,
  ImageSaveFormat format, {
  String? nameHint,
  int jpegQuality = 92,
}) async {
  final originalType = detectFileType(data, nameHint: nameHint);
  if (format == ImageSaveFormat.original) {
    return ImageSaveResult(data, originalType);
  }

  try {
    final bytes = await Isolate.run(
      () => _reencode(data, format, jpegQuality),
    );
    return ImageSaveResult(
      bytes,
      format == ImageSaveFormat.png
          ? const FileType('.png', 'image/png')
          : const FileType('.jpg', 'image/jpeg'),
      converted: true,
    );
  } catch (_) {
    return ImageSaveResult(data, originalType);
  }
}

Uint8List _reencode(
  Uint8List data,
  ImageSaveFormat format,
  int quality,
) {
  final decoded = img.decodeImage(data);
  if (decoded == null) {
    throw const FormatException('Unsupported image format');
  }
  if (format == ImageSaveFormat.png) {
    return Uint8List.fromList(img.encodePng(decoded, level: 6));
  }
  // JPEG 没有 alpha 通道：先铺白底再编码，否则半透明像素会被压成黑色。
  final source = decoded.numChannels == 4
      ? img.compositeImage(
          img.fill(
            img.Image(
              width: decoded.width,
              height: decoded.height,
              numChannels: 3,
            ),
            color: img.ColorRgb8(255, 255, 255),
          ),
          decoded,
        )
      : decoded;
  return Uint8List.fromList(img.encodeJpg(source, quality: quality));
}
