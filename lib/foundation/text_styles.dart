import 'package:flutter/material.dart';

/// 全局字号 token —— 收敛散落在各处的魔法数字，统一层级、便于整体调校。
class AppFontSizes {
  static const double display = 24;
  static const double titleLarge = 20;
  static const double title = 18;
  static const double body = 16;
  static const double bodySmall = 14;
  static const double caption = 13;
  static const double label = 12;
  static const double tiny = 11;
}

/// 中文行高基准 —— 中文默认 height 1.0 偏挤，统一抬到舒适区间。
class AppLineHeights {
  static const double display = 1.3;
  static const double heading = 1.35;
  static const double body = 1.45;
  static const double dense = 1.4;
}

extension TextStyleZh on TextStyle {
  /// 给中文文本加舒适行高（默认 1.45），不改其它属性。
  /// 用法: TextStyle(fontSize: 14).zh() 或 .zh(1.5)
  TextStyle zh([double height = AppLineHeights.body]) => copyWith(height: height);
}
