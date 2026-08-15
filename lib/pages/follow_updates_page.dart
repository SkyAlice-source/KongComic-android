import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/utils/data_sync.dart';
import 'package:kong_comic/utils/notifications.dart';
import 'package:kong_comic/utils/translations.dart';
import '../foundation/global_state.dart';
import 'package:kong_comic/foundation/follow_updates.dart';

class FollowUpdatesWidget extends StatefulWidget {
  const FollowUpdatesWidget({super.key});

  @override
  State<FollowUpdatesWidget> createState() => _FollowUpdatesWidgetState();
}

class _FollowUpdatesWidgetState
    extends AutomaticGlobalState<FollowUpdatesWidget> {
  int _count = 0;

  List<String> get folders => getEffectiveFollowFolders();

  void getCount() {
    final fs = folders;
    if (fs.isEmpty) {
      _count = 0;
      return;
    }
    _count = fs
        .map((f) => LocalFavoritesManager().countUpdates(f))
        .fold(0, (a, b) => a + b);
  }

  void updateCount() {
    setState(() {
      getCount();
    });
  }

  @override
  void initState() {
    super.initState();
    getCount();
  }

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: GlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        onTap: () {
          context.to(() => FollowUpdatesPage());
        },
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    Center(
                      child: Text('Follow Updates'.tl, style: ts.s18),
                    ),
                    const Spacer(),
                    HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: 18, color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ).paddingHorizontal(16),
              if (_count > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  margin: const EdgeInsets.only(bottom: 16, left: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kcRadius8),
                    color: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  child: Text(
                    '@c updates'.tlParams({
                      'c': _count,
                    }),
                    style: ts.s16,
                  ),
                ),
            ],
          ),
      ),
    );
  }

  @override
  Object? get key => 'FollowUpdatesWidget';
}

class FollowUpdatesPage extends StatefulWidget {
  const FollowUpdatesPage({super.key});

  @override
  State<FollowUpdatesPage> createState() => _FollowUpdatesPageState();
}

class _FollowUpdatesPageState extends AutomaticGlobalState<FollowUpdatesPage> {
  List<String> get folders => getEffectiveFollowFolders();

  var updatedComics = <FavoriteItemWithUpdateInfo>[];
  var allComics = <FavoriteItemWithUpdateInfo>[];

  /// When false (default), only the "Updates" section is shown. The large
  /// "All Comics" list is hidden to avoid flooding the screen, and can be
  /// toggled on demand.
  bool _showAll = false;

  /// Sort comics by update time in descending order with nulls at the end.
  void sortComics() {
    allComics.sort((a, b) {
      if (a.updateTime == null && b.updateTime == null) {
        return 0;
      } else if (a.updateTime == null) {
        return -1;
      } else if (b.updateTime == null) {
        return 1;
      }
      try {
        var aNums = a.updateTime!.split('-').map(int.parse).toList();
        var bNums = b.updateTime!.split('-').map(int.parse).toList();
        for (int i = 0; i < aNums.length; i++) {
          if (aNums[i] != bNums[i]) {
            return bNums[i] - aNums[i];
          }
        }
        return 0;
      } catch (_) {
        return 0;
      }
    });
  }

  /// All comics across the followed folders, optionally filtered to only the
  /// ones that have a new update.
  Map<String, List<FavoriteItemWithUpdateInfo>> _comicsGroupedByFolder(
      bool onlyUpdated) {
    final map = <String, List<FavoriteItemWithUpdateInfo>>{};
    for (final f in folders) {
      final list = LocalFavoritesManager().getComicsWithUpdatesInfo(f);
      final filtered =
          onlyUpdated ? list.where((c) => c.hasNewUpdate).toList() : list;
      if (filtered.isNotEmpty) map[f] = filtered;
    }
    return map;
  }

