import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kong_comic/foundation/history.dart';

import 'appdata.dart';
import 'favorites.dart';
import 'local.dart';
import 'log.dart';

export "widget_utils.dart";
export "context.dart";

class _App {
  final version = "1.6.4";
  final appVersion = "1.2.5";

  bool get isAndroid => Platform.isAndroid;

  bool get isIOS => Platform.isIOS;

  bool get isWindows => Platform.isWindows;

  bool get isLinux => Platform.isLinux;

  bool get isMacOS => Platform.isMacOS;

  bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool get isMobile => Platform.isAndroid || Platform.isIOS;

  // Whether the app has been initialized.
  // If current Isolate is main Isolate, this value is always true.
  bool isInitialized = false;

  Locale get locale {
    Locale deviceLocale = PlatformDispatcher.instance.locale;
    if (deviceLocale.languageCode == "zh" &&
        deviceLocale.scriptCode == "Hant") {
      deviceLocale = const Locale("zh", "TW");
    }
    if (appdata.settings['language'] != 'system') {
      return Locale(
        appdata.settings['language'].split('-')[0],
        appdata.settings['language'].split('-')[1],
      );
    }
    return deviceLocale;
  }

  late String dataPath;
  late String cachePath;
  String? externalStoragePath;

  final rootNavigatorKey = GlobalKey<NavigatorState>();

  GlobalKey<NavigatorState>? mainNavigatorKey;

  BuildContext get rootContext => rootNavigatorKey.currentContext!;

  final Appdata data = appdata;

  final HistoryManager history = HistoryManager();

  final LocalFavoritesManager favorites = LocalFavoritesManager();

  final LocalManager local = LocalManager();

  void rootPop() {
    rootNavigatorKey.currentState?.maybePop();
  }

  void pop() {
    if (rootNavigatorKey.currentState?.canPop() ?? false) {
      rootNavigatorKey.currentState?.pop();
    } else if (mainNavigatorKey?.currentState?.canPop() ?? false) {
      mainNavigatorKey?.currentState?.pop();
    }
  }

  Future<void> init() async {
    cachePath = (await getApplicationCacheDirectory()).path;
    dataPath = (await getApplicationSupportDirectory()).path;
    if (isAndroid) {
      externalStoragePath = (await getExternalStorageDirectory())!.path;
    }
    isInitialized = true;
  }

  Future<void> initComponents() async {
    await Future.wait([
      data.init(),
      history.init(),
      favorites.init(),
      local.init(),
    ]);
  }

  /// Returns the device's primary CPU ABI on Android (e.g. "arm64-v8a",
  /// "armeabi-v7a", "x86_64"). Returns null on other platforms.
  /// Reads through the `venera/method_channel` MethodChannel registered in
  /// MainActivity.kt.
  Future<String?> getDeviceAbi() async {
    if (!isAndroid) return null;
    try {
      const channel = MethodChannel("venera/method_channel");
      return await channel.invokeMethod<String>("getDeviceAbi");
    } catch (_) {
      return null;
    }
  }

  /// Ask the Android system to install the APK at [path]. The file is shared
  /// with the installer via a FileProvider configured in AndroidManifest.xml.
  /// Returns true if the install intent was dispatched; false on error.
  Future<bool> installApk(String path) async {
    if (!isAndroid) return false;
    try {
      const channel = MethodChannel("venera/method_channel");
      await channel.invokeMethod<void>("installApk", {"path": path});
      return true;
    } catch (e, s) {
      Log.error("installApk", e.toString(), s);
      return false;
    }
  }

  Function? _forceRebuildHandler;

  static VoidCallback? onLanguageChange;

  void registerForceRebuild(Function handler) {
    _forceRebuildHandler = handler;
  }

  void forceRebuild() {
    _forceRebuildHandler?.call();
    onLanguageChange?.call();
  }
}

// ignore: non_constant_identifier_names
final App = _App();
