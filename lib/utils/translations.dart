import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/log.dart';
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

  String get tlEN => translations["en_US"]?[this] ?? this;

  String tlParams(Map<String, Object> values) {
    var res = _translate();
    for (var entry in values.entries) {
      res = res.replaceFirst("@${entry.key}", entry.value.toString());
    }
    return res;
  }

  /// Never `late`: the table has to be readable even when loading it failed.
  /// A `late` field that never gets assigned turns every single `.tl` into a
  /// `LateInitializationError`, and the first one happens while `MaterialApp`
  /// is being built — before the custom `ErrorWidget.builder` is installed, so
  /// the user is left staring at the default grey screen with no way out.
  /// An empty table degrades to the source strings (English) instead.
  static Map<String, Map<String, String>> translations = {};

  static Future<void> init() async {
    try {
      var data = await rootBundle.load("assets/translation.json");
      var json = jsonDecode(utf8.decode(data.buffer.asUint8List()));
      translations = {
        for (var e in json.entries)
          e.key: Map<String, String>.fromEntries(
            (e.value as Map).entries
                .where((entry) => entry.value is String)
                .map((entry) =>
                    MapEntry(entry.key.toString(), entry.value as String)),
          ),
      };
    } catch (e, s) {
      // One malformed entry used to abort the whole table (a value written as
      // an object instead of a string is enough). Skip bad entries rather than
      // losing every translation, and never leave the table unassigned.
      translations = {};
      Log.error("Translation", "Failed to load translations: $e\n$s");
    }
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

/// 判断错误是否由「未登录 / 未授权」引起。
///
/// 用于把漫画源返回的英文错误（如 "Not logged in" / "unauthorized" /
/// HTTP 401）替换为本地化的「需登录」提示，并在存在漫画源上下文时
/// 提供「去登录」入口。
bool isAuthError(String message) {
  final m = message.toLowerCase();
  return m.contains('not logged') ||
      m.contains('please log in') ||
      m.contains('please login') ||
      m.contains('login required') ||
      m.contains('log in required') ||
      m.contains('sign in') ||
      m.contains('signin') ||
      m.contains('unauthorized') ||
      m.contains('not authorized') ||
      m.contains('authorization failed') ||
      m.contains('auth failed') ||
      m.contains('login failed') ||
      m.contains('log in failed') ||
      m.contains('login error') ||
      m.contains('access denied') ||
      m.contains('access_denied') ||
      m.contains('forbidden') ||
      m.contains('token expired') ||
      m.contains('session expired') ||
      m.contains('login expired') ||
      m.contains('invalid token') ||
      m.contains('invalid credentials') ||
      m.contains('logged out') ||
      m.contains('401') ||
      m.contains('403') ||
      m.contains('未登录') ||
      m.contains('请登录') ||
      m.contains('需要登录') ||
      m.contains('需登录') ||
      m.contains('登陆') ||
      m.contains('登录已过期') ||
      m.contains('登录失效') ||
      m.contains('会话过期') ||
      m.contains('登录');
}

final RegExp _localizedTextRe = RegExp(r'[\u4e00-\u9fff\u3040-\u30ff]');

/// 文本里是否已有中文 / 日文等本地化内容（有就不必再改写）。
bool _hasLocalizedText(String s) => _localizedTextRe.hasMatch(s);

String _friendlyHttpStatus(int? code) {
  if (code == null) return "Network Error".tl;
  if (code >= 500) {
    return "This is server-side error, please try again later. Do not report this issue."
        .tl;
  }
  final messages = <int, String>{
    400: "The Request is invalid.".tl,
    401: "The Request is unauthorized.".tl,
    402: "Payment required.".tl,
    403: "No permission to access the resource. Check your account or network.".tl,
    404: "Not found.".tl,
    405: "Method not allowed.".tl,
    406: "Not acceptable.".tl,
    408: "Request timeout.".tl,
    409: "Conflict.".tl,
    410: "The resource has been removed.".tl,
    429: "Too many requests. Please try again later.".tl,
  };
  return messages[code] ??
      "Server returned @code".tlParams({"code": code.toString()});
}

/// 把来源不明的错误文本归一化成用户能读懂的本地化文案。
///
/// 漫画源 JS、Dio、dart:io 抛出的错误绝大多数是英文技术串，例如
/// `Exception: Invalid status code: 502`、
/// `SocketException: Failed host lookup: 'xxx' (OS Error: ...)`。
/// 原先 SnackBar / 收藏页 / 评论区走 [friendlyError]，对 String 直接
/// `return e`，中文界面里就会整条冒出英文；[NetworkError] 另有自己的一份
/// 映射，两套逻辑彼此独立。这里统一成一份，两处共用。
///
/// 兜底策略：仍无法识别的英文串统一显示「未知错误」，原文只进日志，
/// 保证界面不再出现技术性英文；已经是中文的文案原样返回。
String friendlyErrorMessage(String raw) {
  var msg = raw.trim();
  if (msg.isEmpty) return "Unknown error".tl;

  // 剥掉技术前缀，只留下人类可读部分。
  msg = msg
      .replaceFirst(RegExp(r'^DioException\s*\[[^\]]*\]:\s*'), '')
      .replaceFirst(RegExp(r'^Error:\s*'), '')
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceFirst(RegExp(r'^SocketException:\s*'), '')
      .replaceFirst(RegExp(r'^ClientException with\s*'), '')
      .trim();
  if (msg.isEmpty) return "Unknown error".tl;

  if (isAuthError(msg)) {
    return "Login required".tl;
  }

  // 统一处理 "Invalid Status Code: 410" / "Invalid status code: 410"
  final invalidStatusMatch = RegExp(
    r'Invalid\s+[Ss]tatus\s+[Cc]ode:?\s*(\d{3})',
  ).firstMatch(msg);
  if (invalidStatusMatch != null) {
    final code = int.tryParse(invalidStatusMatch.group(1)!);
    return _friendlyHttpStatus(code);
  }

  if (msg.contains('Connection reset by peer') ||
      msg.contains('连接被重置') ||
      msg.contains('Connection reset')) {
    return "Connection reset".tl;
  }
  if (msg.contains('timed out') ||
      msg.contains('Timeout') ||
      msg.contains('超时')) {
    return "Connection timed out".tl;
  }
  if (msg.contains('Connection terminated during handshake') ||
      msg.contains('handshake')) {
    return "Connection handshake failed".tl;
  }
  if (msg.contains('No route to host') ||
      msg.contains('No address associated with hostname') ||
      msg.contains('Bad address') ||
      msg.contains('Failed host lookup') ||
      msg.contains('Unable to resolve host')) {
    return "Unable to connect server".tl;
  }
  if (msg.contains('Connection refused')) {
    return "Connection refused".tl;
  }
  // 源里抛出的 `Not login` / `未登录` / `请先登录`。之前没有映射，中文界面里
  // 会显示成「未知错误」，用户完全不知道是自己没登录。（不区分大小写，
  // 源作者写法五花八门。）
  if (RegExp(r'not\s*log(?:in|ged)|unlogged|login\s*required|please\s*log\s*in',
          caseSensitive: false)
      .hasMatch(msg)) {
    return "Login required".tl;
  }
  if (msg.contains('Failed to fetch') ||
      msg.contains('NetworkError') ||
      msg.contains('Network Error')) {
    return "Network Error".tl;
  }
  if (msg.contains('HTTP')) {
    final status = RegExp(r'HTTP[^\s]*\s+(\d{3})').firstMatch(msg);
    if (status != null) {
      final code = int.tryParse(status.group(1)!);
      return _friendlyHttpStatus(code);
    }
  }
  // 源解析返回空对象导致的 JS 属性访问错误（如 CopyManga loadInfo null）
  if (msg.contains("cannot read property") ||
      msg.contains("Cannot read properties") ||
      msg.contains("undefined is not an object") ||
      msg.contains("null is not an object") ||
      msg.contains("TypeError")) {
    final sourceMatch = RegExp(r'\(([^:]+):\d+:\d+\)').firstMatch(msg);
    final sourceName = sourceMatch?.group(1) ?? "Source";
    return "@source: Source returned empty data, the comic may have been removed or the source is temporarily unavailable."
        .tlParams({"source": sourceName});
  }
  // 服务器错误（5xx）兜底：源 JS 抛出的错误未必带 "HTTP" 字样，
  // 用 word-boundary 匹配裸状态码，避免误伤漫画名/章节里的数字。
  final low = msg.toLowerCase();
  final serverError = RegExp(r'\b(?:500|502|503|504)\b').firstMatch(low);
  if (serverError != null ||
      low.contains('bad gateway') ||
      low.contains('service unavailable') ||
      low.contains('internal server error') ||
      low.contains('server error')) {
    return "This is server-side error, please try again later. Do not report this issue."
        .tl;
  }
  if (low.contains('failed to fetch') ||
      low.contains('xmlhttprequest') ||
      low.contains('http request failed') ||
      low.contains('failed to load resource')) {
    return "Network Error".tl;
  }
  if (low.contains('unable to resolve host') ||
      low.contains('name or service not known') ||
      low.contains('no such host') ||
      low.contains('dns')) {
    return "Unable to connect server".tl;
  }
  // 连接被中途掐断：本机代理、运营商拦截、源站主动断开都会出现，
  // Android 上典型文案是 "Connection closed before full header was received"。
  if (low.contains('connection closed') ||
      low.contains('connection terminated') ||
      low.contains('connection aborted') ||
      low.contains('connection error') ||
      low.contains('broken pipe') ||
      low.contains('epipe')) {
    return "Network Error".tl;
  }
  if (low.contains('certificate') ||
      low.contains('ssl') ||
      low.contains('tls')) {
    return "SSL connection error".tl;
  }
  // 源返回的内容不是合法 JSON / 解析失败 —— 多半是源站改版或被拦截。
  if (low.contains('formatexception') ||
      low.contains('unexpected character') ||
      low.contains('unexpected end of input') ||
      low.contains('is not valid json') ||
      low.contains('invalid json')) {
    return "This is server-side error, please try again later. Do not report this issue."
        .tl;
  }

  // 兜底：中文原文直接展示；仍是英文技术串则退化为通用提示，
  // 原文写日志供排查，避免中文界面里冒出整条英文异常。
  if (_hasLocalizedText(msg)) return msg;
  Log.info("Error", "Unmapped error text: $raw");
  return "Unknown error".tl;
}

/// 判断一次失败是否值得重试。
///
/// 之前 [LoadingState] 对任何失败都固定重试 3 次（每次 200ms），断网时四次
/// 15s 超时叠加，用户要盯着骨架屏等一分钟才看到「无法连接服务器」；而 DNS
/// 解析失败、证书错误这类硬失败重试一百次也不会成功。
///
/// 只对「可能自愈」的类型重试：超时、连接被重置/中断、5xx、429、源站繁忙。
/// 判定刻意偏保守 —— 宁可少重试，也不要让失败反馈被无限推迟。
bool isRetryableError(String? raw) {
  if (raw == null) return false;
  final msg = raw.trim().toLowerCase();
  if (msg.isEmpty) return false;

  // 1) 硬失败：域名解析不了 / 没有路由 / 证书或握手失败 / 连接被拒绝。
  //    这些重试纯属浪费用户时间（也覆盖已本地化后的中文文案）。
  const permanent = [
    'failed host lookup',
    'no address associated',
    'unable to resolve host',
    'name or service not known',
    'no such host',
    'no route to host',
    'certificate',
    'handshake',
    'connection refused',
    'cannot read propert',
    'undefined is not an object',
    'null is not an object',
    'typeerror',
    '无法连接服务器',
    '证书',
    '连接被拒绝',
  ];
  for (final k in permanent) {
    if (msg.contains(k)) return false;
  }

  // 2) 可自愈：超时、连接被掐断、限流、源站 5xx。
  const transient = [
    'timeout',
    'timed out',
    '超时',
    'reset by peer',
    '连接被重置',
    'connection closed',
    'connection terminated',
    'connection aborted',
    'connection reset',
    'broken pipe',
    'epipe',
    'temporarily',
    'too many requests',
    'bad gateway',
    'service unavailable',
    'server-side error',
    'server error',
    '服务器端错误',
  ];
  for (final k in transient) {
    if (msg.contains(k)) return true;
  }

  // 3) 裸状态码：5xx 与 408 / 429 可重试，其余 4xx 属客户端问题，重试无用。
  final code = RegExp(r'(?:status\s*code|http[^\s]*)\s*[:：]?\s*(\d{3})')
      .firstMatch(msg);
  if (code != null) {
    final c = int.tryParse(code.group(1)!);
    if (c != null) return c >= 500 || c == 408 || c == 429;
  }

  return false;
}

/// 把异常转成用户可读的友好消息。
///
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
    // 图片 / 本地文件读取失败：image_provider 各实现抛的都是
    // "Error: Empty image URL." / "Error: Cover not found." 这类英文。
    if (e.contains("Empty image URL") ||
        e.contains("not found.") ||
        e.contains("Invalid onResponse result")) {
      return "Failed to load image".tl;
    }
    // 其余交给统一的归一化函数：英文技术串不会再原样冒到界面上。
    return friendlyErrorMessage(e);
  }
  // Exception / Error / DioException 等对象：先取 toString 再走同一份映射。
  // 以前这里一律返回「未知错误」，把 `Exception: Invalid status code: 502`
  // 这类本来能识别的原因也一起丢掉了。
  final text = e.toString().trim();
  if (text.isEmpty || text == 'null') return "Unknown error".tl;
  return friendlyErrorMessage(text);
}
