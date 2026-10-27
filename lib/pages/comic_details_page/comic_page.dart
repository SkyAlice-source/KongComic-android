import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:sliver_tools/sliver_tools.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/components/scroll_top_fab.dart';
import 'package:kong_comic/components/rich_comment_content.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_type.dart';
import 'package:kong_comic/foundation/consts.dart';
import 'package:kong_comic/foundation/custom_cover.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/history.dart';
import 'package:kong_comic/foundation/image_provider/cached_image.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/foundation/listen_mixin.dart';
import 'package:kong_comic/foundation/res.dart';
import 'package:kong_comic/network/download.dart';
import 'package:kong_comic/network/cache.dart';
import 'package:kong_comic/pages/downloading_page.dart';
import 'package:kong_comic/pages/favorites/favorites_page.dart';
import 'package:kong_comic/pages/reader/reader.dart';
import 'package:kong_comic/utils/file_type.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:kong_comic/utils/tags_translation.dart';
import 'package:kong_comic/utils/translations.dart';
import 'dart:math' as math;

part 'comments_page.dart';

part 'chapters.dart';

part 'thumbnails.dart';

part 'favorite.dart';

part 'comments_preview.dart';

part 'actions.dart';

part 'cover_viewer.dart';

class ComicPage extends StatefulWidget {
  const ComicPage({
    super.key,
    required this.id,
    required this.sourceKey,
    this.cover,
    this.title,
    this.heroID,
  });

  final String id;

  final String sourceKey;

  final String? cover;

  final String? title;

  final int? heroID;

  @override
  State<ComicPage> createState() => _ComicPageState();
}

