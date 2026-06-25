part of 'settings_page.dart';

class DownloadSettings extends StatefulWidget {
  const DownloadSettings({super.key});

  @override
  State<DownloadSettings> createState() => _DownloadSettingsState();
}

class _DownloadSettingsState extends State<DownloadSettings> {
  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Download".tl)),
        _SwitchSetting(
          title: "Save chapters as CBZ".tl,
          subtitle: "Package each chapter as .cbz file after download".tl,
          settingKey: 'saveAsCbz',
        ).toSliver(),
        _SliderSetting(
          title: "Download Threads".tl,
          settingsIndex: 'downloadThreads',
          interval: 1,
          min: 1,
          max: 16,
        ).toSliver(),

      ],
    );
  }
}
