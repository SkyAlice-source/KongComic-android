part of 'components.dart';

/// 全 App 统一的开关。
///
/// Material 默认的 [Switch] 是 52×32，放在 14sp 的设置行里偏笨重；开态又是
/// 一整块高饱和主色，和「大圆角 + 克制用色」的页面语汇不搭。这里收成
/// 44×26 的胶囊：开态品牌红轨道 + 暖白滑块，关态中性容器色 + 灰滑块。
///
  /// 暗色质感的三个细节：
  /// · 开态轨道用**纵向微渐变**（上亮下暗）而不是纯色块，深灰底上才有体积感；
  /// · 滑块是暖白 `#FFF7F4` 而非纯白，配红轨不发冷（暗色配灰轨也不发冷）；
  /// · 亮色轨道外一层极淡红晕；暗色零彩色，改用极淡灰晕，让开关从深灰底上「浮」起来。
///
/// 交互细节：
/// · 点击回调前先给一次 [HapticFeedback.selectionClick]，与 App 内其它开关一致；
/// · 热区比轨道四周各外扩 4dp，小尺寸也不难按；
/// · 系统「减弱动效」开启时退化为瞬切。
class KcSwitch extends StatelessWidget {
  const KcSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.enabled = true,
  });

  final bool value;

  final ValueChanged<bool>? onChanged;

  final bool enabled;

  static const double _trackWidth = 44;
  static const double _trackHeight = 26;
  static const double _thumbSize = 20;
  static const double _thumbGap = 3;

  /// 暖白滑块：比纯白低 3% 亮度、偏一点暖调，压在红轨上不会显得「发冷发假」。
  static const Color _thumbOn = Color(0xFFFFF7F4);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canTap = enabled && onChanged != null;
    final duration = kcReduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 190);
    // 浅色 / 深色开态轨道都用品牌红（深色底上更沉）；AMOLED 零彩色，开态改用
    // 明显更亮的灰，才能和关态灰区分开。
    final onTrack =
        kcIsAmoled() ? const Color(0xFF6E6E6E) : kcAccentColor(context);
    final offTrack = cs.surfaceContainerHighest.withValues(alpha: 0.9);

    return Semantics(
      toggled: value,
      enabled: canTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canTap
            ? () {
                HapticFeedback.selectionClick();
                onChanged!(!value);
              }
            : null,
        child: SizedBox(
          width: _trackWidth + 8,
          height: _trackHeight + 8,
          child: Center(
            // 禁用态整体压暗：比逐个颜色算透明度更稳，渐变/描边/阴影一起衰减。
            child: Opacity(
              opacity: canTap ? 1 : 0.45,
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                width: _trackWidth,
                height: _trackHeight,
                decoration: BoxDecoration(
                  color: value ? null : offTrack,
                  gradient: value
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.lerp(onTrack, Colors.white, 0.10)!,
                            Color.lerp(onTrack, Colors.black, 0.10)!,
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(kcPillRadius),
                  // 亮色下关态轨道在白底上几乎隐形，用一层极淡黑描边兜底；
                  // 暗色则用极淡白描边，勾出胶囊轮廓。
                  border: Border.all(
                    color: value
                        ? Colors.white.withValues(alpha: 0.12)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.black.withValues(alpha: 0.05)),
                    width: 0.7,
                  ),
                  // 开态红晕：暗色更强（纯黑底需要一点光晕才有层次）。
                  boxShadow: value
                      ? [
                          BoxShadow(
                            color: onTrack.withValues(alpha: isDark ? 0.22 : 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: AnimatedAlign(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _thumbGap),
                    child: AnimatedContainer(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      width: _thumbSize,
                      height: _thumbSize,
                      decoration: BoxDecoration(
                        color: value
                            ? _thumbOn
                            : cs.onSurfaceVariant.withValues(alpha: 0.75),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: value ? 0.22 : 0.10),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
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
      ),
    );
  }
}
