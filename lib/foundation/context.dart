import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';

import 'app_page_route.dart';

/// 顶层路由防抖时间戳：InkWell 在 tap-up 即触发且 to() 无节流，快速双击
/// 封面会把 ComicPage 压栈两次（Hero 动画连跑两遍、详情页请求两次）。
DateTime? _lastPushTime;

extension Navigation on BuildContext {
  void pop<T>([T? result]) {
    if (mounted) {
      Navigator.of(this).pop(result);
    }
  }

  bool canPop() {
    return Navigator.of(this).canPop();
  }

  Future<T?> to<T>(Widget Function() builder) {
    final now = DateTime.now();
    if (_lastPushTime != null &&
        now.difference(_lastPushTime!) < const Duration(milliseconds: 500)) {
      return Future.value(null);
    }
    _lastPushTime = now;
    return Navigator.of(
      this,
    ).push<T>(AppPageRoute(builder: (context) => builder()));
  }

  Future<void> toReplacement<T>(Widget Function() builder) {
    return Navigator.of(
      this,
    ).pushReplacement(AppPageRoute(builder: (context) => builder()));
  }

  double get width => MediaQuery.of(this).size.width;

  double get height => MediaQuery.of(this).size.height;

  EdgeInsets get padding => MediaQuery.of(this).padding;

  EdgeInsets get viewInsets => MediaQuery.of(this).viewInsets;

  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  Brightness get brightness => Theme.of(this).brightness;

  bool get isDarkMode => brightness == Brightness.dark;

  void showMessage({required String message}) {
    showToast(message: message, context: this);
  }

  Color useBackgroundColor(MaterialColor color) {
    return color[brightness == Brightness.light ? 100 : 800]!;
  }

  Color useTextColor(MaterialColor color) {
    return color[brightness == Brightness.light ? 800 : 100]!;
  }
}
