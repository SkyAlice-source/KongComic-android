part of 'components.dart';

class BlurEffect extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final Border? border;
  final double blurSigma;

  const BlurEffect({
    required this.child,
    this.borderRadius,
    this.border,
    // 30 → 20：模糊开销随 sigma 增长，20 观感几乎一致但更省。
    this.blurSigma = 20,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // 真·背景模糊：用 BackdropFilter 把 BlurEffect 背后的内容实时模糊，
    // 子组件（通常为半透明 tint）叠在模糊之上形成玻璃质感。
    // 之前这里只是空 Container，根本不模糊（见 appbar 改造 / 全站玻璃统一）。
    // 滚动/翻页中降级为不模糊（阅读器工具栏等常驻模糊是最贵的一处）。
    return ValueListenableBuilder<bool>(
      valueListenable: KcGlassActivity.scrolling,
      builder: (context, scrolling, _) {
        Widget body = Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: border,
          ),
          child: child,
        );
        if (!scrolling) {
          body = BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: body,
          );
        }
        return ClipRRect(
          borderRadius: borderRadius ?? BorderRadius.zero,
          child: body,
        );
      },
    );
  }
}
