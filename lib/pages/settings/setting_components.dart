part of 'settings_page.dart';

class _SwitchSetting extends StatefulWidget {
  const _SwitchSetting({
    required this.title,
    required this.settingKey,
    this.onChanged,
    this.subtitle,
    this.comicId,
    this.comicSource,
    this.useDeviceSettings = false,
  });

  final String title;

  final String settingKey;

  final VoidCallback? onChanged;

  final String? subtitle;

  final String? comicId;

  final String? comicSource;

  final bool useDeviceSettings;

  @override
  State<_SwitchSetting> createState() => _SwitchSettingState();
}

class _SwitchSettingState extends State<_SwitchSetting> {
  @override
  Widget build(BuildContext context) {
    var value = widget.comicId != null
        ? appdata.settings.getReaderSetting(
            widget.comicId!,
            widget.comicSource!,
            widget.settingKey,
          )
        : widget.useDeviceSettings
        ? appdata.settings.getDeviceReaderSetting(widget.settingKey)
        : appdata.settings[widget.settingKey];

    assert(value is bool);

    void toggle(bool v) {
      setState(() {
        if (widget.comicId != null) {
          appdata.settings.setReaderSetting(
            widget.comicId!,
            widget.comicSource!,
            widget.settingKey,
            v,
          );
        } else if (widget.useDeviceSettings) {
          appdata.settings.setDeviceReaderSetting(widget.settingKey, v);
        } else {
          appdata.settings[widget.settingKey] = v;
        }
      });
      appdata.saveData().then((_) {
        widget.onChanged?.call();
      });
    }

    return InkWell(
      onTap: () => toggle(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.title),
                  if (widget.subtitle != null)
                    Text(
                      widget.subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: value, onChanged: toggle),
          ],
        ),
      ),
    );
  }
}

class SelectSetting extends StatelessWidget {
  const SelectSetting({
    super.key,
    required this.title,
    required this.settingKey,
    required this.optionTranslation,
    this.onChanged,
    this.help,
    this.comicId,
    this.comicSource,
    this.useDeviceSettings = false,
  });

  final String title;

  final String settingKey;

  final Map<String, String> optionTranslation;

  final VoidCallback? onChanged;

  final String? help;

  final String? comicId;

  final String? comicSource;

  final bool useDeviceSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 450) {
            return _DoubleLineSelectSettings(
              title: title,
              settingKey: settingKey,
              optionTranslation: optionTranslation,
              onChanged: onChanged,
              help: help,
              comicId: comicId,
              comicSource: comicSource,
              useDeviceSettings: useDeviceSettings,
            );
          } else {
            return _EndSelectorSelectSetting(
              title: title,
              settingKey: settingKey,
              optionTranslation: optionTranslation,
              onChanged: onChanged,
              help: help,
              comicId: comicId,
              comicSource: comicSource,
              useDeviceSettings: useDeviceSettings,
            );
          }
        },
      ),
    );
  }
}

class _DoubleLineSelectSettings extends StatefulWidget {
  const _DoubleLineSelectSettings({
    required this.title,
    required this.settingKey,
    required this.optionTranslation,
    this.onChanged,
    this.help,
    this.comicId,
    this.comicSource,
    this.useDeviceSettings = false,
  });

  final String title;

  final String settingKey;

  final Map<String, String> optionTranslation;

  final VoidCallback? onChanged;

  final String? help;

  final String? comicId;

  final String? comicSource;

  final bool useDeviceSettings;

  @override
  State<_DoubleLineSelectSettings> createState() =>
      _DoubleLineSelectSettingsState();
}

