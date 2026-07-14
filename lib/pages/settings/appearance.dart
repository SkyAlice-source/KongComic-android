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
        SliverAppbar(title: Text("外观")),
        SelectSetting(
          title: "外观",
          settingKey: "theme_mode",
          optionTranslation: {
            "system": "跟随手机",
            "light": "日间",
            "dark": "夜间",
            "amoled": "纯黑·省电",
          },
          onChanged: () async {
            App.forceRebuild();
          },
        ).toSliver(),
        SelectSetting(
          title: "主题色",
          settingKey: "color",
          optionTranslation: {
            "system": "自动",
            "red": "红",
            "pink": "粉",
            "purple": "紫",
            "green": "绿",
            "orange": "橙",
            "blue": "蓝",
          },
          onChanged: () async {
            App.forceRebuild();
          },
        ).toSliver(),
        SelectSetting(
          title: "Language".tl,
          settingKey: "language",
          optionTranslation: {
            "system": "System".tl,
            "zh-CN": "简体中文",
            "zh-TW": "繁體中文",
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
