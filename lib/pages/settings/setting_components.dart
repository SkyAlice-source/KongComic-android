part of 'settings_page.dart';

// ════════════════════════════════════════════════════════════════════
// 设置页统一视觉元件（2026-10-19 重做）
//
// 旧版直接堆 ListTile + Material 默认 Switch：
//   · 每行 48~56dp 全靠留白分隔，行与行之间没有结构线，长列表显得松散；
//   · 默认开关 52×32，在 14sp 正文旁边偏笨重，开态还是高饱和的 Material
//     主色块，和 App 里其它「大圆角 + 克制用色」的卡片不在一个语汇；
//   · 默认滑块 8dp 粗轨 + 大圆点，数值只是一个裸数字，读起来像调试界面。
//
// 这里把行/开关/滑块/选择器收口成一套元件，各设置页只管往里塞内容：
//   _KcSettingTile   统一行基座（标题 / 副标题 / 右侧值 / trailing / 底部细线）
//   KcSwitch        44×26 胶囊开关，主色轨道 + 中性灰关态
//   _KcChevron       弱化的 18dp 箭头（右 / 下）
//   _KcValuePill     数值气泡（滑块右侧的「1」「80%」）
//   _kcSliderTheme   细轨 + 小圆点的滑块主题
// ════════════════════════════════════════════════════════════════════

/// 行内容的左右内缩。比旧版 ListTile 的 16 略宽，配合底部细线后
/// 文字与线之间留出呼吸，长列表也不显得挤。
const double _kcRowInset = 20;

/// 弱化箭头：设置行里的箭头是「可以进去」的提示，不该和正文抢注意力，
/// 因此统一压低到 onSurfaceVariant 的 42%。
class _KcChevron extends StatelessWidget {
  const _KcChevron({this.down = false});

  final bool down;

  static const double _size = 18;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return HugeIcon(
      icon: down
          ? HugeIcons.strokeRoundedArrowDown01
          : HugeIcons.strokeRoundedArrowRight01,
      size: _size,
      color: cs.onSurfaceVariant.withValues(alpha: 0.42),
    );
  }
}

