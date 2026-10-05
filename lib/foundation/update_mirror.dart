import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/network/proxy.dart';

/// User agent used for update downloads.
///
/// Some public GitHub mirrors reject non-browser clients outright (one of the
/// built-in presets answers `403` to Dart's default `Dart/x.y (dart:io)`
/// agent but serves normally to a browser string), so every request made by
/// the update pipeline identifies itself like a mobile browser.
const String kUpdateUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

/// A download route for the update APK.
///
/// [template] must contain `{url}`, which is replaced by the original GitHub
/// release asset URL. Keeping it declarative means adding a mirror is a single
/// line, and users can point the app at a self-hosted accelerator (typically a
/// Cloudflare Worker) without touching code.
class UpdateMirror {
  const UpdateMirror({
    required this.id,
    required this.name,
    required this.template,
    this.inRotation = true,
  });

  final String id;

  /// Display name. Mirror host names are proper nouns — intentionally not run
  /// through `.tl`, which would translate-an-lock them at first launch.
  final String name;

  final String template;

  /// Whether [UpdateMirrorPreference.rotation] considers this route in
  /// automatic mode.
  final bool inRotation;

  String apply(String url) => template.replaceFirst('{url}', url);

  @override
  String toString() => 'UpdateMirror($id)';
}

/// Result of a cheap reachability check against one mirror.
class MirrorProbeResult {
  const MirrorProbeResult({
    required this.mirror,
    required this.ok,
    required this.latency,
    this.error,
    this.supportsRange = false,
    this.size,
  });

  final UpdateMirror mirror;
  final bool ok;
  final Duration latency;

  /// Human readable failure reason when [ok] is false.
  final String? error;

  /// Whether the endpoint answers HTTP Range requests with `206`. A mirror
  /// that ignores Range must be downloaded as a single stream, otherwise the
  /// parallel-chunk downloader would write several copies of the whole file
  /// at different offsets.
  final bool supportsRange;

  /// Total asset size reported through `Content-Range`, when available.
  final int? size;
}

/// Built-in routes. Every entry except [UpdateMirrors.direct] is a public
/// GitHub proxy that serves exactly the bytes GitHub does; the downloaded APK
/// is still verified against the SHA-256 published with the release, so a
/// broken or hostile mirror can only ever fail the update, never poison it.
class UpdateMirrors {
  static const UpdateMirror direct = UpdateMirror(
    id: 'direct',
    name: 'GitHub',
    template: '{url}',
  );

  static const UpdateMirror ghfast = UpdateMirror(
    id: 'ghfast',
    name: 'ghfast.top',
    template: 'https://ghfast.top/{url}',
  );

  static const UpdateMirror ghProxy = UpdateMirror(
    id: 'ghproxy_com',
    name: 'gh-proxy.com',
    template: 'https://gh-proxy.com/{url}',
  );

  static const UpdateMirror ghProxyNet = UpdateMirror(
    id: 'ghproxy_net',
    name: 'ghproxy.net',
    template: 'https://ghproxy.net/{url}',
  );

  static const UpdateMirror h233 = UpdateMirror(
    id: 'h233',
    name: 'gh.h233.eu.org',
    template: 'https://gh.h233.eu.org/{url}',
  );

  /// Every known route, in fallback order.
  static const List<UpdateMirror> all = [
    direct,
    ghfast,
    ghProxy,
    ghProxyNet,
    h233,
  ];

  static UpdateMirror? byId(String id) {
    for (final mirror in all) {
      if (mirror.id == id) return mirror;
    }
    return null;
  }
}

/// Default mirror template offered when a user switches to the custom route.
const String kDefaultMirrorTemplate = 'https://ghfast.top/{url}';

/// Persisted mirror preference.
///
/// `updateMirror` holds `'auto'`, `'custom'`, or one of the [UpdateMirrors]
/// ids. In `auto` mode every usable route is tried in order — last successful
/// mirror first, then the official GitHub link, then the public mirrors — so a
/// user whose network blocks GitHub still gets their update, and a user with a
/// healthy connection keeps downloading straight from the source.
class UpdateMirrorPreference {
  static const String _keyMode = 'updateMirror';
  static const String _keyTemplate = 'updateMirrorTemplate';
  static const String _keyLastGood = 'updateMirrorLastGood';

  static String get mode {
    final raw = appdata.settings[_keyMode];
    if (raw is! String || raw.isEmpty) return 'auto';
    return raw;
  }

  static set mode(String value) {
    appdata.settings[_keyMode] = value;
    appdata.saveData();
  }

  static String get template {
    final raw = appdata.settings[_keyTemplate];
    if (raw is! String || raw.trim().isEmpty) return kDefaultMirrorTemplate;
    return raw.trim();
  }

  static set template(String value) {
    appdata.settings[_keyTemplate] = value.trim();
    appdata.saveData();
  }

  /// Id of the route that completed an update most recently, or null.
  static String? get lastGood {
    final raw = appdata.settings[_keyLastGood];
    if (raw is! String || raw.isEmpty) return null;
    return raw;
  }

  static set lastGood(String? value) {
    appdata.settings[_keyLastGood] = value ?? '';
    appdata.saveData();
  }

  /// Remember [id] as the route that worked so it is tried first next time.
  static void markWorking(String id) {
    if (lastGood == id) return;
    lastGood = id;
  }

  /// The user configured route, if any. Null in `auto` mode.
  static UpdateMirror? forced() {
    final current = mode;
    if (current == 'auto') return null;
    if (current == 'custom') {
      final custom = _custom();
      // An unusable template would silently disable every download, so fall
      // back to the official route and let auto rotation take over.
      if (custom == null) return UpdateMirrors.direct;
      return custom;
    }
    return UpdateMirrors.byId(current) ?? UpdateMirrors.direct;
  }

