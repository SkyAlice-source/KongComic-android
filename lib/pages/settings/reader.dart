part of 'settings_page.dart';

class ReaderSettings extends StatefulWidget {
  const ReaderSettings({
    super.key,
    this.onChanged,
    this.comicId,
    this.comicSource,
  });

  final void Function(String key)? onChanged;
  final String? comicId;
  final String? comicSource;

  @override
  State<ReaderSettings> createState() => _ReaderSettingsState();
}

class _ReaderSettingsState extends State<ReaderSettings> {
  bool _isChapterCommentsAtEndSupported() {
    // Route through the scope-aware helpers: reading the global key directly
    // skips the comic- and device-specific overrides, so this entry would show
    // (or hide) based on the wrong value.
    final readerMode = _readReaderSetting('readerMode');
    final showChapterComments = _readReaderSetting('showChapterComments');

    // Must have showChapterComments enabled and be in gallery mode
    if (showChapterComments != true) return false;

    return readerMode == 'galleryLeftToRight' ||
        readerMode == 'galleryRightToLeft';
  }

  void _onShowChapterCommentsChanged() {
    // When showChapterComments is turned off, also turn off
    // showChapterCommentsAtEnd — and do it in the same override scope. Writing
    // the global key used to miss entirely whenever comic- or device-specific
    // settings were in effect.
    final showChapterComments = _readReaderSetting('showChapterComments');
    if (showChapterComments != true) {
      _writeReaderSetting('showChapterCommentsAtEnd', false);
    }
    setState(() {});
    widget.onChanged?.call("showChapterComments");
  }

  /// Read a reader setting honoring the active override scope
  /// (comic-specific > device-specific > global).
  dynamic _readReaderSetting(String key) {
    final comicId = widget.comicId;
    final sourceKey = widget.comicSource;
    if (comicId != null &&
        sourceKey != null &&
        appdata.settings.isComicSpecificSettingsEnabled(comicId, sourceKey)) {
      return appdata.settings.getReaderSetting(comicId, sourceKey, key);
    }
    if (appdata.settings.isDeviceSpecificSettingsEnabled()) {
      return appdata.settings.getDeviceReaderSetting(key);
    }
    return appdata.settings[key];
  }