class _ComicPageState extends LoadingState<ComicPage, ComicDetails>
    with _ComicPageActions, AutoListenMixin {
  @override
  History? history;

  bool showAppbarTitle = false;

  var scrollController = ScrollController();

  bool isDownloaded = false;

  DownloadTask? _downloadTask;

  void _findDownloadTask() {
    var target = LocalManager().downloadingTasks.cast<DownloadTask?>().firstWhere(
      (t) =>
          t != null &&
          t.id == widget.id &&
          t.comicType == ComicType.fromKey(widget.sourceKey),
      orElse: () => null,
    );
    if (target != _downloadTask) {
      _downloadTask?.removeListener(_onDownloadProgress);
      _downloadTask = target;
      _downloadTask?.addListener(_onDownloadProgress);
    }
  }

  void _onDownloadProgress() {
    _findDownloadTask();
    if (mounted) setState(() {});
  }

  bool showFAB = false;

  /// 详情页描述折叠状态：超过 4 行时折叠，点击在展开/收起间切换。
  bool _descExpanded = false;

  /// 收藏状态：由 [loadData] 阶段提前查 folder 得到的最终值，
  /// 避免进入页面后异步 setState 导致收藏图标先「未收藏」再跳「已收藏」的闪烁。
  bool? _serverFavorited;

  @override
  void onReadEnd() {
    history ??= HistoryManager().find(
      widget.id,
      ComicType(widget.sourceKey.hashCode),
    );
    update();
  }

  @override
  Widget buildLoading() {
    return _ComicPageLoadingPlaceHolder(
      cover: widget.cover,
      title: widget.title,
      sourceKey: widget.sourceKey,
      cid: widget.id,
      heroID: widget.heroID,
    );
  }

  @override
  Widget buildError() {
    final isDownloaded = LocalManager().isDownloaded(
      widget.id,
      ComicType.fromKey(widget.sourceKey),
    );
    Widget? action;
    if (isDownloaded) {
      action = Button.filled(
        child: Text("Read".tl),
        onPressed: () {
          final localComic = LocalManager().find(
            widget.id,
            ComicType.fromKey(widget.sourceKey),
          );
          if (localComic == null) {
            context.showMessage(message: "Local comic not found".tl);
            return;
          }
          localComic.read();
        },
      );
    }
    return NetworkError(message: error!, retry: retry, action: action);
  }

  @override
  void initState() {
    listen(scrollController, onScroll);
    listen(LocalManager(), _onDownloadProgress);
    super.initState();
  }

  @override
  void dispose() {
    scrollController.dispose();
    _downloadTask?.removeListener(_onDownloadProgress);
    super.dispose();
  }

  @override
  void update() {
    setState(() {});
  }

  @override
  ComicDetails get comic => data!;

  void onScroll() {
    var offset =
        scrollController.position.pixels -
        scrollController.position.minScrollExtent;
    var showFAB = offset > 0;
    if (showFAB != this.showFAB) {
      setState(() {
        this.showFAB = showFAB;
      });
    }
    if (offset > 100) {
      if (!showAppbarTitle) {
        setState(() {
          showAppbarTitle = true;
        });
      }
    } else {
      if (showAppbarTitle) {
        setState(() {
          showAppbarTitle = false;
        });
      }
    }
  }

  var isFirst = true;

  @override
  Widget buildContent(BuildContext context, ComicDetails data) {
    return Scaffold(
      floatingActionButton: showFAB
          ? ScrollTopFab(
              heroTag: 'comicScrollTopFab',
              onPressed: () {
                scrollController.animateTo(
                  0,
                  duration: AppAnimations.duration(const Duration(milliseconds: 400)),
                  curve: kcSpring,
                );
              },
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: SmoothCustomScrollView(
          controller: scrollController,
          slivers: [
          ...buildTitle(),
          buildActions(),
          buildDescription(),
          buildInfo(),
          buildChapters(),
          buildComments(),
          buildThumbnails(),
          buildRecommend(),
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: context.padding.bottom + 80,
            ), // Add additional padding for FAB
          ),
        ],
        ),
      ),
    );
  }

  /// 下拉刷新：重新拉取详情数据并校正收藏/历史状态。
  /// 本地漫画详情页不会停留（[loadData] 会跳转阅读器），无需刷新，直接返回。
  Future<void> _refresh() async {
    if (widget.sourceKey == 'local') return;
    final res = await loadData();
    if (!mounted) return;
    if (res.success) {
      data = res.data;
      await onDataLoaded();
      // onDataLoaded 内部可能再 await（二次 gap），这里要重新检查。
      if (!mounted) return;
      setState(() {});
    } else {
      context.showMessage(message: friendlyError(res.errorMessage ?? "Refresh Failed".tl));
    }
  }

  @override
  Future<Res<ComicDetails>> loadData() async {
    if (widget.sourceKey == 'local') {
      var localComic = LocalManager().find(widget.id, ComicType.local);
      if (localComic == null) {
        return Res.error('Local comic not found'.tl);
      }
      var history = HistoryManager().find(widget.id, ComicType.local);
      if (isFirst) {
        Future.microtask(() {
          App.mainNavigatorKey?.currentContext?.toReplacement(() {
            return Reader(
              type: ComicType.local,
              cid: widget.id,
              name: localComic.title,
              chapters: localComic.chapters,
              initialPage: history?.page,
              initialChapter: history?.ep,
              initialChapterGroup: history?.group,
              history:
                  history ??
                  History.fromModel(model: localComic, ep: 0, page: 0),
              author: localComic.subTitle ?? '',
              tags: localComic.tags,
            );
          });
        });
        isFirst = false;
      }
      await Future.delayed(const Duration(milliseconds: 200));
      // 内部标记：本地漫画已在上面跳转 Reader 并 pop 详情页，
      // 返回 error 仅用于结束加载流程（不展示给用户）。
      return const Res.error('Local comic');
    }
    var comicSource = ComicSource.find(widget.sourceKey);
    if (comicSource == null) {
      return Res.error('Comic source not found'.tl);
    }
    isAddToLocalFav = LocalFavoritesManager().isExist(
      widget.id,
      ComicType(widget.sourceKey.hashCode),
    );
    history = HistoryManager().find(
      widget.id,
      ComicType(widget.sourceKey.hashCode),
    );
    // 提前查 folder 收藏，得到最终 isFavorite，避免进入页面后异步 setState 闪烁。
    _serverFavorited = null;
    if (comicSource.favoriteData?.loadFolders != null && comicSource.isLogged) {
      try {
        final res = await comicSource.favoriteData!.loadFolders!(widget.id);
        if (!res.error && res.subData is List) {
          _serverFavorited = (List<String>.from(res.subData)).isNotEmpty;
        }
      } catch (_) {
        // 查询失败时回退到源的 isFavorite。
      }
    }
    return comicSource.loadComicInfo!(widget.id);
  }

  @override
  Future<void> onDataLoaded() async {
    isLiked = comic.isLiked ?? false;
    // folder 查询已在 [loadData] 阶段提前完成（写入 [_serverFavorited]），
    // 此处直接使用最终值，避免先显示「未收藏」再跳「已收藏」的闪烁。
    isFavorite = _serverFavorited ?? comic.isFavorite ?? false;
    if (comic.chapters == null) {
      isDownloaded = LocalManager().isDownloaded(comic.id, comic.comicType, 0);
    }
  }

  Iterable<Widget> buildTitle() sync* {
    yield SliverAppbar(
      title: AnimatedOpacity(
        opacity: showAppbarTitle ? 1.0 : 0.0,
        duration: AppAnimations.duration(const Duration(milliseconds: 200)),
        child: Text(comic.title),
      ),
      actions: [
        // 复制（合并 ID / 标题）
        Builder(
          builder: (btnCtx) => IconButton(
            onPressed: () => _showCopyMenu(btnCtx),
            icon: HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 18),
            tooltip: "Copy".tl,
          ),
        ),
        // 封面（合并 本地 / 漫画页）
        Builder(
          builder: (btnCtx) => IconButton(
            onPressed: () => _showCoverMenu(btnCtx),
            icon: HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: 18),
            tooltip: CustomCoverManager.hasCustomCover(comic.sourceKey, comic.id)
                ? "Change Cover".tl
                : "Set Cover".tl,
          ),
        ),
      ],
    );

    yield const SliverPadding(padding: EdgeInsets.only(top: 8));

    yield SliverLazyToBoxAdapter(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () => _viewCover(context),
            onLongPress: () => _saveCover(context),
            child: Hero(
              tag: "cover${widget.heroID}",
              child: Container(
                decoration: BoxDecoration(
                  color: context.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(kcCardRadius),
                  boxShadow: [
                    BoxShadow(
                      color: context.colorScheme.outlineVariant,
                      blurRadius: 1,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                height: 144,
                width: 144 * 0.72,
                clipBehavior: Clip.antiAlias,
                child: AnimatedImage(
                  image: CachedImageProvider(
                    widget.cover ?? comic.cover,
                    sourceKey: comic.sourceKey,
                    cid: comic.id,
                  ),
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(comic.title, style: TextStyle(fontSize: kcSectionTitle)),
                if (comic.subTitle != null)
                  SelectableText(
                    comic.subTitle!,
                    style: TextStyle(fontSize: kcBody),
                  ).paddingVertical(4),
                Text(
                  (ComicSource.find(comic.sourceKey)?.name) ?? '',
                  style: TextStyle(fontSize: kcCaption),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildActions() {
    bool isMobile = context.width < changePoint;
    bool hasHistory = history != null && (history!.ep > 1 || history!.page > 1);
    return SliverLazyToBoxAdapter(
      child: Column(
        children: [
          ListView(
            scrollDirection: Axis.horizontal,
            // 12 + chip 自带 4 = 16dp，与下方主按钮、进度注脚的左右边距对齐。
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              if (hasHistory && !isMobile)
                _ActionButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedBook01, size: 18),
                  text: 'Continue'.tl,
                  onPressed: continueRead,
                  iconColor: kcBrandAdaptive(context),
                ),
              // 手机端主阅读入口已移到下方大按钮（继续/开始），这里只在桌面端放
              // Start chip；否则手机上会出现「Start」chip 与下方「Read/Continue」大按钮
              // 两个阅读入口并列，有历史时还会同时冒出「Start」和「Continue」两个。
              if (!isMobile)
                _ActionButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedPlayCircle, size: 18),
                  text: 'Start'.tl,
                  onPressed: read,
                  iconColor: kcBrandAdaptive(context),
                ),
              // 「下载」从主按钮行移到动作行：它是对章节的批量操作，和收藏 /
              // 评论 / 分享同属次级动作，不该和「继续阅读」平起平坐抢同一行宽度
              // （两个药丸等宽不等宽都会让右边缘参差，主 CTA 反而变弱）。
              // 下载中：只停用 + 转圈，不显示百分比 —— 百分比统一由下方下载卡片
              // 表达，同一个数字不在两处出现。
              if (isDownloaded)
                _ActionButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedTick01, size: 18),
                  text: "Downloaded".tl,
                  onPressed: null,
                  iconColor: context.colorScheme.onSurfaceVariant,
                )
              else
                _ActionButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 18),
                  text: 'Download'.tl,
                  onPressed: download,
                  isLoading: _downloadTask != null,
                  iconColor: kcBrandAdaptive(context),
                ),
              if (data!.isLiked != null)
                _ActionButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedThumbsUp, size: 18),
                  activeIcon: HugeIcon(icon: HugeIcons.strokeRoundedThumbsUp, size: 20),
                  isActive: isLiked,
                  text:
                      ((data!.likesCount != null)
                              ? (data!.likesCount! + (isLiked ? 1 : 0))
                              : (isLiked ? 'Liked'.tl : 'Like'.tl))
                          .toString(),
                  isLoading: isLiking,
                  onPressed: likeOrUnlike,
                  iconColor: kcBrandAdaptive(context),
                ),
              _ActionButton(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedFavourite, size: 20),
                activeIcon: Icon(Icons.favorite, size: 20, color: kcBrandAdaptive(context)),
                isActive: isFavorite || isAddToLocalFav,
                text: (isFavorite || isAddToLocalFav) ? 'Favorited'.tl : 'Favorite'.tl,
                onPressed: openFavPanel,
                onLongPressed: quickFavorite,
                iconColor: kcBrandColor,
              ),
              if (comicSource.commentsLoader != null)
                _ActionButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedComment01, size: 18),
                  text: (comic.commentCount ?? 'Comments'.tl).toString(),
                  onPressed: showComments,
                  iconColor: kcBrandAdaptive(context),
                ),
              _ActionButton(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedShare01, size: 18),
                text: 'Share'.tl,
                onPressed: share,
                iconColor: kcBrandColor,
              ),
            ],
          ).fixHeight(48),
          // 手机端只有一个阅读入口，且它和进度是同一样东西：做成一张卡，整卡
          // 命中即继续阅读。此前是「满宽实心按钮 + 下方进度注脚」，两个块各自
          // 可点、各自有形状，读起来像两个按钮在抢同一个动作。
          if (isMobile && hasHistory && history!.maxPage != null)
            _ContinueReadingCard(
              ep: _lastReadEp(),
              page: history!.page,
              maxPage: history!.maxPage!,
              onTap: continueRead,
            ).paddingHorizontal(16).paddingTop(12).paddingBottom(2)
          else if (isMobile)
            // 没有阅读历史时没有进度可合并，回到一颗满宽实心按钮。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
              child: SizedBox(
                width: double.infinity,
                child: Button.filled(
                  onPressed: read,
                  height: 52,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedPlayCircle,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text("Read".tl),
                    ],
                  ),
                ),
              ),
            ),
          // 桌面端已有「Continue」chip，不再重复大卡，只留一行进度注脚。
          if (!isMobile && hasHistory && history!.maxPage != null)
            _ReadProgressLine(
              ep: _lastReadEp(),
              page: history!.page,
              maxPage: history!.maxPage!,
              onTap: continueRead,
            ).paddingHorizontal(16).paddingTop(8).paddingBottom(6),
          if (_downloadTask != null)
            _DownloadStatusCard(
              task: _downloadTask!,
              // 卡片本身不再承载取消等破坏性动作（误触会删掉已下好的文件），
              // 点卡片进下载队列页，取消/置顶等动作在那里完成。
              onOpenQueue: () =>
                  showPopUpWidget(context, const DownloadingPage()),
            ).paddingHorizontal(16).paddingTop(8).paddingBottom(4),
          const Divider(),
        ],
      ).paddingTop(16),
    );
  }

  /// 「上次阅读」的章节文案。章节表缺失或索引越界时退回纯「上次阅读」。
  ///
  /// 拆成 prefix + name 两段返回：进度注脚可以把前缀渲染成小灰字、章节名渲染成
  /// 加粗深色字，避免整行同字重导致前缀比章名还抢眼。
  ({String? prefix, String name}) _lastReadEp() {
    final h = history;
    final chapters = comic.chapters;
    final fallback = (prefix: null, name: 'Last Reading'.tl);
    if (h == null) return fallback;
    if (chapters == null) return fallback;
    var epName = 'E${h.ep}';
    String? groupName;
    try {
      if (h.group == null) {
        epName = chapters.titles.elementAt(
          math.min(h.ep - 1, chapters.length - 1),
        );
      } else {
        groupName = chapters.groups.elementAt(h.group! - 1);
        epName = chapters.getGroupByIndex(h.group! - 1).values.elementAt(h.ep - 1);
      }
    } catch (_) {
      // 章节信息解析失败时保留兜底文案（E<n>），不影响进度展示。
    }
    if (groupName != null) {
      return (prefix: 'Last Reading'.tl, name: '$groupName $epName');
    }
    return (prefix: 'Last Reading'.tl, name: epName);
  }

  Widget buildDescription() {
    if (comic.description == null || comic.description!.trim().isEmpty) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }
    final desc = comic.description!;
    // 估算行数：超过 4 行时才提供折叠，避免短描述也显示「展开」按钮。
    final baseStyle = DefaultTextStyle.of(context).style
        .merge(const TextStyle(height: 1.5));
    final painter = TextPainter(
      text: TextSpan(text: desc, style: baseStyle),
      textDirection: TextDirection.ltr,
      maxLines: 4,
    )..layout(maxWidth: context.width - 32);
    final needFold = painter.didExceedMaxLines;
    painter.dispose();

    return SliverLazyToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KcSectionHeader(title: "Description".tl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SelectableText(
              desc,
              style: const TextStyle(height: 1.5),
              maxLines: _descExpanded || !needFold ? null : 4,
            ).fixWidth(double.infinity),
          ),
          if (needFold)
            Align(
              alignment: Alignment.centerLeft,
              child: Button.text(
                onPressed: () => setState(() => _descExpanded = !_descExpanded),
                child: Text(
                  _descExpanded ? "Collapse".tl : "Show more".tl,
                ),
              ).paddingLeft(8),
            ),
          const SizedBox(height: 16),
          const Divider(),
        ],
      ),
    );
  }

  Widget buildInfo() {
    if (comic.tags.isEmpty &&
        comic.uploader == null &&
        comic.uploadTime == null &&
        comic.updateTime == null &&
        comic.maxPage == null) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }

    Widget buildTag({
      required String text,
      VoidCallback? onTap,
      bool isTitle = false,
    }) {
      final cs = Theme.of(context).colorScheme;

      // 类目标题 chip：中性灰底，退到背景层，不与值 chip 抢色，建立「标签：值」层级
      if (isTitle) {
        final borderRadius = BorderRadius.circular(kcRadius10);
        const padding = EdgeInsets.symmetric(horizontal: 12, vertical: 8);
        final Widget titleWidget = Text(
          text,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: kcBody,
            fontWeight: FontWeight.w600,
          ),
        ).padding(padding);
        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: borderRadius,
          ),
          child: titleWidget,
        );
      }

      // 值 chip：按主题亮度/AMOLED 切换调色板，保持彩色区分（与分类页一致）
      final brightness = Theme.of(context).brightness;
      final amoled = appdata.isAmoledMode;
      // 用标签文本的稳定哈希取色：同一标签在任何页面/任何启动都是同一颜色，
      // 不再像旧版那样「按出现位置 i++ 取色」导致与卡片/分类页配色对不上。
      final bgColor =
          kcTagColor(kcStableHash(text.split(':').last), brightness, amoled: amoled);
      final textColor = kcTagTextColor(bgColor);
      final borderColor = bgColor.withValues(alpha: 0.35);

      final borderRadius = BorderRadius.circular(kcRadius10);
      const padding = EdgeInsets.symmetric(horizontal: 12, vertical: 8);

      Widget textWidget = Text(
        text,
        style: TextStyle(color: textColor, fontSize: kcBody),
      ).padding(padding);

      if (onTap != null) {
        return Material(
          color: bgColor,
          borderRadius: borderRadius,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: onTap,
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: text));
              context.showMessage(message: "Copied".tl);
            },
            onSecondaryTapDown: (details) {
              showMenuX(context, details.globalPosition, [
                MenuEntry(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedEye, size: 18),
                  text: "View".tl,
                  onClick: onTap,
                ),
                MenuEntry(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 18),
                  text: "Copy".tl,
                  onClick: () {
                    Clipboard.setData(ClipboardData(text: text));
                    context.showMessage(message: "Copied".tl);
                  },
                ),
              ]);
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: textWidget,
            ),
          ),
        );
      } else {
        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: borderRadius,
            border: Border.all(color: borderColor, width: 0.5),
          ),
          child: textWidget,
        );
      }
    }

    String formatTime(String time) {
      var t = int.tryParse(time);
      if (t != null && t > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(
          t,
        ).toString().substring(0, 19);
      }
      if (t != null) {
        return DateTime.fromMillisecondsSinceEpoch(
          t * 1000,
        ).toString().substring(0, 19);
      }
      if (time.contains('T') || time.contains('Z')) {
        var t = DateTime.parse(time);
        return t.toString().substring(0, 19);
      }
      return time;
    }

    /// 有些漫画源把站点上的「更新：2026-07-14」整段抓成了标签值本身
    /// （value 里带着开头的冒号，如 `": 2026-07-14"`、`"：2026-07-14"`）。
    /// 直接渲染就会在彩色 chip 里多出一个游离冒号，看起来像「冒号和日期
    /// 粘在一起」。这里只对显示文本剥掉开头的冒号（半角/全角）与空白，
    /// 点按事件仍用原值，避免影响源自己的 handleClickTagEvent 匹配。
    String stripTagPrefix(String v) {
      final cleaned = v.replaceFirst(RegExp(r'^\s*[:：]\s*'), '').trim();
      return cleaned.isEmpty ? v : cleaned;
    }

  Widget buildWrap({required List<Widget> children}) {
    return Wrap(
      runSpacing: 10,
      spacing: 10,
      children: children,
    ).paddingHorizontal(16).paddingBottom(8);
  }

    bool enableTranslation =
        App.locale.languageCode == 'zh' && comicSource.enableTagsTranslate;

    return SliverLazyToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KcSectionHeader(title: "Information".tl),
          if (comic.stars != null)
            Row(
              children: [
                StarRating(value: comic.stars!, size: 24, onTap: starRating),
                const SizedBox(width: 8),
                Text(comic.stars!.toStringAsFixed(2)),
              ],
            ).paddingLeft(16).paddingVertical(8),
          for (var e in comic.tags.entries)
            buildWrap(
              children: [
                if (e.value.isNotEmpty)
                  buildTag(text: e.key.ts(comicSource.key), isTitle: true),
                for (var tag in e.value)
                  buildTag(
                    text: enableTranslation
                        ? TagsTranslation.translationTagWithNamespace(
                            stripTagPrefix(tag),
                            e.key.toLowerCase(),
                          )
                        : stripTagPrefix(tag),
                    // 点按传原值：源可能按原字符串匹配跳转目标。
                    onTap: () => onTapTag(tag, e.key),
                  ),
              ],
            ),
          if (comic.uploader != null)
            buildWrap(
              children: [
                buildTag(text: 'Uploader'.tl, isTitle: true),
                buildTag(text: comic.uploader!),
              ],
            ),
          if (comic.uploadTime != null)
            buildWrap(
              children: [
                buildTag(text: 'Upload Time'.tl, isTitle: true),
                buildTag(text: stripTagPrefix(formatTime(comic.uploadTime!))),
              ],
            ),
          if (comic.updateTime != null)
            buildWrap(
              children: [
                buildTag(text: 'Update Time'.tl, isTitle: true),
                buildTag(text: stripTagPrefix(formatTime(comic.updateTime!))),
              ],
            ),
          if (comic.maxPage != null)
            buildWrap(
              children: [
                buildTag(text: 'Pages'.tl, isTitle: true),
                buildTag(text: comic.maxPage.toString()),
              ],
            ),
          const SizedBox(height: 12),
          const Divider(),
        ],
      ),
    );
  }

  Widget buildChapters() {
    if (comic.chapters == null) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }
    return _ComicChapters(
      history: history,
      groupedMode: comic.chapters!.isGrouped,
    );
  }

  Widget buildThumbnails() {
    if (comic.thumbnails == null && comicSource.loadComicThumbnail == null) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }
    return const _ComicThumbnails();
  }

  Widget buildRecommend() {
    if (comic.recommend == null || comic.recommend!.isEmpty) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: KcSectionHeader(title: "Related".tl)),
        SliverGridComics(comics: comic.recommend!),
      ],
    );
  }

  Widget buildComments() {
    if (comic.comments == null || comic.comments!.isEmpty) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }
    return _CommentsPart(comments: comic.comments!, showMore: showComments);
  }

  void _showCopyMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset(renderBox.size.width, renderBox.size.height));
    showMenuX(
      context,
      offset ?? Offset(context.width - 16, kToolbarHeight + context.padding.top),
      [
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 18),
          text: "Copy Title".tl,
          onClick: () {
            Clipboard.setData(ClipboardData(text: comic.title));
            context.showMessage(message: "Copied".tl);
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 18),
          text: "Copy ID".tl,
          onClick: () {
            Clipboard.setData(ClipboardData(text: comic.id));
            context.showMessage(message: "Copied".tl);
          },
        ),
      ],
    );
  }

  void _showCoverMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset(renderBox.size.width, renderBox.size.height));
    showMenuX(
      context,
      offset ?? Offset(context.width - 16, kToolbarHeight + context.padding.top),
      [
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: 18),
          text: "Local Image".tl,
          onClick: () => _changeCover(context),
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedBook01, size: 18),
          text: "From Comic Pages".tl,
          onClick: () {
            read(1, 1, null, true);
          },
        ),
        if (CustomCoverManager.hasCustomCover(comic.sourceKey, comic.id))
          MenuEntry(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
            text: "Restore Default Cover".tl,
            onClick: () => _restoreCover(context),
          ),
      ],
    );
  }

  void _viewCover(BuildContext context) {
    final imageProvider = CachedImageProvider(
      widget.cover ?? comic.cover,
      sourceKey: comic.sourceKey,
      cid: comic.id,
    );

    context.to(
      () => _CoverViewer(
        imageProvider: imageProvider,
        title: comic.title,
        heroTag: "cover${widget.heroID}",
      ),
    );
  }

  void _saveCover(BuildContext context) async {
    try {
      final imageProvider = CachedImageProvider(
        widget.cover ?? comic.cover,
        sourceKey: comic.sourceKey,
        cid: comic.id,
      );

      final imageStream = imageProvider.resolve(const ImageConfiguration());
      final completer = Completer<Uint8List>();

      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool _) async {
          imageStream.removeListener(listener);
          final byteData = await info.image.toByteData(
            format: ImageByteFormat.png,
          );
          if (byteData != null) {
            completer.complete(byteData.buffer.asUint8List());
          } else {
            completer.completeError("encode cover failed");
          }
        },
        onError: (e, st) {
          imageStream.removeListener(listener);
          completer.completeError(e, st);
        },
      );
      imageStream.addListener(listener);

      final data = await completer.future;
      final fileType = detectFileType(data);
      await saveFile(filename: "cover${fileType.ext}", data: data);
    } catch (e) {
      if (context.mounted) {
        context.showMessage(message: friendlyError(e));
      }
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.text,
    required this.onPressed,
    this.onLongPressed,
    this.activeIcon,
    this.isActive,
    this.isLoading,
    this.iconColor,
  });

  final Widget icon;

  final Widget? activeIcon;

  final bool? isActive;

  final String text;

  /// 传 null 即为「状态 chip」：保留外形但不可点（如整本已下载后的「已下载」）。
  final void Function()? onPressed;

  final bool? isLoading;

  final Color? iconColor;

  final void Function()? onLongPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kcRadius18),
        border: Border.all(
          color: context.colorScheme.outlineVariant,
          width: 0.6,
        ),
      ),
      child: InkWell(
        onTap: onPressed == null
            ? null
            : () {
                if (!(isLoading ?? false)) {
                  onPressed!();
                }
              },
        onLongPress: onLongPressed,
        borderRadius: BorderRadius.circular(kcRadius18),
        child: IconTheme.merge(
          data: IconThemeData(size: 20, color: iconColor),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading ?? false)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                )
              else
                (isActive ?? false) ? (activeIcon ?? icon) : icon,
              const SizedBox(width: 8),
              Text(text),
            ],
          ).paddingHorizontal(16),
        ),
      ),
    );
  }
}