/// 行与行之间的发丝线。
///
/// 不用 `outlineVariant`：AMOLED 下它约为 `#2A2A2A`，和纯黑底只差一点点，
/// 截图里几乎整条线消失；亮色下又偏灰。改为按亮度取「黑 / 白 + 极低透明度」，
/// 两端 8% 渐变淡出，视觉上是一条柔和的定位线，而不是硬切的表格框。
class _KcRowDivider extends StatelessWidget {
  const _KcRowDivider();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final line = (isDark ? Colors.white : Colors.black).withValues(
      alpha: isDark ? 0.085 : 0.06,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kcRowInset),
      child: SizedBox(
        height: 0.7,
        // 显式撑满：Column 的交叉轴是松约束，只给高度的 Container 会量到 0 宽。
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                line.withValues(alpha: 0),
                line,
                line,
                line.withValues(alpha: 0),
              ],
              stops: const [0, 0.08, 0.92, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// 右侧当前值胶囊。
///
/// 旧实现是裸的灰色文本，长行里看不出「这是一个可选项的当前值」；给一层
/// 极淡底 + 小圆角后，行内形成「标题 / 值 / 箭头」三段结构，扫视更快。
class _KcValueChip extends StatelessWidget {
  const _KcValueChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : cs.onSurface.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(kcRadius8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: kcBody,
          height: 1.3,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 数值气泡：滑块右侧显示当前值。
class _KcValuePill extends StatelessWidget {
  const _KcValuePill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(kcPillRadius),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: kcCaption,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// 设置行基座。
///
/// 所有设置项（开关 / 选择 / 跳转 / 回调 / 滑块）都由它排版，
/// 从而保证各页的标题基线、右侧控件位置、行高完全一致。
class _KcSettingTile extends StatelessWidget {
  const _KcSettingTile({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleMaxLines = 2,
    this.value,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    this.compact = false,
  });

  /// 标题（允许传 Row，用于内嵌帮助按钮）。
  final Widget title;

  final String? subtitle;

  /// 副标题行数上限（路径、文件名这类长文本传 1 强制单行省略）。
  final int subtitleMaxLines;

  /// 右侧当前值（选择器）。系统字号很大时会自动折到标题下方。
  final String? value;

  final Widget? trailing;

  final VoidCallback? onTap;

  final bool showDivider;

  /// 紧凑模式：用于固定行高的网格（如 _MultiPagesFilter 的 52dp 行）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 系统字号放大到 ≈1.35 倍以上时，标题 + 右侧值同排会互相挤压，
    // 退化成「标题 / 值」两行（与系统设置在大字号下的行为一致）。
    final stackValue =
        value != null && MediaQuery.textScalerOf(context).scale(kcBody) > 19;

    final titleStyle = TextStyle(
      fontSize: kcBody,
      height: 1.35,
      fontWeight: FontWeight.w500,
      // 纯黑底上纯白正文偏「硬」，压到 93% 更像纸面印刷的墨色。
      color: isDark ? cs.onSurface.withValues(alpha: 0.93) : cs.onSurface,
    );
    final captionStyle = TextStyle(
      fontSize: kcCaption,
      height: 1.35,
      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            // 整行是点击区：不用默认的圆形水波（大面积灰色水波在暗色下发脏），
            // 改成极淡的整行高亮，点按像是「纸面被压了一下」。
            splashFactory: NoSplash.splashFactory,
            highlightColor: isDark
                ? Colors.white.withValues(alpha: 0.035)
                : Colors.black.withValues(alpha: 0.025),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _kcRowInset,
                // 56dp 行是「有右侧控件」的舒适高度；紧凑模式下行高交给外层网格。
                vertical: compact ? 6 : 12,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: compact ? 36 : 32),
                child: Row(
                  children: [
                    Expanded(
                      child: DefaultTextStyle.merge(
                        style: titleStyle,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            title,
                            if (subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  subtitle!,
                                  maxLines: subtitleMaxLines,
                                  overflow: TextOverflow.ellipsis,
                                  style: captionStyle,
                                ),
                              ),
                            if (stackValue)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  value!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: captionStyle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (value != null && !stackValue) ...[
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        // 值最多占屏幕的 42%，超长时省略，标题始终有位置。
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.42,
                        ),
                        child: _KcValueChip(value!),
                      ),
                    ],
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showDivider) const _KcRowDivider(),
      ],
    );
  }
}

/// 标题右侧的帮助按钮（原样式保留，仅把图标压成低对比灰）。
class _KcHelpButton extends StatelessWidget {
  const _KcHelpButton(this.help);

  final String help;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Button.icon(
      size: 18,
      icon: HugeIcon(
        icon: HugeIcons.strokeRoundedHelpCircle,
        size: 18,
        color: cs.onSurfaceVariant.withValues(alpha: 0.55),
      ),
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) {
            return ContentDialog(
              title: "Help".tl,
              content: Text(
                help,
              ).paddingHorizontal(16).fixWidth(double.infinity),
              actions: [
                Button.filled(onPressed: context.pop, child: Text("OK".tl)),
              ],
            );
          },
        );
      },
    );
  }
}

/// 细轨滑块主题：4dp 轨道、8dp 圆点、弱化的拖拽光晕。
///
/// 轨道/圆点走品牌强调色而不是 `cs.primary`：AMOLED 的灰阶 primary 会让滑块
/// 整条掉成灰色，和开关的红色也不在一个体系里。
SliderThemeData _kcSliderThemeData(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final accent = kcAccentColor(context);
  return SliderThemeData(
    trackHeight: 4,
    activeTrackColor: accent,
    inactiveTrackColor: cs.surfaceContainerHighest,
    disabledActiveTrackColor: accent.withValues(alpha: 0.38),
    disabledInactiveTrackColor: cs.surfaceContainerHighest,
    thumbColor: accent,
    disabledThumbColor: accent.withValues(alpha: 0.38),
    // 小圆点 + 一圈白边，让拇指在深浅两种底色上都能「浮」起来。
    thumbShape: const RoundSliderThumbShape(
      enabledThumbRadius: 8,
      elevation: 1.5,
      pressedElevation: 3,
    ),
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
    overlayColor: accent.withValues(alpha: 0.12),
    trackShape: const RoundedRectSliderTrackShape(),
    tickMarkShape: SliderTickMarkShape.noTickMark,
    showValueIndicator: ShowValueIndicator.never,
  );
}

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
    // 先取 dynamic 再 `== true` 归一化：老版本 appdata.json 里可能根本没有这个
    // key（新增设置项若漏写进 Settings 的默认值表），直接 `bool v = ...` 会在
    // 运行时抛 `type 'Null' is not a subtype of type 'bool'`，整行渲染成红色报错。
    final dynamic rawValue = widget.comicId != null
        ? appdata.settings.getReaderSetting(
            widget.comicId!,
            widget.comicSource!,
            widget.settingKey,
          )
        : widget.useDeviceSettings
        ? appdata.settings.getDeviceReaderSetting(widget.settingKey)
        : appdata.settings[widget.settingKey];
    final bool value = rawValue == true;

    void toggle(bool v) {
      HapticFeedback.selectionClick();
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

    return _KcSettingTile(
      title: Text(widget.title),
      subtitle: widget.subtitle,
      trailing: KcSwitch(value: value, onChanged: toggle),
      onTap: () => toggle(!value),
    );
  }
}