  /// Write a reader setting honoring the active override scope
  /// (comic-specific > device-specific > global).
  void _writeReaderSetting(String key, dynamic value) {
    final comicId = widget.comicId;
    final sourceKey = widget.comicSource;
    if (comicId != null &&
        sourceKey != null &&
        appdata.settings.isComicSpecificSettingsEnabled(comicId, sourceKey)) {
      appdata.settings.setReaderSetting(comicId, sourceKey, key, value);
    } else if (appdata.settings.isDeviceSpecificSettingsEnabled()) {
      appdata.settings.setDeviceReaderSetting(key, value);
    } else {
      appdata.settings[key] = value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final comicId = widget.comicId;
    final sourceKey = widget.comicSource;
    final key = "$comicId@$sourceKey";

    bool isEnabledSpecificSettings =
        comicId != null &&
        appdata.settings.isComicSpecificSettingsEnabled(comicId, sourceKey);
    bool useDeviceSpecificSettings =
        !isEnabledSpecificSettings &&
        appdata.settings.isDeviceSpecificSettingsEnabled();

    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Reader Settings".tl)),
        if (comicId != null && sourceKey != null)
          SliverMainAxisGroup(
            slivers: [
              SwitchListTile(
                title: Text("Enable comic specific settings".tl),
                value: isEnabledSpecificSettings,
                onChanged: (b) {
                  setState(() {
                    appdata.settings.setEnabledComicSpecificSettings(
                      comicId,
                      sourceKey,
                      b,
                    );
                  });
                },
              ).toSliver(),
              if (isEnabledSpecificSettings)
                Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        appdata.settings.resetComicReaderSettings(key);
                      });
                    },
                    child: Text(
                      "Clear specific reader settings for this comic".tl,
                    ),
                  ),
                ).toSliver(),
            ],
          ),
        if (comicId == null)
          SliverMainAxisGroup(
            slivers: [
              InkWell(
                onTap: () {
                  final b = !useDeviceSpecificSettings;
                  setState(() {
                    appdata.settings.setEnabledDeviceSpecificSettings(b);
                  });
                  appdata.saveData();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text("Enable device specific settings".tl),
                      ),
                      const SizedBox(width: 12),
                      Switch(
                        value: useDeviceSpecificSettings,
                        onChanged: (b) {
                          setState(() {
                            appdata.settings.setEnabledDeviceSpecificSettings(b);
                          });
                          appdata.saveData();
                        },
                      ),
                    ],
                  ),
                ),
              ).toSliver(),
              if (useDeviceSpecificSettings)
                Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        appdata.settings.resetDeviceReaderSettings();
                      });
                      appdata.saveData();
                    },
                    child: Text(
                      "Clear specific reader settings for this device".tl,
                    ),
                  ),
                ).toSliver(),
            ],
          ),
        _SwitchSetting(
          title: "Tap to turn Pages".tl,
          settingKey: "enableTapToTurnPages",
          onChanged: () {
            widget.onChanged?.call("enableTapToTurnPages");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SwitchSetting(
          title: "Reverse tap to turn Pages".tl,
          settingKey: "reverseTapToTurnPages",
          onChanged: () {
            widget.onChanged?.call("reverseTapToTurnPages");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        SelectSetting(
          title: "Tap Zone Layout".tl,
          settingKey: "tapZoneLayout",
          optionTranslation: {
            "default": "Default (30% edges)".tl,
            "leftRight": "Left & Right".tl,
            "rightOnly": "Right side only".tl,
            "leftOnly": "Left side only".tl,
            "edge": "Edge (15% edges)".tl,
          },
          onChanged: () {
            setState(() {});
            widget.onChanged?.call("tapZoneLayout");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SwitchSetting(
          title: "Page animation".tl,
          settingKey: "enablePageAnimation",
          onChanged: () {
            widget.onChanged?.call("enablePageAnimation");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        SelectSetting(
          title: "Reading mode".tl,
          settingKey: "readerMode",
          optionTranslation: {
            "galleryLeftToRight": "Gallery (Left to Right)".tl,
            "galleryRightToLeft": "Gallery (Right to Left)".tl,
            "galleryTopToBottom": "Gallery (Top to Bottom)".tl,
            "continuousLeftToRight": "Continuous (Left to Right)".tl,
            "continuousRightToLeft": "Continuous (Right to Left)".tl,
            "continuousTopToBottom": "Continuous (Top to Bottom)".tl,
          },
          onChanged: () {
            setState(() {});
            var readerMode = _readReaderSetting('readerMode') as String?;
            if (readerMode?.toLowerCase().startsWith('continuous') ?? false) {
              _writeReaderSetting('readerScreenPicNumberForLandscape', 1);
              widget.onChanged?.call('readerScreenPicNumberForLandscape');
              _writeReaderSetting('readerScreenPicNumberForPortrait', 1);
              widget.onChanged?.call('readerScreenPicNumberForPortrait');
            }
            widget.onChanged?.call("readerMode");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SliderSetting(
          title: "Auto page turning interval".tl,
          settingsIndex: "autoPageTurningInterval",
          interval: 1,
          min: 1,
          max: 20,
          onChanged: () {
            setState(() {});
            widget.onChanged?.call("autoPageTurningInterval");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        SliverAnimatedVisibility(
          visible: (_readReaderSetting('readerMode') as String? ?? '')
              .startsWith('gallery'),
          child: _SliderSetting(
            title:
                "The number of pic in screen for landscape (Only Gallery Mode)"
                    .tl,
            settingsIndex: "readerScreenPicNumberForLandscape",
            interval: 1,
            min: 1,
            max: 5,
            onChanged: () {
              setState(() {});
              widget.onChanged?.call("readerScreenPicNumberForLandscape");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
            useDeviceSettings: useDeviceSpecificSettings,
          ),
        ),
        SliverAnimatedVisibility(
          visible: (_readReaderSetting('readerMode') as String? ?? '')
              .startsWith('gallery'),
          child: _SliderSetting(
            title:
                "The number of pic in screen for portrait (Only Gallery Mode)"
                    .tl,
            settingsIndex: "readerScreenPicNumberForPortrait",
            interval: 1,
            min: 1,
            max: 5,
            onChanged: () {
              widget.onChanged?.call("readerScreenPicNumberForPortrait");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
            useDeviceSettings: useDeviceSpecificSettings,
          ),
        ),
        SliverAnimatedVisibility(
          visible:
              (_readReaderSetting('readerMode') as String? ?? '')
                  .startsWith('gallery') &&
              ((_readReaderSetting('readerScreenPicNumberForLandscape') as int? ??
                          1) >
                      1 ||
                  (_readReaderSetting('readerScreenPicNumberForPortrait')
                              as int? ??
                          1) >
                      1),
          child: _SwitchSetting(
            title: "Show single image on first page".tl,
            settingKey: "showSingleImageOnFirstPage",
            onChanged: () {
              widget.onChanged?.call("showSingleImageOnFirstPage");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
            useDeviceSettings: useDeviceSpecificSettings,
          ),
        ),
        _SwitchSetting(
          title: 'Double tap to zoom'.tl,
          settingKey: 'enableDoubleTapToZoom',
          onChanged: () {
            setState(() {});
            widget.onChanged?.call('enableDoubleTapToZoom');
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SwitchSetting(
          title: 'Long press to zoom'.tl,
          settingKey: 'enableLongPressToZoom',
          onChanged: () {
            setState(() {});
            widget.onChanged?.call('enableLongPressToZoom');
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        SliverAnimatedVisibility(
          // Must respect the same override scope as the switch above, otherwise
          // with comic/device-specific settings enabled this sub-option never
          // appears even though long-press zoom is on in this scope.
          visible: _readReaderSetting('enableLongPressToZoom') == true,
          child: SelectSetting(
            title: "Long press zoom position".tl,
            settingKey: "longPressZoomPosition",
            optionTranslation: {
              "press": "Press position".tl,
              "center": "Screen center".tl,
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
            useDeviceSettings: useDeviceSpecificSettings,
          ),
        ),
        SelectSetting(
          title: "Image Fit Mode".tl,
          settingKey: "imageFitMode",
          optionTranslation: {
            "contain": "Fit screen".tl,
            "fitWidth": "Fit width".tl,
            "fitHeight": "Fit height".tl,
            "cover": "Fill screen".tl,
          },
          onChanged: () {
            setState(() {});
            widget.onChanged?.call("imageFitMode");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SliderSetting(
          title: 'Image display scale'.tl,
          settingsIndex: 'imageDisplayScale',
          interval: 1,
          min: 100,
          max: 200,
          divisions: null,
          roundToInt: true,
          valueSuffix: '%',
          onChanged: () {
            setState(() {});
            widget.onChanged?.call('imageDisplayScale');
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SwitchSetting(
          title: 'Limit image width'.tl,
          subtitle: 'When using Continuous(Top to Bottom) mode'.tl,
          settingKey: 'limitImageWidth',
          onChanged: () {
            widget.onChanged?.call('limitImageWidth');
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SliderSetting(
          title: 'Webtoon side margin'.tl,
          settingsIndex: 'webtoonSidePadding',
          interval: 1,
          min: 0,
          max: 30,
          divisions: null,
          roundToInt: true,
          valueSuffix: '%',
          onChanged: () {
            setState(() {});
            widget.onChanged?.call('webtoonSidePadding');
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        if (App.isAndroid)
          _SwitchSetting(
            title: 'Turn page by volume keys'.tl,
            settingKey: 'enableTurnPageByVolumeKey',
            onChanged: () {
              widget.onChanged?.call('enableTurnPageByVolumeKey');
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
            useDeviceSettings: useDeviceSpecificSettings,
          ).toSliver(),
        _SwitchSetting(
          title: "Display time & battery info in reader".tl,
          settingKey: "enableClockAndBatteryInfoInReader",
          onChanged: () {
            widget.onChanged?.call("enableClockAndBatteryInfoInReader");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SwitchSetting(
          title: "Show system status bar".tl,
          settingKey: "showSystemStatusBar",
          onChanged: () {
            widget.onChanged?.call("showSystemStatusBar");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SwitchSetting(
          title: "Keep screen on".tl,
          settingKey: "keepScreenOn",
          onChanged: () {
            setState(() {});
            widget.onChanged?.call("keepScreenOn");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        SelectSetting(
          title: "Screen orientation".tl,
          settingKey: "screenOrientation",
          optionTranslation: {
            "unspecified": "Follow system".tl,
            "portrait": "Portrait".tl,
            "landscape": "Landscape".tl,
          },
          onChanged: () {
            setState(() {});
            widget.onChanged?.call("screenOrientation");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        SelectSetting(
          title: "Quick collect image".tl,
          settingKey: "quickCollectImage",
          optionTranslation: {
            "No": "Not enable".tl,
            "DoubleTap": "Double Tap".tl,
            "Swipe": "Swipe".tl,
          },
          onChanged: () {
            widget.onChanged?.call("quickCollectImage");
          },
          help:
              "On the image browsing page, you can quickly collect images by sliding horizontally or vertically according to your reading mode"
                  .tl,
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _CallbackSetting(
          title: "Custom Image Processing".tl,
          callback: () => context.to(() => _CustomImageProcessing()),
          actionTitle: "Edit".tl,
        ).toSliver(),
        _SliderSetting(
          title: "Number of images preloaded".tl,
          settingsIndex: "preloadImageCount",
          interval: 1,
          min: 1,
          max: 16,
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SwitchSetting(
          title: "Show Page Number".tl,
          settingKey: "showPageNumberInReader",
          onChanged: () {
            widget.onChanged?.call("showPageNumberInReader");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SwitchSetting(
          title: "Show Chapter Comments".tl,
          settingKey: "showChapterComments",
          onChanged: _onShowChapterCommentsChanged,
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        SliverAnimatedVisibility(
          visible: _isChapterCommentsAtEndSupported(),
          child: _SwitchSetting(
            title: "Show Comments at Chapter End".tl,
            settingKey: "showChapterCommentsAtEnd",
            onChanged: () {
              widget.onChanged?.call("showChapterCommentsAtEnd");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
            useDeviceSettings: useDeviceSpecificSettings,
          ),
        ),
        // 全局章节顺序（不参与漫画/设备级覆盖）
        _SwitchSetting(
          title: "Reverse default chapter order".tl,
          settingKey: "reverseChapterOrder",
        ).toSliver(),
      ],
    );
  }
}

class _CustomImageProcessing extends StatefulWidget {
  const _CustomImageProcessing();

  @override
  State<_CustomImageProcessing> createState() => __CustomImageProcessingState();
}

class __CustomImageProcessingState extends State<_CustomImageProcessing> {
  var current = '';

  @override
  void initState() {
    super.initState();
    current = appdata.settings['customImageProcessing'];
  }

  @override
  void dispose() {
    appdata.settings['customImageProcessing'] = current;
    appdata.saveData();
    super.dispose();
  }

  int resetKey = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: Appbar(
        title: Text("Custom Image Processing".tl),
        actions: [
          TextButton(
            onPressed: () {
              current = defaultCustomImageProcessing;
              appdata.settings['customImageProcessing'] = current;
              resetKey++;
              setState(() {});
            },
            child: Text("Reset".tl),
          ),
        ],
      ),
      body: Column(
        children: [
          _SwitchSetting(
            title: "Enable".tl,
            settingKey: "enableCustomImageProcessing",
          ),
          Expanded(
            child: Container(
              margin: EdgeInsets.all(kcSpaceSm),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kcRadius4),
                border: Border.all(color: context.colorScheme.outlineVariant),
              ),
              child: SizedBox.expand(
                child: CodeEditor(
                  key: ValueKey(resetKey),
                  initialValue: appdata.settings['customImageProcessing'],
                  onChanged: (value) {
                    current = value;
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
