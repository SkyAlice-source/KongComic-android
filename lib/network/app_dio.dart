import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/network/cache.dart';
import 'package:kong_comic/network/proxy.dart';
import 'package:kong_comic/utils/translations.dart';

import '../foundation/app.dart';
import 'cloudflare.dart';
import 'cookie_jar.dart';

export 'package:dio/dio.dart';

class MyLogInterceptor implements Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    Log.error("Network",
        "${err.requestOptions.method} ${err.requestOptions.path}\n$err\n${err.response?.data.toString()}");
    switch (err.type) {
      case DioExceptionType.badResponse:
        var statusCode = err.response?.statusCode;
        if (statusCode != null) {
          err = err.copyWith(
              message: "${"Invalid Status Code".tl}: $statusCode. "
                  "${_getStatusCodeInfo(statusCode)}");
        }
      case DioExceptionType.connectionTimeout:
        err = err.copyWith(message: "Connection Timeout".tl);
      case DioExceptionType.receiveTimeout:
        err = err.copyWith(
            message: "Receive Timeout: "
                "This indicates that the server is too busy to respond".tl);
      case DioExceptionType.unknown:
        if (err.toString().contains("Connection terminated during handshake")) {
          err = err.copyWith(
              message: "Connection terminated during handshake: "
                  "This may be caused by the firewall blocking the connection "
                  "or your requests are too frequent.".tl);
        } else if (err.toString().contains("Connection reset by peer")) {
          err = err.copyWith(
              message: "Connection reset by peer: "
                  "The error is unrelated to app, please check your network.".tl);
        }
      default:
        {}
    }
    handler.next(err);
  }

  String _getStatusCodeInfo(int? statusCode) {
    if (statusCode != null && statusCode >= 500) {
      return "This is server-side error, please try again later. "
          "Do not report this issue.".tl;
    } else {
      final messages = <int, String>{
        400: "The Request is invalid.".tl,
        401: "The Request is unauthorized.".tl,
        403: "No permission to access the resource. Check your account or network.".tl,
        404: "Not found.".tl,
        429: "Too many requests. Please try again later.".tl,
      };
      return messages[statusCode] ?? "";
    }
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    var headers = response.headers.map.map((key, value) => MapEntry(
        key.toLowerCase(), value.length == 1 ? value.first : value.toString()));
    headers.remove("cookie");
    String content;
    if (response.data is List<int>) {
      final dataLength = (response.data as List<int>).length;
      if (dataLength > 10240) {
        // Skip decoding for large binary responses (e.g. images).
        content = "<Bytes>\nlength:$dataLength";
      } else {
        try {
          content = utf8.decode(response.data as List<int>, allowMalformed: false);
        } catch (e) {
          content = "<Bytes>\nlength:$dataLength";
        }
      }
    } else {
      content = response.data.toString();
    }
    Log.addLog(
        (response.statusCode != null && response.statusCode! < 400)
            ? LogLevel.info
            : LogLevel.error,
        "Network",
        "Response ${response.realUri.toString()} ${response.statusCode}\n"
            "headers:\n$headers\n$content");
    handler.next(response);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    const String headerMask = "********";
    const String dataMask = "****** DATA_PROTECTED ******";
    Log.info(
        "Network",
        "${options.method} ${options.uri}\n"
            "headers:\n${
              options.extra.containsKey("maskHeadersInLog")
                ? options.headers.map((key, value) =>
                  MapEntry(
                    key,
                    options.extra["maskHeadersInLog"].contains(key)
                      ? headerMask
                      : value
                  ))
                : options.headers
            }\n"
            "data:\n${
              options.extra["maskDataInLog"] == true
                ? dataMask
                : options.data
            }"
    );
    options.connectTimeout = const Duration(seconds: 15);
    options.receiveTimeout = const Duration(seconds: 15);
    options.sendTimeout = const Duration(seconds: 15);
    handler.next(options);
  }
}

class AppDio with DioMixin {
  AppDio([BaseOptions? options]) {
    this.options = options ?? BaseOptions();
    httpClientAdapter = RHttpAdapter();
    if (App.isInitialized) {
      interceptors.add(CookieManagerSql(SingleInstanceCookieJar.instance!));
      interceptors.add(NetworkCacheManager());
      interceptors.add(CloudflareInterceptor());
      interceptors.add(MyLogInterceptor());
    }
  }

  static final Map<String, bool> _requests = {};

  @override
  Future<Response<T>> request<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    if (options?.headers?['prevent-parallel'] == 'true') {
      while (_requests.containsKey(path)) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      _requests[path] = true;
      options!.headers!.remove('prevent-parallel');
    }
    try {
      return super.request<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        options: options,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );
    } finally {
      if (_requests.containsKey(path)) {
        _requests.remove(path);
      }
    }
  }
}

class RHttpAdapter implements HttpClientAdapter {
  HttpClient? _client;
  String? _lastProxy;

  @override
  void close({bool force = false}) {
    _client?.close(force: force);
    _client = null;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future? cancelFuture,
  ) async {
    if (!options.headers.keys.any((e) => e.toLowerCase() == 'user-agent')) {
      options.headers['User-Agent'] = "kong_comic/v${App.version}";
    }

    final proxy = await getProxy();
    final uri = options.uri;

    // Reuse HttpClient for connection pooling.
    // Recreate only when proxy changes to avoid stale connections.
    if (_client == null || _lastProxy != proxy) {
      _client?.close();
      _client = HttpClient();
      _lastProxy = proxy;
      _client!.findProxy = (_) {
        if (proxy != null) return 'PROXY $proxy';
        return 'DIRECT';
      };
      _client!.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        return appdata.settings['ignoreBadCertificate'] == true;
      };
      _client!.connectionTimeout = const Duration(seconds: 15);
    }

    final request = await _client!.openUrl(options.method, uri);

    options.headers.forEach((key, value) {
      if (value != null) {
        request.headers.set(key, value.toString());
      }
    });

    if (requestStream != null) {
        await request.addStream(requestStream);
    }

    cancelFuture?.then((_) => request.abort());

    final response = await request.close();

    final headers = <String, List<String>>{};
    response.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values;
    });

    return ResponseBody(
      response.cast<Uint8List>(),
      response.statusCode,
      statusMessage: _getStatusMessage(response.statusCode),
      isRedirect: false,
      headers: headers,
    );
  }

  static String _getStatusMessage(int statusCode) {
    return switch (statusCode) {
      200 => 'OK',
      404 => 'Not Found',
      500 => 'Internal Server Error',
      _ => 'Unknown',
    };
  }
}
