part of 'components.dart';

class MouseBackDetector extends StatelessWidget {
  const MouseBackDetector({
    super.key,
    required this.onTapDown,
    required this.child,
  });

  final Widget child;

  final void Function() onTapDown;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kBackMouseButton) {
          onTapDown();
        }
      },
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}

class AnimatedTapRegion extends StatefulWidget {
  const AnimatedTapRegion({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = 0,
  });

  final Widget child;

  final void Function() onTap;

  final double borderRadius;

  @override
  State<AnimatedTapRegion> createState() => _AnimatedTapRegionState();
}

class _AnimatedTapRegionState extends State<AnimatedTapRegion> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() {
          isHovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          isHovered = false;
        });
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedPhysicalModel(
          duration: _fastAnimationDuration,
          elevation: isHovered ? 3 : 1,
          color: context.colorScheme.surface,
          shadowColor: context.colorScheme.shadow,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 系统允许的最大排除带高度（dp）。
///
/// Android 会把 `systemGestureExclusionRects` 按高度累加裁剪到 200dp，
/// 超出部分**直接丢掉**（不报错、不生效）。这里留 2dp 余量，避免四舍五入
/// 后越界被裁掉尾部。
const double kSystemGestureExclusionBand = 198;

/// 把自己占的那一块从 Android 的系统返回手势里排除掉。
///
/// 系统返回手势的起手区是屏幕左右边缘约 20dp 的竖条，而且**优先级高于应用
/// 内手势**：从最左边起手横滑一条横向可滚动的标签栏，会先被判成「返回」。
/// 分类页和发现页都因此会在想滑标签时弹出「确认退出」。
///
/// Flutter 拦不住这件事 —— 系统手势在原生层先于触摸事件分发。唯一能让位的
/// 是 Android 10 的 `systemGestureExclusionRects`，但它规定同一条边被排除
/// 的高度合计不得超过 200dp。
///
/// 于是「横滑切 tab / 边缘滑动退出」只能按高度分区：[excludeHeight] 之内
/// 让给内容（横滑切 tab），之下仍是系统返回（滑动退出）。分类页和发现页用
/// [kSystemGestureExclusionBand] 把这条带拉到上限，覆盖「标签栏 + 一行半
/// 内容」——这是系统允许的最大范围，再想往上加会被静默裁掉。
///
/// ⚠️ [dispose] 时必定清除：排除区是**窗口级**状态，留着会让子页面无法从
/// 边缘侧滑返回。
class SystemGestureExclusion extends StatefulWidget {
  const SystemGestureExclusion({
    super.key,
    required this.child,
    this.enabled = true,
    this.excludeHeight,
  });

  final Widget child;

  /// 关掉时立刻撤销已经注册的排除区。
  ///
  /// 用在「本页被压在子页面下面」的情形：此时边缘侧滑应该回到上一级，不能
  /// 再被这条排除区挡住。
  final bool enabled;

  /// 只把**自身顶部**这一段高度排除出去；null = 整个自身高度。
  ///
  /// 包住整页（标签栏 + 内容区）时传 [kSystemGestureExclusionBand]：只有顶部
  /// 那条可横滑，下半屏的贴边横滑仍然交给系统返回。
  final double? excludeHeight;

  @override
  State<SystemGestureExclusion> createState() => _SystemGestureExclusionState();
}

class _SystemGestureExclusionState extends State<SystemGestureExclusion> {
  static const _channel = MethodChannel('kong_comic/method_channel');

  /// 排除条带的宽度。系统的返回手势热区约 20dp，取 24dp 留一点余量。
  static const _bandWidth = 24.0;

  /// 已上报的矩形（物理像素）。页面滚动时会频繁 rebuild，不加去重就是每帧
  /// 过一次 platform channel。
  List<int>? _sent;

  bool _syncScheduled = false;

  @override
  void dispose() {
    _apply(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleSync();
    return widget.child;
  }

  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      _sync();
    });
  }

  void _sync() {
    if (!widget.enabled) {
      _apply(null);
      return;
    }
    // post-frame 回调里 `mounted` 为真但节点可能刚被 deactivate（同一帧里
    // 换页 / 关页面），此时 `MediaQuery.of` 会抛 "Looking up a deactivated
    // widget's ancestor"。这里只是锦上添花的排除区，不值得让异常冒到
    // FlutterError。
    try {
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;
      final size = renderObject.size;
      if (size.width <= 0 || size.height <= 0) return;

      final origin = renderObject.localToGlobal(Offset.zero);
      final ratio = MediaQuery.devicePixelRatioOf(context);
      final band = (_bandWidth * ratio).round();
      final width = (size.width * ratio).round();
      if (band <= 0 || width <= 0) return;

      // 只排除顶部一段时，下缘按 excludeHeight 裁：矩形高度必须 ≤200dp，
      // 否则系统会静默丢掉超出的部分（也可能整条失效）。
      final excludedHeight = widget.excludeHeight == null
          ? size.height
          : math.min(size.height, widget.excludeHeight!);
      if (excludedHeight <= 0) return;

      _apply([
        0,
        (origin.dy * ratio).round(),
        band < width ? band : width,
        ((origin.dy + excludedHeight) * ratio).round(),
      ]);
    } catch (_) {
      // 拿不到几何信息就维持现状：下一次 build 还会再试。
    }
  }

  void _apply(List<int>? rect) {
    // 只有 Android 有这个原生通道；其它平台调过去会抛
    // MissingPluginException（异步未捕获，日志里一片红）。
    if (!App.isAndroid) return;
    if (rect == null) {
      if (_sent == null) return;
      _sent = null;
    } else {
      if (_sent != null && _sameRect(rect, _sent!)) return;
      _sent = rect;
    }
    _channel.invokeMethod('setGestureExclusionRects', {
      'rects': rect == null ? const <List<int>>[] : <List<int>>[rect],
    });
  }

  /// 不引入 `foundation.listEquals`：本文件是 `components.dart` 的 part，
  /// 那个库没有导出它，为一个三行循环加 import 不值得。
  static bool _sameRect(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
