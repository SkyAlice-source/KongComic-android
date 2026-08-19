import 'dart:io';

import 'package:flutter/services.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/utils/ext.dart';

String? _cachedProxy;

DateTime? _cachedProxyTime;

Future<String?> getProxy() async {
  if (_cachedProxyTime != null &&
      DateTime.now().difference(_cachedProxyTime!).inSeconds < 1) {
    return _cachedProxy;
  }
  String? proxy = await _getProxy();
  _cachedProxy = proxy;
  _cachedProxyTime = DateTime.now();
  return proxy;
}

Future<String?> _getProxy() async {
  if ((appdata.settings['proxy'] as String).removeAllBlank == "direct") {
    return null;
  }
  if (appdata.settings['proxy'] != "system") return appdata.settings['proxy'];

  String res;
  if (!App.isLinux) {
    const channel = MethodChannel("kong_comic/method_channel");
    try {
      res = await channel.invokeMethod("getProxy");
    } catch (e) {
      return null;
    }
  } else {
    res = "No Proxy";
  }
  if (res == "No Proxy") return null;

  if (res.contains(";")) {
    var proxies = res.split(";");
    for (String proxy in proxies) {
      proxy = proxy.removeAllBlank;
      if (proxy.startsWith('https=')) {
        return proxy.substring(6);
      }
    }
  }

  final RegExp regex = RegExp(
    r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+$',
    caseSensitive: false,
    multiLine: false,
  );
  if (!regex.hasMatch(res)) {
    return null;
  }

  return res;
}

/// 解析代理字符串（可能带 `username:password@` 认证前缀），分离出 host:port 与
/// 认证信息。Dart HttpClient 的 findProxy 只接受 `PROXY host:port`，不支持内嵌
/// 认证，需单独通过 authenticateProxy + addProxyCredentials 处理。
({String host, String? username, String? password}) _parseProxyAuth(String proxy) {
  var hostPort = proxy;
  String? username;
  String? password;
  final at = proxy.lastIndexOf('@');
  if (at != -1) {
    final auth = proxy.substring(0, at);
    hostPort = proxy.substring(at + 1);
    final colon = auth.indexOf(':');
    if (colon != -1) {
      username = auth.substring(0, colon);
      password = auth.substring(colon + 1);
    } else {
      username = auth;
    }
  }
  return (host: hostPort, username: username, password: password);
}

/// 给 [client] 配置代理（含认证）。proxy 为 null 表示直连。
///
/// manual 代理可能带 `username:password@host:port` 认证前缀，findProxy 只返回
/// `PROXY host:port`，认证通过 authenticateProxy + addProxyCredentials 注入。
void configureProxy(HttpClient client, String? proxy) {
  if (proxy == null || proxy.isEmpty) {
    client.findProxy = (_) => 'DIRECT';
    return;
  }
  final parsed = _parseProxyAuth(proxy);
  client.findProxy = (_) => 'PROXY ${parsed.host}';
  if (parsed.username != null) {
    client.authenticateProxy = (host, port, scheme, realm) async {
      client.addProxyCredentials(
        host,
        port,
        realm ?? '',
        HttpClientBasicCredentials(parsed.username!, parsed.password ?? ''),
      );
      return true;
    };
  }
}