  static UpdateMirror? _custom() {
    final value = template;
    if (!value.contains('{url}')) return null;
    final uri = Uri.tryParse(value.replaceFirst('{url}', ''));
    if (uri == null || uri.host.isEmpty) return null;
    if (!['http', 'https'].contains(uri.scheme)) return null;
    return UpdateMirror(id: 'custom', name: _hostOf(value), template: value);
  }

  static String _hostOf(String template) {
    final uri = Uri.tryParse(template);
    return uri == null || uri.host.isEmpty ? 'Custom' : uri.host;
  }

  /// Routes to try, in order, for the next download.
  static List<UpdateMirror> rotation() {
    final pinned = forced();
    if (pinned != null) return [pinned];

    final order = <UpdateMirror>[];
    void add(UpdateMirror m) {
      if (!order.any((e) => e.id == m.id)) order.add(m);
    }

    final remembered = lastGood;
    if (remembered != null) {
      final m = UpdateMirrors.byId(remembered);
      // Only a *built-in* route may be remembered: a custom template can point
      // anywhere and must stay an explicit user choice.
      if (m != null) add(m);
    }
    for (final m in UpdateMirrors.all) {
      if (m.inRotation) add(m);
    }
    return order;
  }

  /// Routes offered in the settings picker.
  static List<UpdateMirror> selectable() => [
    UpdateMirrors.direct,
    ...UpdateMirrors.all.where((m) => m.id != UpdateMirrors.direct.id),
  ];
}

/// Build the headers used for update traffic.
Map<String, dynamic> updateRequestHeaders({String? range}) {
  return {
    'Accept': '*/*',
    'Accept-Encoding': 'deflate, gzip',
    'User-Agent': kUpdateUserAgent,
    if (range != null) 'Range': range,
  };
}

Dio _probeDio(Duration timeout) {
  final dio = Dio()
    ..options.connectTimeout = timeout
    ..options.receiveTimeout = timeout
    ..options.sendTimeout = timeout
    ..options.followRedirects = true
    ..options.maxRedirects = 5;
  return dio;
}

Future<void> _attachProxy(Dio dio) async {
  try {
    final proxy = await getProxy();
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        configureProxy(client, proxy);
        return client;
      },
    );
  } catch (e) {
    // No proxy support is better than no download attempt at all.
    Log.error("UpdateMirror", "Failed to configure proxy: $e", null);
  }
}

/// Ask [mirror] for the first kilobyte of [assetUrl] and report whether it is
/// usable, how fast it answered, and whether it honors HTTP Range requests.
///
/// Probing is deliberately cheap (1 KiB). It turns a dead mirror from a
/// multi-minute failure into a couple of seconds of waiting, which is what
/// makes rotating through several routes practical.
Future<MirrorProbeResult> probeMirror(
  UpdateMirror mirror,
  String assetUrl, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final stopwatch = Stopwatch()..start();
  final url = mirror.apply(assetUrl);
  final dio = _probeDio(timeout);
  await _attachProxy(dio);

  StreamSubscription<List<int>>? sub;
  final done = Completer<void>();
  final buffer = BytesBuilder();
  String? networkError;

  MirrorProbeResult fail(String reason) {
    stopwatch.stop();
    return MirrorProbeResult(
      mirror: mirror,
      ok: false,
      latency: stopwatch.elapsed,
      error: reason,
    );
  }

  try {
    final res = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: updateRequestHeaders(range: 'bytes=0-1023'),
        // gh-proxy style services answer 403 for blocked agents; keep those out
        // of Dio's exception path so the reason is readable.
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final status = res.statusCode ?? 0;
    if (status != 200 && status != 206) {
      return fail("HTTP $status");
    }
    final size = _totalFromContentRange(
      res.headers.value('content-range'),
    );

    final stream = res.data?.stream;
    if (stream == null) {
      stopwatch.stop();
      return MirrorProbeResult(
        mirror: mirror,
        ok: true,
        latency: stopwatch.elapsed,
        supportsRange: status == 206,
        size: size,
      );
    }

    sub = stream.listen(
      (chunk) {
        buffer.add(chunk);
        if (buffer.length >= 1024 && !done.isCompleted) done.complete();
      },
      onError: (Object e) {
        if (!done.isCompleted) {
          networkError = e.toString();
          done.complete();
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );

    await done.future.timeout(
      timeout,
      onTimeout: () {
        networkError = "Read timed out";
      },
    );
    await sub.cancel();
    stopwatch.stop();

    if (networkError != null && buffer.isEmpty) {
      return fail(networkError!);
    }
    return MirrorProbeResult(
      mirror: mirror,
      ok: true,
      latency: stopwatch.elapsed,
      supportsRange: status == 206,
      size: size,
    );
  } catch (e) {
    await sub?.cancel();
    return fail(e.toString());
  }
}

/// Parse the total size out of a `Content-Range: bytes 0-1023/18377524`
/// header. Returns null when absent or unparsable.
int? _totalFromContentRange(String? value) {
  if (value == null) return null;
  final match = RegExp(r'/\s*(\d+)\s*$').firstMatch(value);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// Probe every route that would be used for the next download and report them
/// in the same order as [UpdateMirrorPreference.rotation].
Future<List<MirrorProbeResult>> probeAllMirrors(
  String assetUrl, {
  List<UpdateMirror>? mirrors,
}) async {
  final list = mirrors ?? UpdateMirrorPreference.rotation();
  // Run them side by side: the point of this screen is "which route works for
  // me", and doing it serially would take as long as the failures do.
  return Future.wait(list.map((m) => probeMirror(m, assetUrl)));
}
