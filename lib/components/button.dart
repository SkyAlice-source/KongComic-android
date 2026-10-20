part of 'components.dart';

class HoverBox extends StatefulWidget {
  const HoverBox(
      {super.key, required this.child, this.borderRadius = BorderRadius.zero});

  final Widget child;

  final BorderRadius borderRadius;

  @override
  State<HoverBox> createState() => _HoverBoxState();
}

class _HoverBoxState extends State<HoverBox> {
  bool isHover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHover = true),
      onExit: (_) => setState(() => isHover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
            color: isHover
                ? Theme.of(context).colorScheme.surfaceContainerLow
                : null,
            borderRadius: widget.borderRadius),
        child: widget.child,
      ),
    );
  }
}

enum ButtonType { filled, outlined, text, normal }

class Button extends StatefulWidget {
  const Button(
      {super.key,
      required this.type,
      required this.child,
      this.isLoading = false,
      this.width,
      this.height,
      this.padding,
      this.color,
      this.onPressedAt,
      required this.onPressed});

  const Button.filled(
      {super.key,
      required this.child,
      required this.onPressed,
      this.width,
      this.height,
      this.padding,
      this.color,
      this.onPressedAt,
      this.isLoading = false})
      : type = ButtonType.filled;

  const Button.outlined(
      {super.key,
      required this.child,
      required this.onPressed,
      this.width,
      this.height,
      this.padding,
      this.color,
      this.onPressedAt,
      this.isLoading = false})
      : type = ButtonType.outlined;

  const Button.text(
      {super.key,
      required this.child,
      required this.onPressed,
      this.width,
      this.height,
      this.padding,
      this.color,
      this.onPressedAt,
      this.isLoading = false})
      : type = ButtonType.text;

  const Button.normal(
      {super.key,
      required this.child,
      required this.onPressed,
      this.width,
      this.height,
      this.padding,
      this.color,
      this.onPressedAt,
      this.isLoading = false})
      : type = ButtonType.normal;

  static Widget icon(
      {Key? key,
        required Widget icon,
        required VoidCallback onPressed,
        double? size,
        Color? color,
        String? tooltip,
        bool isLoading = false,
        HitTestBehavior behavior = HitTestBehavior.deferToChild}) {
    return _IconButton(
      key: key,
      icon: icon,
      onPressed: onPressed,
      size: size,
      color: color,
      tooltip: tooltip,
      behavior: behavior,
      isLoading: isLoading,
    );
  }

  final ButtonType type;

  final Widget child;

  final bool isLoading;

  final void Function() onPressed;

  final void Function(Offset location)? onPressedAt;

  final double? width;

  final double? height;

  final EdgeInsets? padding;

  final Color? color;

  @override
  State<Button> createState() => _ButtonState();
}

class _ButtonState extends State<Button> {
  bool isHover = false;

  bool isLoading = false;

