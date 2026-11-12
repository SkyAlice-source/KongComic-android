part of 'settings_page.dart';

/// 阅读器设置的分段。
///
/// 原来「阅读器设置」一页 30 多项、要滚两屏多，找「音量键翻页」得从头扫。
/// 根页把它拆成两页：一页管「内容怎么排（阅读布局 + 图片）」，一页管
/// 「怎么翻、界面长什么样（翻页 + 界面 + 章节评论）」。整页模式（阅读器里
/// 打开、以及带漫画/设备特定设置的场景）仍然是全部内容。
enum ReaderSettingsSection {
  /// 全部（阅读器浮层里打开时用）。
  all,

  /// 阅读布局 + 图片与缩放。
  reading,

  /// 翻页 + 界面 + 章节与评论。
  turning,
}

class ReaderSettings extends StatefulWidget {
  const ReaderSettings({
    super.key,
    this.onChanged,
    this.comicId,
    this.comicSource,
    this.appbarColor,
    this.section = ReaderSettingsSection.all,
  });

  final void Function(String key)? onChanged;
  final String? comicId;
  final String? comicSource;

  /// 只渲染哪一段；根页拆出来的两页分别传 [ReaderSettingsSection.reading]
  /// 与 [ReaderSettingsSection.turning]。
  final ReaderSettingsSection section;

  String get _title => switch (section) {
    ReaderSettingsSection.reading => "Reading & images",
    ReaderSettingsSection.turning => "Page & interface",
    ReaderSettingsSection.all => "Reader Settings",
  };

  /// 头部底色。留空时跟随页面底色（[ThemeData.scaffoldBackgroundColor]），
  /// 头部与正文同色、无缝连成一块 —— 之前这里硬编码 surfaceContainerHigh，
  /// 在设置页里就是一截浅灰顶栏压在纯白正文上，怎么看都是两层。
  /// 放进 [showCenteredPanel] 的浮层卡片时才传 surfaceContainerHigh：
  /// 那里卡片本身就是这个色，头部必须与卡片同色，否则又会浮出一块贴纸。
  final Color? appbarColor;

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

  /// 把设置值读成字符串。
  ///
  /// 不能写 `as String?`：备份导入 / WebDAV 同步是把 JSON 原样拷进 settings，
  /// 类型不受默认值表约束，强转抛在 build 里会让整页红屏、连改回来的入口都没了。
  String _readReaderString(String key) => '${_readReaderSetting(key) ?? ''}';

  /// 把设置值读成整数。同一个原因：同步过来的 `3` 可能是 `3.0`（double），
  /// `as int?` 会抛 `type 'double' is not a subtype of type 'int'`。
  int _readReaderInt(String key, {int fallback = 1}) {
    final raw = _readReaderSetting(key);
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}') ?? fallback;
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

