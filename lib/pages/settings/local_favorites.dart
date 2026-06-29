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
          optionTranslation: {
            "start": "Start".tl,
            "end": "End".tl,
          },
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
          optionTranslation: {
            for (var e in LocalFavoritesManager().folderNames) e: e
          },
        ).toSliver(),
        _CallbackSetting(
          title: "Delete all unavailable local favorite items".tl,
          callback: () async {
            var controller = showLoadingDialog(context);
            var count = await LocalFavoritesManager().removeInvalid();
            controller.close();
            context.showMessage(
                message: "Deleted @a favorite items".tlParams({'a': count}));
          },
          actionTitle: 'Delete'.tl,
        ).toSliver(),
        SelectSetting(
          title: "Click favorite".tl,
          settingKey: "onClickFavorite",
          optionTranslation: {
            "viewDetail": "View Detail".tl,
            "read": "Read".tl,
          },
        ).toSliver(),
        _HomeBannerFoldersSetting().toSliver(),
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
    final folders = LocalFavoritesManager().folderNames;
    final selected = (appdata.settings['homeBannerFolders'] as List).cast<String>();
    final subtitle = selected.isEmpty
        ? "All".tl
        : selected.where((f) => folders.contains(f)).join(", ");

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text("Home banner folders".tl),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: HugeIcon(
        icon: HugeIcons.strokeRoundedArrowDown01,
        size: 18,
      ),
      onTap: () => _showFolderPicker(folders, selected),
    );
  }

  void _showFolderPicker(List<String> folders, List<String> selected) {
    var tempSelected = List<String>.from(selected);
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          final isAll = tempSelected.isEmpty;
          return ContentDialog(
            title: "Home banner folders".tl,
            content: SingleChildScrollView(
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
                  if (folders.isNotEmpty)
                    const Divider(height: 1),
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
            actions: [
              TextButton(
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
        });
      },
    );
  }
}
