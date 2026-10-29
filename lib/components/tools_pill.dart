part of "components.dart";

/// 顶栏「工具胶囊条」—— 收藏页 / 历史页等列表页共用同一套外观。
///
/// 圆角 999 容器 + 1px 细分隔线，内部放若干 [ToolsPillButton]。
/// 设计语义：红只用于「激活 / 危险」这类状态，默认图标一律 onSurfaceVariant，
/// 避免出现「一排红图标 + 一颗红选中胶囊」的同屏多红噪音。
class ToolsPill extends StatelessWidget {
  const ToolsPill({super.key, required this.children, this.height = 36});

  final List<Widget> children;

  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kids = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      kids.add(children[i]);
      if (i < children.length - 1) {
        kids.add(Container(width: 1, height: 20, color: cs.outlineVariant));
      }
    }
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kcPillRadius),
        border: Border.all(color: cs.outlineVariant, width: kcHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: kids),
    );
  }
}

/// 胶囊条内的单个图标按钮：紧凑 36×36、中性色；[active] 时走 accent 红。
class ToolsPillButton extends StatelessWidget {
  const ToolsPillButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.color,
    this.tooltip,
    this.size = 18,
  });

  /// HugeIcons 常量（`List<List<dynamic>>` 形式的路径数据），不是 IconData。
  final dynamic icon;

  final VoidCallback? onPressed;

  /// 激活态（如「已启用筛选」）：图标走 accent 红。
  final bool active;

  /// 覆盖图标色（如危险操作用 `colorScheme.error`）。优先级高于 [active]。
  final Color? color;

  final String? tooltip;

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // tooltip 必须交给 IconButton 自己：外层 Tooltip 的 message 只进 tooltipText
    // 通道，读屏与 uiautomator 都拿不到 content-desc（见 navigation_bar.buildTop
    // 的同款注释），胶囊条里的按钮会整体变成「无标签」。
    return IconButton(
      icon: HugeIcon(icon: icon, size: size),
      color: color ?? (active ? kcBrandAdaptive(context) : cs.onSurfaceVariant),
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 38, minHeight: 36),
      padding: EdgeInsets.zero,
      splashRadius: 20,
      onPressed: onPressed,
    );
  }
}

/// 布局模式图标：把**当前布局本身**画成一张缩略图。
///
/// 网格（brief）= 2×2 封面格；列表（detailed）= 左边封面缩略 + 右边三行信息
/// —— 和列表页「左封面右文字」的实际排版一一对应，比抽象的四条横杠好读。
///
/// 为什么不用现成的两个图标换着显示：那样单图标只能表达「点完会变成什么」，
/// 用户看不出当前是什么布局；并排两个图标（旧的双态分段）又占掉双倍宽度，
/// 窄屏上会把共享顶栏的标题挤掉。画成缩略图则一件事说清两件事——形状即现状，
/// 点一下即切换，tooltip 说明动作目标。
///
/// 切换用「淡出 + 轻缩」而不是几何形变：四块格子和「一块竖条 + 三行」的图元
/// 对不上号，硬做位置插值中途会互相穿插（实测出现阶梯状错位，很难看）。
class LayoutGlyphIcon extends StatelessWidget {
  const LayoutGlyphIcon({
    super.key,
    required this.detailed,
    this.size = 18,
    this.color,
  });

  /// true = 当前是详细列表；false = 简洁网格。
  final bool detailed;

  final double size;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    // 没显式给色时跟随 IconTheme —— 放进 IconButton / 顶栏动作位时能和
    // 旁边的图标同色，不用调用方逐处传。
    final color =
        this.color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    final glyph = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LayoutGlyphPainter(detailed: detailed, color: color),
      ),
    );
    // 减弱动效时直接换图，不做过渡。
    if (kcReduceMotion(context)) return glyph;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.86, end: 1).animate(anim),
          child: child,
        ),
      ),
      // 两个形态尺寸相同，AnimatedSwitcher 的默认 Stack 不会引起跳动。
      child: KeyedSubtree(key: ValueKey<bool>(detailed), child: glyph),
    );
  }
}

