part of 'settings_page.dart';

class ImportSettings extends StatefulWidget {
  const ImportSettings({super.key});

  @override
  State<ImportSettings> createState() => _ImportSettingsState();
}

class _ImportSettingsState extends State<ImportSettings> {
  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("导入设置")),

        _CallbackSetting(
          title: "Import CBZ / ZIP / 7Z".tl,
          callback: () => const ImportComic().cbz(),
          actionTitle: "Import".tl,
        ).toSliver(),
        _CallbackSetting(
          title: "Import archives from folder".tl,
          subtitle: "Batch import .cbz/.zip/.7z files".tl,
          callback: () => const ImportComic().multipleCbz(),
          actionTitle: "Import".tl,
        ).toSliver(),
        _CallbackSetting(
          title: "Import image folders".tl,
          subtitle: "Import folders containing images as comics".tl,
          callback: () => const ImportComic().directory(false),
          actionTitle: "Import".tl,
        ).toSliver(),
      ],
    );
  }
}
