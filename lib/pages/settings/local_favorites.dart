part of 'settings_page.dart';

class LocalFavoritesSettings extends StatefulWidget {
  const LocalFavoritesSettings({super.key});

  @override
  State<LocalFavoritesSettings> createState() => _LocalFavoritesSettingsState();
}

class _LocalFavoritesSettingsState extends State<LocalFavoritesSettings> {
  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Local Favorites".tl)),
        _SwitchSetting(
          title: "Show local favorites before network favorites".tl,
          settingKey: "localFavoritesFirst",
        ).toSliver(),
        _SwitchSetting(
          title: "Auto close favorite panel after operation".tl,
          settingKey: "autoCloseFavoritePanel",
        ).toSliver(),
        SelectSetting(
          title: "Add new favorite to".tl,
          settingKey: "newFavoriteAddTo",
          optionTranslation: {"start": "Start".tl, "end": "End".tl},
        ).toSliver(),
        SelectSetting(
          title: "Move favorite after reading".tl,
          settingKey: "moveFavoriteAfterRead",
          optionTranslation: {
            "none": "None".tl,
            "end": "End".tl,
            "start": "Start".tl,
          },
        ).toSliver(),
        SelectSetting(
          title: "Quick Favorite".tl,
          settingKey: "quickFavorite",
          help:
              "Long press on the favorite button to quickly add to this folder"
                  .tl,
          optionTranslation: {for (var e in userFolderNames()) e: e},
        ).toSliver(),
        _CallbackSetting(
          title: "Delete all unavailable local favorite items".tl,
          callback: () async {
            var controller = showLoadingDialog(context);
            int count;
            try {
              count = await LocalFavoritesManager().removeInvalid();
            } catch (e) {
              // Without this the dialog closes never — it has no other exit.
              if (mounted) {
                context.showMessage(message: friendlyError(e));
              }
              return;
            } finally {
              controller.close();
            }
            if (!context.mounted) return;
            context.showMessage(
              message: "Deleted @a favorite items".tlParams({'a': count}),
            );
          },
          actionTitle: 'Delete'.tl,
          destructive: true,
        ).toSliver(),
        SelectSetting(
          title: "Click favorite item".tl,
          settingKey: "onClickFavorite",
          optionTranslation: {
            "viewDetail": "View Detail".tl,
            "read": "Read".tl,
          },
        ).toSliver(),
      ],
    );
  }
}

class _HomeBannerFoldersSetting extends StatefulWidget {
  @override
  State<_HomeBannerFoldersSetting> createState() =>
      _HomeBannerFoldersSettingState();
}

class _HomeBannerFoldersSettingState extends State<_HomeBannerFoldersSetting> {
  @override
  Widget build(BuildContext context) {
    final folders = userFolderNames();
    // 不用 `as List` + `cast<String>()`：值是 null 时直接崩，混进非字符串元素
    // 则在下面 join 时才炸（报错点离原因很远）。统一转成字符串列表。
    final raw = appdata.settings['homeBannerFolders'];
    final selected = raw is List
        ? raw.map((e) => '$e').toList()
        : <String>[];
    // 只显示仍然存在的收藏夹：全部被删掉时按「全部」显示，否则副标题会是一行
    // 空白（还白占一行高度），而弹窗里「全部」又没打勾，看起来像状态丢了。
    final valid = selected.where(folders.contains).toList();
    final subtitle = valid.isEmpty ? "All".tl : valid.join(", ");

    return _KcSettingTile(
      title: Text("Home banner folders".tl),
      subtitle: subtitle,
      trailing: const _KcChevron(down: true),
      onTap: () => _showFolderPicker(folders, selected),
      showDivider: false,
    );
  }

  void _showFolderPicker(List<String> folders, List<String> selected) {
    var tempSelected = List<String>.from(selected);
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isAll = tempSelected.isEmpty;
            return ContentDialog(
              title: "Home banner folders".tl,
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CheckboxListTile(
                        title: Text("All".tl),
                        value: isAll,
                        onChanged: (value) {
                          if (value == true) {
                            tempSelected.clear();
                          }
                          setDialogState(() {});
                        },
                      ),
                      if (folders.isNotEmpty) const Divider(height: 1),
                      ...folders.map((folder) {
                        return CheckboxListTile(
                          title: Text(folder),
                          value: tempSelected.contains(folder),
                          onChanged: (value) {
                            if (value == true) {
                              tempSelected.add(folder);
                            } else {
                              tempSelected.remove(folder);
                            }
                            setDialogState(() {});
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                Button.text(
                  onPressed: () => context.pop(),
                  child: Text("Cancel".tl),
                ),
                Button.filled(
                  onPressed: () {
                    appdata.settings['homeBannerFolders'] = tempSelected;
                    appdata.saveData();
                    setState(() {});
                    context.pop();
                  },
                  child: Text("OK".tl),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
