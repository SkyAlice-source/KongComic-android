import 'package:flutter/widgets.dart';

class Pair<K, V> {
  K left;
  V right;

  Pair(this.left, this.right);
}

abstract class GlobalState {
  static final _state = <Object?, Map<Type, State>>{};

  static void register(State state, [Object? key]) {
    (_state.putIfAbsent(key, () => <Type, State>{}))[state.runtimeType] = state;
  }

  static T find<T extends State>([Object? key]) {
    final map = _state[key];
    if (map != null) {
      final state = map[T];
      if (state != null) return state as T;
    }
    throw Exception('State not found');
  }

  static T? findOrNull<T extends State>([Object? key]) {
    final map = _state[key];
    if (map != null) {
      final state = map[T];
      if (state != null) return state as T;
    }
    return null;
  }

  static void unregister(State state, [Object? key]) {
    final map = _state[key];
    if (map != null) {
      map.remove(state.runtimeType);
      if (map.isEmpty) {
        _state.remove(key);
      }
    }
  }
}

abstract class AutomaticGlobalState<T extends StatefulWidget>
    extends State<T> {
  @override
  @mustCallSuper
  void initState() {
    super.initState();
    GlobalState.register(this, key);
  }

  @override
  @mustCallSuper
  void dispose() {
    super.dispose();
    GlobalState.unregister(this, key);
  }

  Object? get key;

  void update() {
    setState(() {});
  }

  void refresh() {
    update();
  }
}