class SelectSetting extends StatefulWidget {
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
  State<SelectSetting> createState() => _SelectSettingState();
}

class _SelectSettingState extends State<SelectSetting> {
  dynamic get _value => widget.comicId != null
      ? appdata.settings.getReaderSetting(
          widget.comicId!,
          widget.comicSource!,
          widget.settingKey,
        )
      : widget.useDeviceSettings
      ? appdata.settings.getDeviceReaderSetting(widget.settingKey)
      : appdata.settings[widget.settingKey];

  void _write(dynamic value) {
    setState(() {
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
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    final current = widget.optionTranslation[value]?.tl ?? "None".tl;

    return _KcSettingTile(
      title: Row(
        children: [
          Flexible(child: Text(widget.title, overflow: TextOverflow.ellipsis)),
          if (widget.help != null) ...[
            const SizedBox(width: 4),
            _KcHelpButton(widget.help!),
          ],
        ],
      ),
      value: current,
      trailing: const _KcChevron(down: true),
      onTap: () => _showMenu(context),
    );
  }

  void _showMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final rect = offset & renderBox.size;
    final keys = widget.optionTranslation.keys.toList();
    // 选中态用品牌强调色；暗色零彩色，改用中性灰（主题 primary），菜单里不再冒红。
    final accentText = kcBrandAdaptive(context);
    // 锚点必须落在行的右端，否则菜单会从屏幕左边弹出来：
    // showMenu 按「position.left < position.right 就向右展开」定位，
    // 传入整行（左 0 / 右 = 屏宽）时永远得到 left = 0。这里只传行右端
    // 1px 宽的一条，菜单被屏幕右边界挤回来后自然右对齐到值的下方。
    // top 取行的下沿：菜单从这一行「下面」展开，不会盖住当前值。
    final anchor = Rect.fromLTWH(
      rect.right - 1,
      rect.bottom + 6,
      1,
      rect.height,
    );
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        anchor,
        Offset.zero & MediaQuery.of(context).size,
      ),
      // 下拉宽度统一：太窄时「简体中文」这类值会贴着边，太宽又不像下拉。
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
      items: keys.map((key) {
        final selected = key == _value;
        return PopupMenuItem(
          value: key,
          height: App.isMobile ? 44 : 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // 选中项前放一枚主色对勾：菜单里也能一眼看出当前值。
              SizedBox(
                width: 24,
                child: selected
                    ? HugeIcon(
                        icon: HugeIcons.strokeRoundedTick02,
                        size: 18,
                        color: accentText,
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  widget.optionTranslation[key]!.tl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: selected
                      ? TextStyle(
                          color: accentText,
                          fontWeight: FontWeight.w600,
                        )
                      : null,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((value) {
      if (value != null && value != _value) {
        _write(value);
      }
    });
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
    final cs = Theme.of(context).colorScheme;
    final value =
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

    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(_kcRowInset, 12, _kcRowInset, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: kcBody,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _KcValuePill('${_formatValue(value)}${widget.valueSuffix}'),
              ],
            ),
          ),
          Padding(
            // 轨道两端与标题文字对齐（左 20 / 右 20）。Slider 默认还会再
            // 自带 24dp 水平内边距，因此内部再清零，避免二次缩进或溢出到屏幕边缘。
            padding: const EdgeInsets.symmetric(horizontal: _kcRowInset),
            child: SliderTheme(
              data: _kcSliderThemeData(context),
              child: Slider(
                value: value.clamp(widget.min, widget.max),
                padding: EdgeInsets.zero,
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
                divisions:
                    widget.divisions ??
                    ((widget.max - widget.min) / widget.interval).toInt(),
                min: widget.min,
                max: widget.max,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const _KcRowDivider(),
        ],
      ),
    );
  }

  /// 值显示：整数不带小数点；带小数的（如缩略图缩放 1.05）保留到两位并去掉
  /// 无意义的尾零。旧实现一律 `toInt()`，1.05 会显示成「1」，与实际缩放不符。
  String _formatValue(double value) {
    if ((value - value.round()).abs() < 0.001) {
      return '${value.round()}';
    }
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }
}

class _PopupWindowSetting extends StatelessWidget {
  const _PopupWindowSetting({required this.title, required this.builder});

  final Widget Function() builder;

  final String title;

  @override
  Widget build(BuildContext context) {
    return _KcSettingTile(
      title: Text(title),
      trailing: const _KcChevron(),
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
    // 延后到本帧的 dispose 完成后再写回：updateSetting() 会 saveData() →
    // notifyListeners，在 dispose 期间同步触发会让其他监听者在这棵子树已失效时
    // setState。
    Future.microtask(updateSetting);
    // 外部创建的 ScrollController 不会被 ScrollView 自动释放，必须自己关。
    scrollController.dispose();
    super.dispose();
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
            mainAxisExtent: 52,
          ),
          children: children,
        );
      },
    );

    return PopUpWidgetScaffold(
      title: widget.title,
      tailing: [
        if (keys.length < widget.pages.length)
          Button.text(
            onPressed: showAddDialog,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HugeIcon(icon: HugeIcons.strokeRoundedAddCircle, size: 18),
                const SizedBox(width: 6),
                Text("Add".tl),
              ],
            ),
          ),
      ],
      body: view,
    );
  }

  Widget buildItem(String key) {
    final cs = Theme.of(context).colorScheme;
    Widget removeButton = SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        tooltip: "Delete".tl,
        onPressed: () {
          setState(() {
            keys.remove(key);
          });
        },
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedDelete01,
          size: 18,
          color: cs.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      ),
    );

    return _KcSettingTile(
      key: Key(key),
      title: Text(widget.pages[key] ?? "(Invalid) $key"),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          removeButton,
          const SizedBox(width: 4),
          HugeIcon(
            icon: HugeIcons.strokeRoundedMenu02,
            size: 18,
            color: cs.onSurfaceVariant.withValues(alpha: 0.42),
          ),
        ],
      ),
      compact: true,
      showDivider: false,
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
                  Button.text(
                    child: Text("Select All".tl),
                    onPressed: () {
                      setState(() {
                        selected = canAdd.keys.toList();
                      });
                    },
                  )
                else
                  Button.text(
                    child: Text("Deselect All".tl),
                    onPressed: () {
                      setState(() {
                        selected.clear();
                      });
                    },
                  ),
                const SizedBox(width: 8),
                Button.filled(
                  color: selected.isEmpty
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : null,
                  onPressed: () {
                    if (selected.isEmpty) return;
                    this.setState(() {
                      keys.addAll(selected);
                    });
                    Navigator.pop(context);
                  },
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

/// 破坏性操作的胶囊按钮。
///
/// 删除类操作不该和「测试下载源」这种普通动作用同一颗中性灰按钮：
/// 淡红底 + 红字既点明后果，又比整块高饱和红克制，不会在设置页里抢焦点。
class _KcDangerButton extends StatelessWidget {
  const _KcDangerButton({required this.label, required this.onPressed});

  final String label;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 破坏性操作保留语义红：即便深色零彩色，删除类动作也不能退化成中性灰，
    // 否则用户难以第一时间识别「这是危险操作」。
    final accent = kcBrandColor;
    final fg = isDark ? kcBrandColorOnDark : kcBrandColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(kcPillRadius),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: isDark ? 0.14 : 0.08),
            borderRadius: BorderRadius.circular(kcPillRadius),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.20 : 0.14),
              width: 0.6,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: kcCaption + 1,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CallbackSetting extends StatelessWidget {
  const _CallbackSetting({
    required this.title,
    required this.callback,
    required this.actionTitle,
    this.subtitle,
    this.destructive = false,
  });

  final String title;

  final String? subtitle;

  final VoidCallback callback;

  final String actionTitle;

  /// 删除 / 清空这类不可逆操作传 true，按钮转成淡红底红字。
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return _KcSettingTile(
      title: Text(title),
      subtitle: subtitle,
      trailing: destructive
          ? _KcDangerButton(label: actionTitle, onPressed: callback)
          : Button.normal(
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
      child: Padding(
        // 分组标题只做「轻分隔」：小一号、灰色、带一点字距，避免和正文标题
        // 抢层级；上边距比下边距大，形成组的呼吸感。
        padding: const EdgeInsets.fromLTRB(_kcRowInset, 18, _kcRowInset, 6),
        child: Row(
          children: [
            IconTheme.merge(
              data: IconThemeData(
                size: 16,
                color: cs.onSurfaceVariant.withValues(alpha: 0.65),
              ),
              child: icon,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: kcCaption,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
