part of 'settings_page.dart';

class AppSettings extends StatefulWidget {
  const AppSettings({super.key});

  @override
  State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
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
    var res = await manager.setNewPath(result, overwrite: overwrite);
    loadingDialog.close();
    if (!mounted) return;
    if (res != null) {
      context.showMessage(message: res);
    } else {
      context.showMessage(message: "Path set successfully".tl);
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
        ListTile(
          title: Text("Storage Path for local comics".tl),
          subtitle: Text(LocalManager().path, softWrap: false),
          trailing: IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: LocalManager().path));
              context.showMessage(message: "Path copied to clipboard".tl);
            },
          ),
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
          title: "Move to Download/Comic".tl,
          actionTitle: "Move".tl,
          callback: () async {
            final manager = LocalManager();
            final target = await manager.detectDownloadComicPath();
            if (!mounted) return;
            if (target == null) {
              context.showMessage(
                message:
                    "Need all-files access permission to use Download/Comic".tl,
              );
              return;
            }
            if (manager.path == target) {
              context.showMessage(
                message: "Already using Download/Comic".tl,
              );
              return;
            }
            await _setStoragePath(target);
          },
        ).toSliver(),
        ListTile(
          title: Text("Cache Size".tl),
          subtitle: Text(bytesToReadableString(CacheManager().currentSize)),
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
          _CallbackSetting(
            title: "Backup Interval".tl,
            subtitle:
                "${appdata.settings['autoBackupInterval'] ?? 7} @days".tl,
            callback: () async {
              final options = ["1", "3", "7", "14", "30"];
              final current =
                  (appdata.settings['autoBackupInterval'] as int? ?? 7);
              var index = options.indexOf(current.toString());
              if (index < 0) index = 2;
              final result = await showSelectDialog(
                title: "Backup Interval".tl,
                options: options.map((e) => "$e @days".tl).toList(),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                              const BorderRadius.all(Radius.circular(16)),
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
                            Theme.of(context).colorScheme.primaryContainer
                          ][logToShow[index].level.index],
                          borderRadius:
                              const BorderRadius.all(Radius.circular(16)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                          child: Text(
                            logToShow[index].level.name,
                            style: TextStyle(
                                color: [
                              Theme.of(context).colorScheme.onError,
                              Theme.of(context).colorScheme.onErrorContainer,
                              Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer
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
                  TextButton(
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
                      builder: (_) => AlertDialog(
                        title: Text("Skip Setting Fields".tl),
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
              trailing: Switch(
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
                        color: Theme.of(context).colorScheme.primaryContainer,
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
