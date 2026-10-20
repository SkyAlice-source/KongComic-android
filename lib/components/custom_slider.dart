import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kong_comic/design_tokens.dart';

/// 阅读器底栏的「进度胶囊」：一条 28dp 高的胶囊轨道，章节名 · 页码压在里面，
/// 左侧按阅读进度填充，右侧留空。支持 RtL（[reversed]）与键盘左右键翻页。
class CustomSlider extends StatefulWidget {
  const CustomSlider({
    required this.min,
    required this.max,
    required this.value,
    required this.divisions,
    required this.onChanged,
    required this.focusNode,
    this.reversed = false,
    this.chapterText,
    super.key,
  });

  final double min;

  final double max;

  final double value;

  final int divisions;

  final void Function(double) onChanged;

  final FocusNode? focusNode;

  final bool reversed;

  /// Optional chapter/episode name shown before the page counter.
  final String? chapterText;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 填充色不能直接套 primary / primaryContainer：
    // - 亮色主题里 primary 是深色调（tone 40），文字压上去完全看不见
    //   —— 旧版「深蓝底 + 深灰字」就是这么来的；
    // - 暗色主题里 primary 是浅色调（AMOLED 下直接是 #E0E0E0），铺满整条会
    //   变成一条刺眼的白条；primaryContainer 又压到 #2A2A2A，和轨道几乎同色，
    //   进度彻底看不出来。
    // 所以暗色改用「primary 按比例混进底色」得到一块中调色块：既不刺眼，又和
    // 轨道拉开层次；文字在两种主题下都用「与填充块同侧的高对比色」。
    final barSurface = colorScheme.surface;
    final fillColor = isDark
        ? Color.alphaBlend(
            kcAccentColor(context).withValues(alpha: 0.34),
            barSurface,
          )
        : kcAccentColor(context);
    final onFillColor = isDark ? colorScheme.onSurface : colorScheme.onPrimary;
    final trackColor = isDark
        ? Color.alphaBlend(
            colorScheme.onSurface.withValues(alpha: 0.08),
            barSurface,
          )
        : colorScheme.surfaceContainerHighest;

    final step = widget.divisions > 0
        ? (widget.max - widget.min) / widget.divisions
        : (widget.max - widget.min);
    void increase() =>
        widget.onChanged((value + step).clamp(widget.min, widget.max));
    void decrease() =>
        widget.onChanged((value - step).clamp(widget.min, widget.max));

    final chapterText = widget.chapterText;
    final label = chapterText != null && chapterText.isNotEmpty
        ? "$chapterText · ${value.toInt()}/${widget.max.toInt()}"
        : "${value.toInt()}/${widget.max.toInt()}";

    // 单页章节没有可滑动区间，直接让位（底栏会用页码胶囊兜底）。
    if (widget.max - widget.min <= 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final progress = ((value - widget.min) / (widget.max - widget.min))
            .clamp(0.0, 1.0);
        final fillWidth = constraints.maxWidth * progress;
        return Semantics(
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
                // 整块 48dp 高都能点/拖，比只认 28dp 的胶囊本体好按。
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  var dx = details.localPosition.dx;
                  if (widget.reversed) {
                    dx = constraints.maxWidth - dx;
                  }
                  var gap = constraints.maxWidth / widget.divisions;
                  var gapValue = (widget.max - widget.min) / widget.divisions;
                  widget.onChanged.call(
                    (dx / gap).round() * gapValue + widget.min,
                  );
                },
                onVerticalDragUpdate: (details) {
                  var dx = details.localPosition.dx;
                  if (dx > constraints.maxWidth || dx < 0) return;
                  if (widget.reversed) {
                    dx = constraints.maxWidth - dx;
                  }
                  var gap = constraints.maxWidth / widget.divisions;
                  var gapValue = (widget.max - widget.min) / widget.divisions;
                  widget.onChanged.call(
                    (dx / gap).round() * gapValue + widget.min,
                  );
                },
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.all(
                        Radius.circular(kcPillRadius),
                      ),
                      child: SizedBox(
                        height: 28,
                        child: Stack(
                          children: [
                            // 空轨道
                            Positioned.fill(
                              child: ColoredBox(color: trackColor),
                            ),
                            // 进度填充（RtL 时贴右边）
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: widget.reversed ? null : 0,
                              right: widget.reversed ? 0 : null,
                              width: fillWidth,
                              child: ColoredBox(color: fillColor),
                            ),
                            // 文字：整句居中，按进度在「字符边界」切成两段着色
                            // —— 填充内用 onFillColor、轨道上用 onSurface。
                            // 按字符切而不是按像素裁：硬裁会把正好压线的字劈成
                            // 两半（半个白字半个黑字），像渲染错误。
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Center(
                                  child: _buildSplitLabel(
                                    context,
                                    label: label,
                                    availWidth: constraints.maxWidth - 24,
                                    coveredWidth: fillWidth,
                                    coveredColor: onFillColor,
                                    uncoveredColor: colorScheme.onSurface,
                                    reversed: widget.reversed,
                                  ),
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
        );
      },
    );
  }

