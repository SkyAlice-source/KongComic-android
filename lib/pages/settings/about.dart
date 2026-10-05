part of 'settings_page.dart';

class AboutSettings extends StatefulWidget {
  const AboutSettings({super.key});

  @override
  State<AboutSettings> createState() => _AboutSettingsState();
}

class _AboutSettingsState extends State<AboutSettings> {
  bool isCheckingUpdate = false;

  /// Opens the GitHub repository page in an external browser.
  Future<void> _openGitHubRepo() async {
    const url = "https://github.com/SkyAlice-source/KongComic-android";
    if (!await launchUrlString(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        App.rootContext.showMessage(message: "Unable to open browser".tl);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("About".tl)),
        SizedBox(
          height: 120,
          width: double.infinity,
          child: Center(
            child: const Image(
              image: AssetImage("assets/app_icon.png"),
              width: 96,
              height: 96,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ).paddingTop(16).toSliver(),
        Column(
          children: [
            SizedBox(height: 8),
            Text(
              App.appVersion,
              style: TextStyle(fontSize: kcSubtitle),
            ),
            Text("KongComic is a free and open-source comic reader.".tl),
            SizedBox(height: 4),
          ],
        ).toSliver(),
        ListTile(
          title: Text("Source Code".tl),
          trailing: HugeIcon(icon: HugeIcons.strokeRoundedLinkSquare01, size: 18),
          onTap: _openGitHubRepo,
        ).toSliver(),
        ListTile(
          title: Text("Check for Updates".tl),
          subtitle: Text("Download directly from GitHub".tl),
          trailing: Button.filled(
            isLoading: isCheckingUpdate,
            child: Text("Check".tl),
            onPressed: () {
              setState(() => isCheckingUpdate = true);
              checkUpdateUi(true, false).then((_) {
                if (mounted) setState(() => isCheckingUpdate = false);
              });
            },
          ).fixHeight(32),
        ).toSliver(),
        _SwitchSetting(
          title: "Check for updates on startup".tl,
          settingKey: "checkUpdateOnStart",
        ).toSliver(),
        const _MirrorSetting().toSliver(),
        if (UpdateMirrorPreference.mode == 'custom')
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            title: Text("Mirror template".tl),
            subtitle: Text(
              UpdateMirrorPreference.template.isNotEmpty
                  ? UpdateMirrorPreference.template
                  : kDefaultMirrorTemplate,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: HugeIcon(
              icon: HugeIcons.strokeRoundedPencilEdit02,
              size: 18,
            ),
            onTap: () async {
              await showInputDialog(
                context: context,
                title: "Mirror template".tl,
                hintText: kDefaultMirrorTemplate,
                initialValue: UpdateMirrorPreference.template,
                onConfirm: (value) {
                  final v = value.trim();
                  if (!v.contains('{url}')) {
                    return "The template must contain {url}".tl;
                  }
                  final uri = Uri.tryParse(v.replaceFirst('{url}', ''));
                  if (uri == null || uri.host.isEmpty) {
                    return "Invalid url".tl;
                  }
                  UpdateMirrorPreference.template = v;
                  setState(() {});
                  return null;
                },
              );
            },
          ).toSliver(),
        const _MirrorTestTile().toSliver(),
      ],
    );
  }
}

/// Which CDN/route the APK is downloaded through.
///
/// GitHub release downloads are frequently throttled or blocked outright
/// (mainland China being the common case), so the pipeline can also pull the
/// same file through a mirror. Every route is verified against the SHA-256 that
/// CI publishes with the release, so a mirror can fail an update but can never
/// silently substitute a different APK.
class _MirrorSetting extends StatefulWidget {
  const _MirrorSetting();

  @override
  State<_MirrorSetting> createState() => _MirrorSettingState();
}

class _MirrorSettingState extends State<_MirrorSetting> {
  Map<String, String> get _options => {
    'auto': 'Auto (recommended)',
    'direct': 'GitHub (direct)',
    for (final m in UpdateMirrors.all)
      if (m.id != 'direct') m.id: m.name,
    'custom': 'Custom',
  };

