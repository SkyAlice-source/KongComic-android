part of 'settings_page.dart';

/// APP 设置的分段。
///
/// 原来「通用设置」一页 17 行、5 组（语言/启动、存储、缓存、备份同步、用户），
/// 一屏放不下。根页按「应用本身」与「数据」拆成两页：应用页管语言、启动页、
/// 存储与缓存；数据页管导入导出、自动备份、WebDAV 同步与账号相关。
enum AppSettingsSection {
  /// 全部（未拆分的旧入口）。
  all,

  /// 语言与启动 + 存储 + 缓存。
  app,

  /// 备份与同步 + 用户。
  data,
}

class AppSettings extends StatefulWidget {
  const AppSettings({super.key, this.section = AppSettingsSection.all});

  final AppSettingsSection section;

  String get title => switch (section) {
    AppSettingsSection.app => "App & storage",
    AppSettingsSection.data => "Data & backup",
    AppSettingsSection.all => "APP",
  };

  @override
  State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  /// 把存储路径切到公共 Download/Comic 与权限入口已抽到 permissions.dart，
  /// 与「权限」分类共用同一份实现：两边各写一份必然会分叉。

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
          Button.filled(onPressed: () => ctx.pop(true), child: Text("Move".tl)),
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
    final showApp = widget.section != AppSettingsSection.data;
    final showData = widget.section != AppSettingsSection.app;
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text(widget.title.tl)),
        // 「语言与启动」：与数据无关、也不属于任何权限的应用级偏好。
        // 语言从「外观」挪过来 —— 它不影响任何视觉样式，放在主题页里会让人
        // 以为「改语言=换外观」。不叫「通用」是因为本分类在中文里已经叫
        // 「通用设置」，组内再出现一个「通用」会有两层同名。
        if (showApp) ...[
          _SettingPartTitle(
            title: "Language & startup".tl,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings02, size: 18),
          ),
          SelectSetting(
            title: "Initial Page".tl,
            settingKey: "initialPage",
            // 取值必须与 main_page.dart 的 `_pages` 下标一一对应
            // （0 分类 / 1 收藏 / 2 主页 / 3 发现 / 4 历史）。以前少了「历史」，
            // 5 个 tab 里唯一不能当初始页的就是它。
            optionTranslation: {
              '0': "Categories".tl,
              '1': "Favorites".tl,
              '2': "Home".tl,
              '3': "Explore".tl,
              '4': "History".tl,
            },
          ).toSliver(),
          SelectSetting(
            title: "Language".tl,
            settingKey: "language",
            optionTranslation: {
              "system": "System",
              "zh-CN": "Simplified Chinese",
              "zh-TW": "Traditional Chinese",
              "ja-JP": "Japanese",
              "en-US": "English",
            },
            onChanged: () async {
              App.forceRebuild();
              // 关闭设置页后重新打开，让语言立即生效。
              //
              // 不能只看 `Navigator.canPop()`：那判断的是「本页所在 Navigator
              // 的路由栈里还有没有别的路由」，而宽屏双栏时设置页自己就是被
              // push 进 tab Navigator 的，canPop 恒为 true —— 切个语言会把
              // 整个设置页关掉。真正的判据是本页有没有被 `_SettingsDetailPage`
              // 包着（只有窄屏才走那条路由，宽屏是内联渲染）。
              if (!context.mounted) return;
              final inline =
                  context.findAncestorWidgetOfExactType<_SettingsDetailPage>() ==
                  null;
              if (!inline) Navigator.of(context).pop();
            },
          ).toSliver(),
          // 「数据」以前是 13 行一个组：存储、缓存、导入导出、备份、云同步全塞在
          // 同一个标题下，等于没分组。按用途拆成四段后，「改路径」「清缓存」
          // 「备份」「更新源」各自有归属，找的时候不用整段扫。
          if (App.isAndroid)
            _SwitchSetting(
              title: "Exit Confirmation".tl,
              settingKey: "exitConfirm",
              subtitle: "Ask before exiting via back gesture at root".tl,
            ).toSliver(),
          _SettingPartTitle(
            title: "Storage".tl,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedFolder01, size: 18),
          ),
          _KcSettingTile(
            title: Text("Storage Path for local comics".tl),
            // 路径很长：基座里的副标题统一做单行省略，避免被硬裁到半截。
            subtitle: LocalManager().path,
            subtitleMaxLines: 1,
            trailing: IconButton(
              tooltip: "Copy".tl,
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
              final changed = await setStoragePathWithPrompt(context, result);
              if (changed && mounted) setState(() {});
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
          _SettingPartTitle(
            title: "Cache".tl,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedDatabase, size: 18),
          ),
          // 所有与系统授权相关的项（存储访问、通知、后台运行、安装未知应用）都已
          // 迁到独立的「权限」分类：它们和存储路径、缓存大小不是一类东西，夹在
          // 这里时用户既找不到，也没法一处看全。
          //
          // 「缓存大小」不再是单独一行：它是一块只读信息，和「清缓存」讲的是
          // 同一件事，合成一行后少一次上下对照。
          _CallbackSetting(
            title: "Clear Cache".tl,
            subtitle: "Used @size".tlParams({
              'size': bytesToReadableString(CacheManager().currentSize),
            }),
            actionTitle: "Clear".tl,
            callback: () async {
              var loadingDialog = showLoadingDialog(
                App.rootContext,
                barrierDismissible: false,
                allowCancel: false,
              );
              // 这个框既不能点外部关闭也没有取消按钮：clear() 一旦抛 IO 异常
              // （缓存目录被占用 / 权限异常），不兜住就永远挂在屏幕上出不去。
              try {
                await CacheManager().clear();
              } catch (e, s) {
                Log.error("Cache", "Failed to clear cache: $e", s);
                if (mounted) {
                  context.showMessage(message: friendlyError(e));
                }
                return;
              } finally {
                loadingDialog.close();
              }
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
        ],
        if (showData) ...[
          _SettingPartTitle(
            title: "Backup & sync".tl,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedCloudBackup, size: 18),
          ),
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
                // 导出是长耗时操作，用户可能已经离开设置页；对已卸载的 Element
                // 查祖先 Overlay 会在 debug 下触发断言、release 下静默丢提示。
                if (context.mounted) {
                  context.showMessage(message: "Failed to export data".tl);
                }
              } finally {
                controller.close();
              }
            },
            actionTitle: 'Export'.tl,
          ).toSliver(),
          _CallbackSetting(
            title: "Import App Data".tl,
            callback: () async {
              var file = await selectFile(
                ext: ['kongcomic', 'venera', 'picadata'],
              );
              // 系统文件选择器可能开很久，回来时本页可能已经不在树上。
              if (!context.mounted) return;
              if (file != null) {
                var controller = showLoadingDialog(context);
                var cacheFile = File(
                  FilePath.join(App.cachePath, "import_data_temp"),
                );
                var needRestart = false;
                var cancelled = false;
                try {
                  await file.saveTo(cacheFile.path);
                  if (file.name.endsWith('picadata')) {
                    await importPicaData(cacheFile);
                  } else {
                    var hasDuplicates = await importHasDuplicates(cacheFile);
                    if (hasDuplicates) {
                      if (!context.mounted) return;
                      var choice = await _showImportModeDialog(context);
                      if (choice == null || choice == _ConflictChoice.cancel) {
                        cancelled = true;
                        context.showMessage(message: "Import cancelled".tl);
                      } else {
                        needRestart = await importAppData(
                          cacheFile,
                          false,
                          choice == _ConflictChoice.merge,
                        );
                      }
                    } else {
                      needRestart = await importAppData(cacheFile);
                    }
                  }
                } catch (e, s) {
                  Log.error("Import data", e.toString(), s);
                  if (context.mounted) {
                    context.showMessage(message: "Failed to import data".tl);
                  }
                } finally {
                  controller.close();
                  cacheFile.deleteIgnoreError();
                  App.forceRebuild();
                }
                if (cancelled) {
                  // 已显示取消提示，无需额外反馈
                } else if (needRestart && context.mounted) {
                  context.showMessage(
                    message: "Restart app to complete data import".tl,
                  );
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
              subtitle:
                  "Periodically back up your data to the Download folder".tl,
              onChanged: () async {
                await initAutoBackup();
                if (!mounted) return;
                setState(() {});
              },
            ).toSliver(),
          if (App.isAndroid)
            _SwitchSetting(
              title: "Auto-update comic sources".tl,
              settingKey: 'autoUpdateSourcesEnabled',
              subtitle:
                  "Automatically update installed sources on WiFi. Overrides local source edits."
                      .tl,
              onChanged: () => setState(() {}),
            ).toSliver(),
          // 间隔 / 保留时长只在自动备份打开时才有意义：关着的时候它们是两个
          // 永远用不上的「Set」，白占两行还让人以为备份在跑。
          if (App.isAndroid && appdata.settings['autoBackupEnabled'] == true)
            _CallbackSetting(
              title: "Backup Interval".tl,
              subtitle: "@count days".tlParams({
                'count': appdata.settings['autoBackupInterval'] ?? 7,
              }),
              callback: () async {
                final options = ["1", "3", "7", "14", "30"];
                // 不能 `as int?`：备份导入 / 同步过来的 JSON 数字常是 double，
                // 强转会在点「Set」的瞬间抛类型错误（subtitle 不用强转所以正常，
                // 表现为「显示 7 天，一戳就崩」）。
                final rawCurrent = appdata.settings['autoBackupInterval'];
                final current = rawCurrent is num
                    ? rawCurrent.toInt()
                    : (int.tryParse('$rawCurrent') ?? 7);
                var index = options.indexOf(current.toString());
                if (index < 0) index = 2;
                final result = await showSelectDialog(
                  title: "Backup Interval".tl,
                  options: options
                      .map((e) => "@count days".tlParams({'count': e}))
                      .toList(),
                  initialIndex: index,
                );
                if (result != null) {
                  appdata.settings['autoBackupInterval'] = int.parse(
                    options[result],
                  );
                  await appdata.saveData();
                  await initAutoBackup();
                  if (!mounted) return;
                  setState(() {});
                }
              },
              actionTitle: 'Set'.tl,
            ).toSliver(),
          if (App.isAndroid && appdata.settings['autoBackupEnabled'] == true)
            _CallbackSetting(
              title: "Backup Retention".tl,
              subtitle: "@count days".tlParams({
                'count': appdata.settings['autoBackupRetentionDays'] ?? 30,
              }),
              callback: () async {
                final options = ["7", "30", "90", "180", "365"];
                final rawCurrent = appdata.settings['autoBackupRetentionDays'];
                final current = rawCurrent is num
                    ? rawCurrent.toInt()
                    : (int.tryParse('$rawCurrent') ?? 30);
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
                  appdata.settings['autoBackupRetentionDays'] = int.parse(
                    options[result],
                  );
                  await appdata.saveData();
                  if (!mounted) return;
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
          _CallbackSetting(
            title: "Cloud Sync".tl,
            subtitle:
                "Sync data across devices via WebDAV (Nextcloud, etc.)".tl,
            callback: () {
              context.to(() => const _WebdavSetting());
            },
            actionTitle: 'Set'.tl,
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
                  // canCheckBiometrics / isDeviceSupported 在部分 ROM 上会抛
                  // PlatformException。以前不接，异常逃到 zone 里被吞掉，开关
                  // 停在「开」但根本没校验过设备能否认证 —— 下次启动直接卡在
                  // 锁屏页。这里按「不可用」处理，并把开关拨回去。
                  bool canAuthenticate;
                  try {
                    final auth = LocalAuthentication();
                    canAuthenticate =
                        await auth.canCheckBiometrics ||
                        await auth.isDeviceSupported();
                  } catch (e, s) {
                    Log.error(
                      "Auth",
                      "Failed to query biometric capability: $e",
                      s,
                    );
                    canAuthenticate = false;
                  }
                  if (!mounted) return;
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
        ],
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

  /// 用户确认「知道了」：接受当前目录，不再打扰。
  void _ignore() {
    LocalManager().acceptCurrentPath().then((_) {
      if (mounted) widget.onResolved();
    });
  }

  /// 「移动到这里」：把原文件夹的内容搬进当前存储路径。
  ///
  /// 会清空原文件夹，属于不可逆操作（复制成功后才清），所以先弹一次确认，
  /// 把「从哪搬到哪」写清楚 —— 提示条上只给了路径，没有明确说搬完旧的就没了。
  void _adoptOriginalFiles() {
    if (_busy) return;
    final pending = LocalManager().pendingPathFallback;
    if (pending == null) return;
    showConfirmDialog(
      context: context,
      title: "Move files here?".tl,
      content:
          "Files in @old will be copied to @new, then the old folder will be emptied."
              .tlParams({
                'old': pending.originalPath,
                'new': LocalManager().path,
              }),
      confirmText: "Move here",
      onConfirm: _doAdopt,
    );
  }

  Future<void> _doAdopt() async {
    if (_busy) return;
    setState(() => _busy = true);
    String? res;
    try {
      res = await LocalManager().adoptOriginalFiles();
    } catch (e, s) {
      Log.error("Local", "Failed to move files into storage path: $e", s);
      res = e.toString();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (res != null) {
      context.showMessage(message: res);
      return;
    }
    context.showMessage(message: "Files moved".tl);
    widget.onResolved();
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
    // 仍在用临时目录 / 用户已经换到别的目录，是两种不同的处境：后者再说
    // 「正在使用临时文件夹」就不对了，得提醒他原目录的文件并没有跟过来。
    final usingFallbackPath = LocalManager().path == fallback.fallbackPath;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: kcSpaceLg, vertical: kcSpaceXs),
      padding: const EdgeInsets.all(kcSpaceSm),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        // 与设置页其它卡片同档圆角：8dp 在这张「一屏里最显眼的红卡片」上
        // 会显得方，和 16dp 的输入框、12dp 的卡片都不搭。
        borderRadius: BorderRadius.circular(kcCardRadius),
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
            (usingFallbackPath
                    ? "The folder used last time is no longer accessible, so a temporary folder is in use. Your files are still in the original folder."
                    : "The storage path has changed. Files in the previous folder were not moved here.")
                .tl,
            style: TextStyle(
              fontSize: kcCaption,
              color: colorScheme.onErrorContainer,
            ),
          ),
          // 原路径为空（记录损坏 / 早期的异常数据）时不展示：一行空白既没信息量，
          // 又会让人以为「路径就是空的」，下面的「找回」按钮同样无从下手。
          if (fallback.originalPath.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              fallback.originalPath,
              style: TextStyle(
                fontSize: kcCaption,
                color: colorScheme.onErrorContainer,
                fontFamily: "monospace",
              ),
            ),
            const SizedBox(height: 6),
            // 「接下来该怎么办」——过去只有三个按钮，每个都跟「文件夹」有关，
            // 用户看完并不知道点哪个才能把书找回来。这里先用一句话把两条路径
            // 摊开，再由下面的按钮各自对应。
            Text(
              "Move the files into the new folder to keep using it, or switch back to the original one."
                  .tl,
              style: TextStyle(
                fontSize: kcCaption,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ],
          const SizedBox(height: 4),
          // 四个按钮在 448dp 宽的手机屏上排成一行会溢出约 15px
          // （"Choose a different folder" 太长），用 Wrap 让它们按需换行。
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              Button.text(onPressed: _ignore, child: Text("Ignore".tl)),
              Button.text(
                onPressed: _startPick,
                child: Text("Choose a different folder".tl),
              ),
              // 两个「回到原路径」的动作只在原路径有效时才有意义。
              if (fallback.originalPath.isNotEmpty) ...[
                Button.outlined(
                  isLoading: _busy,
                  onPressed: () => _switchTo(fallback.originalPath),
                  child: Text("Use original folder".tl),
                ),
                // 主操作：真正把旧文件搬进当前路径。之前这条需求缺入口 —— 想
                // 「留在新路径」只能先切回原目录、再重新选一次目录绕一圈。
                Button.filled(
                  isLoading: _busy,
                  onPressed: _adoptOriginalFiles,
                  child: Text("Move here".tl),
                ),
              ],
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
            tooltip: "Filter".tl,
            onPressed: () => setState(() {
              final RelativeRect position = RelativeRect.fromLTRB(
                MediaQuery.of(context).size.width,
                MediaQuery.of(context).padding.top + kToolbarHeight,
                0.0,
                0.0,
              );
              showMenu(
                context: context,
                position: position,
                items: [
                  PopupMenuItem(
                    child: Text("all"),
                    onTap: () => setState(() => logLevelToShow = "all"),
                  ),
                  PopupMenuItem(
                    child: Text("info"),
                    onTap: () => setState(() => logLevelToShow = "info"),
                  ),
                  PopupMenuItem(
                    child: Text("warning"),
                    onTap: () => setState(() => logLevelToShow = "warning"),
                  ),
                  PopupMenuItem(
                    child: Text("error"),
                    onTap: () => setState(() => logLevelToShow = "error"),
                  ),
                ],
              );
            }),
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedFilterHorizontal,
              size: 18,
            ),
          ),
          IconButton(
            tooltip: "More".tl,
            onPressed: () => setState(() {
              final RelativeRect position = RelativeRect.fromLTRB(
                MediaQuery.of(context).size.width,
                MediaQuery.of(context).padding.top + kToolbarHeight,
                0.0,
                0.0,
              );
              showMenu(
                context: context,
                position: position,
                items: [
                  PopupMenuItem(
                    child: Text("Clear".tl),
                    onTap: () => setState(() => Log.clear()),
                  ),
                  PopupMenuItem(
                    child: Text("Disable Length Limitation".tl),
                    onTap: () {
                      Log.ignoreLimitation = true;
                      context.showMessage(
                        message: "Only valid for this run".tl,
                      );
                    },
                  ),
                  PopupMenuItem(
                    child: Text("Export".tl),
                    onTap: () => saveLog(Log().toString()),
                  ),
                ],
              );
            }),
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedMoreHorizontal,
              size: 18,
            ),
          ),
        ],
      ),
      body: ListView.builder(
        reverse: true,
        itemCount: logToShow.length,
        itemBuilder: (context, index) {
          index = logToShow.length - index - 1;
          return Padding(
            padding: const EdgeInsets.fromLTRB(kcSpaceLg, 0, kcSpaceLg, kcSpaceSm),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(kcRadius16),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                          child: Text(logToShow[index].title),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Container(
                        decoration: BoxDecoration(
                          color: [
                            Theme.of(context).colorScheme.error,
                            Theme.of(context).colorScheme.errorContainer,
                            kcAccentSurface(context),
                          ][logToShow[index].level.index],
                          borderRadius: const BorderRadius.all(
                            Radius.circular(kcRadius16),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                          child: Text(
                            logToShow[index].level.name,
                            style: TextStyle(
                              color: [
                                Theme.of(context).colorScheme.onError,
                                Theme.of(context).colorScheme.onErrorContainer,
                                kcBrandAdaptive(context),
                              ][logToShow[index].level.index],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(logToShow[index].content),
                  Text(
                    logToShow[index].time.toString().replaceAll(
                      RegExp(r"\.\w+"),
                      "",
                    ),
                  ),
                  Button.text(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: logToShow[index].content),
                      );
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
    // 直接 `.trim()` 会在值被导入成 null / 非字符串时抛 NoSuchMethodError，
    // 整个 WebDAV 页打不开且没有恢复入口。
    final rawDisable = appdata.settings['disableSyncFields'];
    if (rawDisable is String && rawDisable.trim().isNotEmpty) {
      disableSync = rawDisable;
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
              decoration: kcInputDecoration(
                context,
                labelText: "URL".tl,
                hintText: "A valid WebDav directory URL".tl,
              ),
              controller: _urlController,
              onChanged: (value) => url = value,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: kcInputDecoration(context, labelText: "Username".tl),
              controller: _userController,
              onChanged: (value) => user = value,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: kcInputDecoration(context, labelText: "Password".tl),
              controller: _passController,
              onChanged: (value) => pass = value,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: kcInputDecoration(
                context,
                labelText: "Skip Setting Fields (Optional)".tl,
                hintText: "field0, field1, field2, ...",
                suffixIcon: IconButton(
                  tooltip: "Help".tl,
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedHelpCircle,
                    size: 18,
                  ),
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
                              "When sync data, skip certain setting fields, which means these won't be uploaded / override."
                                  .tl,
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
                                    tooltip: "Open Link".tl,
                                    icon: HugeIcon(
                                      icon: HugeIcons.strokeRoundedShare01,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      launchUrlString(
                                        "https://github.com/venera-app/venera/blob/b08f11f6ac49bd07d34b4fcde233ed07e86efbc9/lib/foundation/appdata.dart#L138",
                                      );
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
            KcListTile(
              showDivider: false,
              contentPadding: EdgeInsets.zero,
              leading: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
              title: Text("Auto Sync Data".tl),
              trailing: KcSwitch(value: autoSync, onChanged: onAutoSyncChanged),
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
                  Radio<bool>(value: true),
                  Text("Upload".tl),
                  Radio<bool>(value: false),
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
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedInformationCircle,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Once the operation is successful, app will automatically sync data with the server."
                                  .tl,
                            ),
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
                  // 「跳过同步字段」也在下面被提前写进 settings，测试失败时同样要
                  // 回滚 —— 否则用户填错密码点一次 Continue，就被静默改掉一批
                  // 不同步的字段，而且这回滚前的值已经被 saveData 写盘了。
                  final oldDisableSync = appdata.settings['disableSyncFields'];

                  if (url.trim().isEmpty &&
                      user.trim().isEmpty &&
                      pass.trim().isEmpty) {
                    appdata.settings['webdav'] = [];
                    appdata.implicitData['webdavAutoSync'] = false;
                    appdata.writeImplicitData();
                    appdata.saveData();
                    context.showMessage(message: "Saved".tl);
                    context.pop();
                    return;
                  }

                  appdata.settings['webdav'] = [url, user, pass];
                  appdata.settings['disableSyncFields'] = disableSync;
                  appdata.implicitData['webdavAutoSync'] = autoSync;
                  appdata.writeImplicitData();

                  if (!autoSync) {
                    appdata.saveData();
                    context.showMessage(message: "Saved".tl);
                    context.pop();
                    return;
                  }

                  setState(() {
                    isTesting = true;
                  });
                  var testResult = upload
                      ? await DataSync().uploadData()
                      : await DataSync().downloadData();
                  if (!mounted) return;
                  if (testResult.error) {
                    final restoredDisableSync = oldDisableSync is String
                        ? oldDisableSync
                        : '';
                    setState(() {
                      isTesting = false;
                      disableSync = restoredDisableSync;
                      _disableSyncController.text = restoredDisableSync;
                    });
                    appdata.settings['webdav'] = oldConfig;
                    appdata.settings['disableSyncFields'] = oldDisableSync;
                    appdata.implicitData['webdavAutoSync'] = oldAutoSync;
                    appdata.writeImplicitData();
                    appdata.saveData();
                    context.showMessage(
                      message: friendlyError(testResult.errorMessage ?? ""),
                    );
                    context.showMessage(message: "Saved Failed".tl);
                  } else {
                    appdata.saveData();
                    context.showMessage(message: "Saved".tl);
                    context.pop();
                  }
                },
                child: Text("Continue".tl),
              ),
            ),
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
  return List.generate(
    6,
    (_) => _fileSuffixChars[rand.nextInt(_fileSuffixChars.length)],
  ).join();
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
          Text("Overwrite".tl, style: TextStyle(fontWeight: FontWeight.bold)),
          Text(
            "Move your library and replace any files with the same name.".tl,
            style: TextStyle(
              fontSize: kcCaption,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ).paddingBottom(8),
          Text("Merge".tl, style: TextStyle(fontWeight: FontWeight.bold)),
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
          Text("Merge".tl, style: const TextStyle(fontWeight: FontWeight.bold)),
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
