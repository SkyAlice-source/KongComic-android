part of 'components.dart';

class BlurEffect extends StatelessWidget {
  final Widget child;

  final double blur;

  final BorderRadius? borderRadius;

  final Color? tintColor;

  final double tintOpacity;

  final Border? border;

  const BlurEffect({
    required this.child,
    this.borderRadius,
    this.blur = 15,
    this.tintColor,
    this.tintOpacity = 0.1,
    this.border,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTintColor = tintColor ??
        (Theme.of(context).brightness == Brightness.light
            ? Colors.white
            : Colors.black);

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: TileMode.mirror,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: effectiveTintColor.withValues(alpha: tintOpacity),
            borderRadius: borderRadius,
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}
