part of 'settings_page.dart';

class AppSettings extends StatefulWidget {
  const AppSettings({super.key});

  @override
  State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> with WidgetsBindingObserver {
  /// 是否已获得「所有文件访问」(MANAGE_EXTERNAL_STORAGE)。
  ///
  /// 这个权限只在 Manifest 里声明、从未运行时申请过；只有拿到它，默认存储目录
  /// 才可能是公共 Download/Comic。这里把状态显示出来并给出入口，而不是让
  /// findDefaultPath() 悄悄探测失败后回退。
  bool _allFilesAccess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAllFilesAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置页返回后重新取一次，状态才会跟着变。
    if (state == AppLifecycleState.resumed) {
      _loadAllFilesAccess();
    }
  }

  Future<void> _loadAllFilesAccess() async {
    var granted = await LocalManager.hasAllFilesAccess();
    if (!mounted) return;
    if (granted == _allFilesAccess) return;
    setState(() => _allFilesAccess = granted);
  }
  /// 把下载目录迁移到 [result]：冲突检测 → 弹窗选择覆盖/合并 → 复制+删旧。
  /// 与「Set New Storage Path」和「Move to Download/Comic」共用。
  Future<void> _setStoragePath(String result) async {
    if (result.isEmpty) return;
    if (!mounted) return;
    final manager = LocalManager();
    final existingCount = await manager.countConflicts(result);
    bool overwrite = true;
    if (existingCount > 0) {
      final choice = await showDialog<_ConflictChoice>(
        context: context,
        builder: (ctx) => _StorageConflictDialog(
          existingCount: existingCount,
          newPath: result,
        ),
      );
      if (choice == null || choice == _ConflictChoice.cancel) return;
      overwrite = choice == _ConflictChoice.overwrite;
    }
    if (!mounted) return;
    var loadingDialog = showLoadingDialog(
      App.rootContext,
      barrierDismissible: false,
      allowCancel: false,
    );
    // The dialog above has no cancel button and cannot be dismissed, so any
    // throw out of `setNewPath` (isolate work, file IO) would strand it on
    // screen forever with no way to close it.
    String? res;
    try {
      res = await manager.setNewPath(result, overwrite: overwrite);
    } catch (e) {
      if (mounted) {
        context.showMessage(message: e.toString());
      }
      return;
    } finally {
      loadingDialog.close();
    }
    if (!mounted) return;
    if (res != null) {
      context.showMessage(message: res);
    } else {
      context.showMessage(message: "Path set successfully".tl);
      setState(() {});
    }
  }