class _SelectDownloadChapter extends StatefulWidget {
  const _SelectDownloadChapter(this.eps, this.finishSelect, this.downloadedEps);

  final List<String> eps;
  final void Function(List<int>) finishSelect;
  final List<int> downloadedEps;

  @override
  State<_SelectDownloadChapter> createState() => _SelectDownloadChapterState();
}

class _SelectDownloadChapterState extends State<_SelectDownloadChapter> {
  List<int> selected = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 居中浮层卡片已经铺了 surfaceContainerHigh，Scaffold 再刷默认底色会把
      // 卡片色调盖掉。
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏不再借用 Appbar：Appbar 的栏高是 `56 + context.padding.top`
          // 并且还 paddingTop(context.padding.top)，在悬浮卡片上会凭空多出一段
          // 状态栏高度的空白、把标题往下推。这里用与 ContentDialog 完全一致的
          // 轻量标题栏（柔和圆形关闭 + 标题），零系统留白。
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 16, 0),
            child: Row(
              children: [
                Button.icon(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedCancel01,
                    size: 18,
                  ),
                  color: context.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.85,
                  ),
                  onPressed: () => Navigator.maybePop(context),
                ),
                Expanded(
                  child: Text(
                    "Download".tl,
                    style: TextStyle(
                      fontSize: kcTitleLarge,
                      fontWeight: FontWeight.w700,
                      color: context.colorScheme.onSurface,
                      height: 1.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildSummary(),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: widget.eps.length,
              itemBuilder: (context, i) {
                final cs = context.colorScheme;
                final isDownloaded = widget.downloadedEps.contains(i);
                final isSelected = selected.contains(i);
                // 已下载的章不是「候选项」。旧版给它 value:true + onChanged:null，
                // 画出来是一个勾选且禁用的框 —— 和用户自己勾的那一行长得一模一样，
                // 分不清哪些是自己选的、哪些本来就有；而「下载选中」又会把已下载
                // 的排除掉，外观和行为对不上。现在已下载改成右侧文字标签。
                if (isDownloaded) {
                  return KcListTile(
                    enabled: false,
                    showDivider: false,
                    title: Text(
                      widget.eps[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedTick01,
                          size: 14,
                          color: cs.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "Downloaded".tl,
                          style: TextStyle(fontSize: kcCaption).withColor(cs.outline),
                        ),
                      ],
                    ),
                  );
                }
                return ColoredBox(
                  // 勾选行给一层极浅的主色底，长列表里一眼能看出自己勾了哪几行。
                  color: isSelected
                      ? kcAccentColor(context).withValues(alpha: 0.10)
                      : Colors.transparent,
                  child: CheckboxListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      widget.eps[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: isSelected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          selected.add(i);
                        } else {
                          selected.remove(i);
                        }
                      });
                    },
                  ),
                );
              },
            ),
          ),
          Container(
            height: 50,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: context.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Button.text(
                    onPressed: () {
                      var res = <int>[];
                      for (int i = 0; i < widget.eps.length; i++) {
                        if (!widget.downloadedEps.contains(i)) {
                          res.add(i);
                        }
                      }
                      widget.finishSelect(res);
                      context.pop();
                    },
                    child: Text(
                      "${"Download All".tl} (${widget.eps.length - widget.downloadedEps.length})",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Button.filled(
                  onPressed: () {
                    if (selected.isEmpty) return;
                    widget.finishSelect(selected);
                    context.pop();
                  },
                  color: selected.isEmpty
                      ? context.colorScheme.surfaceContainerHighest
                      : null,
                  child: Text(
                    "${"Download Selected".tl} (${selected.length})",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
          // 卡片居中悬浮、四周本就有留白，不需要再让出系统导航栏高度；
          // 原来这行会在底部凭空多出一段空白。
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 顶部计数条：勾了几章、本来有几章。列表几百行时，没有这行计数就只能靠
  /// 数勾选框知道自己选了多少，按钮上的数字也失去了对照。
  Widget _buildSummary() {
    final cs = context.colorScheme;
    final downloaded = widget.downloadedEps.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.6),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            "@n selected".tlParams({'n': "${selected.length}"}),
            style: TextStyle(fontSize: kcCaption).withColor(cs.onSurfaceVariant),
          ),
          const Spacer(),
          if (downloaded > 0)
            Text(
              "@n downloaded".tlParams({'n': "$downloaded"}),
              style: TextStyle(fontSize: kcCaption).withColor(cs.outline),
            ),
        ],
      ),
    );
  }
}

