import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_source/source_repositories.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/pages/comic_source_page.dart';
import 'package:kong_comic/utils/translations.dart';

/// 自动更新漫画源的最小间隔（24 小时）。
///
/// 源更新频率低，且每次都要逐个拉取脚本；没必要每次启动都跑。一天最多一次
/// 既能及时拿到更新，又不会在用户反复开关 App 时反复联网、互相抢同一份文件。
const _autoSourceUpdateThrottleMs = 24 * 60 * 60 * 1000;

/// 启动后（UI 已挂载）触发的一次性自动更新。
///
/// 仅在用户开启开关、且设备处于非计费网络（WiFi / 有线）时执行；每日节流一次。
/// 复用仓库页已有的批量更新套路（[ComicSourcePage.updateFromEntry] + 末尾统一
/// [ComicSourceManager.reload]），完成后用根 context 弹一条汇总提示。
Future<void> initAutoSourceUpdate() async {
  if (appdata.settings['autoUpdateSourcesEnabled'] != true) return;
  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last =
        appdata.implicitData['autoSourceUpdateLastRun'] as int? ?? 0;
    if (now - last < _autoSourceUpdateThrottleMs) return;
    // 先记时间戳再跑：即便这次中途失败，24 小时内也不会重试，避免崩溃循环。
    appdata.implicitData['autoSourceUpdateLastRun'] = now;
    appdata.writeImplicitData();

    final connectivity = Connectivity();
    final result = await connectivity.checkConnectivity();
    final onUnmetered = result.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
    );
    if (!onUnmetered) {
      Log.info("AutoSourceUpdate", "Skipped: not on WiFi/ethernet");
      return;
    }

    final summary = await autoUpdateAllSources();
    if (summary.total == 0 || !App.isInitialized) return;
    final context = App.rootNavigatorKey.currentContext;
    if (context == null) return;
    var message = "Auto update sources result".tlParams({
      'ok': summary.ok.toString(),
      'fail': summary.fail.toString(),
    });
    if (summary.stale > 0) {
      message +=
          " · ${"Repository out of sync: @n".tlParams({'n': summary.stale.toString()})}";
    }
    context.showMessage(message: message);
  } catch (e, s) {
    Log.error("AutoSourceUpdate", "$e\n$s");
  }
}

/// 遍历所有仓库，把已安装且有新版的源静默更新到最新版本。
///
/// 与仓库页「更新整个仓库」同源逻辑：对每个仓库 fresh 拉取 index，挑出
/// `已安装且版本较新` 的条目，逐条 [ComicSourcePage.updateFromEntry]
/// （不带 loading、不单独 reload），全部跑完再统一 [ComicSourceManager.reload]
/// 一次 —— 否则会把全部脚本重解析 N 遍。返回成功 / 失败 / 仓库未同步 / 总数。
Future<({int ok, int fail, int stale, int total})> autoUpdateAllSources() async {
  final repositories = SourceRepositories.instance.all;
  if (repositories.isEmpty) {
    return (ok: 0, fail: 0, stale: 0, total: 0);
  }
  // 快照一份已安装源：循环里 updateFromEntry 会先从管理器移除源再装回，
  // 用快照比对才不会漏掉后续条目。
  final installed = ComicSource.all();
  ComicSource? findInstalled(String key) {
    for (final s in installed) {
      if (s.key == key) return s;
    }
    return null;
  }

  var ok = 0;
  var fail = 0;
  var stale = 0;
  var total = 0;
  for (final repository in repositories) {
    SourceCatalog catalog;
    try {
      catalog = await SourceRepositories.instance.load(repository, fresh: true);
    } catch (e) {
      Log.warning("AutoSourceUpdate", "Skip ${repository.name}: $e");
      continue;
    }
    final targets = <(SourceCatalogEntry, ComicSource)>[];
    for (final entry in catalog.entries) {
      final source = findInstalled(entry.key);
      if (source == null) continue;
      if (!compareSemVer(entry.version, source.version)) continue;
      targets.add((entry, source));
    }
    total += targets.length;
    for (final (entry, source) in targets) {
      try {
        final outcome = await ComicSourcePage.updateFromEntry(
          source,
          repository,
          entry,
          false,
          false,
        );
        if (outcome != null && outcome.installed != outcome.target) {
          stale++;
        } else {
          ok++;
        }
      } catch (e, s) {
        Log.error("AutoSourceUpdate", e, s);
        fail++;
      }
    }
  }
  try {
    await ComicSourceManager().reload();
  } catch (e, s) {
    Log.error("AutoSourceUpdate", "Reload failed: $e\n$s");
  }
  return (ok: ok, fail: fail, stale: stale, total: total);
}
