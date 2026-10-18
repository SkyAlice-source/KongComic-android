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
          // 顺序即展示顺序：跟随系统 → 浅色 → 深色 → AMOLED。
          // 「跟随系统」只在浅色 / 深色之间切换，不会落到 AMOLED 纯黑。
          optionTranslation: {
            "system": "Follow system",
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
            // 「默认」= 品牌红（不再取系统壁纸色，避免按钮忽然变蓝）。
            "system": "Default",
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
            "ja-JP": "Japanese",
            "en-US": "English",
          },
          onChanged: () async {
            App.forceRebuild();
            // 关闭设置页后重新打开，让语言立即生效。
            // 平板双栏下本页为内联渲染（非路由栈），canPop 为 false，不 pop 以免关掉整个设置页。
            if (context.mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ).toSliver(),
      ],
    );
  }
}