/// [LayoutGlyphIcon] 的画法。
///
/// 几何一律按**视觉边界**给参数：描边居中于路径、会向外溢出半个线宽，
/// 所以每个矩形都先扣掉 stroke，外轮廓才正好落在 size 的正方形里。
class _LayoutGlyphPainter extends CustomPainter {
  const _LayoutGlyphPainter({required this.detailed, required this.color});

  final bool detailed;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final stroke = s * 0.085;
    // 原点向内移半个线宽，描边外溢后视觉外轮廓正好等于 s。
    final ox = (size.width - s) / 2 + stroke / 2;
    final oy = (size.height - s) / 2 + stroke / 2;

    final rects = <Rect>[];
    final radii = <double>[];

    if (detailed) {
      // 左边封面缩略（占宽 0.38s），右边三行信息。
      final coverW = s * 0.38;
      rects.add(Rect.fromLTWH(0, 0, coverW - stroke, s - stroke));
      radii.add(math.max(s * 0.10 - stroke / 2, 0));
      final lineH = s * 0.115 - stroke;
      for (final top in const [0.1225, 0.4425, 0.7625]) {
        rects.add(Rect.fromLTWH(s * 0.52, s * top, s * 0.48 - stroke, lineH));
        radii.add(lineH / 2);
      }
    } else {
      // 2×2 封面格。
      final gapVis = s * 0.16;
      final cellVis = (s - gapVis) / 2;
      final cell = cellVis - stroke;
      final gap = gapVis + stroke;
      final r = math.max(cellVis * 0.26 - stroke / 2, 0.0);
      for (var i = 0; i < 4; i++) {
        rects.add(
          Rect.fromLTWH(
            (i % 2) * (cell + gap),
            (i ~/ 2) * (cell + gap),
            cell,
            cell,
          ),
        );
        radii.add(r);
      }
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    for (var i = 0; i < rects.length; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rects[i].shift(Offset(ox, oy)),
          Radius.circular(radii[i]),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LayoutGlyphPainter oldDelegate) =>
      oldDelegate.detailed != detailed || oldDelegate.color != color;
}

/// 胶囊条内的「布局切换」按钮（收藏 / 历史等列表页共用）。
///
/// 单图标，形态即当前布局（见 [LayoutGlyphIcon]），点击翻转全局
/// comicDisplayMode。监听 `appdata.settings`：从别的页面（根 tab 顶栏、
/// 设置页）改了模式，回到这里图标自动跟上，不依赖宿主页面重建。
class ToolsPillLayoutButton extends StatefulWidget {
  const ToolsPillLayoutButton({super.key, this.size = 18});

  final double size;

