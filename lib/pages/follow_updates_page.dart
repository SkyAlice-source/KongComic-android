import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/utils/data_sync.dart';
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

  String? get folder => appdata.settings["followUpdatesFolder"];

  void getCount() {
    if (folder == null) {
      _count = 0;
      return;
    }
    if (!LocalFavoritesManager().folderNames.contains(folder)) {
      _count = 0;
      appdata.settings["followUpdatesFolder"] = null;
      Future.microtask(() {
        appdata.saveData();
      });
    } else {
      _count = LocalFavoritesManager().countUpdates(folder!);
    }
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
                    borderRadius: BorderRadius.circular(8),
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
  String? get folder => appdata.settings["followUpdatesFolder"];

  var updatedComics = <FavoriteItemWithUpdateInfo>[];
  var allComics = <FavoriteItemWithUpdateInfo>[];

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

  @override
  void initState() {
    super.initState();
    if (folder != null) {
      allComics = LocalFavoritesManager().getComicsWithUpdatesInfo(folder!);
      sortComics();
      updatedComics = allComics.where((c) => c.hasNewUpdate).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SmoothCustomScrollView(
        slivers: [
          SliverAppbar(title: Text('Follow Updates'.tl)),
          if (folder == null)
            buildNotConfigured(context)
          else
            buildConfigured(context),
          SliverPadding(padding: const EdgeInsets.only(top: 8)),
          buildUpdatedComics(),
          buildAllComics(),
        ],
      ),
    );
  }

  Widget buildNotConfigured(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.6,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, size: 18),
              title: Text("Not Configured".tl),
            ),
            Text(
              "Choose a folder to follow updates.".tl,
              style: ts.s16,
            ).paddingHorizontal(16),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: showSelector,
              child: Text("Choose Folder".tl),
            ).paddingHorizontal(16).toAlign(Alignment.centerRight),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget buildConfigured(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.6,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: HugeIcon(icon: HugeIcons.strokeRoundedStar, size: 18),
              title: Text(folder!),
            ),
            Text(
              "Automatic update checking enabled.".tl,
              style: ts.s14,
            ).paddingHorizontal(16),
            Text(
              "The app will check for updates at most once a day.".tl,
              style: ts.s14,
            ).paddingHorizontal(16),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: showSelector,
                  child: Text("Change Folder".tl),
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

  Widget buildUpdatedComics() {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
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
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedCancelCircle, size: 18),
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
        ),
        if (updatedComics.isNotEmpty)
          SliverToBoxAdapter(
            child: Text(
                    "The comic will be marked as no updates as soon as you read it."
                        .tl)
                .paddingHorizontal(16)
                .paddingVertical(4),
          ),
        if (updatedComics.isNotEmpty)
          SliverGridComics(comics: updatedComics)
        else
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
                    borderRadius: BorderRadius.circular(16),
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
      ],
    );
  }

  Widget buildAllComics() {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
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
              ],
            ),
          ),
        ),
        SliverGridComics(comics: allComics),
      ],
    );
  }

  void showSelector() {
    var folders = LocalFavoritesManager().folderNames;
    if (folders.isEmpty) {
      context.showMessage(message: "No folders available".tl);
      return;
    }
    String? selectedFolder;
    showDialog(
      context: App.rootContext,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return ContentDialog(
            title: "Choose Folder".tl,
            content: Column(
              children: [
                ListTile(
                  title: Text("Folder".tl),
                  trailing: Select(
                    minWidth: 120,
                    current: selectedFolder,
                    values: folders,
                    onTap: (i) {
                      setState(() {
                        selectedFolder = folders[i];
                      });
                    },
                  ),
                ),
              ],
            ),
            actions: [
              if (appdata.settings["followUpdatesFolder"] != null)
                TextButton(
                  onPressed: () {
                    disable();
                    context.pop();
                  },
                  child: Text("Disable".tl),
                ),
              FilledButton(
                onPressed: selectedFolder == null
                    ? null
                    : () {
                        context.pop();
                        setFolder(selectedFolder!);
                      },
                child: Text("Confirm".tl),
              ),
            ],
          );
        });
      },
    );
  }

  void disable() {
    appdata.settings["followUpdatesFolder"] = null;
    appdata.saveData();
    updateFollowUpdatesUI();
  }

  void setFolder(String folder) async {
    FollowUpdatesService._cancelChecking?.call();
    LocalFavoritesManager().prepareTableForFollowUpdates(folder);

    var count = LocalFavoritesManager().count(folder);

    if (count > 0) {
      bool isCanceled = false;
      void onCancel() {
        isCanceled = true;
      }

      var loadingController = showLoadingDialog(
        App.rootContext,
        withProgress: true,
        cancelButtonText: "Cancel".tl,
        onCancel: onCancel,
        message: "Updating comics...".tl,
      );

      await for (var progress in updateFolder(folder, true)) {
        if (isCanceled) {
          return;
        }
        loadingController.setProgress(progress.current / progress.total);
      }

      loadingController.close();
    }

    setState(() {
      appdata.settings["followUpdatesFolder"] = folder;
      updatedComics = [];
      allComics = LocalFavoritesManager().getComicsWithUpdatesInfo(folder);
      sortComics();
    });
    appdata.saveData();
  }

  void checkNow() async {
    FollowUpdatesService._cancelChecking?.call();
    await Future.delayed(const Duration(milliseconds: 50));

    bool isCanceled = false;
    void onCancel() {
      isCanceled = true;
    }

    var loadingController = showLoadingDialog(
      App.rootContext,
      withProgress: true,
      cancelButtonText: "Cancel".tl,
      onCancel: onCancel,
      message: "Updating comics...".tl,
    );

    int updated = 0;

    await for (var progress in updateFolder(folder!, true)) {
      if (isCanceled) {
        return;
      }
      loadingController.setProgress(progress.current / progress.total);
      updated = progress.updated;
    }

    loadingController.close();

    if (updated > 0) {
      GlobalState.findOrNull<_FollowUpdatesWidgetState>()?.updateCount();
      updateComics();
    }
  }

  void updateComics() {
    if (folder == null) {
      setState(() {
        allComics = [];
        updatedComics = [];
      });
      return;
    }
    setState(() {
      allComics = LocalFavoritesManager().getComicsWithUpdatesInfo(folder!);
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
    var folder = appdata.settings["followUpdatesFolder"];
    if (folder == null) {
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
    try {
      await for (var progress in updateFolder(folder, false)) {
        if (isCanceled) {
          return;
        }
        updated = progress.updated;
      }
    } finally {
      _cancelChecking = null;
      _isChecking = false;
      if (updated > 0) {
        updateFollowUpdatesUI();
      }
    }
  }

  /// Initialize the checker.
  static void initChecker() {
    if (_isInitialized) return;
    _isInitialized = true;
    _check();
    DataSync().addListener(updateFollowUpdatesUI);
    // A short interval will not affect the performance since every comic has a check time.
    _timer = Timer.periodic(const Duration(minutes: 10), (timer) {
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