  /// 把整句文字按进度切成两段着色。
  ///
  /// [coveredWidth] 是已填充区域的宽度。先量出整句在 [availWidth] 里的实际排版
  /// 宽度（文字居中），再算出填充边界落在哪个字符位置，以该位置为切分点 ——
  /// 每个字只会有一种颜色，不会被劈成半个白字半个黑字（按像素裁剪就会那样）。
  Widget _buildSplitLabel(
    BuildContext context, {
    required String label,
    required double availWidth,
    required double coveredWidth,
    required Color coveredColor,
    required Color uncoveredColor,
    required bool reversed,
  }) {
    const base = TextStyle(
      fontSize: kcCaption,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    );

    // fillSplit = 文字坐标系里「填充边界左侧」的字符数：
    // - 非反转（LTR）：填充在左，边界 = coveredWidth，左侧字符都压在填充上；
    // - 反转（RTL）：填充在右，左边缘 = availWidth - coveredWidth，左侧字符压在轨道上。
    // 之后按方向决定哪一段着 coveredColor（压在填充上），哪一段着 uncoveredColor（压在轨道）。
    var fillSplit = reversed ? 0 : label.length;
    if (availWidth > 0) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: base),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
        locale: Localizations.maybeLocaleOf(context),
      )..layout(maxWidth: availWidth);
      if (painter.width > 0) {
        final textLeft = ((availWidth - painter.width) / 2).clamp(
          0.0,
          double.infinity,
        );
        final edgeInBar = reversed ? availWidth - coveredWidth : coveredWidth;
        final edgeInText = edgeInBar - textLeft;
        if (edgeInText <= 0) {
          fillSplit = 0;
        } else if (edgeInText >= painter.width) {
          fillSplit = label.length;
        } else {
          fillSplit = painter
              .getPositionForOffset(Offset(edgeInText, painter.height / 2))
              .offset
              .clamp(0, label.length);
        }
      }
      painter.dispose();
    }

    final spans = <TextSpan>[];
    if (reversed) {
      // 填充在右：左段是轨道（uncovered），右段是填充（covered）。
      if (fillSplit > 0) {
        spans.add(
          TextSpan(
            text: label.substring(0, fillSplit),
            style: TextStyle(color: uncoveredColor),
          ),
        );
      }
      if (fillSplit < label.length) {
        spans.add(
          TextSpan(
            text: label.substring(fillSplit),
            style: TextStyle(color: coveredColor),
          ),
        );
      }
    } else {
      // 填充在左：左段是填充（covered），右段是轨道（uncovered）。
      if (fillSplit > 0) {
        spans.add(
          TextSpan(
            text: label.substring(0, fillSplit),
            style: TextStyle(color: coveredColor),
          ),
        );
      }
      if (fillSplit < label.length) {
        spans.add(
          TextSpan(
            text: label.substring(fillSplit),
            style: TextStyle(color: uncoveredColor),
          ),
        );
      }
    }

    return Text.rich(
      TextSpan(children: spans),
      style: base,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
