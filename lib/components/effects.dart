part of 'components.dart';

class BlurEffect extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final Border? border;

  const BlurEffect({
    required this.child,
    this.borderRadius,
    this.border,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: border,
      ),
      child: child,
    );
  }
}
