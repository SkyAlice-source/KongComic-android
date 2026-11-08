import 'dart:async';
import 'dart:math' as math;
import 'package:kong_comic/foundation/appdata.dart';
import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/consts.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/history.dart';
import 'package:kong_comic/foundation/listen_mixin.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/pages/comic_details_page/comic_page.dart';
import 'package:kong_comic/pages/comic_source_page.dart';
import 'package:kong_comic/foundation/follow_updates.dart';
import 'package:kong_comic/pages/follow_updates_page.dart';
import 'package:kong_comic/pages/image_favorites_page/image_favorites_page.dart';
import 'package:kong_comic/utils/translations.dart';

import 'local_comics_page.dart';

/// 平板/宽屏下英雄卡（封面大卡）的最大宽度，避免随屏宽线性放大导致卡片过大。
/// 手机屏宽 * 0.60 恒定小于此值，故手机版外观不受此上限影响。
const double _maxHeroCardWidth = 420;

/// 整叠（装饰卡 + 层间缝 + 主卡）统一向下让位的距离。
/// 主卡顶边原来贴着 `Stack` 的 Clip.hardEdge，顶部那半圈接触阴影被直接
/// 裁平，看起来像被切了一刀。留出一个缝宽 + 2dp：缝在四边都能完整露出，
/// 阴影向上扩散的部分也落在裁切边界内。banner 内的富余是 12dp，够用。
const double _stackTopInset = kcStackSeamWidth + 2.0;

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _currentComic = ValueNotifier<FavoriteItem?>(null);
  Key _bannerKey = UniqueKey();

  @override
  void dispose() {
    _currentComic.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    setState(() {
      _bannerKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        // dock 浮层高度跟随自适应底栏（大字号下栏体会长高），写死 58dp
        // 会让末行被浮岛底栏压住；bottomBarHeight 已含系统手势区。
        final dockHeight = NaviPane.of(context).bottomBarHeight;
        // 中间卡片内在高度：主卡宽上限 sw*0.60、高 cardW*1.4。
        // 用 LayoutBuilder 的内容列宽，而不是 MediaQuery 的整屏宽：宽屏下
        // 内容列被限到 900dp 并居中，按整屏算装饰卡会错位 112dp 并被裁。
        final sw = constraints.maxWidth;
        // 可用内容区高度（减去顶部状态栏和底部 dock）。
        final contentArea = math.max(
          0.0,
          availableHeight - context.padding.top - dockHeight,
        );
        // 原版 v1.5.18 用 0.42：卡片 + 标题 + CTA + 两行胶囊刚好铺满首屏。
        // 之前为修「720x1280 @320dpi」这台模拟小屏的入口遮挡把它压到 0.32，
        // 结果真实 1.5K/2K 手机首屏底部空出约 160dp；实拍 103 又发现按
        // contentArea 阈值分档会误判高屏手机（扣掉共享顶栏 + 浮岛 dock +
        // 手势区后只剩 630~690dp），主卡被压到约 135dp（34% 屏宽）。
        //   2026-11-08 拍板：720p 小屏档也一并放大，**全档统一 0.42**。
        //   入口遮挡不再靠压 banner 解决 —— cardW 由 banner 高度反算并受
        //   sw*0.60 / 420 上限约束，整叠封面一定落在 banner 内；页面本身是
        //   可滚动的 Sliver 列表，矮屏多出来的内容往下滚即可，不会被裁掉。
        //   cardW 同样受 sw*0.60 约束，堆叠卡不会溢出压住标题。
        final bannerHeight = contentArea * 0.42;
        // 堆叠封面是主页的固定视觉，保留。旧问题不是「有堆叠」而是
        // cardW 只按屏宽算、cardW*1.4 常大于 bannerHeight，加上 Clip.none，
        // 整叠会溢出压住标题和底部入口（实拍 42/46/50）。现在由 banner 高度
        // 反算 cardW，让主卡和 4 张装饰卡都完整落在 banner 内，视觉不变。
        final cardW = math.min(
          math.min(sw * 0.60, _maxHeroCardWidth),
          math.max(0.0, (bannerHeight - kcSpaceMd) / 1.4),
        );
        return _BannerProvider(
          bannerHeight: bannerHeight,
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            child: SmoothCustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(top: context.padding.top),
                ),
                _Banner(
                  key: _bannerKey,
                  height: bannerHeight,
                  width: sw,
                  cardWidth: cardW,
                  currentComicNotifier: _currentComic,
                ),
                _ComicInfoSection(currentComicNotifier: _currentComic),
                const _HomeHints(),
                const _HomeCapsules(),
                const _BottomModules(),
                SliverPadding(
                  padding: EdgeInsets.only(
                    bottom: dockHeight + kcPageBottomGap + kcSpaceLg,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    // 宽屏/平板：限制内容最大宽度并居中，避免单列在宽屏上拉满全屏、
    // 按钮/卡片被过度拉伸。手机宽度 < changePoint，分支不进入，外观与手机版一致。
    if (context.width > changePoint) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kcContentMaxWidth),
          child: content,
        ),
      );
    }
    return content;
  }
}