  @override
  State<ToolsPillLayoutButton> createState() => _ToolsPillLayoutButtonState();
}

class _ToolsPillLayoutButtonState extends State<ToolsPillLayoutButton>
    with AutoListenMixin {
  bool get _detailed => appdata.settings['comicDisplayMode'] != 'brief';

  @override
  void initState() {
    super.initState();
    listen(appdata.settings, () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: LayoutGlyphIcon(
        detailed: _detailed,
        size: widget.size,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      // tooltip 描述**动作**（点完会切到哪种），图标描述**现状**。
      tooltip: _detailed ? "Switch to grid view".tl : "Switch to list view".tl,
      constraints: const BoxConstraints(minWidth: 38, minHeight: 36),
      padding: EdgeInsets.zero,
      splashRadius: 20,
      onPressed: () {
        appdata.settings['comicDisplayMode'] = _detailed ? 'brief' : 'detailed';
        appdata.saveData();
      },
    );
  }
}

/// 胶囊条内的「更多」按钮：点击在按钮自身位置弹出菜单（复刻 MenuButton 的
/// showMenuX 逻辑，但去掉自带圆角背景，融入胶囊条）。
///
/// ⚠️ 必须用 [Builder] 拿「按钮自己」的 context 去取 RenderBox：
/// 直接用外层 State 的 context，`findRenderObject()` 会一路回溯到整页根节点，
/// `localToGlobal(Offset.zero)` 得到 (0,0)，菜单就会弹到屏幕左上角
/// （实测过：点右侧「⋯」菜单跑到标题下方）。
class ToolsPillMoreButton extends StatelessWidget {
  const ToolsPillMoreButton({
    super.key,
    required this.entries,
    this.tooltip,
    this.icon,
  });

  final List<MenuEntry> entries;

  final String? tooltip;

  /// 自定义图标（默认「⋯」）——排序这类「点开是菜单」的功能按钮复用
  /// 同一套弹出定位逻辑，只换图标。
  final dynamic icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final btn = Builder(
      builder: (ctx) => IconButton(
        icon: HugeIcon(
          icon: icon ?? HugeIcons.strokeRoundedMoreHorizontal,
          size: 18,
        ),
        color: cs.onSurfaceVariant,
        constraints: const BoxConstraints(minWidth: 38, minHeight: 36),
        padding: EdgeInsets.zero,
        splashRadius: 20,
        onPressed: () {
          final rb = ctx.findRenderObject() as RenderBox;
          showMenuX(
            ctx,
            rb.localToGlobal(Offset.zero),
            entries,
            anchorSize: rb.size,
          );
        },
      ),
    );
    return Tooltip(message: tooltip ?? "More".tl, child: btn);
  }
}

/// 胶囊条内的「当前值」标签：一句话说清现在的状态，点开还是同一套菜单。
///
/// 排序这类「单选状态 + 点开可改」的功能，原先做成「图标 + 文字」塞进一个按钮：
/// 两个元素挤在 36dp 高的胶囊里显得零碎，而且排序图标本身就是几根横线，跟旁边
/// 布局图标的横线撞脸 —— 两个按钮挨着时像同一族，谁也不突出。
///
/// 改成纯文字 + 下拉箭头：文字即状态，箭头即「可以展开」，与左右纯图标按钮
/// 分工明确（图标 = 动作，胶囊 = 状态）。
class ToolsPillValueChip extends StatelessWidget {
  const ToolsPillValueChip({
    super.key,
    required this.label,
    required this.entries,
    this.tooltip,
  });

  /// 当前值短标签（手动 / 最近 / 标题），由调用方翻译后传入。
  final String label;

  final List<MenuEntry> entries;

  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(kcPillRadius);
    // 左右各留 4：图标按钮是固定 38 宽、自带留白，标签是自适应宽，不加这
    // 圈 margin 会直接贴住两侧的 1px 分隔线（实测很挤）。
    final chip = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Builder(
        builder: (ctx) => Material(
          // 比胶囊底色深一档的极淡中性底：让它读起来像「标签」而不是「按钮」。
          // 不用品牌红——红在这个设计里只代表激活/危险。
          color: cs.onSurface.withValues(alpha: 0.055),
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: () {
              final rb = ctx.findRenderObject() as RenderBox;
              showMenuX(
                ctx,
                rb.localToGlobal(Offset.zero),
                entries,
                anchorSize: rb.size,
              );
            },
            child: Padding(
              // 左多右少：视觉重心压在文字上，箭头只做「可展开」的提示。
              // 垂直 5 让标签高度约 25dp —— 比 36dp 的图标按钮矮一档，读起来
              // 是「贴在工具条里的状态」，而不是又一个按钮。
              padding: const EdgeInsets.fromLTRB(9, 5, 4, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    // 长语种（如「タイトル」）不许把胶囊撑开：超出就省略。
                    constraints: const BoxConstraints(maxWidth: 52),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: kcCaption,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 1),
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowDown01,
                    size: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}
