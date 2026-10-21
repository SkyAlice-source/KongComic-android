import 'package:flutter/material.dart';

/// 自动登记 / 注销监听的 mixin —— 根治「收藏角标刷新」那类根因 bug
///（手写 `addListener` + `removeListener` 配对，漏 dispose 或忘调用导致
/// 旧 State 永远收不到更新 / 内存泄漏）。
///
/// 用法（替代手写配对）：
/// ```dart
/// class _XState extends State<X> with AutoListenMixin {
///   @override
///   void initState() {
///     super.initState();
///     listen(LocalFavoritesManager(), _onChanged); // 自动登记
///   }
///   // 不需要手写 dispose：mixin 在 dispose 时统一 removeListener。
///   // 若本类仍需 dispose，务必调用 super.dispose()。
/// }
/// ```
///
/// ⚠️ 约定：接入本 mixin 后**不要再手写 `removeListener`**；且若类自身
/// 重写了 `dispose`，必须调用 `super.dispose()`（否则登记不会被注销）。
/// 双重注销是安全的（Flutter 对未登记的监听 removeListener 是 no-op）。
mixin AutoListenMixin<T extends StatefulWidget> on State<T> {
  final List<_ListenerEntry> _entries = [];

  /// 登记一个监听，返回其句柄。dispose 时自动注销，无需手动 removeListener。
  AutoListenHandle listen(Listenable listenable, VoidCallback listener) {
    listenable.addListener(listener);
    final entry = _ListenerEntry(listenable, listener);
    _entries.add(entry);
    return AutoListenHandle._(entry, _entries);
  }

  @mustCallSuper
  @override
  void dispose() {
    for (final e in _entries) {
      e.listenable.removeListener(e.listener);
    }
    _entries.clear();
    super.dispose();
  }
}

class _ListenerEntry {
  _ListenerEntry(this.listenable, this.listener);

  final Listenable listenable;
  final VoidCallback listener;
}

/// 监听句柄：允许在 widget 销毁前主动注销（罕见场景，多数情况交给 mixin）。
class AutoListenHandle {
  AutoListenHandle._(this._entry, this._entries);

  final _ListenerEntry _entry;
  final List<_ListenerEntry> _entries;

  void cancel() {
    _entry.listenable.removeListener(_entry.listener);
    _entries.remove(_entry);
  }
}
