import 'package:flutter/material.dart';

/// 圆角 token —— 收敛散落的 `BorderRadius.circular(N)` 魔法数字。
///
/// 现状代码中 8/12/16/20 是隐含的主流层级（合计占绝大多数用量），
/// 这里将其显式化为唯一事实来源。新代码请引用这些层级，
/// 不要再引入 10/11/22 这类漂移值。
class AppRadii {
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double extraLarge = 20;

  static const BorderRadius smallBorder =
      BorderRadius.all(Radius.circular(small));
  static const BorderRadius mediumBorder =
      BorderRadius.all(Radius.circular(medium));
  static const BorderRadius largeBorder =
      BorderRadius.all(Radius.circular(large));
  static const BorderRadius extraLargeBorder =
      BorderRadius.all(Radius.circular(extraLarge));
}

/// 间距 token —— 基于 4dp 网格，收敛散落的 padding/gap 魔法数字。
///
/// 现状以 4/8/12/16 为主，这里补充更大的层级以覆盖常用 gap。
/// 新代码请优先选用这些层级，避免 5/7/10/14 这类离群值。
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}
