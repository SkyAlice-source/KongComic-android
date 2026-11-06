part of 'settings_page.dart';

/// 打开「所有文件访问」的授权入口，返回是否已经拿到权限。
///
/// Android 10 及以下先走运行时授权框；Android 11+ 没有申请接口，只能跳系统
/// 设置页。原生侧会逐级降级尝试三个页面，全都打不开（极少数定制 ROM）时给一句
/// 可见提示 —— 否则用户点完按钮只会觉得「点了没反应」。
Future<bool> openStoragePermission(BuildContext context) async {
  var granted = await LocalManager.requestStoragePermission();
  if (!context.mounted) return granted;
  if (granted) return true;
  final opened = await LocalManager.openAllFilesAccessSettings();
  if (!context.mounted || opened) return false;
  context.showMessage(
    message:
        "Cannot open system settings. Please grant the permission manually.".tl,
  );
  return false;
}

/// 把存储路径切到 [path]：冲突检测 → 弹窗选择覆盖/合并 → 复制 + 删旧。
///
/// 返回是否真的切换成功。调用方据此决定要不要刷新界面（路径行、缓存大小等
/// 都直接读 `LocalManager()`，不重建就不会变）。
Future<bool> setStoragePathWithPrompt(BuildContext context, String path) async {
  if (path.isEmpty) return false;
  if (!context.mounted) return false;
  final manager = LocalManager();
  final existingCount = await manager.countConflicts(path);
  bool overwrite = true;
  if (existingCount > 0) {
    final choice = await showDialog<_ConflictChoice>(
      context: context,
      builder: (ctx) =>
          _StorageConflictDialog(existingCount: existingCount, newPath: path),
    );
    if (choice == null || choice == _ConflictChoice.cancel) return false;
    overwrite = choice == _ConflictChoice.overwrite;
  }
  if (!context.mounted) return false;
  var loadingDialog = showLoadingDialog(
    App.rootContext,
    barrierDismissible: false,
    allowCancel: false,
  );
  // The dialog has no cancel button and cannot be dismissed, so any throw out
  // of `setNewPath` (isolate work, file IO) would strand it on screen forever.
  String? res;
  try {
    res = await manager.setNewPath(path, overwrite: overwrite);
  } catch (e) {
    if (context.mounted) {
      // 用户可见提示统一走 friendlyError：底层异常（IO / isolate）直接
      // toString 会在中文界面里冒出整条英文技术串。
      context.showMessage(message: friendlyError(e));
    }
    return false;
  } finally {
    loadingDialog.close();
  }
  if (!context.mounted) return res == null;
  if (res != null) {
    context.showMessage(message: res);
    return false;
  }
  context.showMessage(message: "Path set successfully".tl);
  return true;
}

/// 把存储路径切到公共 `Download/Comic`，返回是否切换成功。
///
/// 授予「所有文件访问」本身不会改变当前路径（默认路径只在首次启动时探测一次），
/// 所以必须有这个显式入口，否则用户开了权限却看不到任何变化。
Future<bool> useDownloadComicFolder(BuildContext context) async {
  final target = await LocalManager().detectDownloadComicPath();
  if (!context.mounted) return false;
  if (target == null) {
    // 没有「所有文件访问」时探测注定失败。只弹一句「无法使用 Download/Comic」
    // 等于死路：用户不知道要开哪个权限、去哪里开。
    if (!await LocalManager.hasAllFilesAccess()) {
      if (!context.mounted) return false;
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => ContentDialog(
          title: "All files access".tl,
          content: Text(
            "All files access is required to use the public Download/Comic folder."
                .tl,
          ),
          actions: [
            Button.text(
              onPressed: () => ctx.pop(false),
              child: Text("Cancel".tl),
            ),
            Button.filled(
              onPressed: () => ctx.pop(true),
              child: Text("Open settings".tl),
            ),
          ],
        ),
      );
      if (open == true) await openStoragePermission(context);
      return false;
    }
    if (context.mounted) {
      context.showMessage(message: "Cannot use the Download/Comic folder".tl);
    }
    return false;
  }
  if (await LocalManager().isSameAsCurrentPath(target)) {
    if (context.mounted) {
      context.showMessage(message: "Already in current storage path".tl);
    }
    return false;
  }
  if (!context.mounted) return false;
  return setStoragePathWithPrompt(context, target);
}

/// 系统权限页。
///
/// 这几项彼此无关，但排查「功能为什么没生效」时永远是同一批：漫画写不进去、
/// 通知收不到、后台任务被系统掐掉、更新装不上。以前它们散在 APP 的「数据」分组
/// 里，夹在存储路径和缓存大小之间 —— 用户既找不到，也没法一处看全。
class PermissionsSettings extends StatefulWidget {
  const PermissionsSettings({super.key});

  @override
  State<PermissionsSettings> createState() => _PermissionsSettingsState();
}

