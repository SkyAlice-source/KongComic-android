import 'package:kong_comic/foundation/comic_source/comic_source.dart';

class ComicType {
  final int value;

  const ComicType(this.value);

  @override
  bool operator ==(Object other) => other is ComicType && other.value == value;

  @override
  int get hashCode => value.hashCode;

  String get sourceKey {
    if (this == local) {
      return "local";
    }
    // 源被卸载 / 脚本损坏时 comicSource 为 null。以前这里直接 `!`，
    // 任何「源没了但库里还有记录」的路径（本地漫画、历史、收藏）都会崩；
    // 与 History.sourceKey 保持同一套兜底文案。
    return comicSource?.key ?? "Unknown:$value";
  }

  ComicSource? get comicSource {
    if (this == local) {
      return null;
    } else {
      return ComicSource.fromIntKey(value);
    }
  }

  static const local = ComicType(0);

  factory ComicType.fromKey(String key) {
    if (key == "local") {
      return local;
    } else {
      return ComicType(key.hashCode);
    }
  }
}