class _DoubleLineSelectSettingsState extends State<_DoubleLineSelectSettings> {
  @override
  Widget build(BuildContext context) {
    var value = widget.comicId != null
        ? appdata.settings.getReaderSetting(
            widget.comicId!,
            widget.comicSource!,
            widget.settingKey,
          )
        : widget.useDeviceSettings
        ? appdata.settings.getDeviceReaderSetting(widget.settingKey)
        : appdata.settings[widget.settingKey];

    return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Row(
        children: [
          Text(widget.title),
          const SizedBox(width: 4),
          if (widget.help != null)
            Button.icon(
              size: 18,
              icon: HugeIcon(icon: HugeIcons.strokeRoundedHelpCircle, size: 18),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return ContentDialog(
                      title: "Help".tl,
                      content: Text(
                        widget.help!,
                      ).paddingHorizontal(16).fixWidth(double.infinity),
                      actions: [
                        Button.filled(
                          onPressed: context.pop,
                          child: Text("OK".tl),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
        ],
      ),
      subtitle: Text((widget.optionTranslation[value] ?? "None").tl),
      trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowDown01, size: 18),
      onTap: () {
        var renderBox = context.findRenderObject() as RenderBox;
        var offset = renderBox.localToGlobal(Offset.zero);
        var size = renderBox.size;
        var rect = offset & size;
        showMenu(
          elevation: 3,
          color: context.colorScheme.surfaceContainer,
          context: context,
          position: RelativeRect.fromRect(
            rect,
            Offset.zero & MediaQuery.of(context).size,
          ),
          items: widget.optionTranslation.keys
              .map(
                (key) => PopupMenuItem(
                  value: key,
                  height: App.isMobile ? 46 : 40,
                  child: Text(widget.optionTranslation[key]!.tl),
                ),
              )
              .toList(),
        ).then((value) {
          if (value != null) {
            setState(() {
              if (widget.comicId != null) {
                appdata.settings.setReaderSetting(
                  widget.comicId!,
                  widget.comicSource!,
                  widget.settingKey,
                  value,
                );
              } else if (widget.useDeviceSettings) {
                appdata.settings.setDeviceReaderSetting(
                  widget.settingKey,
                  value,
                );
              } else {
                appdata.settings[widget.settingKey] = value;
              }
            });
            appdata.saveData();
            widget.onChanged?.call();
          }
        });
      },
    );
  }
}

class _EndSelectorSelectSetting extends StatefulWidget {
  const _EndSelectorSelectSetting({
    required this.title,
    required this.settingKey,
    required this.optionTranslation,
    this.onChanged,
    this.help,
    this.comicId,
    this.comicSource,
    this.useDeviceSettings = false,
  });

  final String title;

  final String settingKey;

  final Map<String, String> optionTranslation;

  final VoidCallback? onChanged;

  final String? help;

  final String? comicId;

  final String? comicSource;

  final bool useDeviceSettings;

  @override
  State<_EndSelectorSelectSetting> createState() =>
      _EndSelectorSelectSettingState();
}

class _EndSelectorSelectSettingState extends State<_EndSelectorSelectSetting> {
  @override
  Widget build(BuildContext context) {
    var options = widget.optionTranslation;
    var value = widget.comicId != null
        ? appdata.settings.getReaderSetting(
            widget.comicId!,
            widget.comicSource!,
            widget.settingKey,
          )
        : widget.useDeviceSettings
        ? appdata.settings.getDeviceReaderSetting(widget.settingKey)
        : appdata.settings[widget.settingKey];
    return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Row(
        children: [
          Text(widget.title),
          const SizedBox(width: 4),
          if (widget.help != null)
            Button.icon(
              size: 18,
              icon: HugeIcon(icon: HugeIcons.strokeRoundedHelpCircle, size: 18),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return ContentDialog(
                      title: "Help".tl,
                      content: Text(
                        widget.help!,
                      ).paddingHorizontal(16).fixWidth(double.infinity),
                      actions: [
                        Button.filled(
                          onPressed: context.pop,
                          child: Text("OK".tl),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
        ],
      ),
      trailing: Select(
        current: options[value]?.tl ?? "None".tl,
        values: options.values.map((v) => v.tl).toList(),
        minWidth: 64,
        onTap: (index) {
          setState(() {
            var value = options.keys.elementAt(index);
            if (widget.comicId != null) {
              appdata.settings.setReaderSetting(
                widget.comicId!,
                widget.comicSource!,
                widget.settingKey,
                value,
              );
            } else if (widget.useDeviceSettings) {
              appdata.settings.setDeviceReaderSetting(widget.settingKey, value);
            } else {
              appdata.settings[widget.settingKey] = value;
            }
          });
          appdata.saveData();
          widget.onChanged?.call();
        },
      ),
    );
  }
}

class _SliderSetting extends StatefulWidget {
  const _SliderSetting({
    required this.title,
    required this.settingsIndex,
    required this.interval,
    required this.min,
    required this.max,
    this.onChanged,
    this.comicId,
    this.comicSource,
    this.useDeviceSettings = false,
    this.valueSuffix = '',
    this.divisions,
    this.roundToInt = false,
  });

  final String title;

  final String settingsIndex;

  final double interval;

  final double min;

  final double max;

  final VoidCallback? onChanged;

  final String? comicId;

  final String? comicSource;

  final bool useDeviceSettings;

  final String valueSuffix;

  /// When null, the slider is continuous (free drag). Otherwise snaps to
  /// the given number of divisions.
  final int? divisions;

  /// When true, the value is rounded to the nearest integer before storing.
  final bool roundToInt;

  @override
  State<_SliderSetting> createState() => _SliderSettingState();
}

class _SliderSettingState extends State<_SliderSetting> {
  @override
  Widget build(BuildContext context) {
    var value =
        (widget.comicId != null
                ? appdata.settings.getReaderSetting(
                    widget.comicId!,
                    widget.comicSource!,
                    widget.settingsIndex,
                  )
                : widget.useDeviceSettings
                ? appdata.settings.getDeviceReaderSetting(widget.settingsIndex)
                : appdata.settings[widget.settingsIndex])
            .toDouble();
    return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(widget.title, softWrap: true, maxLines: 2),
      trailing: Text('${value.toInt()}${widget.valueSuffix}', style: ts.s12),
      subtitle: Slider(
        value: value,
        onChanged: (value) {
          final v = widget.roundToInt
              ? value.round()
              : (value.toInt() == value ? value.toInt() : value);
          setState(() {
            if (widget.comicId != null) {
              appdata.settings.setReaderSetting(
                widget.comicId!,
                widget.comicSource!,
                widget.settingsIndex,
                v,
              );
            } else if (widget.useDeviceSettings) {
              appdata.settings.setDeviceReaderSetting(
                widget.settingsIndex,
                v,
              );
            } else {
              appdata.settings[widget.settingsIndex] = v;
            }
            appdata.saveData();
          });
          widget.onChanged?.call();
        },
        divisions: widget.divisions ??
            ((widget.max - widget.min) / widget.interval).toInt(),
        min: widget.min,
        max: widget.max,
      ),
    );
  }
}

class _PopupWindowSetting extends StatelessWidget {
  const _PopupWindowSetting({required this.title, required this.builder});

  final Widget Function() builder;

  final String title;

  @override
  Widget build(BuildContext context) {
    return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(title),
      trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: 18),
      onTap: () {
        showPopUpWidget(App.rootContext, builder());
      },
    );
  }
}

class _MultiPagesFilter extends StatefulWidget {
  const _MultiPagesFilter({
    required this.title,
    required this.settingsIndex,
    required this.pages,
  });

  final String title;

  final String settingsIndex;

  // key - name
  final Map<String, String> pages;

  @override
  State<_MultiPagesFilter> createState() => _MultiPagesFilterState();
}

class _MultiPagesFilterState extends State<_MultiPagesFilter> {
  late List<String> keys;

  @override
  void initState() {
    keys = List.from(appdata.settings[widget.settingsIndex]);
    keys.remove("");
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    Future.microtask(() {
      updateSetting();
    });
  }

  var reorderWidgetKey = UniqueKey();
  var scrollController = ScrollController();
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    var tiles = keys.map((e) => buildItem(e)).toList();

    var view = ReorderableBuilder<String>(
      key: reorderWidgetKey,
      scrollController: scrollController,
      longPressDelay: App.isDesktop
          ? const Duration(milliseconds: 100)
          : const Duration(milliseconds: 500),
      dragChildBoxDecoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 5,
            offset: Offset(0, 2),
            spreadRadius: 2,
          ),
        ],
      ),
      onReorder: (reorderFunc) {
        setState(() {
          keys = List.from(reorderFunc(keys));
        });
      },
      children: tiles,
      builder: (children) {
        return GridView(
          key: _key,
          controller: scrollController,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 1,
            mainAxisExtent: 48,
          ),
          children: children,
        );
      },
    );

    return PopUpWidgetScaffold(
      title: widget.title,
      tailing: [
        if (keys.length < widget.pages.length)
          TextButton.icon(
            label: Text("Add".tl),
            icon: HugeIcon(icon: HugeIcons.strokeRoundedAddCircle, size: 18),
            onPressed: showAddDialog,
          ),
      ],
      body: view,
    );
  }

  Widget buildItem(String key) {
    Widget removeButton = Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton(
        onPressed: () {
          setState(() {
            keys.remove(key);
          });
        },
        icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
      ),
    );

    return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(widget.pages[key] ?? "(Invalid) $key"),
      key: Key(key),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [removeButton, HugeIcon(icon: HugeIcons.strokeRoundedMenu02, size: 18)],
      ),
    );
  }

  void showAddDialog() {
    var canAdd = <String, String>{};
    widget.pages.forEach((key, value) {
      if (!keys.contains(key)) {
        canAdd[key] = value;
      }
    });
    var selected = <String>[];
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return ContentDialog(
              title: "Add".tl,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: canAdd.entries
                    .map(
                      (e) => CheckboxListTile(
                        value: selected.contains(e.key),
                        title: Text(e.value),
                        key: Key(e.key),
                        onChanged: (value) {
                          setState(() {
                            if (value!) {
                              selected.add(e.key);
                            } else {
                              selected.remove(e.key);
                            }
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
              actions: [
                if (selected.length < canAdd.length)
                  TextButton(
                    child: Text("Select All".tl),
                    onPressed: () {
                      setState(() {
                        selected = canAdd.keys.toList();
                      });
                    },
                  )
                else
                  TextButton(
                    child: Text("Deselect All".tl),
                    onPressed: () {
                      setState(() {
                        selected.clear();
                      });
                    },
                  ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: selected.isNotEmpty
                      ? () {
                          this.setState(() {
                            keys.addAll(selected);
                          });
                          Navigator.pop(context);
                        }
                      : null,
                  child: Text("Add".tl),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void updateSetting() {
    appdata.settings[widget.settingsIndex] = keys;
    appdata.saveData();
  }
}

class _CallbackSetting extends StatelessWidget {
  const _CallbackSetting({
    required this.title,
    required this.callback,
    required this.actionTitle,
    this.subtitle,
  });

  final String title;

  final String? subtitle;

  final VoidCallback callback;

  final String actionTitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Button.normal(
        onPressed: callback,
        child: Text(actionTitle),
      ).fixHeight(28),
      onTap: callback,
    );
  }
}

class _SettingPartTitle extends StatelessWidget {
  const _SettingPartTitle({required this.title, required this.icon});

  final String title;

  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 12),
            Text(title, style: ts.s18.copyWith(
              color: cs.onSurface,
            )),
          ],
        ),
      ),
    );
  }
}
