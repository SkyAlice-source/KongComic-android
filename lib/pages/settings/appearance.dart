part of 'settings_page.dart';

/// 外观：主题模式 + 主题色。
///
/// 两项都不用下拉菜单，直接铺在页面上点选：
/// 缩略预览卡（模式）一眼看出差别，色点（主题色）点一下即生效。
/// 改个主题原本要「点整行 → 弹菜单 → 点选项 → 等菜单收起」四步，
/// 现在是设置页里最不该有的往返。
///
/// 语言不在这一页 —— 它跟外观无关，已移到 APP 的「通用」组。
class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({super.key});

  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  String get _mode => appdata.settings['theme_mode'] as String? ?? 'system';

  String get _color => appdata.settings['color'] as String? ?? 'system';

  /// 深色与 AMOLED 的实际底色（与 main.dart 的 getTheme 保持一致）。
  static const _darkBg = kcDarkBackground;
  static const _amoledBg = kcAmoledBackground;
  static const _darkFg = kcDarkForeground;

  void _write(String key, String value) {
    if (appdata.settings[key] == value) return;
    HapticFeedback.selectionClick();
    setState(() => appdata.settings[key] = value);
    appdata.saveData();
    // MaterialApp 在根部，本页 setState 只重绘本页，必须整棵树重建。
    App.forceRebuild();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Appearance".tl)),
        _SettingPartTitle(
          title: "Theme Mode".tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedContrast, size: 20),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kcRowInsetH),
            child: Row(
              spacing: 8,
              children: [
                for (final mode in const ["system", "light", "dark", "amoled"])
                  Expanded(child: _buildModeCard(mode)),
              ],
            ),
          ),
        ),
        _SettingPartTitle(
          title: "Theme Color".tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedPaintBucket, size: 20),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kcRowInsetH),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in kcThemePalettes.entries)
                  _buildColorDot(entry.key, entry.value.$1),
              ],
            ),
          ),
        ),
        // 说清楚它能作用到哪：深色下主题色本来就统一成品牌红，AMOLED 是纯灰阶。
        // 不写这句，用户在深色外观里换色「看不出变化」，只会当成 bug。
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(kcRowInsetH, kcSpaceMd, kcRowInsetH, 0),
            child: Text(
              "Applies to light appearance. Dark always uses brand red, AMOLED is pure grayscale."
                  .tl,
              style: TextStyle(
                fontSize: kcCaption,
                height: 1.35,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeCard(String mode) {
    final selected = _mode == mode;
    final cs = Theme.of(context).colorScheme;
    final accent = kcAccentColor(context);

    return Semantics(
      button: true,
      selected: selected,
      label: _modeLabel(mode),
      child: InkWell(
        borderRadius: BorderRadius.circular(kcCardRadius),
        onTap: () => _write('theme_mode', mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(kcSpaceXs),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kcCardRadius),
            color: selected
                ? accent.withValues(alpha: 0.07)
                : Colors.transparent,
            border: Border.all(
              color: selected ? accent : cs.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(kcRadius8),
                child: AspectRatio(
                  aspectRatio: 1.15,
                  child: _buildPreview(mode),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  _modeLabel(mode),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: kcCaption,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? cs.onSurface
                        : cs.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _modeLabel(String mode) => switch (mode) {
    "light" => "Light".tl,
    "dark" => "Dark".tl,
    "amoled" => "AMOLED".tl,
    _ => "System".tl,
  };

  /// 缩略预览：把「底色 + 文字灰阶 + 强调色」压成几根色条。
  ///
  /// 强调色取当前实际会生效的那一支 —— 深色恒为品牌红、AMOLED 恒为灰，
  /// 否则预览会骗人（在深色卡上画一个用户选中的紫色，点下去却是红的）。
  Widget _buildPreview(String mode) {
    // 不能用 `kcThemePalettes[_color]!`：老版本存过已下线的主题色（如 orange），
    // 这里一解包就抛 null，整个外观页白屏。取不到就和 main.dart 一样退回默认红。
    final picked = (kcThemePalettes[_color] ?? kcThemePalettes['system']!).$1;
    const fgLight = Color(0xFF1A1A1A);

    switch (mode) {
      case "light":
        return _previewPane(Colors.white, fgLight, picked);
      case "dark":
        return _previewPane(_darkBg, _darkFg, kcBrandColorOnDark);
      case "amoled":
        return _previewPane(_amoledBg, _darkFg, const Color(0xFFE0E0E0));
      default:
        // 「跟随系统」左右各一半，直观表达「由系统决定」。
        return Row(
          children: [
            Expanded(child: _previewPane(Colors.white, fgLight, picked)),
            Expanded(child: _previewPane(_darkBg, _darkFg, kcBrandColorOnDark)),
          ],
        );
    }
  }

  Widget _previewPane(Color bg, Color fg, Color accent) {
    Widget bar(double widthFactor, double alpha) => FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: fg.withValues(alpha: alpha),
          borderRadius: BorderRadius.circular(kcRadius3),
        ),
      ),
    );

    return Container(
      color: bg,
      padding: const EdgeInsets.all(5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(0.45, 0.55),
          const SizedBox(height: 4),
          bar(0.95, 0.14),
          const SizedBox(height: 3),
          bar(0.7, 0.14),
          const Spacer(),
          FractionallySizedBox(
            widthFactor: 0.4,
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(kcRadius3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorDot(String key, Color swatch) {
    final selected = _color == key;
    final cs = Theme.of(context).colorScheme;
    // 黄色这类亮色在白底上会「化开」，所以每个点都留一圈淡描边。
    final ring = selected
        ? cs.onSurface
        : cs.outlineVariant.withValues(alpha: 0.5);
    final check = swatch.computeLuminance() > 0.6 ? Colors.black : Colors.white;

    return Semantics(
      button: true,
      selected: selected,
      label: _colorLabel(key),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _write('color', key),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: swatch,
                border: Border.all(color: ring, width: selected ? 2.5 : 1),
              ),
              child: selected
                  ? HugeIcon(
                      icon: HugeIcons.strokeRoundedTick02,
                      size: 18,
                      color: check,
                    )
                  : null,
            ),
            const SizedBox(height: 5),
            Text(
              _colorLabel(key),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: kcCaption,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? cs.onSurface
                    : cs.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _colorLabel(String key) => switch (key) {
    "red" => "Red".tl,
    "pink" => "Pink".tl,
    "purple" => "Purple".tl,
    "green" => "Green".tl,
    "blue" => "Blue".tl,
    "yellow" => "Yellow".tl,
    "cyan" => "Cyan".tl,
    _ => "Default".tl,
  };
}
