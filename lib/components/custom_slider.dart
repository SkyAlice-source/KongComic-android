import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kong_comic/foundation/app.dart';

/// patched slider.dart with RtL support
class _SliderDefaultsM3 extends SliderThemeData {
  _SliderDefaultsM3(this.context)
      : super(trackHeight: 4.0);

  final BuildContext context;
  late final ColorScheme _colors = Theme.of(context).colorScheme;

  @override
  Color? get activeTrackColor => _colors.primary;

  @override
  Color? get inactiveTrackColor => _colors.surfaceContainerHighest;

  @override
  Color? get secondaryActiveTrackColor => _colors.primary.toOpacity(0.54);

  @override
  Color? get disabledActiveTrackColor => _colors.onSurface.toOpacity(0.38);

  @override
  Color? get disabledInactiveTrackColor => _colors.onSurface.toOpacity(0.12);

  @override
  Color? get disabledSecondaryActiveTrackColor => _colors.onSurface.toOpacity(0.12);

  @override
  Color? get activeTickMarkColor => _colors.onPrimary.toOpacity(0.38);

  @override
  Color? get inactiveTickMarkColor => _colors.onSurfaceVariant.toOpacity(0.38);

  @override
  Color? get disabledActiveTickMarkColor => _colors.onSurface.toOpacity(0.38);

  @override
  Color? get disabledInactiveTickMarkColor => _colors.onSurface.toOpacity(0.38);

  @override
  Color? get thumbColor => _colors.primary;

  @override
  Color? get disabledThumbColor => Color.alphaBlend(_colors.onSurface.toOpacity(0.38), _colors.surface);

  @override
  Color? get overlayColor => WidgetStateColor.resolveWith((Set<WidgetState> states) {
    if (states.contains(WidgetState.dragged)) {
      return _colors.primary.toOpacity(0.1);
    }
    if (states.contains(WidgetState.hovered)) {
      return _colors.primary.toOpacity(0.08);
    }
    if (states.contains(WidgetState.focused)) {
      return _colors.primary.toOpacity(0.1);
    }

    return Colors.transparent;
  });

  @override
  TextStyle? get valueIndicatorTextStyle => Theme.of(context).textTheme.labelMedium!.copyWith(
    color: _colors.onPrimary,
  );

  @override
  SliderComponentShape? get valueIndicatorShape => const DropSliderValueIndicatorShape();
}

class CustomSlider extends StatefulWidget {
  const CustomSlider({required this.min, required this.max, required this.value, required this.divisions, required this.onChanged, required this.focusNode, this.reversed = false, super.key});

  final double min;

  final double max;

  final double value;

  final int divisions;

  final void Function(double) onChanged;

  final FocusNode? focusNode;

  final bool reversed;

  @override
  State<CustomSlider> createState() => _CustomSliderState();
}

class _CustomSliderState extends State<CustomSlider> {
  late double value;

  @override
  void initState() {
    super.initState();
    value = widget.value;
  }

  @override
  void didUpdateWidget(CustomSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      setState(() {
        value = widget.value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = _SliderDefaultsM3(context);
    final step = widget.divisions > 0
        ? (widget.max - widget.min) / widget.divisions
        : (widget.max - widget.min);
    void increase() =>
        widget.onChanged((value + step).clamp(widget.min, widget.max));
    void decrease() =>
        widget.onChanged((value - step).clamp(widget.min, widget.max));
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      child: widget.max - widget.min > 0 ? LayoutBuilder(
        builder: (context, constraints) => Semantics(
          slider: true,
          value: "${value.toInt()}",
          increasedValue:
              "${(value + step).clamp(widget.min, widget.max).toInt()}",
          decreasedValue:
              "${(value - step).clamp(widget.min, widget.max).toInt()}",
          onIncrease: increase,
          onDecrease: decrease,
          child: Focus(
            focusNode: widget.focusNode,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                    event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  increase();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                    event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  decrease();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (details){
              var dx = details.localPosition.dx;
              if(widget.reversed){
                dx = constraints.maxWidth - dx;
              }
              var gap = constraints.maxWidth / widget.divisions;
              var gapValue = (widget.max - widget.min)  / widget.divisions;
              widget.onChanged.call((dx / gap).round() * gapValue + widget.min);
            },
            onVerticalDragUpdate: (details){
              var dx = details.localPosition.dx;
              if(dx > constraints.maxWidth || dx < 0)  return;
              if(widget.reversed){
                dx = constraints.maxWidth - dx;
              }
              var gap = constraints.maxWidth / widget.divisions;
              var gapValue = (widget.max - widget.min)  / widget.divisions;
              widget.onChanged.call((dx / gap).round() * gapValue + widget.min);
            },
            child: SizedBox(
              height: 32,
              child: Center(
                child: SizedBox(
                  height: 32,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 背景轨道
                      Positioned.fill(
                        child: Center(
                          child: Container(
                            width: double.infinity,
                            height: 28,
                            decoration: BoxDecoration(
                                color: theme.inactiveTrackColor,
                                borderRadius: const BorderRadius.all(Radius.circular(14))),
                          ),
                        ),
                      ),
                      // 激活轨道
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: widget.reversed ? null : 0,
                        right: widget.reversed ? 0 : null,
                        child: Align(
                          alignment: widget.reversed ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            width: constraints.maxWidth * ((value - widget.min) / (widget.max - widget.min)),
                            height: 28,
                            decoration: BoxDecoration(
                                color: theme.activeTrackColor,
                                borderRadius: const BorderRadius.all(Radius.circular(14))),
                          ),
                        ),
                      ),
                      // 文字覆盖层
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Text(
                                "${value.toInt()}/${widget.max.toInt()}",
                                style: TextStyle(
                                  color: colorScheme.onPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
            ),
          ),
      ) : null,
    );
  }
}