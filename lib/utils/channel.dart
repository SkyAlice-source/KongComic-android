import 'dart:async';
import 'dart:collection';

class Channel<T> {
  final Queue<T> _queue;

  final int size;

  Channel(this.size) : _queue = Queue<T>();

  Completer? _releaseCompleter;

  Completer? _pushCompleter;

  var currentSize = 0;

  var isClosed = false;

  Future<void> push(T item) async {
    if (currentSize >= size) {
      _releaseCompleter ??= Completer();
      return _releaseCompleter!.future.then((_) {
        if (isClosed) {
          return;
        }
        _queue.addLast(item);
        currentSize++;
      });
    }
    _queue.addLast(item);
    currentSize++;
    _pushCompleter?.complete();
    _pushCompleter = null;
  }

  Future<T?> pop() async {
    while (_queue.isEmpty) {
      if (isClosed) {
        return null;
      }
      _pushCompleter ??= Completer();
      await _pushCompleter!.future;
    }
    var item = _queue.removeFirst();
    currentSize--;
    if (_releaseCompleter != null && currentSize < size) {
      _releaseCompleter!.complete();
      _releaseCompleter = null;
    }
    return item;
  }

  /// 关闭队列并唤醒所有阻塞的 push/pop。
  ///
  /// 生产者在投递完毕后会 close 一次；订阅方结束（`await for` 退出 / 流被
  /// 关闭）时 `onCancel` 又会 close 一次 —— 两次都调用 complete() 会抛
  /// 「Bad state: Future already completed」，在追更检查里刷了一堆红色堆栈。
  /// 这里做成幂等：已完成的 completer 不再重复 complete。
  void close() {
    isClosed = true;
    final push = _pushCompleter;
    if (push != null && !push.isCompleted) push.complete();
    final release = _releaseCompleter;
    if (release != null && !release.isCompleted) release.complete();
  }
}