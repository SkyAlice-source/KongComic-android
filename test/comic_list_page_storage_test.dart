import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kong_comic/components/components.dart';

// PageStorage 槽位隔离的回归测试。
//
// 背景（真实线上崩溃）：`ComicList` 会把整份分页状态（一个 `Map`）用
// `PageStorage.writeState(context, state)` 写进当前 bucket，槽位标识是
// 「到 bucket 为止路径上有哪些 PageStorageKey」。Flutter 的
// `PageStorageBucket` **只按 key 列表比较槽位，不看 widget 类型**：
//
//   ComicList(key: PageStorageKey('comic_list'))  → 槽 ['comic_list']
//   它内部无 key 的 GridView / ListView              → 槽 ['comic_list']（同一个！）
//
// 于是一次刷新 / 跳到未加载页时，骨架屏的 `ScrollPosition.restoreScrollOffset`
// 会执行 `readState(...) as double?`，拿到的却是分页状态的 `_Map<String,
// dynamic>`，直接抛
// 「type '_Map<String, dynamic>' is not a subtype of type 'double?'」，
// 整块列表变成 ErrorWidget —— 用户看到的就是「整页空白 + 一行报错」。
//
// 修复方式不是禁止写状态，而是要求 ComicList 子树里每个滚动视图都持有**自己的**
// PageStorageKey。本测试把这个约束钉在骨架屏上：有人删掉那个 key，这里立刻红。

void main() {
  testWidgets('骨架屏的滚动视图持有独立 PageStorageKey', (tester) async {
    // 永不完成的加载：让 ComicList 稳定停在骨架屏状态。
    // `Completer<Never>` 的 future 是 `Future<Res<List<Comic>>>` 的子类型
    // （Never 是底部类型），这样测试不必 import 业务模型层。
    final pending = Completer<Never>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComicList(
            key: const PageStorageKey('comic_list'),
            enablePageStorage: true,
            loadPage: (_) => pending.future,
          ),
        ),
      ),
    );
    await tester.pump();

    final grids = tester.widgetList<GridView>(find.byType(GridView));
    expect(grids, isNotEmpty, reason: '加载中应渲染骨架屏网格');
    for (final grid in grids) {
      expect(
        grid.key,
        isA<PageStorageKey>(),
        reason: '骨架屏滚动视图必须自带 PageStorageKey，'
            '否则会读到 ComicList 写进同一槽位的 Map 并抛类型错误',
      );
    }
  });
}