  /// 把散落在存储目录之外的本地漫画归拢进当前存储路径。
  ///
  /// 之前这里的判据是 `manager.directory.path == manager.path` —— 两边永远相等
  /// （`directory` 就是 `Directory(path)`），按钮点了永远只弹一句「已在当前存储
  /// 路径」，什么都不会搬。真正该判断的是「有没有 baseDir 不在当前路径下的漫画」。
  Future<void> _moveExternalToCurrentPath() async {
    final manager = LocalManager();
    final comics = manager.externalComics;
    if (!mounted) return;
    if (comics.isEmpty) {
      context.showMessage(message: "Already in current storage path".tl);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: "Move comics into storage path".tl,
        contentPadding: ContentDialog.hPadding,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Found @count comic(s) stored outside the current storage path. Move them into this folder?"
                  .tlParams({'count': comics.length}),
            ).paddingBottom(8),
            Text(
              manager.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: kcCaption,
                color: context.colorScheme.onSurfaceVariant,
                fontFamily: "monospace",
              ),
            ),
          ],
        ),
        actions: [
          Button.text(
            onPressed: () => ctx.pop(false),
            child: Text("Cancel".tl),
          ),
          Button.filled(
            onPressed: () => ctx.pop(true),
            child: Text("Move".tl),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    var loadingDialog = showLoadingDialog(
      App.rootContext,
      barrierDismissible: false,
      allowCancel: false,
    );
    String? res;
    try {
      res = await manager.gatherExternalComics();
    } catch (e, s) {
      Log.error("Local", "Failed to gather external comics: $e", s);
      res = e.toString();
    } finally {
      loadingDialog.close();
    }
    if (!mounted) return;
    if (res != null) {
      context.showMessage(message: res);
    } else {
      context.showMessage(message: "Comics moved into storage path".tl);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("APP".tl)),
        SelectSetting(
          title: "Initial Page".tl,
          settingKey: "initialPage",
          optionTranslation: {
            '0': "Categories".tl,
            '1': "Favorites".tl,
            '2': "Home".tl,
            '3': "Explore".tl,
          },
        ).toSliver(),
        _SettingPartTitle(
          title: "Data".tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDatabase, size: 18),
        ),
        _KcSettingTile(
          title: Text("Storage Path for local comics".tl),
          // 路径很长：基座里的副标题统一做单行省略，避免被硬裁到半截。
          subtitle: LocalManager().path,
          subtitleMaxLines: 1,
          trailing: IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: LocalManager().path));
              context.showMessage(message: "Path copied to clipboard".tl);
            },
          ),
        ).toSliver(),
        // 上次启动发现存储目录不可用、已临时切换时，提示用户文件还在原处。
        if (LocalManager().pendingPathFallback != null)
          _StoragePathFallbackBanner(
            onResolved: () => setState(() {}),
          ).toSliver(),
        _CallbackSetting(
          title: "Set New Storage Path".tl,
          actionTitle: "Set".tl,
          callback: () async {
            String? result;
            if (App.isAndroid) {
              var picker = DirectoryPicker();
              result = (await picker.pickDirectory())?.path;
            } else if (App.isIOS) {
              result = await selectDirectoryIOS();
            } else {
              result = await selectDirectory();
            }
            if (result == null || result.isEmpty) return;
            await _setStoragePath(result);
          },
        ).toSliver(),
        _CallbackSetting(
          title: "Move to Current Storage Path".tl,
          subtitle:
              "Move all your local comics into the Storage Path folder. No extra permission needed, and the setting stays unchanged."
                  .tl,
          actionTitle: "Move".tl,
          callback: () => _moveExternalToCurrentPath(),
        ).toSliver(),
        if (App.isAndroid)
          _CallbackSetting(
            title: "All files access".tl,
            subtitle: _allFilesAccess
                ? "Granted".tl
                : "Required only to use the public Download/Comic folder".tl,
            actionTitle: "Open".tl,
            callback: () => LocalManager.openAllFilesAccessSettings(),
          ).toSliver(),
        _KcSettingTile(
          title: Text("Cache Size".tl),
          subtitle: bytesToReadableString(CacheManager().currentSize),
        ).toSliver(),
        _CallbackSetting(
          title: "Clear Cache".tl,
          actionTitle: "Clear".tl,
          callback: () async {
            var loadingDialog = showLoadingDialog(
              App.rootContext,
              barrierDismissible: false,
              allowCancel: false,
            );
            await CacheManager().clear();
            loadingDialog.close();
            if (!mounted) return;
            context.showMessage(message: "Cache cleared".tl);
            setState(() {});
          },
        ).toSliver(),
        _CallbackSetting(
          title: "Cache Limit".tl,
          subtitle: "${appdata.settings['cacheSize']} ${"MB".tl}",
          callback: () {
            showInputDialog(
              context: context,
              title: "Set Cache Limit".tl,
              hintText: "Size in MB".tl,
              inputValidator: RegExp(r"^\d+$"),
              onConfirm: (value) {
                appdata.settings['cacheSize'] = int.parse(value);
                appdata.saveData();
                setState(() {});
                CacheManager().setLimitSize(appdata.settings['cacheSize']);
                return null;
              },
            );
          },
          actionTitle: 'Set'.tl,
        ).toSliver(),
        _CallbackSetting(
          title: "Export App Data".tl,
          callback: () async {
            var controller = showLoadingDialog(context);
            try {
              var file = await exportAppData(false);
              final now = DateTime.now();
              final dateStr =
                  "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
              final suffix = _randomFileSuffix();
              final targetName = "KongComic_${dateStr}_$suffix.kongcomic";
              final targetPath = FilePath.join(App.cachePath, targetName);
              final renamed = await file.copy(targetPath);
              file.deleteIgnoreError();
              await saveFile(filename: targetName, file: renamed);
              if (context.mounted) {
                context.showMessage(message: "Export completed".tl);
              }
            } catch (e, s) {
              Log.error("Export data", e.toString(), s);
              context.showMessage(message: "Failed to export data".tl);
            } finally {
              controller.close();
            }
          },
          actionTitle: 'Export'.tl,
        ).toSliver(),
        _CallbackSetting(
          title: "Import App Data".tl,
          callback: () async {
            var file = await selectFile(ext: ['kongcomic', 'venera', 'picadata']);
            if (file != null) {
              var controller = showLoadingDialog(context);
              var cacheFile =
                  File(FilePath.join(App.cachePath, "import_data_temp"));
              var needRestart = false;
              var cancelled = false;
              try {
                await file.saveTo(cacheFile.path);
                if (file.name.endsWith('picadata')) {
                  await importPicaData(cacheFile);
                } else {
                  var hasDuplicates = await importHasDuplicates(cacheFile);
                  if (hasDuplicates) {
                    var choice = await _showImportModeDialog(context);
                    if (choice == null || choice == _ConflictChoice.cancel) {
                      cancelled = true;
                      context.showMessage(message: "Import cancelled".tl);
                    } else {
                      needRestart = await importAppData(
                          cacheFile, false, choice == _ConflictChoice.merge);
                    }
                  } else {
                    needRestart = await importAppData(cacheFile);
                  }
                }
              } catch (e, s) {
                Log.error("Import data", e.toString(), s);
                context.showMessage(message: "Failed to import data".tl);
              } finally {
                controller.close();
                cacheFile.deleteIgnoreError();
                App.forceRebuild();
              }
              if (cancelled) {
                // 已显示取消提示，无需额外反馈
              } else if (needRestart && context.mounted) {
                context.showMessage(
                    message: "Restart app to complete data import".tl);
              } else if (context.mounted) {
                context.showMessage(message: "Import completed".tl);
              }
            }
          },
          actionTitle: 'Import'.tl,
        ).toSliver(),
        if (App.isAndroid)
          _SwitchSetting(
            title: "Auto Backup".tl,
            settingKey: 'autoBackupEnabled',
            subtitle: "Periodically back up your data to the Download folder".tl,
            onChanged: () async {
              await initAutoBackup();
              setState(() {});
            },
          ).toSliver(),
        if (App.isAndroid)
          _SwitchSetting(
            title: "Auto-update comic sources".tl,
            settingKey: 'autoUpdateSourcesEnabled',
            subtitle:
                "Automatically update installed sources on WiFi. Overrides local source edits.".tl,
            onChanged: () => setState(() {}),
          ).toSliver(),
        if (App.isAndroid)
          _CallbackSetting(
            title: "Backup Interval".tl,
            subtitle:
                "@count days".tlParams({'count': appdata.settings['autoBackupInterval'] ?? 7}),
            callback: () async {
              final options = ["1", "3", "7", "14", "30"];
              final current =
                  (appdata.settings['autoBackupInterval'] as int? ?? 7);
              var index = options.indexOf(current.toString());
              if (index < 0) index = 2;
              final result = await showSelectDialog(
                title: "Backup Interval".tl,
                options: options.map((e) => "@count days".tlParams({'count': e})).toList(),
                initialIndex: index,
              );
              if (result != null) {
                appdata.settings['autoBackupInterval'] =
                    int.parse(options[result]);
                await appdata.saveData();
                await initAutoBackup();
                setState(() {});
              }
            },
            actionTitle: 'Set'.tl,
          ).toSliver(),
        if (App.isAndroid)
          _CallbackSetting(
            title: "Backup Retention".tl,
            subtitle:
                "@count days".tlParams({'count': appdata.settings['autoBackupRetentionDays'] ?? 30}),
            callback: () async {
              final options = ["7", "30", "90", "180", "365"];
              final current =
                  (appdata.settings['autoBackupRetentionDays'] as int? ?? 30);
              var index = options.indexOf(current.toString());
              if (index < 0) index = 1;
              final result = await showSelectDialog(
                title: "Backup Retention".tl,
                options: options
                    .map((e) => "@count days".tlParams({'count': e}))
                    .toList(),
                initialIndex: index,
              );
              if (result != null) {
                appdata.settings['autoBackupRetentionDays'] =
                    int.parse(options[result]);
                await appdata.saveData();
                setState(() {});
              }
            },
            actionTitle: 'Set'.tl,
          ).toSliver(),
        if (App.isAndroid)
          _CallbackSetting(
            title: "Back Up Now".tl,
            callback: () async {
              var controller = showLoadingDialog(context);
              try {
                await performAutoBackup();
                if (context.mounted) {
                  context.showMessage(message: "Backup created".tl);
                }
              } catch (e, s) {
                Log.error("Backup", e.toString(), s);
                if (context.mounted) {
                  context.showMessage(message: "Backup failed".tl);
                }
              } finally {
                controller.close();
              }
            },
            actionTitle: 'Backup'.tl,
          ).toSliver(),
        _SettingPartTitle(
          title: "User".tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedUser, size: 18),
        ),
        if (!App.isLinux)
          _SwitchSetting(
            title: "Authorization Required".tl,
            settingKey: "authorizationRequired",
            onChanged: () async {
              var current = appdata.settings['authorizationRequired'];
              if (current) {
                final auth = LocalAuthentication();
                final bool canAuthenticateWithBiometrics =
                    await auth.canCheckBiometrics;
                final bool canAuthenticate = canAuthenticateWithBiometrics ||
                    await auth.isDeviceSupported();
                if (!canAuthenticate) {
                  context.showMessage(message: "Biometrics not supported".tl);
                  setState(() {
                    appdata.settings['authorizationRequired'] = false;
                  });
                  appdata.saveData();
                  return;
                }
              }
            },
          ).toSliver(),
        if (App.isAndroid)
          _SwitchSetting(
            title: "Exit Confirmation".tl,
            settingKey: "exitConfirm",
            subtitle: "Ask before exiting via back gesture at root".tl,
          ).toSliver(),
      ],
    );
  }
}

