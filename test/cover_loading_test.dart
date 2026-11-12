import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kong_comic/components/components.dart';

// 封面「加载中」指示的两条行为约束。
//
// 1. 立刻转圈是错的：多数封面 200–600ms 就回来了，列表滚动时会变成满屏
//    「一闪而过的圈」，比没有指示更躁。所以必须延迟（320ms）后才出现。
// 2. 图到得快时不能出现：延迟窗口内加载完成的封面，整个占位会被
//    AnimatedSwitcher 换走，环一次都不该被建出来。

/// 永不完成的图片源：模拟「图还在路上」，既不成功也不失败。
class _PendingImageProvider extends ImageProvider<_PendingImageProvider> {
  @override
  Future<_PendingImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_PendingImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _PendingImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: Completer<ui.Codec>().future,
      scale: 1.0,
      debugLabel: 'pending',
    );
  }
}


/// 可手动发 chunk 事件的图片源：模拟「正在下载、总长已知」。
class _ChunkCompleter extends ImageStreamCompleter {
  void emit(int loaded, int? total) {
    reportImageChunkEvent(
      ImageChunkEvent(
        cumulativeBytesLoaded: loaded,
        expectedTotalBytes: total,
      ),
    );
  }
}

class _ChunkImageProvider extends ImageProvider<_ChunkImageProvider> {
  final completer = _ChunkCompleter();

  @override
  Future<_ChunkImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_ChunkImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _ChunkImageProvider key,
    ImageDecoderCallback decode,
  ) => completer;
}

/// 第一次失败、之后一直挂起的图片源：用来验证「刷新后失败封面会再试一次」。
class _FlakyImageProvider extends ImageProvider<_FlakyImageProvider> {
  int loads = 0;

  @override
  Future<_FlakyImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FlakyImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _FlakyImageProvider key,
    ImageDecoderCallback decode,
  ) {
    loads++;
    if (loads == 1) {
      return MultiFrameImageStreamCompleter(
        codec: Future<ui.Codec>.error('boom'),
        scale: 1.0,
        debugLabel: 'flaky',
      );
    }
    return MultiFrameImageStreamCompleter(
      codec: Completer<ui.Codec>().future,
      scale: 1.0,
      debugLabel: 'flaky-pending',
    );
  }
}

void main() {
  testWidgets('封面加载超过 320ms 才出现圆环', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 160,
            child: CoverBox(image: _PendingImageProvider(), label: '测试漫画'),
          ),
        ),
      ),
    );
    await tester.pump();

    // 延迟窗口内：只有首字占位，不能有转圈。
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: '320ms 内不应出现加载环（否则快图会在列表里闪一下圈）',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // 超过延迟：环出现，且首字仍在（退为背景）。
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(CoverPlaceholder), findsOneWidget);
  });

  testWidgets('封面加载失败时给出可点的重试入口', (tester) async {
    // 空字节必然解码失败，走 onError 分支。
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 140,
            child: CoverBox(
              image: MemoryImage(Uint8List(0)),
              label: '测试漫画',
              retryable: false,
              initialFontSize: 32,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.bySemanticsLabel('Retry'),
      findsOneWidget,
      reason: '失败态必须有可见、可点的重试入口，'
          '否则用户看到的首字占位和「正在加载」完全一样',
    );

    // 让一次性自动重试的 Timer 走完，避免测试结束时留下 pending timer。
    await tester.pump(const Duration(seconds: 2));
    handle.dispose();
  });

  testWidgets('大卡显示真实下载百分比', (tester) async {
    final provider = _ChunkImageProvider();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 160,
            height: 220,
            child: CoverBox(
              image: provider,
              label: '测试漫画',
              initialFontSize: 52,
              showProgressPercent: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // 装载完成后再发 chunk：环出现时应该直接读到最新比例。
    provider.completer.emit(1024, 4096);
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('25%'),
      findsOneWidget,
      reason: '大卡必须显示真实百分比，否则「慢」和「卡死」仍然分不出来',
    );
    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, closeTo(0.25, 0.001), reason: '环的弧长应与百分比一致');
  });

  testWidgets('服务器不报总长时退回不确定环，不显示假百分比', (tester) async {
    final provider = _ChunkImageProvider();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 160,
            height: 220,
            child: CoverBox(
              image: provider,
              label: '测试漫画',
              initialFontSize: 52,
              showProgressPercent: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    provider.completer.emit(1024, null);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('%'), findsNothing);
    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, isNull, reason: '算不出比例时必须是 undefined 进度');
  });

  testWidgets('下拉刷新后失败的封面会重新加载', (tester) async {
    final handle = tester.ensureSemantics();
    final provider = _FlakyImageProvider();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 140,
            child: CoverBox(
              image: provider,
              label: '测试漫画',
              retryable: false,
              initialFontSize: 32,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(provider.loads, 1);
    expect(find.bySemanticsLabel('Retry'), findsOneWidget);

    // 模拟下拉刷新：列表数据回来了，封面也应跟着重来。
    CoverBox.refreshAll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      provider.loads,
      2,
      reason: '下拉刷新必须真的重新请求封面，否则「刷了还是缺图」',
    );
    expect(find.bySemanticsLabel('Retry'), findsNothing);
    handle.dispose();
  });
}
