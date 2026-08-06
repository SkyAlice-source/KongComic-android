part of 'settings_page.dart';

class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({super.key});

  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Appearance".tl)),
        SelectSetting(
          title: "Appearance".tl,
          settingKey: "theme_mode",
          optionTranslation: {
            "system": "System",
            "light": "Light",
            "dark": "Dark",
            "amoled": "AMOLED",
          },
          onChanged: () async {
            App.forceRebuild();
          },
        ).toSliver(),
        SelectSetting(
          title: "Theme Color".tl,
          settingKey: "color",
          optionTranslation: {
            "system": "Auto",
            "red": "Red",
            "pink": "Pink",
            "purple": "Purple",
            "green": "Green",
            "blue": "Blue",
            "yellow": "Yellow",
            "cyan": "Cyan",
          },
          onChanged: () async {
            App.forceRebuild();
          },
        ).toSliver(),
        SelectSetting(
          title: "Language".tl,
          settingKey: "language",
          optionTranslation: {
            "system": "System",
            "zh-CN": "Simplified Chinese",
            "zh-TW": "Traditional Chinese",
            "en-US": "English",
          },
          onChanged: () async {
            App.forceRebuild();
            // 关闭设置页后重新打开，让语言立即生效
            if (context.mounted) Navigator.of(context).pop();
          },
        ).toSliver(),
      ],
    );
  }
}