  @override
  void initState() {
    super.initState();
    updateComics();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SmoothCustomScrollView(
        slivers: [
          SliverAppbar(title: Text('Follow Updates'.tl)),
          if (folders.isEmpty)
            buildNotConfigured(context)
          else
            buildConfigured(context),
          const SliverPadding(padding: EdgeInsets.only(top: 8)),
          ...buildUpdatedComics(),
          ...buildAllComics(),
        ],
      ),
    );
  }

  Widget buildNotConfigured(BuildContext context) {    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.6,
          ),
          borderRadius: BorderRadius.circular(kcRadius8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, size: 18),
              title: Text("Not Configured".tl),
            ),
            Text(
              "Choose folders to follow updates.".tl,
              style: ts.s16,
            ).paddingHorizontal(16),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: showSelector,
              child: Text("Select Folders".tl),
            ).paddingHorizontal(16).toAlign(Alignment.centerRight),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 追更检查间隔选项（天）
  static const _intervalDaysList = [1, 3, 7];

  String _intervalLabel(int days) => switch (days) {
        1 => "Daily".tl,
        3 => "Every 3 days".tl,
        7 => "Weekly".tl,
        _ => "Daily".tl,
      };

  Widget buildConfigured(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.6,
          ),
          borderRadius: BorderRadius.circular(kcRadius8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: HugeIcon(icon: HugeIcons.strokeRoundedFolder01, size: 18),
              title: Text("Following @c folders"
                  .tlParams({'c': folders.length})),
              subtitle: folders.contains('*')
                  ? Text("All folders".tl)
                  : null,
            ),
            Text(
              "Automatic update checking enabled.".tl,
              style: ts.s14,
            ).paddingHorizontal(16),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text("Check update interval".tl),
              subtitle: Text(
                "Checks each comic at most once per interval".tl,
                style: ts.s12,
              ),
              trailing: Select(
                minWidth: 96,
                current: _intervalLabel(
                  (appdata.settings['followUpdateInterval'] as num?)
                          ?.toInt() ??
                      1,
                ),
                values: [for (var d in _intervalDaysList) _intervalLabel(d)],
                onTap: (i) {
                  setState(() {
                    appdata.settings['followUpdateInterval'] =
                        _intervalDaysList[i];
                    appdata.saveData();
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: showSelector,
                  child: Text("Change Folders".tl),
                ),
                FilledButton.tonal(
                  onPressed: checkNow,
                  child: Text("Check Now".tl),
                ),
                const SizedBox(width: 16),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Groups comics by their source (漫画源) name, sorted alphabetically.
  Map<String, List<FavoriteItemWithUpdateInfo>> _groupBySource(
      List<FavoriteItemWithUpdateInfo> comics) {
    final map = <String, List<FavoriteItemWithUpdateInfo>>{};
    for (var c in comics) {
      final key = c.type.comicSource?.name ?? "Unknown";
      (map[key] ??= []).add(c);
    }
    final entries = map.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Map.fromEntries(entries);
  }

  /// A sub-header showing the source name and how many comics it has.
  Widget _sourceHeader(String source, int count) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedGlobe,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(source, style: ts.s16),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(kcRadius8),
              ),
              child: Text(
                '@c'.tlParams({'c': count}),
                style: ts.s14,
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  /// A folder-level header showing its name, total comics, and updated count.
  Widget _folderHeader(String folder, int total, int updated) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 4),
        child: Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedFolder01,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(folder, style: ts.s16),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(kcRadius8),
              ),
              child: Text('@total'.tlParams({'total': total}), style: ts.s14),
            ),
            if (updated > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(kcRadius8),
                ),
                child: Text('@updated updated'.tlParams({'updated': updated}),
                    style: ts.s14),
              ),
            ],
            const Spacer(),
          ],
        ),
      ),
    );
  }

  /// Render one folder's comics (grouped by source) as a flat list of slivers.
  List<Widget> _folderGroup(String folder, List<FavoriteItemWithUpdateInfo> comics) {
    final groups = _groupBySource(comics);
    final slivers = <Widget>[_folderHeader(
      folder,
      comics.length,
      comics.where((c) => c.hasNewUpdate).length,
    )];
    groups.forEach((source, items) {
      slivers.add(_sourceHeader(source, items.length));
      slivers.add(SliverGridComics(comics: items));
    });
    return slivers;
  }

  List<Widget> buildUpdatedComics() {
    final header = SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 0.6,
            ),
          ),
        ),
        child: Row(
          children: [
            HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
            const SizedBox(width: 8),
            Text(
              "Updates".tl,
              style: ts.s18,
            ),
            const Spacer(),
            if (updatedComics.isNotEmpty)
              IconButton(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
                onPressed: () {
                  showConfirmDialog(
                    context: App.rootContext,
                    title: "Mark all as read".tl,
                    content: "Do you want to mark all as read?".tl,
                    onConfirm: () {
                      for (var comic in updatedComics) {
                        LocalFavoritesManager().markAsRead(
                          comic.id,
                          comic.type,
                        );
                      }
                      updateFollowUpdatesUI();
                      appdata.saveData();
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );

    final grouped = _comicsGroupedByFolder(true);
    if (grouped.isEmpty) {
      return [
        header,
        SliverToBoxAdapter(
          child: Row(
            children: [
              Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(kcRadius16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "No updates found".tl,
                      style: ts.s16,
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ];
    }

    final slivers = <Widget>[
      header,
      SliverToBoxAdapter(
        child: Text(
                "The comic will be marked as no updates as soon as you read it."
                    .tl)
            .paddingHorizontal(16)
            .paddingVertical(4),
      ),
    ];
    grouped.forEach((folder, comics) {
      slivers.addAll(_folderGroup(folder, comics));
    });
    return slivers;
  }

  List<Widget> buildAllComics() {
    if (!_showAll) return [];

    final header = SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 0.6,
            ),
          ),
        ),
        child: Row(
          children: [
            HugeIcon(icon: HugeIcons.strokeRoundedMenu02, size: 18),
            const SizedBox(width: 8),
            Text(
              "All Comics".tl,
              style: ts.s18,
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                setState(() {
                  _showAll = false;
                });
              },
              child: Text("Hide".tl),
            ),
          ],
        ),
      ),
    );

    final grouped = _comicsGroupedByFolder(false);
    if (grouped.isEmpty) {
      return [header];
    }

    final slivers = <Widget>[header];
    grouped.forEach((folder, comics) {
      slivers.addAll(_folderGroup(folder, comics));
    });
    return slivers;
  }

  void showSelector() {
    var allFolders = LocalFavoritesManager().folderNames;
    if (allFolders.isEmpty) {
      context.showMessage(message: "No folders available".tl);
      return;
    }
    final current = getEffectiveFollowFolders();
    final allSelected =
        current.isNotEmpty && current.length == allFolders.length;
    final Set<String> selected =
        allSelected ? {...allFolders} : {...current};
    var allToggle = current.contains('*') || allSelected;

    showDialog(
      context: App.rootContext,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return ContentDialog(
            title: "Select Folders".tl,
            content: SizedBox(
              width: double.maxFinite,
              height: 340,
              child: Column(
                children: [
                  CheckboxListTile(
                    title: Text("All Folders".tl),
                    value: allToggle,
                    onChanged: (v) {
                      setState(() {
                        allToggle = v ?? false;
                        if (allToggle) selected.addAll(allFolders);
                      });
                    },
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView(
                      children: allFolders.map((f) {
                        return CheckboxListTile(
                          title: Text(f),
                          value: allToggle ? true : selected.contains(f),
                          onChanged: allToggle
                              ? null
                              : (v) {
                                  setState(() {
                                    if (v == true) {
                                      selected.add(f);
                                    } else {
                                      selected.remove(f);
                                    }
                                  });
                                },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (getEffectiveFollowFolders().isNotEmpty)
                TextButton(
                  onPressed: () {
                    disable();
                    context.pop();
                  },
                  child: Text("Disable".tl),
                ),
              FilledButton(
                onPressed: (allToggle || selected.isNotEmpty)
                    ? () {
                        context.pop();
                        final list = allToggle ? ['*'] : selected.toList();
                        setFolders(list);
                      }
                    : null,
                child: Text("Confirm".tl),
              ),
            ],
          );
        });
      },
    );
  }

  void disable() {
    appdata.settings["followUpdatesFolders"] = <String>[];
    appdata.saveData();
    updateFollowUpdatesUI();
  }

  void setFolders(List<String> selected) async {
    FollowUpdatesService._cancelChecking?.call();
    final resolved = selected.contains('*')
        ? LocalFavoritesManager().folderNames
        : selected;

    for (final f in resolved) {
      LocalFavoritesManager().prepareTableForFollowUpdates(f);
    }

    appdata.settings["followUpdatesFolders"] = selected;
    appdata.saveData();
    updateFollowUpdatesUI();

    if (resolved.isNotEmpty) {
      bool isCanceled = false;
      FollowUpdatesService._cancelChecking = () {
        isCanceled = true;
      };

      await AppNotifications.requestPermission();
      await AppNotifications.showComicUpdateCheck();

      int updated = 0;
      int errors = 0;
      await for (var progress in updateFolders(resolved, true)) {
        if (isCanceled) {
          await AppNotifications.cancelComicUpdate();
          FollowUpdatesService._cancelChecking = null;
          return;
        }
        updated = progress.updated;
        errors = progress.errors;
        await AppNotifications.showComicUpdateProgress(
          current: progress.current,
          total: progress.total,
          updated: progress.updated,
          errors: progress.errors,
        );
      }

      FollowUpdatesService._cancelChecking = null;
      await AppNotifications.showComicUpdateComplete(
        updated: updated,
        errors: errors,
      );
    }

    setState(() {
      updatedComics = [];
      allComics = [];
      updateComics();
    });
  }

  void checkNow() async {
    final folders = this.folders;
    if (folders.isEmpty) return;
    FollowUpdatesService._cancelChecking?.call();
    await Future.delayed(const Duration(milliseconds: 50));

    bool isCanceled = false;
    FollowUpdatesService._cancelChecking = () {
      isCanceled = true;
    };

    await AppNotifications.requestPermission();
    await AppNotifications.showComicUpdateCheck();

    int updated = 0;
    int errors = 0;

    await for (var progress in updateFolders(folders, true)) {
      if (isCanceled) {
        await AppNotifications.cancelComicUpdate();
        FollowUpdatesService._cancelChecking = null;
        return;
      }
      updated = progress.updated;
      errors = progress.errors;
      await AppNotifications.showComicUpdateProgress(
        current: progress.current,
        total: progress.total,
        updated: progress.updated,
        errors: progress.errors,
      );
    }

    FollowUpdatesService._cancelChecking = null;
    await AppNotifications.showComicUpdateComplete(
      updated: updated,
      errors: errors,
    );

    if (updated > 0) {
      GlobalState.findOrNull<_FollowUpdatesWidgetState>()?.updateCount();
      updateComics();
      showUpdateBanner(
        count: updatedComics.length,
        coverPath: updatedComics.firstOrNull?.coverPath,
        title: '@c updates'.tlParams({'c': updatedComics.length}),
        subtitle: updatedComics.firstOrNull?.name ?? 'Follow Updates'.tl,
        onTap: () => App.mainNavigatorKey?.currentContext
            ?.to(() => FollowUpdatesPage()),
      );
    }
  }

  void updateComics() {
    final folders = this.folders;
    if (folders.isEmpty) {
      setState(() {
        allComics = [];
        updatedComics = [];
      });
      return;
    }
    final all = <FavoriteItemWithUpdateInfo>[];
    for (final f in folders) {
      all.addAll(LocalFavoritesManager().getComicsWithUpdatesInfo(f));
    }
    setState(() {
      allComics = all;
      sortComics();
      updatedComics = allComics.where((c) => c.hasNewUpdate).toList();
    });
  }

  @override
  Object? get key => 'FollowUpdatesPage';
}

/// Background service for checking updates
abstract class FollowUpdatesService {
  static bool _isChecking = false;

  static void Function()? _cancelChecking;

  static bool _isInitialized = false;
  static Timer? _timer;

  static void _check() async {
    if (_isChecking) {
      return;
    }
    var folders = getEffectiveFollowFolders();
    if (folders.isEmpty) {
      return;
    }
    bool isCanceled = false;
    _cancelChecking = () {
      isCanceled = true;
      _isChecking = false;
    };

    _isChecking = true;

    while (DataSync().isDownloading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    int updated = 0;
    int errors = 0;
    try {
      await AppNotifications.showComicUpdateCheck();
      await for (var progress in updateFolders(folders, false)) {
        if (isCanceled) {
          await AppNotifications.cancelComicUpdate();
          return;
        }
        updated = progress.updated;
        errors = progress.errors;
        await AppNotifications.showComicUpdateProgress(
          current: progress.current,
          total: progress.total,
          updated: progress.updated,
          errors: progress.errors,
        );
      }
      await AppNotifications.showComicUpdateComplete(
        updated: updated,
        errors: errors,
      );
    } finally {
      _cancelChecking = null;
      _isChecking = false;
      if (updated > 0) {
        updateFollowUpdatesUI();
        final comics = <FavoriteItemWithUpdateInfo>[];
        for (final f in getEffectiveFollowFolders()) {
          comics.addAll(LocalFavoritesManager().getUpdates(f));
        }
        if (comics.isNotEmpty) {
          showUpdateBanner(
            count: comics.length,
            coverPath: comics.firstOrNull?.coverPath,
            title: '@c updates'.tlParams({'c': comics.length}),
            subtitle: comics.firstOrNull?.name ?? 'Follow Updates'.tl,
            onTap: () => App.mainNavigatorKey?.currentContext
                ?.to(() => FollowUpdatesPage()),
          );
        }
      }
    }
  }

  /// Initialize the checker.
  static void initChecker() {
    if (_isInitialized) return;
    _isInitialized = true;

    // Migrate the old single-folder setting to the new list-based one.
    final old = appdata.settings["followUpdatesFolder"];
    if (old is String) {
      appdata.settings["followUpdatesFolders"] = [old];
      appdata.settings["followUpdatesFolder"] = null;
      appdata.saveData();
    }

    _check();
    DataSync().addListener(updateFollowUpdatesUI);
    // 每本漫画有 1 天的检查间隔过滤（见 updateFolder），
    // 这里 1 小时轮询一次只为按时触发，实际每本每天最多检查 1 次；
    // 大部分漫画周更/月更，无需更频繁的唤醒。
    _timer = Timer.periodic(const Duration(hours: 1), (timer) {
      _check();
    });
  }

  static void disposeChecker() {
    _timer?.cancel();
    _timer = null;
    _isInitialized = false;
  }
}

/// Update the UI of follow updates.
void updateFollowUpdatesUI() {
  GlobalState.findOrNull<_FollowUpdatesWidgetState>()?.updateCount();
  GlobalState.findOrNull<_FollowUpdatesPageState>()?.updateComics();
}
