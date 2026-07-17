part of 'settings_page.dart';

class AboutSettings extends StatefulWidget {
  const AboutSettings({super.key});

  @override
  State<AboutSettings> createState() => _AboutSettingsState();
}

class _AboutSettingsState extends State<AboutSettings> {
  bool isCheckingUpdate = false;
  bool isCheckingGithubUpdate = false;

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("About".tl)),
        SizedBox(
          height: 112,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(136),
              ),
              clipBehavior: Clip.antiAlias,
              child: const Image(
                image: AssetImage("assets/app_icon.png"),
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ).paddingTop(16).toSliver(),
        Column(
          children: [
            SizedBox(height: 8),
            Text(
              App.appVersion,
              style: TextStyle(fontSize: 16),
            ),
            Text("KongComic is a free and open-source comic reader.".tl),
            SizedBox(height: 8),
          ],
        ).toSliver(),
        ListTile(
          title: Text("Accelerated Source".tl),
          subtitle: Text("Download via CDN proxy, faster in some regions".tl),
          trailing: Button.filled(
            isLoading: isCheckingUpdate,
            child: Text("Check".tl),
            onPressed: () {
              setState(() {
                isCheckingUpdate = true;
              });
              checkAcceleratedUpdate().then((_) {
                if (mounted) {
                  setState(() {
                    isCheckingUpdate = false;
                  });
                }
              });
            },
          ).fixHeight(32),
        ).toSliver(),
        ListTile(
          title: Text("GitHub Source".tl),
          subtitle: Text("Download via GitHub source".tl),
          trailing: Button.outlined(
            isLoading: isCheckingGithubUpdate,
            child: Text("Check".tl),
            onPressed: () {
              setState(() {
                isCheckingGithubUpdate = true;
              });
              checkGithubSource().then((_) {
                if (mounted) {
                  setState(() {
                    isCheckingGithubUpdate = false;
                  });
                }
              });
            },
          ).fixHeight(32),
        ).toSliver(),
        _SwitchSetting(
          title: "Check for updates on startup".tl,
          settingKey: "checkUpdateOnStart",
        ).toSliver(),
      ],
    );
  }
}

Future<bool> checkUpdate() async {
  // Startup check: tries GitHub first, falls back to accelerated source.
  // Returns true iff a newer version is available.
  try {
    final info = await AppUpdate.check();
    if (info != null) return true;
  } catch (_) {
    // GitHub unreachable — try accelerated source
    try {
      final info = await AppUpdate.checkAccelerated();
      return info != null;
    } catch (_) {
      return false;
    }
  }
  return false;
}

Future<void> checkUpdateUi(
    [bool showMessageIfNoUpdate = true, bool delay = false]) async {
  // Try GitHub source first, fall back to accelerated source on failure
  AppUpdateInfo? value;
  try {
    value = await AppUpdate.check();
  } catch (_) {
    // GitHub unreachable — fall back to accelerated source
    try {
      value = await AppUpdate.checkAccelerated();
    } catch (_) {
      // Both sources unreachable
      if (delay) {
        await Future.delayed(const Duration(seconds: 2));
      }
      if (showMessageIfNoUpdate) {
        _showNetworkErrorDialog();
      }
      return;
    }
  }

  if (delay) {
    await Future.delayed(const Duration(seconds: 2));
  }

  if (value != null) {
    // Found an update
    await _showUpdateSourceDialog(value);
  } else if (showMessageIfNoUpdate) {
    if (App.rootContext.mounted) {
      App.rootContext.showMessage(message: "No new version available".tl);
    }
  }
}

/// Show a dialog with new version info and let the user choose update source.
Future<void> _showUpdateSourceDialog(AppUpdateInfo info) async {
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
                    child: Text(info.releaseNotes),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "Choose download source:".tl,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(ctx).colorScheme.onSurface,
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
          Button.filled(
            onPressed: () => Navigator.of(ctx).pop("accelerated"),
            child: Text("Download via CDN".tl),
          ),
          const SizedBox(width: 8),
          Button.outlined(
            onPressed: () => Navigator.of(ctx).pop("github"),
            child: Text("View on GitHub".tl),
          ),
        ],
      );
    },
  );

  if (choice == null || !App.rootContext.mounted) return;

  if (choice == "accelerated") {
    await _showDownloadDialog(info, abi: abi, accelerated: true);
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

/// Show a dialog with a live progress bar. The user can cancel; cancelling
/// stops the download but does not roll back any partial file.
Future<void> _showDownloadDialog(AppUpdateInfo info, {String? abi, bool accelerated = false}) async {
  if (!App.rootContext.mounted) return;
  showDialog(
    context: App.rootContext,
    barrierDismissible: false,
    builder: (context) {
      return _UpdateDownloadDialog(info: info, abi: abi, accelerated: accelerated);
    },
  );
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

Future<void> checkAcceleratedUpdate() async {
  try {
    final value = await AppUpdate.checkAccelerated();
    if (value != null) {
      final abi = await App.getDeviceAbi();
      final downloadUrl = value.pickUrlForCurrentDevice(abi);
      if (downloadUrl == null) {
        if (App.rootContext.mounted) {
          App.rootContext.showMessage(
            message: "No download available for this device".tl,
          );
        }
        return;
      }
      await _showDownloadDialog(value, abi: abi, accelerated: true);
    } else {
      if (App.rootContext.mounted) {
        App.rootContext.showMessage(message: "No new version available".tl);
      }
    }
  } catch (_) {
    if (App.rootContext.mounted) {
      App.rootContext.showMessage(message: "Network error".tl);
    }
  }
}

Future<void> checkGithubSource() async {
  try {
    final value = await AppUpdate.check();
    if (value != null) {
      final abi = await App.getDeviceAbi();
      final downloadUrl = value.pickUrlForCurrentDevice(abi);
      if (downloadUrl == null) {
        if (App.rootContext.mounted) {
          App.rootContext.showMessage(
            message: "No download available for this device".tl,
          );
        }
        return;
      }
      await _showDownloadDialog(value, abi: abi, accelerated: false);
    } else {
      if (App.rootContext.mounted) {
        App.rootContext.showMessage(message: "No new version available".tl);
      }
    }
  } catch (_) {
    if (App.rootContext.mounted) {
      App.rootContext.showMessage(message: "Network error".tl);
    }
  }
}

class _UpdateDownloadDialog extends StatefulWidget {
  final AppUpdateInfo info;
  final String? abi;
  final bool accelerated;

  const _UpdateDownloadDialog({required this.info, required this.abi, this.accelerated = false});

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  double _progress = 0;
  int _bytesPerSecond = 0;
  String? _error;
  bool _starting = true;
  bool _installing = false;
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
    });
    try {
      if (widget.accelerated) {
        await AppUpdate.downloadAndInstallAccelerated(
        widget.info,
        abi: widget.abi,
        onProgress: (p, speed) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            _bytesPerSecond = speed;
          });
        },
        handle: _handle,
      );
      } else {
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
          handle: _handle,
        );
      }
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
        _error = "Download failed".tl;
        _starting = false;
      });
    }
  }

  void _cancel() {
    _handle.cancel();
    if (mounted) {
      Navigator.of(context).pop();
    }
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
                  child: Text(widget.info.releaseNotes),
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
        if (_error != null)
          Button.filled(
            onPressed: () {
              _startDownload();
            },
            child: Text("Retry".tl),
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
          Expanded(child: Text("Connecting...".tl)),
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
