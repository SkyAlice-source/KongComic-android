import 'dart:async';

import 'package:display_mode/display_mode.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_saf/flutter_saf.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/cache_manager.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/js_engine.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/network/cookie_jar.dart';
import 'package:kong_comic/pages/comic_source_page.dart';
import 'package:kong_comic/pages/follow_updates_page.dart';
import 'package:kong_comic/pages/settings/settings_page.dart';
import 'package:kong_comic/utils/app_links.dart';
import 'package:kong_comic/utils/handle_text_share.dart';
import 'package:kong_comic/utils/opencc.dart';
import 'package:kong_comic/utils/tags_translation.dart';
import 'package:kong_comic/utils/translations.dart';
import 'foundation/appdata.dart';
import 'package:kong_comic/utils/auto_backup.dart';
import 'package:kong_comic/utils/notifications.dart';

Timer? _heartbeatTimer;

void cancelHeartbeatTimer() {
  _heartbeatTimer?.cancel();
  _heartbeatTimer = null;
}

extension _FutureInit<T> on Future<T> {
  /// Prevent unhandled exception
  ///
  /// A unhandled exception occurred in init() will cause the app to crash.
  Future<void> wait() async {
    try {
      await this;
    } catch (e, s) {
      Log.error("init", "$e\n$s");
    }
  }
}

Future<void> init() async {
  // Set up error handling first, before any async work
  FlutterError.onError = (details) {
    Log.error("Unhandled Exception", "${details.exception}\n${details.stack}");
  };

  // Critical path - must complete before UI renders
  await App.init().wait();
  await SingleInstanceCookieJar.createInstance();
  try {
    var criticalFutures = [
      App.initComponents(),
      AppTranslation.init().wait(),
      JsEngine().init().wait(),
      ComicSourceManager().init().wait(),
    ];
    if (App.isAndroid) {
      // SAF is needed early on Android for file access
      criticalFutures.add(SAFTaskWorker().init().wait());
    }
    await Future.wait(criticalFutures);
  } catch (e, s) {
    Log.error("init", "$e\n$s");
  }
  CacheManager().setLimitSize(appdata.settings['cacheSize']);
  _checkOldConfigs();
  await initAutoBackup().wait();
  await AppNotifications.init().wait();
  DownloadNotifier.start();

  // Non-critical path - schedule to run after the UI is rendered
  _scheduleDeferredInit();
}

/// Deferred initialization: runs after the first frame so the UI appears faster.
void _scheduleDeferredInit() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future(() async {
      try {
        var deferredFutures = [
          TagsTranslation.readData().wait(),
          OpenCC.init(),
        ];
        await Future.wait(deferredFutures);
      } catch (e, s) {
        Log.error("deferred init", "$e\n$s");
      }

      if (App.isAndroid) {
        handleLinks();
        handleTextShare();
        try {
          await FlutterDisplayMode.setHighRefreshRate();
        } catch (e) {
          Log.error("Display Mode", "Failed to set high refresh rate: $e");
        }
      }
      if (App.isWindows) {
        // Report to the monitor thread that the app is running
        // https://github.com/venera-app/venera/issues/343
        _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          const methodChannel = MethodChannel('kong_comic/method_channel');
          methodChannel.invokeMethod("heartBeat");
        });
      }
    });
  });
}

void _checkOldConfigs() {
  if (appdata.settings['searchSources'] == null) {
    appdata.settings['searchSources'] = ComicSource.enabled()
        .where((e) => e.searchPageData != null)
        .map((e) => e.key)
        .toList();
  }

  if (appdata.implicitData['webdavAutoSync'] == null) {
    var webdavConfig = appdata.settings['webdav'];
    if (webdavConfig is List &&
        webdavConfig.length == 3 &&
        webdavConfig.whereType<String>().length == 3) {
      appdata.implicitData['webdavAutoSync'] = true;
    } else {
      appdata.implicitData['webdavAutoSync'] = false;
    }
    appdata.writeImplicitData();
  }

  if (appdata.settings['comicSourceListUrl'].toString().contains("git.nyne.dev")) {
    // migrate to jsdelivr cdn
    appdata.settings['comicSourceListUrl'] = "https://cdn.jsdelivr.net/gh/SkyAlice-source/venera-configs@main/index.json";
    appdata.saveData();
  }
}

Future<void> _checkAppUpdates() async {
  var lastCheck = appdata.implicitData['lastCheckUpdate'] ?? 0;
  var now = DateTime.now().millisecondsSinceEpoch;
  if (now - lastCheck < 24 * 60 * 60 * 1000) {
    return;
  }
  appdata.implicitData['lastCheckUpdate'] = now;
  appdata.writeImplicitData();
  ComicSourcePage.checkComicSourceUpdate();
  if (appdata.settings['checkUpdateOnStart']) {
    await checkUpdateUi(false, true);
  }
}

void checkUpdates() {
  _checkAppUpdates();
  FollowUpdatesService.initChecker();
}
