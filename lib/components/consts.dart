part of 'components.dart';

/// 动画时长 token —— 收敛散落的 [Duration] 魔法数字，统一节奏、便于整体调校。
///
/// 分层依据现有代码的实际使用频率：
/// - [fast]：微交互（悬停、按压回弹、小部件展开），约 160ms。
/// - [normal]：标准过渡（列表项出现、弹层、AnimatedContainer），约 200ms。
/// - [slow]：较大位移/页面级过渡，约 300ms。
///
/// 新增动画时优先选用这里的层级，不要再裸写 `Duration(milliseconds:)`。
class AppDurations {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);
}

/// 旧有私有令牌，保留以兼容 components 库内 11 处既有引用；
/// 新代码请使用 [AppDurations.fast]。
const _fastAnimationDuration = AppDurations.fast;
