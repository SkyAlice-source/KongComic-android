import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/pages/comic_details_page/comic_page.dart';
import 'package:kong_comic/utils/data_sync.dart';
import 'package:kong_comic/utils/follow_update_worker.dart';
import 'package:kong_comic/utils/notifications.dart';
import 'package:kong_comic/utils/translations.dart';
import '../foundation/global_state.dart';
import 'package:kong_comic/foundation/follow_updates.dart';

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
    // 用户已经进到追更页看到了结果，通知栏里那条「漫画更新检查完成」就没必要
    // 再留着。检查正在进行时不能动，否则会把进度通知撤掉。
    if (!AppNotifications.comicUpdateCheckActive) {
      AppNotifications.cancelComicUpdate();
    }
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
            KcListTile(
              showDivider: false,
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
    final intervalDays = followUpdateIntervalDays;
    // getEffectiveFollowFolders() 已经把 '*' 展开成真实文件夹名，所以判断
    // 「全部文件夹」必须读原始设置，不能看 folders（原来那个分支永远为 false）。
    final rawSelection = appdata.settings['followUpdatesFolders'];
    final isAllFolders = rawSelection is List && rawSelection.contains('*');
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
                        isAllFolders
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
                    // 间隔变了要重排后台周期任务（内部按签名判断是否真的变）。
                    unawaited(initFollowUpdateWorker());
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
                // 检查进行中时把「立即检查」换成「取消」：原来检查一旦跑起来
                // 页面上没有任何中止入口，只能退出页面干等。
                ValueListenableBuilder<bool>(
                  valueListenable: FollowUpdatesService.checking,
                  builder: (context, checking, _) {
                    if (checking) {
                      return Button.outlined(
                        height: 36,
                        onPressed: () =>
                            FollowUpdatesService.cancelCurrent(),
                        child: Text("Cancel".tl),
                      );
                    }
                    return Button.filled(
                      height: 36,
                      onPressed: checkNow,
                      child: Text("Check Now".tl),
                    );
                  },
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
      // 紧凑小行：把大封面网格换成「缩略图 + 两行文字」的行，一屏看全更新，
      // 密度与顶部压扁配置卡一致。
      //
      // ⚠️ 这里曾经直接塞 ComicTile：它的 brief / detailed 两种模式内部都有
      // Expanded / Spacer，必须由父级给出确定高度；而 SliverList 的子项高度是
      // 无界的，一旦真的有漫画要渲染就抛
      // 「RenderFlex children have non-zero flex but incoming height constraints
      //  are unbounded」并连带整页白屏（收藏夹里有更新时必现）。
      // 所以改用自适应高度的 _FollowComicRow。
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _FollowComicRow(comic: items[i]),
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
            // 「全部关注漫画」区块此前没有任何入口（_showAll 永远是 false，
            // buildAllComics 恒返回空），关注文件夹里没更新的漫画根本看不到。
            if (!_showAll)
              Button.text(
                height: 32,
                onPressed: () {
                  setState(() {
                    _showAll = true;
                  });
                },
                child: Text("All Comics".tl),
              ),
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
                        // 批量场景统一在末尾广播一次，避免每本都触发一次首页重建。
                        LocalFavoritesManager().markAsRead(
                          comic.id,
                          comic.type,
                          notify: false,
                        );
                      }
                      LocalFavoritesManager().notifyChanges();
                      updateFollowUpdatesUI();
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
                        if (allToggle) {
                          selected.addAll(allFolders);
                        } else {
                          // 取消「全部」时要把自动勾上的子项一起清掉，否则下面
                          // 每一行仍是勾选态，看起来像点了没反应。
                          selected.clear();
                        }
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
    // 关闭追更时，正在跑的检查和通知栏里的残留通知都要一起收掉，
    // 否则关掉之后还会看到「正在检查漫画更新」。
    FollowUpdatesService.cancelCurrent();
    appdata.settings["followUpdatesFolders"] = <String>[];
    appdata.saveData();
    updateFollowUpdatesUI();
    if (!AppNotifications.comicUpdateCheckActive) {
      AppNotifications.cancelComicUpdate();
    }
    // 关掉追更就不该再有后台周期任务。
    unawaited(initFollowUpdateWorker());
  }

  void setFolders(List<String> selected) async {
    FollowUpdatesService.cancelCurrent();
    final resolved =
        selected.contains('*') ? userFolderNames() : selected;
    // 改动前的关注列表：只给「新增进来的文件夹」跑首次检查。
    // 原来是无条件全量重查（ignoreCheckTime=true），文件夹和漫画一多，
    // 只是删掉一个文件夹也要把所有漫画重拉一遍章节信息，又慢又费流量。
    final previous = getEffectiveFollowFolders();
    final added = resolved.where((f) => !previous.contains(f)).toList();

    for (final f in resolved) {
      // 第二个参数必须是 false：默认值 true 会把该文件夹里所有
      // has_new_update 清成 0 —— 用户只是改一下关注文件夹，已有的「有更新」
      // 红标就被抹掉了（看起来像更新记录丢了）。这里只补列，不动数据。
      LocalFavoritesManager().prepareTableForFollowUpdates(f, false);
    }

    appdata.settings["followUpdatesFolders"] = selected;
    appdata.saveData();
    updateFollowUpdatesUI();
    // 关注范围/间隔可能变了，重新登记后台周期任务（内部按签名去重）。
    unawaited(initFollowUpdateWorker());

    if (added.isNotEmpty) {
      bool isCanceled = false;
      // 用命名函数而非匿名闭包：finally 里要靠 identical() 认领自己那一份
      // 取消句柄，闭包变量立刻被 lint 判成 prefer_function_declarations。
      void cancelToken() {
        isCanceled = true;
      }

      FollowUpdatesService._cancelChecking = cancelToken;
      FollowUpdatesService._setChecking(true);

      await AppNotifications.requestPermission();
      final session = await AppNotifications.showComicUpdateCheck();

      int updated = 0;
      int errors = 0;
      try {
        await for (var progress in updateFolders(added, true)) {
          if (isCanceled) return;
          updated = progress.updated;
          errors = progress.errors;
          await AppNotifications.showComicUpdateProgress(
            session: session,
            current: progress.current,
            total: progress.total,
            updated: progress.updated,
            errors: progress.errors,
          );
        }
      } finally {
        // 保证 ongoing 的「检查中」通知一定被收掉（取消 / 异常路径同理）。
        // 只有仍持有取消槽位时才复位 UI 状态：新检查（手动/定时）可能已经接管，
        // 无条件复位会把「取消」按钮又变回「立即检查」。
        final owned =
            identical(FollowUpdatesService._cancelChecking, cancelToken);
        if (owned) {
          FollowUpdatesService._cancelChecking = null;
          FollowUpdatesService._setChecking(false);
        }
        if (isCanceled) {
          await AppNotifications.cancelComicUpdate(session: session);
        } else {
          await AppNotifications.showComicUpdateComplete(
            session: session,
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
    FollowUpdatesService.cancelCurrent();
    await Future.delayed(const Duration(milliseconds: 50));

    bool isCanceled = false;
    void cancelToken() {
      isCanceled = true;
    }

    FollowUpdatesService._cancelChecking = cancelToken;
    FollowUpdatesService._setChecking(true);

    if (App.isAndroid) {
      final granted = await AppNotifications.requestPermission();
      // 权限被拒时检查照跑，但用户看不到任何进度条/结果 —— 之前是彻底静默，
      // 很容易被当成「点了没反应」。这里明确告知一次。
      if (!granted && mounted) {
        context.showMessage(
          message:
              "Notification permission is off. The check still runs, but its progress won't be shown."
                  .tl,
        );
      }
    }
    final session = await AppNotifications.showComicUpdateCheck();

    int updated = 0;
    int errors = 0;

    try {
      await for (var progress in updateFolders(folders, true)) {
        if (isCanceled) return;
        updated = progress.updated;
        errors = progress.errors;
        await AppNotifications.showComicUpdateProgress(
          session: session,
          current: progress.current,
          total: progress.total,
          updated: progress.updated,
          errors: progress.errors,
        );
      }
    } finally {
      // 无论正常结束、被取消还是 updateFolders 抛异常，都必须把这个 ongoing
      // 的「检查中」通知收掉——ongoing 通知用户划不掉，异常路径漏掉就会一直挂在
      // 通知栏。取消 → 直接撤销；其余 → 换成「检查完成」（限时自动消失）。
      final owned =
          identical(FollowUpdatesService._cancelChecking, cancelToken);
      if (owned) {
        FollowUpdatesService._cancelChecking = null;
        FollowUpdatesService._setChecking(false);
      }
      if (isCanceled) {
        await AppNotifications.cancelComicUpdate(session: session);
      } else {
        await AppNotifications.showComicUpdateComplete(
          session: session,
          updated: updated,
          errors: errors,
        );
      }
    }

    if (updated > 0) {
      // 原来这里找的是早已废弃的 FollowUpdatesWidget（主页追更入口其实是
      // _FlatBox，只听 LocalFavoritesManager），改走统一入口把两边一起刷新。
      updateFollowUpdatesUI();
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

/// 追更页的紧凑漫画行：封面缩略图 + 标题 / 作者 / 更新时间 / 来源。
///
/// 高度完全自适应（[Column] 用 [MainAxisSize.min]，不用 Expanded / Spacer），
/// 因此可以安全地作为 [SliverList] 的子项 —— 见 [_FollowUpdatesPageState
/// ._folderGroup] 里关于 ComicTile 的说明。
class _FollowComicRow extends StatelessWidget {
  const _FollowComicRow({required this.comic});

  final FavoriteItemWithUpdateInfo comic;

  static const double _coverWidth = 46;
  static const double _coverHeight = 62;

  void _open() {
    App.mainNavigatorKey?.currentContext?.to(
      () => ComicPage(
        id: comic.id,
        sourceKey: comic.sourceKey,
        cover: comic.cover,
        title: comic.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final image = comicCoverImageProvider(comic);

    return InkWell(
      borderRadius: BorderRadius.circular(kcCardRadius),
      onTap: _open,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          children: [
            Container(
              width: _coverWidth,
              height: _coverHeight,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(kcRadius8),
              ),
              clipBehavior: Clip.antiAlias,
              child: image == null
                  ? const SizedBox()
                  : AnimatedImage(
                      key: ValueKey(image.hashCode),
                      image: image,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      cacheWidth: (_coverWidth * dpr).ceil().clamp(24, 400),
                      cacheHeight: (_coverHeight * dpr).ceil().clamp(24, 400),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comic.title.replaceAll('\n', ''),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: kcBody,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (comic.author.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      comic.author.replaceAll('\n', ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: kcCaption,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // 从没检查过（updateTime 为 null）时不显示「未知」占位，
                      // 只留来源 —— 否则每行都顶着一个「未知」很吵。
                      if (comic.updateTime != null) ...[
                        Flexible(
                          child: Text(
                            comic.updateTime!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: kcCaption,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          comic.type.comicSource?.name ?? "Unknown".tl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: kcCaption,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (comic.hasNewUpdate) ...[
              const SizedBox(width: 8),
              AppBadge(
                "NEW",
                type: AppBadgeType.neutral,
                backgroundColor: kcBrandColor,
                fontSize: kcCaption,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Background service for checking updates
abstract class FollowUpdatesService {
  static bool _isChecking = false;

  /// 检查是否正在进行（UI 用它决定显示「立即检查」还是「取消」）。
  static final ValueNotifier<bool> checking = ValueNotifier<bool>(false);

  static void Function()? _cancelChecking;

  static bool _isInitialized = false;
  static Timer? _timer;

  /// 同 [_isChecking]，额外把状态推给监听 UI 的 notifier。
  static void _setChecking(bool value) {
    _isChecking = value;
    checking.value = value;
  }

  /// 中止当前正在跑的检查（页面上的「取消」按钮）。
  ///
  /// 立刻清掉槽位并把按钮状态复位，给用户「点到了」的即时反馈：单本漫画的
  /// 请求可能正卡在 45s 超时里，等它回来才复位的话，看起来像是点了没反应。
  /// 取消标记交给各流程自己的 finally 收尾（撤通知、广播 UI）。
  static void cancelCurrent() {
    final token = _cancelChecking;
    if (token == null) return;
    _cancelChecking = null;
    _setChecking(false);
    token();
    // 通知栏那条「正在检查」也不用等流程收尾（可能正卡在单本 45s 超时里）。
    // 无条件撤销会把会话置为非活跃，后续迟到的进度回调自然被会话闸门挡掉。
    unawaited(AppNotifications.cancelComicUpdate());
  }

  static void _check() async {
    if (_isChecking) {
      return;
    }
    var folders = getEffectiveFollowFolders();
    if (folders.isEmpty) {
      return;
    }
    // 没有到期该查的漫画就直接静默退出：不贴「正在检查」通知、不建流。
    // 否则每小时都会在通知栏抖一次「无更新」（大部分漫画周更/月更）。
    if (countDueUpdates(folders) == 0) {
      return;
    }
    bool isCanceled = false;
    void cancelToken() {
      isCanceled = true;
      // 只有仍然持有槽位时才复位（被新检查接管后不能动 UI 状态）。
      if (identical(_cancelChecking, cancelToken)) _setChecking(false);
    }

    _cancelChecking = cancelToken;

    _setChecking(true);

    // 下载占带宽时不抢资源，但不能无限等：最多等 30 秒就照常查。
    var waited = 0;
    while (DataSync().isDownloading && waited < 30000) {
      await Future.delayed(const Duration(milliseconds: 200));
      waited += 200;
    }
    if (isCanceled) {
      if (identical(_cancelChecking, cancelToken)) _cancelChecking = null;
      return;
    }

    int updated = 0;
    int errors = 0;
    final session = await AppNotifications.showComicUpdateCheck();
    try {
      await for (var progress in updateFolders(folders, false)) {
        if (isCanceled) return;
        updated = progress.updated;
        errors = progress.errors;
        await AppNotifications.showComicUpdateProgress(
          session: session,
          current: progress.current,
          total: progress.total,
          updated: progress.updated,
          errors: progress.errors,
        );
      }
    } finally {
      // 只清自己那一份：别的检查（手动 / 改文件夹）可能已经接管了这个槽位，
      // 无条件置 null 会把它们的取消能力一起抹掉。
      //
      // `_setChecking(false)` 也必须跟着这个判断走：定时检查被「立即检查」
      // 顶掉时，这一句会无条件把刚置上的 true 又抹回去 —— 表现为手动检查
      // 正在跑、按钮却还停在「立即检查」（没有取消入口）。
      final owned = identical(_cancelChecking, cancelToken);
      if (owned) {
        _cancelChecking = null;
        _setChecking(false);
      }
      // 同 checkNow：保证 ongoing 的「检查中」通知一定被收掉，异常路径否则会
      // 一直挂在通知栏。取消 → 撤销；其余 → 换成「检查完成」（限时自动消失）。
      if (isCanceled) {
        await AppNotifications.cancelComicUpdate(session: session);
      } else {
        await AppNotifications.showComicUpdateComplete(
          session: session,
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
///
/// 仅刷新已挂载的追更页（[FollowUpdatesPage]）。历史上这里还尝试刷新一个
/// 从未挂载的 `FollowUpdatesWidget`（主页追更入口其实是别处），那行
/// `findOrNull<_FollowUpdatesWidgetState>()` 恒为 null、静默不执行，已于
/// v1.5.2 删除 —— 不要再把刷新逻辑挂到不存在的 widget 上。
void updateFollowUpdatesUI() {
  GlobalState.findOrNull<_FollowUpdatesPageState>()?.updateComics();
}