  @override
  Widget build(BuildContext context) {
    final mode = UpdateMirrorPreference.mode;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Row(
        children: [
          Expanded(child: Text("Download mirror".tl)),
          Button.icon(
            size: 18,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedHelpCircle, size: 18),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) {
                  return ContentDialog(
                    title: "Download mirror".tl,
                    content: Text("Updates are normally downloaded straight from GitHub. When that connection is blocked or very slow, KongComic can fetch the same file through a mirror instead. Every download is verified against the SHA-256 published with the release, so a mirror cannot tamper with your update — it can only succeed or fail."
                            .tl)
                        .paddingHorizontal(16)
                        .fixWidth(double.infinity),
                    actions: [
                      Button.filled(
                        onPressed: context.pop,
                        child: Text("OK".tl),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      subtitle: Text(_options[mode]?.tl ?? mode),
      trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowDown01, size: 18),
      onTap: () {
        var renderBox = context.findRenderObject() as RenderBox;
        var offset = renderBox.localToGlobal(Offset.zero);
        var rect = offset & renderBox.size;
        showMenu(
          elevation: 3,
          color: context.colorScheme.surfaceContainer,
          context: context,
          position: RelativeRect.fromRect(
            rect,
            Offset.zero & MediaQuery.of(context).size,
          ),
          items: _options.keys
              .map(
                (key) => PopupMenuItem<String>(
                  value: key,
                  height: App.isMobile ? 46 : 40,
                  child: Text(_options[key]!.tl),
                ),
              )
              .toList(),
        ).then((value) {
          if (value != null) {
            UpdateMirrorPreference.mode = value;
            setState(() {});
          }
        });
      },
    );
  }
}

/// Probes every configured route and reports which ones actually work on this
/// network. Useful right after the "download failed" symptom appears: it says
/// whether GitHub itself is the problem and which mirror takes over.
class _MirrorTestTile extends StatefulWidget {
  const _MirrorTestTile();

  @override
  State<_MirrorTestTile> createState() => _MirrorTestTileState();
}

class _MirrorTestTileState extends State<_MirrorTestTile> {
  bool _running = false;

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    String? assetUrl;
    try {
      assetUrl = await AppUpdate.latestAssetUrl();
    } catch (e) {
      AppUpdate.safeLog(e);
    }
    if (!mounted) return;
    if (assetUrl == null) {
      setState(() => _running = false);
      context.showMessage(message: "Network error".tl);
      return;
    }
    final results = await probeAllMirrors(assetUrl);
    if (!mounted) return;
    setState(() => _running = false);
    showDialog(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: "Download sources".tl,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: results.map((r) {
              final color = r.ok
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(r.mirror.name)),
                    Text(
                      r.ok
                          ? "${r.latency.inMilliseconds} ms"
                          : "Unavailable".tl,
                      style: TextStyle(color: color),
                    ),
                  ],
                ),
              );
            }).toList(),
          ).paddingHorizontal(16),
          actions: [
            Button.filled(
              onPressed: context.pop,
              child: Text("OK".tl),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text("Test download sources".tl),
      subtitle: Text("Check which mirror works on this network".tl),
      trailing: Button.normal(
        isLoading: _running,
        onPressed: _run,
        child: Text("Test".tl),
      ).fixHeight(32),
      onTap: _run,
    );
  }
}

Future<bool> checkUpdate() async {
  // Startup check against the GitHub Releases API.
  // Returns true iff a newer version is available.
  try {
    final info = await AppUpdate.check();
    return info != null;
  } catch (_) {
    return false;
  }
}

Future<void> checkUpdateUi(
    [bool showMessageIfNoUpdate = true, bool delay = false]) async {
  // Check against GitHub only.
  AppUpdateInfo? value;
  try {
    value = await AppUpdate.check();
  } catch (_) {
    // GitHub unreachable
    if (delay) {
      await Future.delayed(const Duration(seconds: 2));
    }
    if (showMessageIfNoUpdate) {
      _showNetworkErrorDialog();
    }
    return;
  }

  if (delay) {
    await Future.delayed(const Duration(seconds: 2));
  }

  if (value != null) {
    // Found an update
    await _showUpdateDialog(value);
  } else if (showMessageIfNoUpdate) {
    if (App.rootContext.mounted) {
      App.rootContext.showMessage(message: "No new version available".tl);
    }
  }
}

/// Build a Markdown stylesheet that follows the current app theme.
MarkdownStyleSheet _mdStyleSheet(BuildContext context) {
  final theme = Theme.of(context);
  final base = theme.textTheme.bodyMedium!;
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: base,
    listBullet: base,
    a: base.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
    ),
    code: base.copyWith(
      fontFamily: "monospace",
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
    ),
    h1: theme.textTheme.titleLarge,
    h2: theme.textTheme.titleMedium,
    h3: theme.textTheme.titleSmall,
    blockSpacing: 8,
  );
}