/// 「上次使用的存储目录不可用，已临时切换」提示条。
///
/// 目录失效（SAF 授权被收回 / 文件夹被删 / SD 卡卸载）后 App 会切到默认目录，
/// 已下载的漫画随之从界面消失，但文件仍在原目录。这里把这件事说清楚，并给出
/// 「切回原目录 / 另选目录」两条找回路径，避免用户以为数据丢了。
class _StoragePathFallbackBanner extends StatefulWidget {
  const _StoragePathFallbackBanner({required this.onResolved});

  final VoidCallback onResolved;

  @override
  State<_StoragePathFallbackBanner> createState() =>
      _StoragePathFallbackBannerState();
}

class _StoragePathFallbackBannerState
    extends State<_StoragePathFallbackBanner> {
  bool _busy = false;

  /// 纯切换目录，不搬运文件 —— 文件本来就在目标目录里。
  Future<void> _switchTo(String path) async {
    if (_busy) return;
    setState(() => _busy = true);
    String? res;
    try {
      res = await LocalManager().switchPathWithoutMoving(path);
    } catch (e, s) {
      Log.error("Local", "Failed to switch storage path: $e", s);
      res = e.toString();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (res != null) {
      context.showMessage(message: res);
      return;
    }
    context.showMessage(message: "Path set successfully".tl);
    widget.onResolved();
  }

  /// 用户确认「知道了」：丢掉提示，不再打扰。
  void _ignore() {
    LocalManager().clearPathFallback().then((_) {
      if (mounted) widget.onResolved();
    });
  }

  void _startPick() {
    _pickFolder();
  }

  Future<void> _pickFolder() async {
    if (_busy) return;
    String? result;
    if (App.isAndroid) {
      result = (await DirectoryPicker().pickDirectory())?.path;
    } else if (App.isIOS) {
      result = await selectDirectoryIOS();
    } else {
      result = await selectDirectory();
    }
    if (result == null || result.isEmpty) return;
    if (!mounted) return;
    await _switchTo(result);
  }

  @override
  Widget build(BuildContext context) {
    final fallback = LocalManager().pendingPathFallback;
    if (fallback == null) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(kcSpaceSm),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(kcRadius8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedInformationCircle,
                size: 20,
                color: colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Storage path unavailable".tl,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "The folder used last time is no longer accessible, so a temporary folder is in use. Your files are still in the original folder."
                .tl,
            style: TextStyle(
              fontSize: kcCaption,
              color: colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            fallback.originalPath,
            style: TextStyle(
              fontSize: kcCaption,
              color: colorScheme.onErrorContainer,
              fontFamily: "monospace",
            ),
          ),
          const SizedBox(height: 4),
          // 三个按钮在 448dp 宽的手机屏上排成一行会溢出约 15px
          // （"Choose a different folder" 太长），用 Wrap 让它们按需换行。
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: [
              Button.text(
                onPressed: _ignore,
                child: Text("Ignore".tl),
              ),
              Button.text(
                onPressed: _startPick,
                child: Text("Choose a different folder".tl),
              ),
              Button.filled(
                isLoading: _busy,
                onPressed: () => _switchTo(fallback.originalPath),
                child: Text("Use original folder".tl),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  String logLevelToShow = "all";

  @override
  Widget build(BuildContext context) {
    var logToShow = logLevelToShow == "all"
        ? Log.logs
        : Log.logs.where((log) => log.level.name == logLevelToShow).toList();
    return Scaffold(
      // 顶栏玻璃 tint 的基色是 scaffoldBackgroundColor，页面底色必须同源，
      // 用 colorScheme.surface（浅色下 #FAF8FF）会在顶栏下缘留一条分层色带。
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: Appbar(
        title: Text("Logs".tl),
        actions: [
          IconButton(
              onPressed: () => setState(() {
                    final RelativeRect position = RelativeRect.fromLTRB(
                      MediaQuery.of(context).size.width,
                      MediaQuery.of(context).padding.top + kToolbarHeight,
                      0.0,
                      0.0,
                    );
                    showMenu(context: context, position: position, items: [
                      PopupMenuItem(
                          child: Text("all"),
                          onTap: () => setState(() => logLevelToShow = "all")
                      ),
                      PopupMenuItem(
                          child: Text("info"),
                          onTap: () => setState(() => logLevelToShow = "info")
                      ),
                      PopupMenuItem(
                          child: Text("warning"),
                          onTap: () => setState(() => logLevelToShow = "warning")
                      ),
                      PopupMenuItem(
                          child: Text("error"),
                          onTap: () => setState(() => logLevelToShow = "error")
                      ),
                    ]);
              }),
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedFilterHorizontal, size: 18)
          ),
          IconButton(
              onPressed: () => setState(() {
                    final RelativeRect position = RelativeRect.fromLTRB(
                      MediaQuery.of(context).size.width,
                      MediaQuery.of(context).padding.top + kToolbarHeight,
                      0.0,
                      0.0,
                    );
                    showMenu(context: context, position: position, items: [
                      PopupMenuItem(
                        child: Text("Clear".tl),
                        onTap: () => setState(() => Log.clear()),
                      ),
                      PopupMenuItem(
                        child: Text("Disable Length Limitation".tl),
                        onTap: () {
                          Log.ignoreLimitation = true;
                          context.showMessage(
                              message: "Only valid for this run".tl);
                        },
                      ),
                      PopupMenuItem(
                        child: Text("Export".tl),
                        onTap: () => saveLog(Log().toString()),
                      ),
                    ]);
                  }),
              icon: HugeIcon(icon: HugeIcons.strokeRoundedMoreHorizontal, size: 18))
        ],
      ),
      body: ListView.builder(
        reverse: true,
        controller: ScrollController(),
        itemCount: logToShow.length,
        itemBuilder: (context, index) {
          index = logToShow.length - index - 1;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius:
                              const BorderRadius.all(Radius.circular(kcRadius16)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                          child: Text(logToShow[index].title),
                        ),
                      ),
                      const SizedBox(
                        width: 3,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: [
                            Theme.of(context).colorScheme.error,
                            Theme.of(context).colorScheme.errorContainer,
                            kcAccentSurface(context)
                          ][logToShow[index].level.index],
                          borderRadius:
                              const BorderRadius.all(Radius.circular(kcRadius16)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                          child: Text(
                            logToShow[index].level.name,
                            style: TextStyle(
                                color: [
                              Theme.of(context).colorScheme.onError,
                              Theme.of(context).colorScheme.onErrorContainer,
                              kcBrandAdaptive(context)
                            ][logToShow[index].level.index]),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(logToShow[index].content),
                  Text(logToShow[index].time
                      .toString()
                      .replaceAll(RegExp(r"\.\w+"), "")),
                  Button.text(
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: logToShow[index].content));
                    },
                    child: Text("Copy".tl),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void saveLog(String log) async {
    saveFile(data: utf8.encode(log), filename: 'log.txt');
  }
}

class _WebdavSetting extends StatefulWidget {
  const _WebdavSetting();

  @override
  State<_WebdavSetting> createState() => _WebdavSettingState();
}

class _WebdavSettingState extends State<_WebdavSetting> {
  String url = "";
  String user = "";
  String pass = "";
  String disableSync = "";

  bool autoSync = true;

  bool isTesting = false;
  bool upload = true;

  // 输入框 controller（缓存 + dispose，避免 rebuild 丢输入/内存泄漏）
  late final TextEditingController _urlController;
  late final TextEditingController _userController;
  late final TextEditingController _passController;
  late final TextEditingController _disableSyncController;

  @override
  void initState() {
    super.initState();
    if (appdata.settings['webdav'] is! List) {
      appdata.settings['webdav'] = [];
    }
    if (appdata.settings['disableSyncFields'].trim().isNotEmpty) {
      disableSync = appdata.settings['disableSyncFields'];
    }
    var configs = appdata.settings['webdav'] as List;
    if (configs.whereType<String>().length == 3) {
      url = configs[0];
      user = configs[1];
      pass = configs[2];
    }
    autoSync = appdata.implicitData['webdavAutoSync'] ?? true;
    _urlController = TextEditingController(text: url);
    _userController = TextEditingController(text: user);
    _passController = TextEditingController(text: pass);
    _disableSyncController = TextEditingController(text: disableSync);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    _disableSyncController.dispose();
    super.dispose();
  }

  void onAutoSyncChanged(bool value) {
    setState(() {
      autoSync = value;
      appdata.implicitData['webdavAutoSync'] = value;
      appdata.writeImplicitData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: "Webdav".tl,
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "URL".tl,
                hintText: "A valid WebDav directory URL".tl,
                border: OutlineInputBorder(),
              ),
              controller: _urlController,
              onChanged: (value) => url = value,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Username".tl,
                border: const OutlineInputBorder(),
              ),
              controller: _userController,
              onChanged: (value) => user = value,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Password".tl,
                border: const OutlineInputBorder(),
              ),
              controller: _passController,
              onChanged: (value) => pass = value,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Skip Setting Fields (Optional)".tl,
                hintText: "field0, field1, field2, ...",
                hintStyle: TextStyle(color: Theme.of(context).hintColor),
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedHelpCircle, size: 18),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => ContentDialog(
                        title: "Skip Setting Fields".tl,
                        contentPadding: ContentDialog.hPadding,
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "When sync data, skip certain setting fields, which means these won't be uploaded / override.".tl,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    "See source code for available fields.".tl,
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: IconButton(
                                    icon: HugeIcon(icon: HugeIcons.strokeRoundedShare01, size: 18),
                                    onPressed: () {
                                      launchUrlString("https://github.com/venera-app/venera/blob/b08f11f6ac49bd07d34b4fcde233ed07e86efbc9/lib/foundation/appdata.dart#L138");
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              controller: _disableSyncController,
              onChanged: (value) => disableSync = value,
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
              title: Text("Auto Sync Data".tl),
              contentPadding: EdgeInsets.zero,
              trailing: KcSwitch(
                value: autoSync,
                onChanged: onAutoSyncChanged,
              ),
            ),
            const SizedBox(height: 12),
            RadioGroup<bool>(
              groupValue: upload,
              onChanged: (value) {
                setState(() {
                  upload = value ?? upload;
                });
              },
              child: Row(
                children: [
                  Text("Operation".tl),
                  Radio<bool>(
                    value: true,
                  ),
                  Text("Upload".tl),
                  Radio<bool>(
                    value: false,
                  ),
                  Text("Download".tl),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: autoSync
                  ? Container(
                      padding: const EdgeInsets.all(kcSpaceSm),
                      decoration: BoxDecoration(
                        color: kcAccentSurface(context),
                        borderRadius: BorderRadius.circular(kcRadius8),
                      ),
                      child: Row(
                        children: [
                          HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                "Once the operation is successful, app will automatically sync data with the server."
                                    .tl),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            Center(
              child: Button.filled(
                isLoading: isTesting,
                onPressed: () async {
                  var oldConfig = appdata.settings['webdav'];
                  var oldAutoSync = appdata.implicitData['webdavAutoSync'];

                  if (url.trim().isEmpty &&
                      user.trim().isEmpty &&
                      pass.trim().isEmpty) {
                    appdata.settings['webdav'] = [];
                    appdata.implicitData['webdavAutoSync'] = false;
                    appdata.writeImplicitData();
                    appdata.saveData();
                    context.showMessage(message: "Saved".tl);
                    App.rootPop();
                    return;
                  }

                  appdata.settings['webdav'] = [url, user, pass];
                  appdata.settings['disableSyncFields'] = disableSync;
                  appdata.implicitData['webdavAutoSync'] = autoSync;
                  appdata.writeImplicitData();

                  if (!autoSync) {
                    appdata.saveData();
                    context.showMessage(message: "Saved".tl);
                    App.rootPop();
                    return;
                  }

                  setState(() {
                    isTesting = true;
                  });
                  var testResult = upload
                      ? await DataSync().uploadData()
                      : await DataSync().downloadData();
                  if (testResult.error) {
                    setState(() {
                      isTesting = false;
                    });
                    appdata.settings['webdav'] = oldConfig;
                    appdata.implicitData['webdavAutoSync'] = oldAutoSync;
                    appdata.writeImplicitData();
                    appdata.saveData();
                    context.showMessage(message: testResult.errorMessage!);
                    context.showMessage(message: "Saved Failed".tl);
                  } else {
                    appdata.saveData();
                    context.showMessage(message: "Saved".tl);
                    App.rootPop();
                  }
                },
                child: Text("Continue".tl),
              ),
            )
          ],
        ).paddingHorizontal(16),
      ),
    );
  }
}

enum _ConflictChoice { overwrite, merge, cancel }

const _fileSuffixChars = "abcdefghijklmnopqrstuvwxyz0123456789";

String _randomFileSuffix() {
  final rand = Random.secure();
  return List.generate(6, (_) => _fileSuffixChars[rand.nextInt(_fileSuffixChars.length)]).join();
}

class _StorageConflictDialog extends StatelessWidget {
  const _StorageConflictDialog({
    required this.existingCount,
    required this.newPath,
  });

  final int existingCount;
  final String newPath;

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: "Destination is not empty".tl,
      contentPadding: ContentDialog.hPadding,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "The selected folder already contains %d file(s). How do you want to proceed?"
                .tl
                .replaceAll("%d", "$existingCount"),
          ).paddingBottom(8),
          Text(
            newPath,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: kcCaption,
              color: context.colorScheme.onSurfaceVariant,
              fontFamily: "monospace",
            ),
          ).paddingBottom(12),
          Text(
            "Overwrite".tl,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            "Move your library and replace any files with the same name.".tl,
            style: TextStyle(
              fontSize: kcCaption,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ).paddingBottom(8),
          Text(
            "Merge".tl,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            "Move your library and skip files that already exist.".tl,
            style: TextStyle(
              fontSize: kcCaption,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        Button.text(
          onPressed: () => context.pop(_ConflictChoice.cancel),
          child: Text("Cancel".tl),
        ),
        Button.text(
          onPressed: () => context.pop(_ConflictChoice.merge),
          child: Text("Merge".tl),
        ),
        Button.filled(
          onPressed: () => context.pop(_ConflictChoice.overwrite),
          child: Text("Overwrite".tl),
        ),
      ],
    );
  }
}

/// 导入备份时，若检测到与本地数据重复，询问用户「覆盖」还是「合并」。
Future<_ConflictChoice?> _showImportModeDialog(BuildContext context) async {
  return showDialog<_ConflictChoice?>(
    context: context,
    builder: (ctx) => _ImportConflictDialog(),
  );
}

class _ImportConflictDialog extends StatelessWidget {
  const _ImportConflictDialog();

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: "Duplicate data found".tl,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "The backup contains comics or reading history that already exist on this device. How do you want to import?"
                .tl,
          ).paddingBottom(16),
          Text(
            "Overwrite".tl,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            "Replace all local data with the backup. Current data will be lost."
                .tl,
            style: TextStyle(
              fontSize: kcCaption,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ).paddingBottom(8),
          Text(
            "Merge".tl,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            "Keep local data and append only the items missing from the backup."
                .tl,
            style: TextStyle(
              fontSize: kcCaption,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ).paddingHorizontal(20).paddingVertical(4),
      actions: [
        Button.text(
          onPressed: () => context.pop(_ConflictChoice.cancel),
          child: Text("Cancel".tl),
        ),
        Button.text(
          onPressed: () => context.pop(_ConflictChoice.merge),
          child: Text("Merge".tl),
        ),
        Button.filled(
          onPressed: () => context.pop(_ConflictChoice.overwrite),
          child: Text("Overwrite".tl),
        ),
      ],
    );
  }
}