class _ComicPageLoadingPlaceHolder extends StatelessWidget {
  const _ComicPageLoadingPlaceHolder({
    this.cover,
    this.title,
    required this.sourceKey,
    required this.cid,
    this.heroID,
  });

  final String? cover;

  final String? title;

  final String sourceKey;

  final String cid;

  final int? heroID;

  @override
  Widget build(BuildContext context) {
    // 骨架屏占位块使用中性容器色（surfaceContainerHighest 本身为中性灰，不受
    // 主题色影响而偏蓝/偏紫），同时随主题/AMOLED 自动适配，避免硬编码色差。
    final neutralPlaceholder = context.colorScheme.surfaceContainerHighest;

    Widget buildContainer(
      double? width,
      double? height, {
      Color? color,
      double? radius,
    }) {
      return Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: color ?? neutralPlaceholder,
          borderRadius: BorderRadius.circular(radius ?? 4),
        ),
      );
    }

    return Shimmer(
      color: context.isDarkMode ? Colors.grey.shade600 : Colors.white,
      child: Column(
        children: [
          Appbar(
              title: Text(""),
              backgroundColor: Theme.of(context).scaffoldBackgroundColor),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 16),
              buildImage(context, neutralPlaceholder),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(title ?? "", style: TextStyle(fontSize: kcSectionTitle))
                    else
                      buildContainer(200, 25),
                    const SizedBox(height: 8),
                    buildContainer(80, 20),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (context.width < changePoint)
            // 与加载完成后的按钮布局对齐：主按钮占满剩余宽 + 下载按钮内容宽度，
            // 48dp 高、胶囊圆角。旧骨架是两条等宽 36dp 圆角 18 的灰条，加载完成
            // 后换成「宽实心 + 窄描边」会跳一下。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(child: buildContainer(null, 48, radius: kcPillRadius)),
                  const SizedBox(width: 10),
                  buildContainer(108, 48, radius: kcPillRadius),
                ],
              ),
            ),
          const Divider(),
          const SizedBox(height: 8),
          Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
            ).fixHeight(24).fixWidth(24),
          ),
        ],
      ),
    );
  }

  Widget buildImage(BuildContext context, Color placeholderColor) {
    Widget child;
    if (cover != null) {
      child = AnimatedImage(
        image: CachedImageProvider(cover!, sourceKey: sourceKey, cid: cid),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
      );
    } else {
      child = const SizedBox();
    }

    return Hero(
      tag: "cover$heroID",
      child: Container(
        decoration: BoxDecoration(
          color: placeholderColor,
          borderRadius: BorderRadius.circular(kcRadius8),
          boxShadow: [
            BoxShadow(
              color: context.colorScheme.outlineVariant,
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        height: 144,
        width: 144 * 0.72,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/// 手机端阅读入口：主按钮与阅读进度合成的一张卡。
///
/// 历史形态在这里反复摇摆过三次：① 实心胶囊进度条 + 文字压在上面；② 满宽
/// 实心按钮 + 下方独立进度卡片（播放圆钮 + 右箭头，看着像第二个按钮）；
/// ③ 满宽实心按钮 + 无形状的进度注脚（视觉干净了，但进度不可点、信息也被
/// 压成脚注）。
///
/// 现在回到「一个动作一张卡」：左侧播放圆钮是唯一的主色实心块，中间两行
/// 分别是「上次阅读: 章节名」和「阅读进度 26% · P6/19」，右侧箭头暗示可进，
/// 卡底压一条 3dp 进度线。整卡命中即继续阅读——只有一个入口，也就谈不上
/// 和谁重复。
class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({
    required this.ep,
    required this.page,
    required this.maxPage,
    required this.onTap,
  });

  final ({String? prefix, String name}) ep;
  final int page;
  final int maxPage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 与「Read」实心按钮同色：这个圆钮就是阅读入口的主色实心块，
    // 暗色下若跟着 AMOLED 的灰阶走，会掉成一颗灰点、失去主入口分量。
    final accent = kcAccentColor(context);
    final pct = (page / maxPage).clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(kcRadius16),
      child: Material(
        // 强调色轻染叠在低对比容器上：亮色走品牌红、暗色走中性灰，既有主入口的
        // 分量，又不会像整块 primaryContainer 那样把下方内容压成背景。
        color: kcAccentSurface(context, alpha: 0.10),
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 10, 0),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        // 实心三角（不是 strokeRoundedPlay 的空心描边三角）：
                        // 18dp 的空心三角在深色圆钮上只剩一圈细线，读不出「播放」。
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                if (ep.prefix != null)
                                  TextSpan(
                                    text: '${ep.prefix}: ',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                TextSpan(
                                  text: ep.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: kcBody,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            "Reading progress @progress · P@page".tlParams({
                              'progress': "${(pct * 100).round()}%",
                              'page': "$page/$maxPage",
                            }),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              // 进度/页码属「正文辅助层」，按阶梯取 12sp（原 11sp 偏小）。
                              fontSize: kcCaption,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurfaceVariant,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      size: 18,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
              // 进度线内缩 12dp 并圆头收尾，和卡片内文字左边缘对齐；不做通栏
              // 出血，否则看起来像下拉刷新的边缘指示器而不是「这一话的进度」。
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(kcPillRadius),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final full = constraints.maxWidth;
                      return Stack(
                        children: [
                          Container(
                            height: 3,
                            width: full,
                            color: cs.onSurface.withValues(alpha: 0.08),
                          ),
                          Container(
                            height: 3,
                            width: full * pct,
                            color: accent,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 详情页的「下载中」任务卡。
///
/// 旧实现是一条 11px 文字 + 通栏 4dp 进度线，线直接压在卡片下边框上：线色取
/// `tertiary`（本主题下是酱紫色）既和下载页的 `primary` 进度色撞不上，通栏使
/// 进度条看起来像卡片渲染溢出的下边框，而右侧一大片空白既没有信息也没有操作。
///
/// 现在与 [_ContinueReadingCard] 同构：40dp 前导圆钮 + 双行文字 + 右侧百分比 +
/// 内缩 3dp 细线。层级靠"描边卡片 + primaryContainer 圆钮"低一档，不抢主阅读
/// 入口。卡片整块可点 → 打开下载队列（取消/置顶等破坏性操作留在那页）。
class _DownloadStatusCard extends StatelessWidget {
  const _DownloadStatusCard({required this.task, required this.onOpenQueue});

  final DownloadTask task;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = task.progress.clamp(0.0, 1.0).toDouble();
    final failed = task.isError;
    // 只把"用户主动暂停"算暂停。排队中的任务 isPaused 也是 true（它等于
    // !_isRunning），当成暂停会显示「已暂停」，而它其实只是在队列里等。
    final paused = task.isPaused && task.pausedByUser && !failed;

    // 进度色与下载队列页对齐（primary）；失败转 error，暂停时降透明度表达
    // "停住了"，而不是换一个色系让人以为下载被取消。
    final barColor = failed
        ? cs.error
        : paused
                  ? kcAccentColor(context).withValues(alpha: 0.45)
                  : kcAccentColor(context);

    final title = failed ? 'Download failed'.tl : 'Downloading'.tl;

    // 副标题只陈述一次状态：失败给原因，暂停给状态词，正常给「图数 · 速度」。
    // task.message 在图片任务里是 "128/240"，打包阶段是 "Packaging..."。
    String? subtitle;
    if (failed) {
      final msg = task.message.trim();
      subtitle = msg.isEmpty ? null : msg;
    } else if (paused) {
      subtitle = 'Paused'.tl;
    } else {
      final parts = <String>[
        if (task.message.trim().isNotEmpty) task.message.trim(),
        if (task.speed > 0) '${bytesToReadableString(task.speed)}/s',
      ];
      subtitle = parts.isEmpty ? null : parts.join(' · ');
    }

    return Material(
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kcRadius16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        onTap: onOpenQueue,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: failed ? cs.errorContainer : cs.surfaceContainerLow,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        failed
                            ? Icons.priority_high_rounded
                            : paused
                            ? Icons.pause_rounded
                            : Icons.download_rounded,
                        size: 21,
                        color: failed
                            ? cs.onErrorContainer
                            : kcBrandAdaptive(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: kcBody,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 百分比等宽数字：进度跳动时右边缘不左右抖。
                            Text(
                              "${(pct * 100).toInt()}%",
                              style: TextStyle(
                                fontSize: kcBody,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: kcCaption,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurfaceVariant,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 只放"可逆"的暂停/继续；取消会删掉已下好的章节，不放这里。
                  _DownloadIconButton(
                    icon: failed
                        ? Icons.refresh_rounded
                        : paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    tooltip: failed
                        ? 'Resume'.tl
                        : paused
                        ? 'Resume'.tl
                        : 'Pause'.tl,
                    onPressed: () {
                      if (failed || paused) {
                        task.resume();
                      } else {
                        task.pause();
                      }
                    },
                  ),
                ],
              ),
            ),
            // 细线内缩 12dp、圆头收尾，和文字左边缘对齐；不做通栏出血，
            // 否则会和卡片下边框糊成一条。
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(kcPillRadius),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: pct),
                  duration: kcReduceMotion(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => LayoutBuilder(
                    builder: (context, constraints) {
                      final full = constraints.maxWidth;
                      return Stack(
                        children: [
                          Container(
                            height: 3,
                            width: full,
                            color: cs.onSurface.withValues(alpha: 0.08),
                          ),
                          Container(
                            height: 3,
                            width: full * value,
                            color: barColor,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡内的小图标按钮：36dp 命中区（配合整卡 40dp 圆钮不至于过密），
/// 无背景、仅 onSurfaceVariant 色，避免在卡片里再长出一颗按钮。
class _DownloadIconButton extends StatelessWidget {
  const _DownloadIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      color: context.colorScheme.onSurfaceVariant,
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      style: IconButton.styleFrom(
        foregroundColor: context.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 桌面端阅读进度注脚：章节名 + 右侧百分比 / 页码，下面压一条 3dp 细线。
///
/// 手机端已由 [_ContinueReadingCard] 承担「按钮 + 进度」二合一，这里只服务
/// 桌面端：那侧主入口是动作行里的「Continue」chip，进度只做陈述，所以去掉
/// 圆钮、边框、箭头，避免和 chip 争同一个动作。仍可点击。
class _ReadProgressLine extends StatelessWidget {
  const _ReadProgressLine({
    required this.ep,
    required this.page,
    required this.maxPage,
    required this.onTap,
  });

  final ({String? prefix, String name}) ep;
  final int page;
  final int maxPage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 与手机端 [_ContinueReadingCard] 的进度线同色，跨尺寸不跳色。
    final accent = kcAccentColor(context);
    final pct = (page / maxPage).clamp(0.0, 1.0).toDouble();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kcRadius8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (ep.prefix != null)
                          TextSpan(
                            text: '${ep.prefix} ',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        TextSpan(
                          text: ep.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: kcBody, color: cs.onSurface),
                  ),
                ),
                const SizedBox(width: 10),
                // 数字用等宽字形：翻页时百分比不会左右抖。
                Text(
                  '${(pct * 100).round()}% · P$page/$maxPage',
                  style: TextStyle(
                    fontSize: kcCaption,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(kcPillRadius),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final full = constraints.maxWidth;
                  return Stack(
                    children: [
                      Container(
                        height: 3,
                        width: full,
                        color: cs.surfaceContainerHighest,
                      ),
                      Container(
                        height: 3,
                        width: full * pct,
                        color: accent,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
