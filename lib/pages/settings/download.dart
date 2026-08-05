part of 'settings_page.dart';

class DownloadSettings extends StatefulWidget {
  const DownloadSettings({super.key});

  @override
  State<DownloadSettings> createState() => _DownloadSettingsState();
}

class _DownloadSettingsState extends State<DownloadSettings> {
  @override
  void initState() {
    super.initState();
    appdata.settings.addListener(_onSettingsChange);
  }

  @override
  void dispose() {
    appdata.settings.removeListener(_onSettingsChange);
    super.dispose();
  }

  void _onSettingsChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool cbzEnabled = appdata.settings['saveAsCbz'] == true;

    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Download".tl)),

        // CBZ packaging section
        _SettingPartTitle(
          title: "CBZ Packaging".tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedArchive02, size: 20),
        ),
        _SwitchSetting(
          title: "Save chapters as CBZ".tl,
          subtitle: "Package each chapter as .cbz file after download".tl,
          settingKey: 'saveAsCbz',
        ).toSliver(),
        if (cbzEnabled)
          _SwitchSetting(
            title: "Delete folder after CBZ packaging".tl,
            subtitle: "Keep only the .cbz file, remove the original folder".tl,
            settingKey: 'deleteFolderAfterCbz',
          ).toSliver(),

        // Download performance section
        _SettingPartTitle(
          title: "Download Performance".tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 20),
        ),
        _SliderSetting(
          title: "Download Threads".tl,
          settingsIndex: 'downloadThreads',
          interval: 1,
          min: 1,
          max: 16,
        ).toSliver(),

        // Info text
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              "Higher thread count speeds up downloads but increases memory and network load. 3-8 is recommended.".tl,
              style: TextStyle(
                fontSize: kcCaption,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