    // 分段只影响「根页拆出来的两页」：整页模式两段都为 true。
    final showReading = widget.section != ReaderSettingsSection.turning;
    final showTurning = widget.section != ReaderSettingsSection.reading;

    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(
          title: Text(widget._title.tl),
          // 实心头（不用毛玻璃，避免把下面滚动内容糊进标题栏），
          // 底色默认跟随页面：设置页里与正文同色，不再出现一条浅灰色带；
          // 浮层面板里由调用方传入卡片同色。
          style: AppbarStyle.shadow,
          backgroundColor: widget.appbarColor,
          leading: IconButton(
            tooltip: "Close".tl,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
        if (comicId != null && sourceKey != null)
          SliverMainAxisGroup(
            slivers: [
              // 用与其它设置项相同的 _KcSettingTile 基座，保证这一行与下方所有
              // 开关行的标题基线、开关位置完全对齐（旧实现手写 InkWell + Padding，
              // 一旦基座改内缩就会错位）。
              _KcSettingTile(
                title: Text("Enable comic specific settings".tl),
                trailing: KcSwitch(
                  value: isEnabledSpecificSettings,
                  semanticLabel: "Enable comic specific settings".tl,
                  onChanged: (b) {
                    setState(() {
                      appdata.settings.setEnabledComicSpecificSettings(
                        comicId,
                        sourceKey,
                        b,
                      );
                    });
                    // 与下面「设备特定设置」对齐：不开关落盘，重启后开关回到关闭，
                    // 这期间设的一整套漫画级配置全部失效（值还在文件里但被忽略）。
                    appdata.saveData();
                  },
                ),
                onTap: () {
                  setState(() {
                    appdata.settings.setEnabledComicSpecificSettings(
                      comicId,
                      sourceKey,
                      !isEnabledSpecificSettings,
                    );
                  });
                  appdata.saveData();
                },
              ).toSliver(),
              if (isEnabledSpecificSettings)
                Center(
                  child: Button.text(
                    onPressed: () {
                      setState(() {
                        appdata.settings.resetComicReaderSettings(key);
                      });
                      // 不落盘的话：界面立刻回到全局值，重启后漫画级配置又冒回来。
                      appdata.saveData();
                    },
                    child: Text(
                      "Clear specific reader settings for this comic".tl,
                    ),
                  ),
                ).toSliver(),
            ],
          ),
        // 「设备特定设置」只在「阅读 & 图片」这一页出现：拆页后两页都会有
        // 这个开关的话，同一个状态在同一次操作里出现两次，用户会以为是两件事。
        if (comicId == null && widget.section != ReaderSettingsSection.turning)
          SliverMainAxisGroup(
            slivers: [
              _KcSettingTile(
                title: Text("Enable device specific settings".tl),
                trailing: KcSwitch(
                  value: useDeviceSpecificSettings,
                  semanticLabel: "Enable device specific settings".tl,
                  onChanged: (b) {
                    setState(() {
                      appdata.settings.setEnabledDeviceSpecificSettings(b);
                    });
                    appdata.saveData();
                  },
                ),
                onTap: () {
                  final b = !useDeviceSpecificSettings;
                  setState(() {
                    appdata.settings.setEnabledDeviceSpecificSettings(b);
                  });
                  appdata.saveData();
                },
              ).toSliver(),
              if (useDeviceSpecificSettings)
                Center(
                  child: Button.text(
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
        // 30 多项平铺时，「翻页」和「图片缩放」混在一条长列表里，找一个开关
        // 得从头扫到尾。按五组切开（翻页 / 阅读布局 / 图片与缩放 / 界面 /
        // 章节与评论），只加标题、不折叠内容 —— 滚动手感不变，但眼睛能先
        // 定位到组。分组依据是「调什么动作」：翻页是手势与翻页节奏，
        // 阅读布局是页面怎么排，两者混在一起时「阅读模式」夹在翻页中间，
        // 用户会以为它也只影响翻页手势。
        if (showTurning) ...[
          _SettingPartTitle(
            title: "Page turning".tl,
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedFlipHorizontal,
              size: 20,
            ),
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
          if (App.isAndroid)
            _SwitchSetting(
              title: 'Turn page by volume keys'.tl,
              settingKey: 'enableTurnPageByVolumeKey',
              onChanged: () {
                widget.onChanged?.call('enableTurnPageByVolumeKey');
              },
              comicId: isEnabledSpecificSettings ? widget.comicId : null,
              comicSource: isEnabledSpecificSettings
                  ? widget.comicSource
                  : null,
              useDeviceSettings: useDeviceSpecificSettings,
            ).toSliver(),
        ],
        if (showReading) ...[
          _SettingPartTitle(
            title: "Reading layout".tl,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedBook02, size: 20),
          ),
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
              final readerMode = _readReaderString('readerMode');
              if (readerMode.toLowerCase().startsWith('continuous')) {
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
          _SwitchSetting(
            title: "Auto Webtoon detection".tl,
            settingKey: "autoDetectWebtoon",
            onChanged: () {
              widget.onChanged?.call("autoDetectWebtoon");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
            useDeviceSettings: useDeviceSpecificSettings,
          ).toSliver(),
          SliverAnimatedVisibility(
            visible: _readReaderString('readerMode').startsWith('gallery'),
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
              comicSource: isEnabledSpecificSettings
                  ? widget.comicSource
                  : null,
              useDeviceSettings: useDeviceSpecificSettings,
            ),
          ),
          SliverAnimatedVisibility(
            visible: _readReaderString('readerMode').startsWith('gallery'),
            child: _SliderSetting(
              title:
                  "The number of pic in screen for portrait (Only Gallery Mode)"
                      .tl,
              settingsIndex: "readerScreenPicNumberForPortrait",
              interval: 1,
              min: 1,
              max: 5,
              onChanged: () {
                // 这一行必须 setState：下面「首屏显示单张图」的 SliverAnimatedVisibility
                // 依赖本项 > 1，漏了 setState 就永远不出现（横屏那个滑块是有的，
                // 于是同一页两个滑块行为不一致）。
                setState(() {});
                widget.onChanged?.call("readerScreenPicNumberForPortrait");
              },
              comicId: isEnabledSpecificSettings ? widget.comicId : null,
              comicSource: isEnabledSpecificSettings
                  ? widget.comicSource
                  : null,
              useDeviceSettings: useDeviceSpecificSettings,
            ),
          ),
          SliverAnimatedVisibility(
            visible:
                _readReaderString('readerMode').startsWith('gallery') &&
                (_readReaderInt('readerScreenPicNumberForLandscape') > 1 ||
                    _readReaderInt('readerScreenPicNumberForPortrait') > 1),
            child: _SwitchSetting(
              title: "Show single image on first page".tl,
              settingKey: "showSingleImageOnFirstPage",
              onChanged: () {
                widget.onChanged?.call("showSingleImageOnFirstPage");
              },
              comicId: isEnabledSpecificSettings ? widget.comicId : null,
              comicSource: isEnabledSpecificSettings
                  ? widget.comicSource
                  : null,
              useDeviceSettings: useDeviceSpecificSettings,
            ),
          ),
          _SettingPartTitle(
            title: "Images & zoom".tl,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedImage02, size: 20),
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
              comicSource: isEnabledSpecificSettings
                  ? widget.comicSource
                  : null,
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
            // 阅读器的 preCacheCount 按 int 用；显式取整避免导入/同步写进
            // double 后首次翻页抛类型错误（读取侧另有 num→int 兜底）。
            roundToInt: true,
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
            useDeviceSettings: useDeviceSpecificSettings,
          ).toSliver(),
        ],
        if (showTurning) ...[
          _SettingPartTitle(
            title: "Interface".tl,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedEye, size: 20),
          ),
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
          // 全局设置，故意不传 comicId/comicSource/useDeviceSettings：
          // 导航栏是全 App 共用的框架，按漫画或按设备分开配置会自相矛盾
          // （issue #3 的作者要求「加一个开关自行选择」）。
          _SwitchSetting(
            title: "Hide navigation while reading".tl,
            subtitle:
                "Hides the side/bottom navigation bar so the page fills the screen"
                    .tl,
            settingKey: "autoHideNavigationInReader",
            onChanged: () {
              widget.onChanged?.call("autoHideNavigationInReader");
            },
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
          _SettingPartTitle(
            title: "Chapters & comments".tl,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedComment01, size: 20),
          ),
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
              comicSource: isEnabledSpecificSettings
                  ? widget.comicSource
                  : null,
              useDeviceSettings: useDeviceSpecificSettings,
            ),
          ),
          // 全局章节顺序（不参与漫画/设备级覆盖）
          _SwitchSetting(
            title: "Reverse default chapter order".tl,
            settingKey: "reverseChapterOrder",
          ).toSliver(),
        ],
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
          Button.text(
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
                // 与全站输入框同圆角（kcFieldRadius=16）：10dp 的编辑框在
                // 满屏 16dp 圆角里像一块遗留的旧控件。
                borderRadius: BorderRadius.circular(kcFieldRadius),
                border: Border.all(
                  color: kcHairlineColor(context),
                  width: kcHairline,
                ),
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