class _BannerProvider extends InheritedWidget {
  final double bannerHeight;
  const _BannerProvider({required this.bannerHeight, required super.child});
  @override
  bool updateShouldNotify(_BannerProvider old) =>
      old.bannerHeight != bannerHeight;
}

class _Banner extends StatefulWidget {
  final double height;

  /// 内容列的宽度（由主页 LayoutBuilder 传入），不是整屏宽。
  /// 装饰卡按它居中，才不会在 900dp 内容列里按整屏宽偏出去 112dp 并被裁。
  final double width;

  /// 由主页 LayoutBuilder 统一算好的主卡宽度（受 banner 高度上限约束）。
  /// _Banner 不再自己按屏宽算，避免父子两套 cardW 不一致导致溢出。
  final double cardWidth;
  final ValueNotifier<FavoriteItem?> currentComicNotifier;
  const _Banner({
    super.key,
    this.height = 360,
    required this.width,
    required this.cardWidth,
    required this.currentComicNotifier,
  });
  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with AutoListenMixin {
  int _currentIndex = 0;
  Timer? _timer;

  /// 手动滑动切换后暂停自动轮播
  bool _pauseAutoPlay = false;

  /// 已确认加载失败的封面（按漫画 id）。
  ///
  /// 轮播每 4 秒换一张，AnimatedSwitcher 会把整张卡重建一次、CoverBox 的
  /// State 也随之销毁；不在这里记一笔，断网时会看到它一遍遍「重新加载」，
  /// 永远等不到失败态，也就永远没有重试按钮。
  final Set<String> _failedCovers = {};
  List<FavoriteItem> _comics = [];
  void _loadComics() {
    final allFolderNames = userFolderNames();
    final selectedFolders = appdata.settings['homeBannerFolders'] as List;
    final folders = selectedFolders.isEmpty
        ? allFolderNames
        : selectedFolders
              .cast<String>()
              .where((f) => allFolderNames.contains(f))
              .toList();
    final all = <FavoriteItem>[];
    for (final folder in folders) {
      all.addAll(LocalFavoritesManager().getFolderComics(folder));
    }
    all.shuffle();
    final comics = all.take(7).toList();
    if (mounted) {
      setState(() {
        _comics = comics;
        if (_currentIndex >= _comics.length) {
          _currentIndex = _comics.isEmpty ? 0 : _comics.length - 1;
        }
        widget.currentComicNotifier.value = _comics.isNotEmpty
            ? _comics[_currentIndex]
            : null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // No PageController needed
    _loadComics();
    listen(LocalFavoritesManager(), _loadComics);
    listen(appdata.settings, _loadComics);
    _startTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只把 AnimatedSwitcher 归零是不够的：Timer 照跑会变成每 4 秒**瞬切**
    // 一张封面，比原来的淡入更刺眼。减少动效时必须让轮播彻底停摆。
    // MediaQuery 变化会重新触发这里，用户运行中改设置也能立即生效。
    if (kcReduceMotion(context)) {
      _timer?.cancel();
      _timer = null;
    } else if (_timer == null && !_pauseAutoPlay) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    // 手动滑动切换后暂停自动轮播（下拉刷新重建页面后恢复）
    if (_pauseAutoPlay || AppAnimations.reduceMotion) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _comics.length < 2) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _comics.length;
        widget.currentComicNotifier.value = _comics[_currentIndex];
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _navigateToComic(FavoriteItem c) {
    context.to(
      () => ComicPage(
        id: c.id,
        sourceKey: c.type.comicSource?.key ?? '',
        cover: c.coverPath,
        title: c.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_comics.isEmpty) return const SliverToBoxAdapter(child: SizedBox());
    if (_comics.length < 3) {
      // Show single card centered when fewer than 3 comics
      // 注：3 本以下才退回单卡。3~4 本仍走堆叠，由 _buildStackedCards
      // 去重后少画外侧装饰卡（绝不重复封面），左右拖拽换卡入口也保留。
      return SliverToBoxAdapter(
        child: SizedBox(
          height: widget.height,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              // 与堆叠分支同样的顶部让位：单卡时接触阴影的上半圈也不能被
              // Stack 的 hardEdge 裁平。
              Padding(
                padding: const EdgeInsets.only(top: _stackTopInset),
                child: GestureDetector(
                  onTap: () => _navigateToComic(_comics[_currentIndex]),
                  child: _buildSingleCard(
                    context,
                    _comics[_currentIndex],
                    width: widget.cardWidth,
                  ),
                ),
              ),
            ],
          ),
        ).paddingVertical(2).paddingBottom(8),
      );
    }

    final cardW = widget.cardWidth;
    return SliverToBoxAdapter(
      child: SizedBox(
        height: widget.height,
        // 方案 B-lite：整叠左右各淡出 kcStackEdgeFade 宽度，替代原来被
        // Clip.hardEdge 直切出的那道竖直硬边；不碰堆叠几何，也不改变
        // 「卡片刚好铺满首屏」的宽度。
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [
              0.0,
              kcStackEdgeFade,
              1 - kcStackEdgeFade,
              1.0,
            ],
          ).createShader(rect),
          child: Stack(
            // 保留原版的 4 层堆叠，但裁在 banner 边界内：溢出部分不再跨到
            // 标题区 / 底部入口上。cardW 已由 banner 高度反算，装饰卡缩放后
            // 更小，不会触发裁切，只有极端窄屏才会削掉最外侧一点边缘。
            clipBehavior: Clip.hardEdge,
            alignment: Alignment.topCenter,
            children: [
              // Decorative stacked cards (background)
              ..._buildStackedCards(context, cardW, widget.width),
              // 层间缝：垫在装饰卡与主卡之间，主卡四周露出 2dp 背景色间隙。
              // 放在这里而不是叠在主卡上，是为了不缩小封面、不改堆叠几何。
              _buildStackSeam(context, cardW),
              // Main card with in-place replacement (AnimatedSwitcher)
              // 整叠（装饰卡 + 缝 + 主卡）统一下移 [_stackTopInset]，主卡
              // 不再贴着 Stack 顶边，顶部的缝和接触阴影不会被 Clip.hardEdge
              // 切掉；四边缝宽因此完全一致。
              Positioned(
                top: _stackTopInset,
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                  if (details.velocity.pixelsPerSecond.dx > 80) {
                    final prev =
                        (_currentIndex - 1 + _comics.length) % _comics.length;
                    _pauseAutoPlay = true;
                    setState(() {
                      _currentIndex = prev;
                      widget.currentComicNotifier.value =
                          _comics[_currentIndex];
                    });
                  } else if (details.velocity.pixelsPerSecond.dx < -80) {
                    final next = (_currentIndex + 1) % _comics.length;
                    _pauseAutoPlay = true;
                    setState(() {
                      _currentIndex = next;
                      widget.currentComicNotifier.value =
                          _comics[_currentIndex];
                    });
                  }
                },
                child: AnimatedSwitcher(
                  duration: kcReduceMotion(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    );
                  },
                  child: SizedBox(
                    key: ValueKey(_currentIndex),
                    width: cardW,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => _navigateToComic(_comics[_currentIndex]),
                        child: _buildSingleCard(
                          context,
                          _comics[_currentIndex],
                          width: cardW,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ],
          ),
        ),
      ).paddingVertical(2).paddingBottom(8),
    );
  }

  /// 主页英雄区最多 4 张堆叠装饰封面（v1.5.18 视觉）。
  /// 以当前主卡为中心向左右各两张；漫画不足 5 本时按由内到外的顺序少画
  /// 外侧的（3 本画 2 张、4 本画 3 张），只从主卡以外的漫画里取，绝不重复。
  /// `Transform.scale` 按**中心**等比缩小
  /// （不调平底边，用户明确要求保留原来的错落感）。重叠处由主卡盖住，
  /// 层间缝的下段渐变淡出负责消掉底边错开处的硬折角。
  /// 尺寸全部由 [cardW] 派生，cardW 由主页按 banner 高度反算，因此整叠不会
  /// 溢出到标题区；装饰卡不显示图标和重试按钮，但保留淡灰书名首字作为
  /// 封面加载中 / 失败时的占位（见 [_buildCover]），避免出现纯色空框。
  ///
  /// 边缘按方案 A 收口：与主卡一样只用 [kcCardRadius] 单层圆角，原来 3dp
  /// 白边换成 [kcHairlineColor] 发丝描边。旧版四层 blur6 阴影叠加后糊成
  /// 一团且被 ClipRRect 裁掉，浅色下还有一圈「贴纸白框」，这里不复刻。
  ///
  /// 分层由两件事共同承担：越靠外的装饰卡叠越厚的 surface / 黑色 scrim，
  /// 视觉上退到背景里；**每张卡**（含 4 张装饰卡和主卡）都带一圈四边等宽
  /// 的实体色层间缝，保证复杂封面下前后关系仍然可读，也让装饰卡底边不再
  /// 是一条被横切的硬直线。描边只留 0.8dp 发丝做轮廓，不负责分层。
  List<Widget> _buildStackedCards(
    BuildContext context,
    double cardW,
    double sw,
  ) {
    final items = <Widget>[];
    final cs = Theme.of(context).colorScheme;
    // 浅色叠 surface（往背景淡化），深色叠纯黑（往背景压暗），两条路都是
    // 「让外侧卡片退后」，不会在浅色下出现一圈发白的贴纸边。
    final scrimColor = cs.brightness == Brightness.dark
        ? Colors.black
        : cs.surface;
    // 整叠的视觉宽度恰好是 2 × cardW：最外侧 layer=±2 缩到 0.8 后，外缘落在
    // sw/2 ± (2 × overlap + 0.4 × cardW)。原版 overlap=0.30 × cardW 时该式
    // 化简为 sw/2 ± cardW —— 只有 cardW ≈ sw/2 才刚好铺满。现在 cardW 改由
    // banner 高度反算，矮屏 / 720p 会被压到约 0.35sw，左右就各空出十几 dp
    // 纯白，看起来就是「卡片没填满框」（实拍 141：720p 左右各空约 51dp）。
    //
    // 让间距自适应：cardW 够大时维持原版 0.30 × cardW；cardW 偏小时把最外侧
    // 两张往外推，使外缘重新贴到内容列两边。clamp 到 0.80 × cardW 是保证
    // layer=±1 与 ±2 始终重叠，不会为了贴边把整叠拆成几张孤立的卡。
    final overlap = math.min(
      math.max(cardW * 0.30, sw / 4 - cardW * 0.20),
      cardW * 0.80,
    );
    // 缝不再是主卡专属：4 张装饰卡各自也带一圈四边等宽的缝，底边同样
    // 有收口。共用一个 [BoxDecoration] 实例，颜色/圆角/阴影完全一致。
    final seam = kcStackSeamWidth;
    final seamDecoration = _stackSeamDecoration(context);
    // 原来直接按 (_currentIndex + layer) % len 取漫画：只有 3 本时 ±1 与
    // ±2 两两撞车、4 本时最外侧两张撞车，左右会出现对称的同款封面。这里
    // 改成从「主卡以外的漫画」里按内层→外层顺序取，凑不够 4 张就少画外侧
    // 的，绝不重复；主卡的左右拖拽换卡逻辑完全不受影响。
    // 绘制仍按 |layer| 从大到小（外层先画、内层后画压在上面），保持原有
    // 前后层次；同为内层时左侧先画、右侧后画（排序结果 [-2,2,-1,1]）。
    final otherIndices = <int>[
      for (var d = 1; d < _comics.length; d++)
        (_currentIndex + d) % _comics.length,
    ];
    final layerSlots = const [-1, 1, -2, 2];
    final slots = <MapEntry<int, int>>[];
    final slotCount = math.min(layerSlots.length, otherIndices.length);
    for (var i = 0; i < slotCount; i++) {
      slots.add(MapEntry(layerSlots[i], otherIndices[i]));
    }
    slots.sort((a, b) {
      final byDepth = b.key.abs().compareTo(a.key.abs());
      return byDepth != 0 ? byDepth : a.key.compareTo(b.key);
    });
    for (final slot in slots) {
      final layer = slot.key;
      final comic = _comics[slot.value];
      final scale = 1.0 - layer.abs() * 0.1;
      // 与主卡一起下移 [_stackTopInset]，保持「装饰卡比主卡低 2/4dp」
      // 的相对关系，整叠内部几何不变。
      final topOff = _stackTopInset + layer.abs() * 2.0;
      final pos = sw * 0.5 + layer * overlap - cardW * 0.5;
      // ±1 轻压一层、±2 再压一层：两档差值足够看出前后，又不至于把最外侧
      // 卡片淡得像没加载出来（实拍 0.14/0.30 偏重）。主卡不在此循环，
      // 保持原色 + 阴影，自然跳到最前。
      final scrimAlpha = layer.abs() == 1 ? 0.10 : 0.22;
      items.add(
        Positioned(
          // 外框四边各比卡片大一个缝宽；Transform.scale 以中心为基准，
          // 中心与原来只放卡片时完全一致，堆叠几何不变。
          left: pos - seam,
          top: topOff - seam,
          width: cardW + 2 * seam,
          child: Transform.scale(
            scale: scale,
            child: SizedBox(
              width: cardW + 2 * seam,
              height: cardW * 1.4 + 2 * seam,
              // Clip.none 只放行缝外侧那圈柔和阴影；子节点尺寸都精确，
              // 不会真的溢出到标题区。
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 每张装饰卡自己的层间缝：底边也有一圈背景色收口，
                  // 不再是贯穿左右的硬直线（实拍 321「底部好像切割了」）。
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(decoration: seamDecoration),
                    ),
                  ),
                  Positioned(
                    left: seam,
                    top: seam,
                    width: cardW,
                    height: cardW * 1.4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(kcCardRadius),
                      child: Container(
                        decoration: BoxDecoration(
                          // 外沿统一走全站发丝色（浅色中性灰、深色
                          // onSurface@0.38）；层间前后关系交给缝，描边
                          // 只负责把封面轮廓从缝里划出来。
                          border: Border.all(
                            color: kcHairlineColorFromScheme(cs),
                            width: kcHairline,
                          ),
                          borderRadius: BorderRadius.circular(kcCardRadius),
                        ),
                        child: SizedBox(
                          height: cardW * 1.4,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: _buildCover(comic, decorative: true),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: ColoredBox(
                                    color: scrimColor.withValues(
                                      alpha: scrimAlpha,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return items;
  }

  /// 主卡与身后装饰卡之间的「层间缝」。
  ///
  /// 分层只靠逐层蒙层时，蒙层是叠在**封面**上的半透明色：封面花纹一密、
  /// 或两张封面明暗接近，那 0.10/0.22 的差值就被吃掉了，整叠看着像一张
  /// 被竖线切开的图。这里改成在两层之间垫一圈不随封面变化的背景色间隙
  /// （浅色近白、深色近黑，都是半透明），缝本身是实体色，任何封面都盖不住。
  ///
  /// **四边等宽**：垫片比主卡上下左右各大一个 [kcStackSeamWidth]，主卡则
  /// 连同装饰卡一起下移 [_stackTopInset]，让顶部那道缝也完整露出。早期版本
  /// 只垫左右和底部，顶部没有缝、主卡又贴着裁切边界，实拍就是「上边被切平」。
  /// 圆角取 [kcCardRadius] + 缝宽，保证四角露出的厚度与四边一致。
  Widget _buildStackSeam(BuildContext context, double cardW) {
    final seam = kcStackSeamWidth;
    return Positioned(
      top: _stackTopInset - seam,
      child: IgnorePointer(
        child: Container(
          width: cardW + 2 * seam,
          height: cardW * 1.4 + 2 * seam,
          // 主卡这圈缝的下段做垂直淡出：装饰卡按中心等比缩小，底边比主卡
          // 高 0.05H/0.10H，实体色缝的竖直边会在装饰卡结束处突然断掉，
          // 形成「水平→竖直→水平」的白色 L 形硬折角（实拍 325 用户指出）。
          // 淡出后折角消失，顶部与中段的缝仍完整，几何一点不动。
          decoration: _stackSeamDecoration(
            context,
            shadow: false,
            fadeBottom: true,
          ),
        ),
      ),
    );
  }

  /// 层间缝的统一外观：随主题的背景色 + 一圈柔和暗晕。
  /// 主卡和 4 张装饰卡的颜色、圆角完全一致，保证「每张卡四边等边」。
  ///
  /// [shadow] 只给装饰卡开：装饰卡靠这圈暗晕把底边收口，不会又变成一条
  /// 横切硬线。主卡用的是 `shadow: false`——它的缝是纯实体色，浮起感交给
  /// [_buildSingleCard] 里跟随卡片圆角的阴影；如果缝自己也投一道带向下
  /// offset 的矩形影，三层阴影会在主卡底边叠成一条边界笔直、与圆角脱节
  /// 的深灰横带（实拍 330/333 用户指出的「底部阴影有问题」）。
  ///
  /// [fadeBottom] 只给主卡开：把缝的下 30% 从实体色渐变到透明。装饰卡按
  /// 中心等比缩小，底边比主卡高，实体缝的竖直硬边原本会在装饰卡结束处
  /// 突然断掉形成白色 L 形折角；淡出后下段不再有硬边，顶部/中段的分层
  /// 缝仍完整。渐变与纯色互斥，所以 [color] 此时置空。
  BoxDecoration _stackSeamDecoration(
    BuildContext context, {
    bool shadow = true,
    bool fadeBottom = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final seamColor = cs.surface.withValues(alpha: isDark ? 0.72 : 0.82);
    return BoxDecoration(
      color: fadeBottom ? null : seamColor,
      gradient: fadeBottom
          ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                seamColor,
                seamColor,
                seamColor.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.70, 1.0],
            )
          : null,
      borderRadius: BorderRadius.circular(kcCardRadius + kcStackSeamWidth),
      // 零 offset、零 spread、柔 blur：四边对称的一圈淡晕，任何一边都不会
      // 比另一边更重，也不会留下矩形硬芯。分层主要靠实体色缝，这圈晕只
      // 负责把装饰卡底边收口，所以强度压到几乎看不见。
      boxShadow: shadow
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.06),
                blurRadius: 6,
              ),
            ]
          : null,
    );
  }

  Widget _buildSingleCard(
    BuildContext context,
    FavoriteItem comic, {
    double? width,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sw = widget.width;
    final cardW = width ?? (sw * 0.60).clamp(0.0, _maxHeroCardWidth);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            boxShadow: [
              // 接触阴影：四边均匀的一圈窄暗晕，盖在身后的装饰卡上。
              // 不加 spreadRadius——1dp 硬芯会让卡片底边像贴了一条深灰
              // 直线；不加 offset，左右与上下才会同样柔和。
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.11),
                blurRadius: 5,
              ),
              // 抬升阴影：只留极轻的向下趋势，配合大 blur 让底边阴影
              // 顺着圆角渐隐，而不是形成一条贯穿卡片宽度的硬横带。
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 1),
              ),
            ],
            borderRadius: BorderRadius.circular(kcCardRadius),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kcCardRadius),
            child: Container(
              // 3dp 白边 → 0.8dp 发丝描边：浅色不再是「贴纸白框」，深色
              // 也能看清卡片轮廓；与主卡、装饰卡共用一条边缘语言。
              decoration: BoxDecoration(
                border: Border.all(
                  color: kcHairlineColor(context),
                  width: kcHairline,
                ),
                borderRadius: BorderRadius.circular(kcCardRadius),
              ),
              child: SizedBox(
                width: cardW,
                height: cardW * 1.4,
                child: _buildCover(comic),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCover(FavoriteItem comic, {bool decorative = false}) {
    // 走全 App 统一的封面加载链（自定义封面 > 本地漫画 > CacheManager 网络缓存），
    // 不再用裸 CachedNetworkImage：那是第二套 HTTP 缓存，和 App 自己的
    // CacheManager 互不复用 —— 收藏页刚下好的封面到了主页要重下一遍，
    // 断网时主页就是一片空白（其它页面反而有图，用户会以为是主页坏了）。
    //
    // 占位/失败态由 CoverBox 兜住：加载中显示「书名首字」，失败给重试。
    return CoverBox(
      image: comicCoverImageProvider(comic),
      // 堆叠卡只是背景装饰：关掉图标与重试按钮（否则一屏四五个「重试」比
      // 空白还吵），但**保留淡灰书名首字**。以前装饰卡把 label 也设为 null，
      // 封面还没加载出来或加载失败时 CoverPlaceholder 只剩一块纯色，看起来
      // 就像一个「没填满内容的空框」；首字随 0.8/0.9 缩放一起变小，不抢主卡。
      label: comic.name,
      showIcon: !decorative,
      retryable: !decorative,
      failed: _failedCovers.contains(comic.id),
      onFailed: () => _failedCovers.add(comic.id),
      initialFontSize: decorative ? 38 : 52,
    );
  }
}

class _ComicInfoSection extends StatelessWidget {
  final ValueNotifier<FavoriteItem?> currentComicNotifier;
  const _ComicInfoSection({required this.currentComicNotifier});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FavoriteItem?>(
      valueListenable: currentComicNotifier,
      builder: (context, comic, _) {
        if (comic == null) return const SliverToBoxAdapter(child: SizedBox());
        final cs = Theme.of(context).colorScheme;
        // 漫画名字号与卡片一起收进 kcTitleMain(20)，但高度不再写死：
        // 见下方 AnimatedSize 的说明。
        final history = HistoryManager().find(comic.id, comic.type);
        final progress = history != null
            ? "Chapter %s · %s chapters read".tl
                  .replaceFirst("%s", "${history.ep}")
                  .replaceFirst("%s", "${history.readEpisode.length}")
            : null;
        final updatedTime = comic.time.isNotEmpty
            ? comic.time.substring(0, 10)
            : null;
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(kcSpaceLg, kcSpaceSm, kcSpaceLg, kcSpaceSm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题高度交给 Text 自己算：单行只占一行、两行才撑两行，
                // 系统大字号也不会被写死的 64*scale 裁掉。原先固定双行高度
                // 让短书名下方空一大截，是「标题太大」的另一半原因。
                // AnimatedSize 让切换漫画时（单行 ↔ 两行）平滑过渡，避免
                // 下方 CTA 与信息行「啪」地跳一下。
                AnimatedSize(
                  duration: kcReduceMotion(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      comic.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: kcTitleMain,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
                if (comic.author.isNotEmpty || comic.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: kcSpaceXs),
                    child: Text(
                      comic.author.isNotEmpty ? comic.author : comic.tags.first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: kcBody,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (progress != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: kcSpaceXs),
                    child: Text(
                      progress,
                      style: TextStyle(fontSize: kcBody, color: cs.onSurface),
                    ),
                  ),
                Text(
                  "Total @count chapters".tlParams({
                    'count': "${history?.maxPage ?? '?'}",
                  }),
                  style: TextStyle(
                    fontSize: kcCaption,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (updatedTime != null)
                  Padding(
                    padding: const EdgeInsets.only(top: kcSpaceXs),
                    child: Text(
                      "Updated @time".tlParams({'time': updatedTime}),
                      style: TextStyle(
                        fontSize: kcCaption,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  // 浅色与深色都用「上亮下饱和」的红色渐变 + 柔和大半径红晕包裹；
                  // 圆角走 kcPillRadius（全圆胶囊），与下方入口块同形。
                  // 主 CTA 才有体积与质感；AMOLED 零彩色，退化为实心灰底、无光晕。
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(kcPillRadius),
                      gradient: kcIsAmoled()
                          ? null
                          : const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              // 主页入口卡渐变底：上端用深色版品牌红提亮层次，
                              // 下端落到标准品牌红 —— 两支都必须是品牌色本身，
                              // 不换成 colorScheme 派生色（AMOLED 下整块渐变直接去掉）。
                              // 上端与 kcBrandColorOnDark 同值，直接引用 token。
                              colors: [kcBrandColorOnDark, kcBrandColor],
                            ),
                      boxShadow: kcIsAmoled()
                          ? null
                          : [
                              BoxShadow(
                                color: kcBrandColor.withValues(alpha: 0.30),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () => context.to(
                        () => ComicPage(
                          id: comic.id,
                          sourceKey: comic.type.comicSource?.key ?? '',
                          cover: comic.coverPath,
                          title: comic.name,
                        ),
                      ),
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedPlayCircle,
                        size: 20,
                      ),
                      label: Text(
                        "Read Now".tl,
                        style: TextStyle(
                          fontSize: kcSubtitle,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        // 渐变由外层 Container 提供，按钮本身透明只承载文字/涟漪；
                        // AMOLED 则退回中性灰实心（与灰阶按钮同源）。
                        backgroundColor: kcIsAmoled()
                            ? kcAccentColor(context)
                            : Colors.transparent,
                        foregroundColor: kcOnAccentColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kcPillRadius),
                        ),
                        // 显式清掉边线：深色主题给 ElevatedButton 强加了灰描边，
                        // 会在这个灰底 CTA 外再套一圈灰环。
                        side: BorderSide.none,
                        elevation: 0,
                        surfaceTintColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeCapsules extends StatefulWidget {
  const _HomeCapsules();
  @override
  State<_HomeCapsules> createState() => _HomeCapsulesState();
}

class _HomeCapsulesState extends State<_HomeCapsules> with AutoListenMixin {
  int _updateCount = 0;
  List<String> get folders => getEffectiveFollowFolders();
  void _refresh() {
    if (!mounted) return;
    setState(() {
      _updateCount = folders.fold(
        0,
        (sum, f) => sum + LocalFavoritesManager().countUpdates(f),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    listen(LocalFavoritesManager(), _refresh);
    listen(LocalManager(), _refresh);
  }

  @override
  Widget build(BuildContext context) {
    final lc = LocalManager().count;
    return SliverToBoxAdapter(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg, vertical: kcSpaceXs),
            child: Row(
              children: [
                Expanded(
                  child: _FlatBox(
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedRefresh,
                      size: 20,
                    ),
                    label: "Follow Updates".tl,
                    value: _updateCount > 0 ? "$_updateCount" : null,
                    alert: _updateCount > 0,
                    onTap: () => context.to(() => const FollowUpdatesPage()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FlatBox(
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedFolder01,
                      size: 20,
                    ),
                    label: "Local".tl,
                    value: "$lc",
                    onTap: () => context.to(() => const LocalComicsPage()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomModules extends StatelessWidget {
  const _BottomModules();
  @override
  Widget build(BuildContext context) {
    final cc = ComicSource.all().length;
    final imgCount = ImageFavoriteManager().length;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg, vertical: kcSpaceXs),
        child: Row(
          children: [
            Expanded(
              child: _FlatBox(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: 20),
                label: "Image Favorites".tl,
                value: imgCount > 0 ? "$imgCount" : null,
                onTap: () => context.to(() => const ImageFavoritesPage()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _FlatBox(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedGlobe02, size: 20),
                label: "Comic Source".tl,
                value: "$cc",
                onTap: () => context.to(() => const ComicSourcePage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlatBox extends StatelessWidget {
  final Widget icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool alert;
  const _FlatBox({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.alert = false,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            // 大字号下「Follow Updates / Image Favorites」会换行，写死 48dp
            // 时第二行与数字徽章会溢出，并被玻璃 dock 盖住（实拍 46/50）。
            constraints: BoxConstraints(
              minHeight: kcMinTapTarget *
                  MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: kcSpaceMd),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kcPillRadius),
              color: cs.surfaceContainerLow,
            ),
            child: Row(
              children: [
                icon,
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: kcBody, color: cs.onSurface),
                  ),
                ),
                if (value != null)
                  Container(
                    margin: const EdgeInsets.only(right: kcSpaceMd),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    decoration: BoxDecoration(
                      // 未读强调走品牌红（设计系统：强调一律 accent 红），不再用 errorContainer。
                      color: alert
                          ? kcAccentColor(context)
                          : kcAccentSurface(context),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        value!,
                        style: TextStyle(
                          fontSize: kcFont11,
                          fontWeight: FontWeight.w600,
                          color: alert
                              ? kcOnAccentColor
                              : kcBrandAdaptive(context),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 轻量主页底部提示区 —— 根据当前状态显示上下文引导文字。
/// 纯展示（SliverToBoxAdapter），不触碰任何现有组件逻辑/状态。
class _HomeHints extends StatefulWidget {
  const _HomeHints();

  @override
  State<_HomeHints> createState() => _HomeHintsState();
}

class _HomeHintsState extends State<_HomeHints> with AutoListenMixin {
  int _localCount = 0;
  int _favoriteCount = 0;
  int _sourceCount = 0;

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _localCount = LocalManager().count;
      _favoriteCount = LocalFavoritesManager().totalComics;
      _sourceCount = ComicSource.enabled().length;
    });
  }

  @override
  void initState() {
    super.initState();
    _localCount = LocalManager().count;
    _favoriteCount = LocalFavoritesManager().totalComics;
    _sourceCount = ComicSource.enabled().length;
    listen(LocalManager(), _refresh);
    listen(LocalFavoritesManager(), _refresh);
    listen(ComicSourceManager(), _refresh);
  }

  @override
  Widget build(BuildContext context) {
    // 只要任意一类内容存在，就不显示引导提示
    if (_sourceCount > 0 || _localCount > 0 || _favoriteCount > 0) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final shown = <String>[
      'Go to "Comic Source" to add sources and discover more.'.tl,
      'No local comics yet? Tap "Local" above to add a comic folder.'.tl,
    ].take(2).toList();

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg, vertical: 20),
        child: Column(
          children: shown.map((hint) => _HintCard(text: hint)).toList(),
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  final String text;
  const _HintCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: kcSpaceLg, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kcRadius18),
        // 柔光微投影：让提示卡从纯白页面上轻轻「浮」起，增加质感而不抢眼。
        boxShadow: kcContourGlow(context),
      ),
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedBulb,
            size: 20,
            color: kcBrandAdaptive(context).withValues(alpha: 0.8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: kcBody,
                color: cs.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