class _PermissionsSettingsState extends State<PermissionsSettings>
    with WidgetsBindingObserver {
  /// 均为 null 表示「还没查到」：首帧不渲染状态，避免闪一下「未授予」再跳成
  /// 「已授予」。查不到（非 Android）时直接按已授予处理。
  bool? _allFilesAccess;
  bool? _notificationsAllowed;
  bool? _batteryUnrestricted;
  bool? _canInstall;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置页返回后必须重新取一次：这些开关没有回调，只能靠回前台补查。
    if (state == AppLifecycleState.resumed) _loadAll();
  }

  Future<void> _loadAll() async {
    if (!App.isAndroid) {
      if (!mounted) return;
      setState(() {
        _allFilesAccess = true;
        _notificationsAllowed = true;
        _batteryUnrestricted = true;
        _canInstall = true;
      });
      return;
    }
    final results = await Future.wait<bool>([
      LocalManager.hasAllFilesAccess(),
      AppNotifications.isAllowed,
      AppPower.isIgnoringBatteryOptimizations,
      App.canRequestPackageInstalls,
    ]);
    if (!mounted) return;
    setState(() {
      _allFilesAccess = results[0];
      _notificationsAllowed = results[1];
      _batteryUnrestricted = results[2];
      _canInstall = results[3];
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Permissions".tl)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(kcRowInsetH, kcSpaceMd, kcRowInsetH, kcSpace6),
            child: Text(
              "These permissions are optional. Denying one only affects the matching feature - the app itself keeps working."
                  .tl,
              style: TextStyle(
                fontSize: kcCaption,
                height: 1.45,
                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
        if (!App.isAndroid)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                kcRowInsetH,
                8,
                kcRowInsetH,
                8,
              ),
              child: Text(
                "This platform does not require any of these permissions.".tl,
                style: TextStyle(
                  fontSize: kcSubtitle,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        if (App.isAndroid) ...[
          _SettingPartTitle(
            title: "Storage access".tl,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedFolder01, size: 18),
          ),
          _CallbackSetting(
            title: "All files access".tl,
            subtitle: _allFilesAccess == null
                ? null
                : (_allFilesAccess!
                      ? "Granted".tl
                      : "Required only to use the public Download/Comic folder"
                            .tl),
            actionTitle: "Open".tl,
            callback: () async {
              final granted = await openStoragePermission(context);
              if (!mounted || !granted) return;
              await _loadAll();
            },
          ).toSliver(),
          // 只有拿到权限才显示：没有权限时这一行点下去必然失败，等于给用户
          // 摆一个死按钮。授权后原地出现，正好是「下一步该做什么」。
          if (_allFilesAccess == true)
            _CallbackSetting(
              title: "Use Download/Comic".tl,
              subtitle:
                  "Switch the storage path to the public Download/Comic folder"
                      .tl,
              actionTitle: "Switch".tl,
              callback: () async {
                final switched = await useDownloadComicFolder(context);
                if (!mounted || !switched) return;
                setState(() {});
              },
            ).toSliver(),
          _SettingPartTitle(
            title: "System permissions".tl,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedShieldKey, size: 18),
          ),
          _CallbackSetting(
            title: "Notifications".tl,
            subtitle: _notificationsAllowed == null
                ? null
                : (_notificationsAllowed! ? "Granted".tl : "Turned off".tl),
            actionTitle: "Open".tl,
            callback: () async {
              // 还没授权时先弹一次系统授权框（Android 13+ 只有在「从未问过」
              // 时才会弹）。直接把用户丢进设置页，等于跳过了能一键搞定的那步。
              if (_notificationsAllowed == false) {
                final granted = await AppNotifications.requestPermission();
                if (!mounted) return;
                if (granted) {
                  await _loadAll();
                  return;
                }
              }
              final opened = await AppNotifications.openSettings();
              if (!mounted || opened) return;
              context.showMessage(
                message:
                    "Cannot open system settings. Please grant the permission manually."
                        .tl,
              );
            },
          ).toSliver(),
          // 后台追更检查与自动备份跑在 WorkManager 里：系统的省电策略会把它们
          // 推迟到维护窗口，MIUI / EMUI / ColorOS 上甚至直接不执行。没有这一行
          // 时用户只能看到「开了却不生效」，在应用内完全无从排查。
          _CallbackSetting(
            title: "Unrestricted battery usage".tl,
            subtitle: _batteryUnrestricted == null
                ? null
                : (_batteryUnrestricted!
                      ? "Granted".tl
                      : "Background updates and auto backup may be delayed by the system"
                            .tl),
            actionTitle: "Open".tl,
            callback: () async {
              final opened = await AppPower.requestIgnoreBatteryOptimizations();
              if (!mounted || opened) return;
              context.showMessage(
                message:
                    "Cannot open system settings. Please grant the permission manually."
                        .tl,
              );
            },
          ).toSliver(),
          // Android 8.0 起按来源授予，没有申请接口。不摆出来时，用户点「立即
          // 更新」只会看到安装器一闪而过，不知道被谁拦下了。
          _CallbackSetting(
            title: "Install unknown apps".tl,
            subtitle: _canInstall == null
                ? null
                : (_canInstall!
                      ? "Granted".tl
                      : "Needed only to install updates downloaded from GitHub"
                            .tl),
            actionTitle: "Open".tl,
            callback: () async {
              final opened = await App.openInstallPermissionSettings();
              if (!mounted || opened) return;
              context.showMessage(
                message:
                    "Cannot open system settings. Please grant the permission manually."
                        .tl,
              );
            },
          ).toSliver(),
        ],
      ],
    );
  }
}
