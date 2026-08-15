import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import '../foundation/app.dart';

extension AppTranslation on String {
  String _translate() {
    var locale = App.locale;
    var key = "${locale.languageCode}_${locale.countryCode}";
    if (locale.languageCode == "en") {
      key = "en_US";
    }
    return (translations[key]?[this]) ?? this;
  }

  String get tl => _translate();

  String get tlEN => translations["en_US"]![this] ?? this;

  String tlParams(Map<String, Object> values) {
    var res = _translate();
    for (var entry in values.entries) {
      res = res.replaceFirst("@${entry.key}", entry.value.toString());
    }
    return res;
  }

  static late final Map<String, Map<String, String>> translations;

  static Future<void> init() async {
    var data = await rootBundle.load("assets/translation.json");
    var json = jsonDecode(utf8.decode(data.buffer.asUint8List()));
    translations = {
      for (var e in json.entries) e.key: Map<String, String>.from(e.value)
    };
  }

  /// Translate a string using specified comic source
  String ts(String sourceKey) {
    var comicSource = ComicSource.find(sourceKey);
    if (comicSource == null || comicSource.translations == null) {
      return this;
    }
    var locale = App.locale;
    var lc = locale.languageCode;
    var cc = locale.countryCode;
    var key = "$lc${cc == null ? "" : "_$cc"}";
    return (comicSource.translations![key] ??
            comicSource.translations![lc])?[this] ??
        this;
  }
}

extension ListTranslation on List<String> {
  List<String> _translate() {
    return List.generate(length, (index) => this[index].tl);
  }

  List<String> get tl => _translate();
}

/// 把异常转成用户可读的友好消息。
/// 业务异常（throw String，多为已翻译文案）原样返回；
/// 已知的技术性英文异常映射为友好中文提示；
/// 其他技术异常（Exception/Error 对象）显示通用提示，避免英文技术信息直出。
String friendlyError(Object e) {
  if (e is String) {
    // 图片/内容加载相关的底层技术异常 → 友好提示
    if (e.contains("Empty response body") ||
        e.contains("Empty file") ||
        e.contains("No ImageFavoritesEp") ||
        e.contains("Invalid data")) {
      return "Failed to load image".tl;
    }
    if (e.contains("Comic source not found")) {
      return "Comic source not found".tl;
    }
    return e;
  }
  return "Unknown error".tl;
}
