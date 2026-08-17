import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kong_comic/foundation/history.dart';

import 'package:package_info_plus/package_info_plus.dart';

import 'appdata.dart';
import 'favorites.dart';
import 'local.dart';
import 'log.dart';

export "widget_utils.dart";
export "context.dart";

/// 动画工具：尊重系统「减少动态效果」无障碍设置。
/// 开启时主要动画时长归零（不播放），避免动画引发不适。
class AppAnimations {
  static bool reduceMotion = false;

  /// 返回动画时长；系统开启「减少动态效果」时归零。
  static Duration duration(Duration d) => reduceMotion ? Duration.zero : d;

  /// 初始化：读取系统无障碍设置（需在 WidgetsBinding 初始化后调用）。
  static void init() {
    reduceMotion =
        WidgetsBinding.instance.accessibilityFeatures.disableAnimations;
  }
}

class _App {
  final version = "1.6.4";
  // Populated from package_info_plus during [init] so the About page and the
  // update check always reflect the real build version (no manual bump needed).
  String appVersion = "1.2.40";

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

  BuildContext get rootContext {
    final context = rootNavigatorKey.currentContext;
    assert(context != null,
        'rootContext accessed before the root navigator is mounted');
    return context!;
  }

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
    // Ensure the binding exists before registering the memory-pressure
    // observer (this runs before runApp in some entry paths).
    WidgetsFlutterBinding.ensureInitialized();
    WidgetsBinding.instance.addObserver(_ImageCacheMemoryObserver());
    cachePath = (await getApplicationCacheDirectory()).path;
    dataPath = (await getApplicationSupportDirectory()).path;
    if (isAndroid) {
      externalStoragePath = (await getExternalStorageDirectory())!.path;
    }
    // Reflect the real build version in [appVersion] (About page + update check).
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
    } catch (_) {
      // Keep the compile-time default if PackageInfo is unavailable.
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

// Evicts decoded images when the OS reports memory pressure. Comic covers and
// reader pages are large bitmaps; without this, low-RAM devices can be killed
// by the system (OOM) while scrolling long lists or chapters.
class _ImageCacheMemoryObserver extends WidgetsBindingObserver {
  @override
  void didHaveMemoryPressure() {
    PaintingBinding.instance.imageCache.clear();
    Log.info(
      "ImageCache",
      "Cleared decoded image cache due to system memory pressure",
    );
  }
}

// ignore: non_constant_identifier_names
final App = _App();
