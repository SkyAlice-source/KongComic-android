import 'package:flutter/services.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/log.dart';

/// 与系统省电策略打交道的入口。
///
/// 后台追更检查与自动备份都跑在 WorkManager 里。Android 的 Doze 会把周期任务
/// 推迟到「维护窗口」，而 MIUI / EMUI / ColorOS 一类的厂商策略更激进：应用被
/// 判定为「不常用」后，后台任务直接不执行，且不会给任何提示。用户看到的现象是
/// 「设置里明明开着自动备份，从来没备份过」「追更从来没通知过」，在应用内完全
/// 无从排查。
///
/// Mihon 与 Tachiyomi 的处理方式一致：设置里摆一行状态 + 一个入口，让用户自己
/// 决定是否豁免。这里保持同样的边界 —— 只展示状态、只负责把用户送到系统开关前，
/// 是否放开由用户在系统对话框里决定，App 不替任何人改系统设置。
class AppPower {
  const AppPower._();

  static const MethodChannel _channel = MethodChannel(
    'kong_comic/method_channel',
  );

  /// 是否已被排除在电池优化之外。
  ///
  /// 非 Android 平台恒为 true（没有这个概念）；原生侧读取失败时也按 true 处理：
  /// 状态未知不该在界面上渲染成「受限制」，那会误导用户去点一个其实不必要的开关。
  static Future<bool> get isIgnoringBatteryOptimizations async {
    if (!App.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          true;
    } catch (e) {
      Log.warning("Power", "Failed to read battery optimization state: $e");
      return true;
    }
  }

  /// 打开系统的电池优化开关，返回是否成功跳转到某个设置页。
  ///
  /// 返回 true 只代表「用户被送到了开关前」，不代表已经豁免 —— 真正的结果要在
  /// 应用回到前台后重新查 [isIgnoringBatteryOptimizations]。
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!App.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>(
            'requestIgnoreBatteryOptimizations',
          ) ??
          false;
    } catch (e) {
      Log.error(
        "Power",
        "Failed to request battery optimization exemption: $e",
        null,
      );
      return false;
    }
  }
}