  @override
  void didUpdateWidget(covariant Button oldWidget) {
    if (oldWidget.isLoading != widget.isLoading) {
      setState(() => isLoading = widget.isLoading);
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    var padding = widget.padding ??
        const EdgeInsets.symmetric(horizontal: 16);
    var width = widget.width;
    if (width != null) {
      width = width - padding.horizontal;
    }
    var height = widget.height;
    if (height != null) {
      height = height - padding.vertical;
    }
    Widget child = IconTheme(
      data: IconThemeData(
        color: textColor,
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: textColor,
          fontSize: kcBody,
        ),
        child: isLoading
            ? CircularProgressIndicator(
          color: widget.type == ButtonType.filled
              ? kcOnAccentColor
              : kcBrandAdaptive(context),
          strokeWidth: 1.8,
        ).fixWidth(16).fixHeight(16)
            : widget.child,
      ),
    );
    if (width != null || height != null) {
      child = child.toCenter();
    }
    return Semantics(
      button: true,
      enabled: !isLoading,
      child: MouseRegion(
      onEnter: (_) => setState(() => isHover = true),
      onExit: (_) => setState(() => isHover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (isLoading) return;
          widget.onPressed();
          if (widget.onPressedAt != null) {
            var renderBox = context.findRenderObject() as RenderBox;
            var offset = renderBox.localToGlobal(Offset.zero);
            widget.onPressedAt!(offset);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: padding,
          constraints: const BoxConstraints(
            minWidth: 76,
            minHeight: 32,
          ),
          decoration: BoxDecoration(
            color: buttonColor,
            borderRadius: BorderRadius.circular(kcRadius16),
            boxShadow: (isHover && !isLoading && (widget.type == ButtonType.filled || widget.type == ButtonType.normal))
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
            border: widget.type == ButtonType.outlined
                ? Border.all(
                    color: widget.color ??
                        Theme.of(context).colorScheme.outlineVariant,
                    width: 0.6,
                  )
                // AMOLED 实心按钮是「深灰底 + 白字」，若不描边就会和同色系的
                // 弹窗底糊在一起（退出确认弹窗里几乎看不见按钮），补一道发丝线。
                : (widget.type == ButtonType.filled &&
                        widget.color == null &&
                        kcIsAmoled()
                    ? Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                        width: 0.8,
                      )
                    : null),
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 160),
            child: SizedBox(
              width: width,
              height: height,
              child: Center(
                widthFactor: 1,
                child: child,
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Color get buttonColor {
    if (widget.type == ButtonType.filled) {
      // 主按钮恒为「强调色」：浅色/深色是品牌红，AMOLED 是中性深灰。
      // 不再退回 colorScheme.primary —— 浅色下 primary 是用户选的蓝/绿，
      // 会在红主色设计里冒出与品牌无关的蓝按钮（分页「前进」、弹窗确认都踩过）。
      // AMOLED 取 Highest 一档：弹窗底本身是 High 色，同级会糊成一片。
      var color = widget.color ??
          (kcIsAmoled()
              ? context.colorScheme.surfaceContainerHighest
              : kcAccentColor(context));
      if (isHover) {
        return color.withValues(alpha: 0.9);
      } else {
        return color;
      }
    }
    if (widget.type == ButtonType.normal) {
      var color = widget.color ?? context.colorScheme.surfaceContainer;
      if (isHover) {
        return color.withValues(alpha: 0.9);
      } else {
        return color;
      }
    }
    if (isHover) {
      return context.colorScheme.outline.withValues(alpha: 0.2);
    }
    return Colors.transparent;
  }

  Color get textColor {
    if (widget.type == ButtonType.outlined) {
      return widget.color ?? context.colorScheme.onSurfaceVariant;
    }
    if (widget.type == ButtonType.filled) {
      // 显式指定按钮色时按亮度取黑/白前景（如「未选择」的灰态确认键），
      // 否则一律用强调色上的白字。
      final custom = widget.color;
      if (custom == null) return kcOnAccentColor;
      return custom.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    }
    if (widget.type == ButtonType.text) {
      // 文字按钮是「次级动作」（取消、跳过…）：中性灰比主题色安静，
      // 不会和右侧的红色主按钮抢注意力。
      return widget.color ?? context.colorScheme.onSurfaceVariant;
    }
    return context.colorScheme.onSurface;
  }
}

class _IconButton extends StatefulWidget {
  const _IconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size,
    this.color,
    this.tooltip,
    this.isLoading = false,
    this.behavior = HitTestBehavior.deferToChild,
  });

  final Widget icon;

  final VoidCallback onPressed;

  final double? size;

  final String? tooltip;

  final Color? color;

  final HitTestBehavior behavior;

  final bool isLoading;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool isHover = false;

  @override
  Widget build(BuildContext context) {
    var iconSize = widget.size ?? 24;
    Widget icon = IconTheme(
      data: IconThemeData(
        size: iconSize,
        color: widget.color ?? kcBrandAdaptive(context),
      ),
      child: widget.icon,
    );
    if (widget.isLoading) {
      icon = const CircularProgressIndicator(
        strokeWidth: 1.5,
      ).paddingAll(2).fixWidth(iconSize).fixHeight(iconSize);
    }
    return Semantics(
      button: true,
      enabled: !widget.isLoading,
      child: MouseRegion(
      onEnter: (_) => setState(() => isHover = true),
      onExit: (_) => setState(() => isHover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: () {
          if (widget.isLoading) return;
          widget.onPressed();
        },
        child: Tooltip(
          message: widget.tooltip ?? "",
          child: Container(
            decoration: BoxDecoration(
              color: isHover
                  ? Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.4)
                  : null,
              borderRadius: BorderRadius.circular((iconSize + 12) / 2),
            ),
            padding: const EdgeInsets.all(kcSpaceXxs),
            child: icon,
          ),
        ),
      ),
      ),
    );
  }
}

class MenuButton extends StatefulWidget {
  const MenuButton({super.key, required this.entries, this.color});

  final List<MenuEntry> entries;

  /// 图标颜色。默认沿用 `Button.icon` 的 primary（品牌红）。
  /// 文件夹列表里传中性色，避免每行都挂一个红「⋯」抢走选中态的强调。
  final Color? color;

  @override
  State<MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<MenuButton> {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'more'.tl,
      child: Button.icon(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedMoreHorizontal, size: 18),
        color: widget.color,
        onPressed: () {
          var renderBox = context.findRenderObject() as RenderBox;
          var offset = renderBox.localToGlobal(Offset.zero);
          showMenuX(
            context,
            offset,
            widget.entries,
          );
        },
      ),
    );
  }
}