/// Show a simple "new version available" prompt with the GitHub download.
Future<void> _showUpdateDialog(AppUpdateInfo info) async {
  if (!App.rootContext.mounted) return;
  final abi = await App.getDeviceAbi();
  final downloadUrl = info.pickUrlForCurrentDevice(abi);
  if (downloadUrl == null) {
    if (!App.rootContext.mounted) return;
    App.rootContext.showMessage(
      message: "No download available for this device".tl,
    );
    return;
  }
  if (!App.rootContext.mounted) return;

  final choice = await showDialog<String>(
    context: App.rootContext,
    barrierDismissible: true,
    builder: (ctx) {
      return ContentDialog(
        title: "New version available".tl,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Version @v"
                    .tlParams({"v": info.latestVersion}))
                .paddingHorizontal(16),
            if (info.releaseNotes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(
                    child: MarkdownBody(
                      data: info.releaseNotes,
                      styleSheet: _mdStyleSheet(ctx),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          Button.text(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text("Cancel".tl),
          ),
          Button.outlined(
            onPressed: () => Navigator.of(ctx).pop("github"),
            child: Text("View on GitHub".tl),
          ),
          const SizedBox(width: 8),
          Button.filled(
            onPressed: () => Navigator.of(ctx).pop("update"),
            child: Text("Update now".tl),
          ),
        ],
      );
    },
  );

  if (choice == null || !App.rootContext.mounted) return;

  if (choice == "update") {
    await _startBackgroundUpdateDownload(info, abi: abi);
  } else if (choice == "github") {
    try {
      await AppUpdate.openReleasePageInBrowser();
    } catch (_) {
      if (App.rootContext.mounted) {
        App.rootContext.showMessage(message: "Network error".tl);
      }
    }
  }
}

/// Download the update APK in the background and report progress through
/// the system notification shade so the screen stays free.
Future<void> _startBackgroundUpdateDownload(
  AppUpdateInfo info, {
  String? abi,
}) async {
  if (!App.isAndroid) {
    // Fallback to the browser on non-Android platforms.
    await AppUpdate.openReleasePageInBrowser();
    return;
  }
  await AppNotifications.requestPermission();
  if (!await AppNotifications.isAllowed) {
    // Nothing would be visible without the notification permission, and the
    // download is a 40 MB GitHub asset the user is waiting on. Fall back to an
    // in-app dialog: same pipeline, but progress and the stage-aware actions
    // ("Retry" / "Install manually" / "Open in browser") live on screen.
    if (!App.rootContext.mounted) return;
    await showDialog(
      context: App.rootContext,
      barrierDismissible: false,
      builder: (ctx) => _UpdateDownloadDialog(info: info, abi: abi),
    );
    return;
  }
  if (App.rootContext.mounted) {
    App.rootContext.showMessage(message: "Downloading update in the background".tl);
  }
  unawaited(_backgroundUpdateDownload(info, abi: abi));
}

Future<void> _backgroundUpdateDownload(
  AppUpdateInfo info, {
  String? abi,
}) async {
  try {
    await AppNotifications.showAppUpdateCheck();
    await AppUpdate.downloadAndInstall(
      info,
      abi: abi,
      onProgress: (progress, speed) {
        final max = 100;
        final current = (progress * max).round();
        AppNotifications.showAppUpdateDownload(
          progress: current,
          maxProgress: max,
          bytesPerSecond: speed,
        );
      },
    );
    await AppNotifications.showAppUpdateComplete(version: info.latestVersion);
  } catch (e, s) {
    AppUpdate.safeLog(e, s);
    // Report which stage actually failed. For an install failure the APK is
    // already downloaded, so tapping the notification retries *installing* it
    // rather than starting another download.
    final stage = updateFailureStage(e);
    await AppNotifications.showAppUpdateComplete(
      error: updateFailureMessage(e),
      version: stage == UpdateFailureStage.install ? info.latestVersion : null,
    );
  }
}

Future<void> _showNetworkErrorDialog() async {
  if (!App.rootContext.mounted) return;
  showDialog(
    context: App.rootContext,
    builder: (context) {
      return ContentDialog(
        title: "Network error".tl,
        content: Text(
          "Unable to reach the update server. Open the release page in your browser to update manually?"
              .tl,
        ).paddingHorizontal(16),
        actions: [
          Button.text(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Cancel".tl),
          ),
          Button.filled(
            onPressed: () {
              Navigator.of(context).pop();
              AppUpdate.openReleasePageInBrowser().catchError((e) {
                if (App.rootContext.mounted) {
                  App.rootContext.showMessage(message: "Network error".tl);
                }
              });
            },
            child: Text("Open in browser".tl),
          ),
        ],
      );
    },
  );
}

class _UpdateDownloadDialog extends StatefulWidget {
  final AppUpdateInfo info;
  final String? abi;

  const _UpdateDownloadDialog({required this.info, required this.abi});

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  double _progress = 0;
  int _bytesPerSecond = 0;
  String? _error;
  UpdateFailureStage _failureStage = UpdateFailureStage.download;
  bool _starting = true;
  bool _installing = false;
  bool _exportingApk = false;
  String? _mirrorName;
  final FileDownloaderHandle _handle = FileDownloaderHandle();

  @override
  void dispose() {
    _handle.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() {
      _starting = true;
      _error = null;
      _failureStage = UpdateFailureStage.download;
    });
    try {
      await AppUpdate.downloadAndInstall(
        widget.info,
        abi: widget.abi,
        onProgress: (p, speed) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            _bytesPerSecond = speed;
          });
        },
        onMirrorChanged: (name) {
          if (!mounted) return;
          setState(() => _mirrorName = name);
        },
        handle: _handle,
      );
      if (!mounted) return;
      setState(() {
        _installing = true;
      });
    } catch (e, s) {
      AppUpdate.safeLog(e, s);
      if (!mounted) return;
      // Cancellation is not an error: the user closed the dialog and
      // [dispose] already triggered [_handle.cancel]. Do not mutate state.
      if (_handle.isCanceled) return;
      setState(() {
        _failureStage = updateFailureStage(e);
        _error = updateFailureMessage(e);
        _starting = false;
      });
    }
  }

  /// Manual recovery for the install stage: publish the already-downloaded APK
  /// to the public Download folder and let the system installer handle it.
  Future<void> _installManually() async {
    setState(() => _exportingApk = true);
    String? error;
    try {
      error = await AppUpdate.installFromDownloads(widget.info.latestVersion);
    } on UpdateVerifyException {
      // The local copy went bad between downloads; fall back to redownloading.
      if (mounted) {
        setState(() => _exportingApk = false);
        _startDownload();
      }
      return;
    } catch (e, s) {
      AppUpdate.safeLog(e, s);
      error ??= e.toString();
    }
    if (!mounted) return;
    setState(() => _exportingApk = false);
    if (error == null) {
      if (mounted) {
        App.rootContext.showMessage(
          message: "Opened the system installer".tl,
        );
      }
      return;
    }
    App.rootContext.showMessage(
      message: "Failed to open the system installer".tl,
    );
  }

  void _cancel() {
    _handle.cancel();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _openInBrowser() {
    AppUpdate.openReleasePageInBrowser().catchError((e) {
      if (mounted) {
        App.rootContext.showMessage(message: "Network error".tl);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ContentDialog(
      title: "New version available".tl,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Version @v"
                  .tlParams({"v": widget.info.latestVersion}))
              .paddingHorizontal(16),
          if (widget.info.releaseNotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: widget.info.releaseNotes,
                    styleSheet: _mdStyleSheet(context),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _buildProgressSection(colorScheme),
          ),
        ],
      ),
      actions: [
        if (!_installing)
          Button.text(
            onPressed: _cancel,
            child: Text("Cancel".tl),
          ),
        // The APK is already on disk for the install stage, so retrying the
        // download would just redownload the same file. Offer the paths that
        // can actually get it installed.
        if (_error != null && _failureStage == UpdateFailureStage.install)
          Button.text(
            onPressed: () {
              if (_exportingApk) return;
              _installManually();
            },
            child: _exportingApk
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text("Install manually".tl),
          ),
        if (_error != null && _failureStage != UpdateFailureStage.install)
          Button.text(
            onPressed: () {
              _startDownload();
            },
            child: Text("Retry".tl),
          ),
        if (_error != null)
          Button.outlined(
            onPressed: _openInBrowser,
            child: Text("Open in browser".tl),
          ),
        if (_installing)
          Button.filled(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("OK".tl),
          ),
      ],
    );
  }

  Widget _buildProgressSection(ColorScheme colorScheme) {
    if (_error != null) {
      return Text(
        _error!,
        style: TextStyle(color: colorScheme.error),
      );
    }
    if (_installing) {
      return Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text("Installing, follow the system prompt".tl)),
        ],
      );
    }
    if (_starting && _progress == 0) {
      return Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _mirrorName == null
                  ? "Connecting...".tl
                  : "Connecting to @source..."
                      .tlParams({"source": _mirrorName!}),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: _progress),
        const SizedBox(height: 6),
        Text(
          "${(_progress * 100).toStringAsFixed(1)}%  ${_formatSpeed(_bytesPerSecond)}",
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_mirrorName != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              "Source: @source".tlParams({"source": _mirrorName!}),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond <= 0) return "";
    if (bytesPerSecond < 1024) return "$bytesPerSecond B/s";
    if (bytesPerSecond < 1024 * 1024) {
      return "${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s";
    }
    return "${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s";
  }
}
