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
                      child: Text('Follow Updates'.tl, style: TextStyle(fontSize: kcSectionTitle)),
                    ),
                    const Spacer(),
                    HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                    color: kcAccentSurface(context),
                  ),
                  child: Text(
                    '@c updates'.tlParams({
                      'c': _count,
                    }),
                    style: TextStyle(
                      fontSize: kcSubtitle,
                      color: kcBrandAdaptive(context),
                    ),
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
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.6,
          ),
          borderRadius: BorderRadius.circular(kcCardRadius),
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
              style: TextStyle(fontSize: kcSubtitle),
            ).paddingHorizontal(16),
            const SizedBox(height: 8),
            Button.filled(
              height: 36,
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
    final scheme = Theme.of(context).colorScheme;
    final intervalDays =
        (appdata.settings['followUpdateInterval'] as num?)?.toInt() ?? 1;
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border.all(color: scheme.outlineVariant, width: 0.6),
          borderRadius: BorderRadius.circular(kcCardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 图标容器：浅红染圆角底 + 品牌红图标，比裸图标更有卡片质感，
                // 也让「关注文件夹」在视觉上和普通列表行区分开。
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: kcAccentSurface(context, alpha: 0.12),
                    borderRadius: BorderRadius.circular(kcRadius8),
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedFolder01,
                      size: 17,
                      color: kcAccentColor(context),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Following @c folders"
                            .tlParams({'c': folders.length}),
                        style: TextStyle(
                          fontSize: kcSubtitle,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        folders.contains('*')
                            ? "All folders · Auto-check on".tl
                            : "Auto-check on".tl,
                        style: TextStyle(
                          fontSize: kcCaption,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Select(
                  minWidth: 84,
                  current: _intervalLabel(intervalDays),
                  values: [for (var d in _intervalDaysList) _intervalLabel(d)],
                  onTap: (i) {
                    setState(() {
                      appdata.settings['followUpdateInterval'] =
                          _intervalDaysList[i];
                      appdata.saveData();
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 次要动作（更改文件夹）靠左、主 CTA（立即检查）靠右：
            // 原写法两个都堆在右侧，左侧留一大片空，视觉重心失衡。
            Row(
              children: [
                Button.text(
                  onPressed: showSelector,
                  child: Text("Change Folders".tl),
                ),
                const Spacer(),
                Button.filled(
                  height: 36,
                  onPressed: checkNow,
                  child: Text("Check Now".tl),
                ),
              ],
            ),
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
      final key = c.type.comicSource?.name ?? "Unknown".tl;
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
              color: kcBrandAdaptive(context),
            ),
            const SizedBox(width: 6),
            Text(source, style: TextStyle(fontSize: kcSubtitle)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(kcRadius8),
              ),
              child: Text(
                '@c'.tlParams({'c': count}),
                style: TextStyle(fontSize: kcBody),
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
              color: kcBrandAdaptive(context),
            ),
            const SizedBox(width: 6),
            Text(folder, style: TextStyle(fontSize: kcSubtitle)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(kcRadius8),
              ),
              child: Text('@total'.tlParams({'total': total}), style: TextStyle(fontSize: kcBody)),
            ),
            if (updated > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  // 用品牌强调浅染而非 errorContainer：
                  // 1) 语义上「有更新」不是错误；2) AMOLED 下 errorContainer 被
                  //    灰阶化会丢失强调，改用 kcAccentSurface 在纯黑下退化为
                  //    中性灰浅染 + kcBrandAdaptive 文字，信号不丢。
                  color: kcAccentSurface(context),
                  borderRadius: BorderRadius.circular(kcRadius8),
                ),
                child: Text('@updated updated'.tlParams({'updated': updated}),
                    style: TextStyle(
                        fontSize: kcBody, color: kcBrandAdaptive(context))),
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
      // 紧凑小行：把大封面网格换成 ComicTile 列表，一屏看全更新，密度与顶部压扁配置卡一致。
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => ComicTile(
              comic: items[i],
              badge: items[i].hasNewUpdate ? 'NEW' : null,
              badgeColor: kcBrandColor,
            ),
            childCount: items.length,
          ),
        ),
      );
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
            HugeIcon(
              icon: HugeIcons.strokeRoundedRefresh,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              "Updates".tl,
              style: TextStyle(fontSize: kcSectionTitle),
            ),
            const Spacer(),
            if (updatedComics.isNotEmpty)
              IconButton(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedTick01, size: 18),
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
      final scheme = Theme.of(context).colorScheme;
      return [
        header,
        // 空状态：原来是一个贴在左边的小灰胶囊，视觉上很孤立。
        // 改成居中的「图标 + 主副文案」，让「没有更新」读起来是一个完整结论，
        // 而不是一条漏掉的内容。
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedTick01,
                      size: 26,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "You're all caught up".tl,
                  style: TextStyle(
                    fontSize: kcSubtitle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "No new updates in followed folders".tl,
                  style: TextStyle(
                    fontSize: kcCaption,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
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
            HugeIcon(
              icon: HugeIcons.strokeRoundedMenu02,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              "All Comics".tl,
              style: TextStyle(fontSize: kcSectionTitle),
            ),
            const Spacer(),
            Button.text(
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
    var allFolders = userFolderNames();
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
                Button.text(
                  onPressed: () {
                    disable();
                    context.pop();
                  },
                  child: Text("Disable".tl),
                ),
              Button.filled(
                onPressed: (allToggle || selected.isNotEmpty)
                    ? () {
                        context.pop();
                        final list = allToggle ? ['*'] : selected.toList();
                        setFolders(list);
                      }
                    : () {},
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
    final resolved =
        selected.contains('*') ? userFolderNames() : selected;

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
      try {
        await for (var progress in updateFolders(resolved, true)) {
          if (isCanceled) return;
          updated = progress.updated;
          errors = progress.errors;
          await AppNotifications.showComicUpdateProgress(
            current: progress.current,
            total: progress.total,
            updated: progress.updated,
            errors: progress.errors,
          );
        }
      } finally {
        // 保证 ongoing 的「检查中」通知一定被收掉（取消 / 异常路径同理）。
        FollowUpdatesService._cancelChecking = null;
        if (isCanceled) {
          await AppNotifications.cancelComicUpdate();
        } else {
          await AppNotifications.showComicUpdateComplete(
            updated: updated,
            errors: errors,
          );
        }
      }
    }

    if (!mounted) return;
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

    try {
      await for (var progress in updateFolders(folders, true)) {
        if (isCanceled) return;
        updated = progress.updated;
        errors = progress.errors;
        await AppNotifications.showComicUpdateProgress(
          current: progress.current,
          total: progress.total,
          updated: progress.updated,
          errors: progress.errors,
        );
      }
    } finally {
      // 无论正常结束、被取消还是 updateFolders 抛异常，都必须把这个 ongoing
      // 的「检查中」通知收掉——ongoing 通知用户划不掉，异常路径漏掉就会一直挂在
      // 通知栏。取消 → 直接撤销；其余 → 换成「检查完成」。
      FollowUpdatesService._cancelChecking = null;
      if (isCanceled) {
        await AppNotifications.cancelComicUpdate();
      } else {
        await AppNotifications.showComicUpdateComplete(
          updated: updated,
          errors: errors,
        );
      }
    }

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
        if (isCanceled) return;
        updated = progress.updated;
        errors = progress.errors;
        await AppNotifications.showComicUpdateProgress(
          current: progress.current,
          total: progress.total,
          updated: progress.updated,
          errors: progress.errors,
        );
      }
    } finally {
      _cancelChecking = null;
      _isChecking = false;
      // 同 checkNow：保证 ongoing 的「检查中」通知一定被收掉，异常路径否则会
      // 一直挂在通知栏。取消 → 撤销；其余 → 换成「检查完成」。
      if (isCanceled) {
        await AppNotifications.cancelComicUpdate();
      } else {
        await AppNotifications.showComicUpdateComplete(
          updated: updated,
          errors: errors,
        );
      }
      if (updated > 0 && !isCanceled) {
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
