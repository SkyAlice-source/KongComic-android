part of 'settings_page.dart';

/// 下载与导入。
///
/// 「导入」原本独占一个分类，里面只有 3 个一次性动作 —— 分类列表白白多一项，
/// 而它和下载讲的是同一件事（把文件弄进本地库）。合并后分类 10 → 9，
/// 两件事仍分在各自的小标题下，不会混。
class DownloadSettings extends StatefulWidget {
  const DownloadSettings({super.key});

  @override
  State<DownloadSettings> createState() => _DownloadSettingsState();
}

class _DownloadSettingsState extends State<DownloadSettings>
    with AutoListenMixin {
  @override
  void initState() {
    super.initState();
    listen(appdata.settings, _onSettingsChange);
  }

  void _onSettingsChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Download & Import".tl)),

        // ── 下载 ──────────────────────────────────────────────
        _SettingPartTitle(
          title: "Download".tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 20),
        ),
        // 「打包后删除原文件夹」这个开关已移除：阅读器只认目录，删掉目录后
        // 章节仍被标记为「已下载」，点开必然 PathNotFoundException，
        // 而 .cbz 只能导入、不能直接读。
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
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg, vertical: kcSpaceSm),
            child: Text(
              "Higher thread count speeds up downloads but increases memory and network load. 3-8 is recommended."
                  .tl,
              style: TextStyle(
                fontSize: kcCaption,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),

        // ── 导入 ──────────────────────────────────────────────
        _SettingPartTitle(
          title: "Import".tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedFolderImport, size: 20),
        ),
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
