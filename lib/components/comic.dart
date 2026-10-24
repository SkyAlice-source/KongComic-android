part of 'components.dart';

/// 「已收藏」封面角标的可见范围开关。
///
/// 默认开启：发现页、搜索结果、排行/分类、详情页推荐等**浏览场景**里，
/// 角标能提醒用户「这本已经收过了」，是有效信息。
///
/// 收藏、历史、本地等**库页面**用 [FavoriteBadgeScope.disabled] 包一层
/// 把它关掉——在自家货架上给自己的书贴「已收藏」标签纯属噪音，
/// 还会在每个封面上多一个视觉焦点。角标样式与位置见
/// [ComicTileState._buildFavoriteCornerBadge]。
class FavoriteBadgeScope extends InheritedWidget {
  const FavoriteBadgeScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  /// 便捷包装：关闭角标的子树。
  static Widget disabled({Key? key, required Widget child}) =>
      FavoriteBadgeScope(key: key, enabled: false, child: child);

  /// 向上查找最近的作用域；没有作用域时视为开启（默认浏览场景）。
  ///
  /// 用 [getInheritedWidgetOfExactType] 而非 dependOn：角标开关不随
  /// 作用域变化做精准重建，页面本身的 setState 已经足够。
  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FavoriteBadgeScope>()?.enabled ??
      true;

  final bool enabled;

  @override
  bool updateShouldNotify(FavoriteBadgeScope oldWidget) =>
      oldWidget.enabled != enabled;
}

ImageProvider? _findImageProvider(Comic comic) {
  // 自定义封面优先
  final customPath = CustomCoverManager.getCustomCoverPath(
    comic.sourceKey,
    comic.id,
  );
  if (customPath != null && CustomCoverManager.coverFileExists(customPath)) {
    return FileImage(File(customPath));
  }

  ImageProvider image;
  if (comic is LocalComic) {
    image = LocalComicImageProvider(comic);
  } else if (comic is History) {
    image = HistoryImageProvider(comic);
  } else if (comic.sourceKey == 'local') {
    var localComic = LocalManager().find(comic.id, ComicType.local);
    if (localComic == null) {
      return null;
    }
    image = FileImage(localComic.coverFile);
  } else {
    image = CachedImageProvider(
      comic.cover,
      sourceKey: comic.sourceKey,
      cid: comic.id,
      fallbackToLocalCover: comic is FavoriteItem,
    );
  }
  return image;
}

/// 公开封装的封面取图入口，供需要「自绘封面缩略图」的页面使用
/// （例如追更页的紧凑行，它不能用 [ComicTile] 作 SliverList 子项）。
///
/// 解析顺序与 [ComicTile] 完全一致：自定义封面 > 本地漫画 > 历史 > 网络缓存。
ImageProvider? comicCoverImageProvider(Comic comic) =>
    _findImageProvider(comic);

/// brief 模式卡片里「封面下方标题行」的垂直开销（不含封面本身）。
///
/// 收藏书架按这条公式给每个卡槽预留高度。之前书架把卡高写死成封面高，
/// 书名叠在封面底部又被「第 X 话 · 进度」胶囊挤掉，看起来就是「名字没了、
/// 一排下面空一大截」。字号档位与 [ComicTile] 内部保持一致，行高也统一
/// 锁在 1.3，两端算出来的值才对得上。
double comicTileTitleBlock(double cardWidth, TextScaler scaler) {
  final fontSize = cardWidth < 120
      ? kcCaption
      : cardWidth < 150
      ? kcBody
      : kcFont15;
  // 上内边距 4 + 一行文字。
  return 4 + scaler.scale(fontSize) * 1.3;
}

class ComicTile extends StatelessWidget {
  const ComicTile({
    super.key,
    required this.comic,
    this.enableLongPressed = true,
    this.badge,
    this.badgeColor,
    this.menuOptions,
    this.onTap,
    this.onLongPressed,
    this.heroID,
    this.isFavorite,
    this.history,
    this.showSourceOnCover = true,
    this.showBottomSourceDate = false,
    this.badgeAsTopLeftSource = false,
    this.openLocalIfAvailable = false,
    this.showTitleAtBottom = false,
    this.displayMode,
  });

  final Comic comic;

  final bool enableLongPressed;

  final String? badge;

  /// 可选 badge 底色，按业务维度（如漫画源）区分颜色；null 时由 [_ComicDescription] 走中性色。
  final Color? badgeColor;

  final List<MenuEntry>? menuOptions;

  final VoidCallback? onTap;

  final VoidCallback? onLongPressed;

  final int? heroID;

  /// Pre-computed favorite status. When non-null, skips the
  /// `LocalFavoritesManager().isExist()` call in build().
  /// Also signals that [history] was pre-computed (even if null).
  final bool? isFavorite;

  /// Pre-computed history record. Only meaningful when [isFavorite] is non-null.
  /// A null value here means "no history record" (or history display is disabled).
  final History? history;

  /// When false, the brief-mode top-right metadata pill is hidden entirely.
  final bool showSourceOnCover;

  /// When true, the brief-mode shows source/date as a bottom pill above the
  /// history progress bar.
  final bool showBottomSourceDate;

  /// When true and [badge] is non-null, use [badge] as the top-left source
  /// pill instead of the comic subtitle (author).
  final bool badgeAsTopLeftSource;

  /// When true, tapping the tile opens the locally-downloaded copy if one
  /// exists (offline reading), otherwise falls back to the online ComicPage.
  /// Used by the favorites pages so downloaded comics can be read without network.
  final bool openLocalIfAvailable;

  /// When true, overlays the comic title as a dark gradient strip at the bottom
  /// of the cover (instead of below it). Used by the favorites "bookshelf" rows
  /// where the tile is height-constrained to the cover and there is no room for
  /// a separate title line.
  final bool showTitleAtBottom;

  /// 覆盖全局 `comicDisplayMode` 的显示模式（'brief' / 'detailed'）。
  ///
  /// 供槽位尺寸固定的调用方（收藏页货架 `_shelfBook` 等）锁定模式：detailed
  /// 的封面宽按行高算（`height * 0.68`），在窄槽位里必然横向溢出、书名被挤没。
  /// null 时跟随全局设置。
  final String? displayMode;

  void _onTap() {
    if (onTap != null) {
      onTap!();
      return;
    }
    if (openLocalIfAvailable) {
      final type = ComicType.fromKey(comic.sourceKey);
      final local = LocalManager().find(comic.id, type);
      if (local != null) {
        local.read();
        return;
      }
    }
    App.mainNavigatorKey?.currentContext?.to(
      () => ComicPage(
        id: comic.id,
        sourceKey: comic.sourceKey,
        cover: comic.cover,
        title: comic.title,
        heroID: heroID,
      ),
    );
  }

  void _onLongPressed(context) {
    if (onLongPressed != null) {
      onLongPressed!();
      return;
    }
    onLongPress(context);
  }

  void onLongPress(BuildContext context) {
    var renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;
    var location = renderBox.localToGlobal(
      Offset((size.width - 242) / 2, size.height / 2),
    );
    showMenu(location, context);
  }

  void onSecondaryTap(TapDownDetails details, BuildContext context) {
    showMenu(details.globalPosition, context);
  }

  void showMenu(Offset location, BuildContext context) {
    showMenuX(App.rootContext, location, [
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedBook01, size: 18),
        text: 'Details'.tl,
        onClick: () {
          App.mainNavigatorKey?.currentContext?.to(
            () => ComicPage(
              id: comic.id,
              sourceKey: comic.sourceKey,
              cover: comic.cover,
              title: comic.title,
            ),
          );
        },
      ),
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 18),
        text: 'Copy Title'.tl,
        onClick: () {
          Clipboard.setData(ClipboardData(text: comic.title));
          App.rootContext.showMessage(message: 'Title copied'.tl);
        },
      ),
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedFavourite, size: 18),
        text: 'Add to favorites'.tl,
        onClick: () {
          addFavorite([comic]);
        },
      ),
      MenuEntry(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
        text: 'Block'.tl,
        onClick: () => block(context),
      ),
      ...?menuOptions,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    var type = displayMode ?? appdata.settings['comicDisplayMode'];

    var isFavorite = appdata.settings['showFavoriteStatusOnTile']
        ? LocalFavoritesManager().isExist(
            comic.id,
            ComicType.fromKey(comic.sourceKey),
          )
        : false;
    var history = appdata.settings['showHistoryStatusOnTile']
        ? HistoryManager().find(comic.id, ComicType.fromKey(comic.sourceKey))
        : null;
    // Use pre-computed values when available (from SliverGridComics batch query)
    if (this.isFavorite != null) {
      isFavorite = this.isFavorite!;
      history = this.history;
    }
    // 收藏/历史/本地等库页面（FavoriteBadgeScope.disabled 包裹）不显示
    // 「已收藏」角标；阅读进度角标不受影响，历史页需要它。
    if (!FavoriteBadgeScope.of(context)) {
      isFavorite = false;
    }
    if (history?.page == 0) {
      history!.page = 1;
    }

    Widget? histBadge;
    if (history != null) {
      final hasProgress = history.maxPage != null && history.maxPage! > 0;
      final progress = hasProgress
          ? (history.page / history.maxPage!).clamp(0.0, 1.0)
          : 0.0;
      final text = hasProgress
          ? "Ep @ep·@progress%".tlParams({
              'ep': history.ep,
              'progress': (progress * 100).toInt(),
            })
          : "Ep @ep".tlParams({'ep': history.ep});
      histBadge = ClipRRect(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(kcCardInnerRadius),
          bottomRight: Radius.circular(kcCardInnerRadius),
        ),
        child: Container(
          height: 16,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
          ),
          child: Stack(
            children: [
              if (hasProgress)
                FractionallySizedBox(
                  widthFactor: progress,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    color: kcAccentColor(context).withValues(alpha: 0.70),
                  ),
                ),
              Center(
                child: Text(
                  text,
                  style: TextStyle(
                    color: Colors.white,
                    // 10sp 中文在 3x 屏上只有约 3mm 高，进度数字几乎糊成一条；
                    // 提到 11sp（徽标类下限），16dp 的条高仍放得下（11 * 1.2 = 13.2）。
                    fontSize: kcFont11,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.60),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget child = type == 'detailed'
        ? _buildDetailedMode(context, histBadge, isFavorite)
        : _buildBriefMode(context, histBadge, isFavorite);

    // 无障碍：漫画卡是核心可点元素，给 TalkBack 一个可读标签（漫画名 + 按钮角色）。
    // 否则视障用户只能听到「按钮」或整块无标签。进度胶囊信息次要，留待语义
    // 树自动合并（histBadge 内有 Text，会被并入同节点）。
    return Semantics(
      label: comic.title.replaceAll('\n', ''),
      button: true,
      child: child,
    );
  }

  Widget buildImage(BuildContext context) {
    var image = _findImageProvider(comic);
    if (image == null) {
      return const SizedBox();
    }
    // 自定义封面变化时强制重建 AnimatedImage
    final customKey = CustomCoverManager.getCustomCoverPath(
      comic.sourceKey,
      comic.id,
    );
    // Decode covers at (at most) the on-screen size * devicePixelRatio so a
    // 1200px-wide network cover doesn't get fully decoded for a ~160px grid
    // cell. This cuts per-cover RAM and decode time on the busiest screens
    // (home / favorites / search grids) and keeps scrolling smooth.
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        int? cacheWidth;
        int? cacheHeight;
        if (constraints.hasBoundedWidth && constraints.maxWidth.isFinite) {
          cacheWidth = (constraints.maxWidth * dpr).ceil().clamp(24, 512);
        }
        if (constraints.hasBoundedHeight && constraints.maxHeight.isFinite) {
          cacheHeight = (constraints.maxHeight * dpr).ceil().clamp(24, 512);
        }
        return AnimatedImage(
          key: ValueKey(customKey ?? '${comic.sourceKey}_${comic.id}'),
          image: image,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
        );
      },
    );
  }

  /// 角标 tile 边长随封面宽度线性缩放。
  ///
  /// 夹在 18–26 之间：小于 18 时白心在 3x 屏上糊成一个点；大于 26 时
  /// tile 会压进封面标题区。列表模式封面只有 60 上下，走同一个公式
  /// 也不会出现「小封面上顶着一颗大方块」。
  double _favoriteBadgeSize(double coverWidth) =>
      (coverWidth * 0.19).clamp(18.0, 26.0);

  /// 收藏角标：封面右上角悬浮的「红圆 + 白心」徽章。
  ///
  /// 点赞徽章的全球通用语法（Instagram/小红书同构）：红色承载品牌与
  /// 「已收藏」语义，白心是全站收藏入口卡同一颗心。前两版——实心
  /// 方 tile（棱角太硬）、白描边环（线状元素在花封面上发虚）——都
  /// 不如实心圆耐看：圆形没有方向性，任何封面构图下都不打架。
  /// AMOLED 下沿用入口卡的「页面级品牌标记」豁免保持品牌红。
  Widget _buildFavoriteCornerBadge(BuildContext context, double side) {
    // 距右上边缘留呼吸缝：贴边会跟封面圆角打架，悬浮一点才像徽章。
    return Padding(
      padding: EdgeInsets.only(top: side * 0.36, right: side * 0.22),
      child: Container(
        width: side,
        height: side,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: kcBrandColor,
          boxShadow: [
            // 徽章投影：把徽章从封面「抬」起来，只用黑白 alpha，
            // 不参与主题语义，不进令牌。
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(Icons.favorite, size: side * 0.54, color: kcOnAccentColor),
      ),
    );
  }

  /// Builds the source/date pill shown at the bottom of the cover in brief
  /// mode for favorites. The text is taken from [comic.description] (which
  /// favorites set to "source | date") with a fallback to the source name.
  Widget _buildBottomMetadataPill(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    String? text;
    if (comic.description.isNotEmpty) {
      text = comic.description;
    } else {
      final source = ComicSource.find(comic.sourceKey);
      text = source?.name ?? (comic.sourceKey.isEmpty ? null : comic.sourceKey);
    }
    text = text
        ?.split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join(' · ');

    // Floor the size at 11pt so the cover caption stays legible even on the
    // narrowest cards — the old 8pt floor was effectively unreadable.
    final fontSize = constraints.maxWidth < 80
        ? 11.0
        : constraints.maxWidth < 150
        ? 12.0
        : 13.0;

    if (text == null || text.isEmpty) {
      return const SizedBox();
    }

    return ClipRRect(
      borderRadius: BorderRadius.only(
        bottomLeft: Radius.circular(kcCardInnerRadius),
        bottomRight: Radius.circular(kcCardInnerRadius),
      ),
      child: Container(
        height: 16,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55)),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              height: 1.2,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.60),
                  blurRadius: 2,
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedMode(
    BuildContext context,
    Widget? histBadge,
    bool isFavorite,
  ) {
    return LayoutBuilder(
      builder: (context, constrains) {
        final height = constrains.maxHeight - 16;

        // 列表模式封面宽度 = 行高 * 0.68，角标按它取档，与网格模式同一套比例。
        final coverWidth = height * 0.68;
        final badgeSize = _favoriteBadgeSize(coverWidth);
        final favBadge = isFavorite
            ? Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(kcCardInnerRadius),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: _buildFavoriteCornerBadge(context, badgeSize),
                    ),
                  ),
                ),
              )
            : null;

        Widget image = Container(
          width: height * 0.68,
          height: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(kcCardInnerRadius),
            boxShadow: [
              BoxShadow(
                color: context.colorScheme.outlineVariant,
                blurRadius: 1,
                offset: const Offset(0, 1),
              ),
              ...kcContourGlow(context),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: buildImage(context),
        );

        if (histBadge != null || favBadge != null) {
          image = SizedBox(
            width: height * 0.68,
            child: Stack(
              children: [
                Positioned.fill(child: image),
                if (favBadge != null) favBadge,
                if (histBadge != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 16,
                    child: histBadge,
                  ),
              ],
            ),
          );
        }

        if (heroID != null) {
          image = Hero(tag: "cover$heroID", child: image);
        }

        return InkWell(
          borderRadius: BorderRadius.circular(kcCardRadius),
          onTap: _onTap,
          onLongPress: enableLongPressed ? () => _onLongPressed(context) : null,
          onSecondaryTapDown: (detail) => onSecondaryTap(detail, context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 24, 8),
            child: Row(
              children: [
                image,
                SizedBox.fromSize(size: const Size(16, 5)),
                Expanded(
                  child: _ComicDescription(
                    title: comic.maxPage == null
                        ? comic.title.replaceAll("\n", "")
                        : "[${comic.maxPage}P]${comic.title.replaceAll("\n", "")}",
                    subtitle: comic.subtitle ?? '',
                    description: comic.description,
                    badge: badge ?? comic.language,
                    badgeColor: badgeColor,
                    tags: comic.tags,
                    maxLines: 2,
                    enableTranslate:
                        ComicSource.find(
                          comic.sourceKey,
                        )?.enableTagsTranslate ??
                        false,
                    rating: comic.stars,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBriefMode(
    BuildContext context,
    Widget? histBadge,
    bool isFavorite,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 折角随封面宽度缩放（网格卡座的 padding 左右各 6，实际封面更窄，
        // 但同一档位下的比例关系不变，没必要在这里再减）。
        final badgeSize = _favoriteBadgeSize(constraints.maxWidth);
        // 网格卡宽决定标题字号：三列窄卡（~137dp）用 15sp 中文只放得下 6 个字，
        // 几乎每条都被截；降到正文档后同一屏能读全更多标题。
        final titleFont = constraints.maxWidth < 120
            ? kcCaption
            : constraints.maxWidth < 150
            ? kcBody
            : kcFont15;
        final favBadge = isFavorite
            ? Positioned.fill(
                // 角标要「长在」封面上：按封面同款圆角裁一刀，折角的尖
                // 因此被吃掉一点，看起来是沿着圆角包过去的，而不是贴在
                // 直角边上。整层铺满封面但只画右上角那一块。
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(kcCardInnerRadius),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: _buildFavoriteCornerBadge(context, badgeSize),
                    ),
                  ),
                ),
              )
            : null;

        Widget image = Container(
          decoration: BoxDecoration(
            color: context.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(kcCardInnerRadius),
            boxShadow: [kcCardShadow(context), ...kcContourGlow(context)],
          ),
          clipBehavior: Clip.antiAlias,
          child: buildImage(context),
        );

        if (heroID != null) {
          image = Hero(tag: "cover$heroID", child: image);
        }

        return InkWell(
          borderRadius: BorderRadius.circular(kcCardRadius),
          onTap: _onTap,
          onLongPress: enableLongPressed ? () => _onLongPressed(context) : null,
          onSecondaryTapDown: (detail) => onSecondaryTap(detail, context),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: image),
                    Align(
                      alignment: Alignment.topLeft,
                      child: (() {
                        String? text;
                        if (badgeAsTopLeftSource &&
                            badge != null &&
                            badge!.isNotEmpty) {
                          text = badge;
                        } else {
                          text = comic.subtitle?.replaceAll('\n', '').trim();
                        }
                        if (text == null || text.isEmpty) {
                          return const SizedBox();
                        }
                        final fontSize = constraints.maxWidth < 80
                            ? 8.0
                            : constraints.maxWidth < 150
                            ? 10.0
                            : 12.0;
                        return Container(
                          margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
                          padding: constraints.maxWidth < 80
                              ? const EdgeInsets.fromLTRB(3, 1, 3, 1)
                              : constraints.maxWidth < 150
                              ? const EdgeInsets.fromLTRB(4, 2, 4, 2)
                              : const EdgeInsets.fromLTRB(5, 2, 5, 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(kcRadius8),
                            color: Colors.black.withValues(alpha: 0.5),
                          ),
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.62,
                          ),
                          child: Text(
                            text,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: fontSize,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      })(),
                    ),
                    Align(
                      alignment: Alignment.topRight,
                      child: (() {
                        // Pages like Discover want a clean cover and never show
                        // the top-right metadata pill.
                        if (!showSourceOnCover) {
                          return const SizedBox();
                        }
                        // When a history progress pill is already shown at the
                        // bottom AND the cover's description badge repeats the
                        // same chapter/page info, skip it to avoid clutter.
                        // Favorites use the same area for source/date metadata,
                        // which is not duplicated by the history pill, so keep it.
                        // Note: history pages pass History.toComic() (a Comic),
                        // so `comic is History` does not work; use history.
                        if (history != null) {
                          final desc = comic.description.toLowerCase();
                          final isChapterLike =
                              desc.contains('第') ||
                              desc.contains('话') ||
                              desc.contains('章') ||
                              desc.contains('页') ||
                              desc.contains('%');
                          if (isChapterLike) {
                            return const SizedBox();
                          }
                        }
                        // Unify the chapter/page, source/date, or other metadata
                        // into a single right-aligned pill so it never stacks into
                        // multiple floating badges and covers the cover.
                        // If no metadata is available, show the comic source so
                        // favorites/grid views always expose where the comic is
                        // from.
                        String? text;
                        if (comic.description.isNotEmpty) {
                          text = comic.description;
                        } else {
                          final source = ComicSource.find(comic.sourceKey);
                          text =
                              source?.name ??
                              (comic.sourceKey.isEmpty
                                  ? null
                                  : comic.sourceKey);
                        }
                        text = text
                            ?.split('|')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .join(' · ');

                        final fortSize = constraints.maxWidth < 80
                            ? 8.0
                            : constraints.maxWidth < 150
                            ? 10.0
                            : 12.0;

                        if (text == null || text.isEmpty) {
                          return const SizedBox();
                        }

                        return Padding(
                          // 让位高度跟折角尺寸走：折角占 badgeSize 见方，
                          // 再留 2px 呼吸，右上角的信息条不会被斜边切到。
                          padding: EdgeInsets.only(
                            top: isFavorite ? badgeSize + 2 : 0,
                          ),
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
                            padding: constraints.maxWidth < 80
                                ? const EdgeInsets.fromLTRB(3, 1, 3, 1)
                                : constraints.maxWidth < 150
                                ? const EdgeInsets.fromLTRB(4, 2, 4, 2)
                                : const EdgeInsets.fromLTRB(5, 2, 5, 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(kcRadius8),
                              color: Colors.black.withValues(alpha: 0.5),
                            ),
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth,
                            ),
                            child: Text(
                              text,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: fortSize,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      })(),
                    ),
                    // 底部叠漫画名的渐变条必须贴底（bottom:0）且渲染在进度条
                    // 之前（下层）：整体上移会露出一条无渐变的封面底边，形成
                    // 「名字黑条悬浮」的割裂感（用户反馈）。文字让位改为在渐变
                    // 内部加 padding-bottom，进度条则叠在渐变上层。
                    if (showTitleAtBottom)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: EdgeInsets.fromLTRB(
                            6,
                            12,
                            6,
                            histBadge != null ? 18.0 : 4.0,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.72),
                                Colors.transparent,
                              ],
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(kcCardInnerRadius),
                              bottomRight: Radius.circular(kcCardInnerRadius),
                            ),
                          ),
                          child: Text(
                            comic.title.replaceAll('\n', ''),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: titleFont,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              shadows: const [
                                // 封面底部渐变上叠白字的投影：35% 黑 scrim，
                                // 语义同上（可读性投影，非主题色）。
                                Shadow(color: Color(0x59000000), blurRadius: 2),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (histBadge != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 16,
                        child: histBadge,
                      ),
                    if (favBadge != null) favBadge,
                    if (showBottomSourceDate)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: histBadge != null ? 16 : 0,
                        height: 16,
                        child: _buildBottomMetadataPill(context, constraints),
                      ),
                  ],
                ),
              ),
              if (!showTitleAtBottom)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Text(
                    comic.title.replaceAll('\n', ''),
                    maxLines: 1,
                    // clip 会把字从中间劈开（「美奈酱与千寻姊」截在笔画上），
                    // 窄卡更常见；改省略号，截断位置看起来是排版而非故障。
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: titleFont,
                      // 行高锁定：卡槽高度按 [comicTileTitleBlock] 算，
                      // 靠字体默认 metrics 会随系统字体/Sans fallback 漂移，
                      // 高度对不上时多出来的部分就是一整条空白。
                      height: 1.3,
                    ),
                  ),
                ),
            ],
          ).paddingHorizontal(6).paddingVertical(8),
        );
      },
    );
  }

  List<String> _splitText(String text) {
    // split text by comma, brackets
    var words = <String>[];
    var buffer = StringBuffer();
    var inBracket = false;
    String? prevBracket;
    for (var i = 0; i < text.length; i++) {
      var c = text[i];
      if (c == '[' || c == '(') {
        if (inBracket) {
          buffer.write(c);
        } else {
          if (buffer.isNotEmpty) {
            words.add(buffer.toString().trim());
            buffer.clear();
          }
          inBracket = true;
          prevBracket = c;
        }
      } else if (c == ']' || c == ')') {
        if (prevBracket == '[' && c == ']' || prevBracket == '(' && c == ')') {
          if (buffer.isNotEmpty) {
            words.add(buffer.toString().trim());
            buffer.clear();
          }
          inBracket = false;
        } else {
          buffer.write(c);
        }
      } else if (c == ',') {
        if (inBracket) {
          buffer.write(c);
        } else {
          words.add(buffer.toString().trim());
          buffer.clear();
        }
      } else {
        buffer.write(c);
      }
    }
    if (buffer.isNotEmpty) {
      words.add(buffer.toString().trim());
    }
    words.removeWhere((element) => element == "");
    words = words.toSet().toList();
    return words;
  }

  void block(BuildContext comicTileContext) {
    showDialog(
      context: App.rootContext,
      builder: (context) {
        var words = <String>[];
        var all = <String>[];
        all.addAll(_splitText(comic.title));
        if (comic.subtitle != null && comic.subtitle != "") {
          all.add(comic.subtitle!);
        }
        all.addAll(comic.tags ?? []);
        return StatefulBuilder(
          builder: (context, setState) {
            return ContentDialog(
              title: 'Block'.tl,
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.min(400, context.height - 136),
                ),
                child: SingleChildScrollView(
                  child: Wrap(
                    runSpacing: 8,
                    spacing: 8,
                    children: [
                      for (var word in all)
                        OptionChip(
                          text: (comic.tags?.contains(word) ?? false)
                              ? word.translateTagIfNeed
                              : word,
                          isSelected: words.contains(word),
                          onTap: () {
                            setState(() {
                              if (!words.contains(word)) {
                                words.add(word);
                              } else {
                                words.remove(word);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ).paddingHorizontal(16),
              ),
              actions: [
                Button.filled(
                  onPressed: () {
                    context.pop();
                    for (var word in words) {
                      appdata.settings['blockedWords'].add(word);
                    }
                    appdata.saveData();
                    context.showMessage(message: 'Blocked'.tl);
                    comicTileContext
                        .findAncestorStateOfType<_SliverGridComicsState>()
                        ?.update();
                  },
                  child: Text('Block'.tl),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ComicDescription extends StatelessWidget {
  const _ComicDescription({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.enableTranslate,
    this.badge,
    this.badgeColor,
    this.maxLines = 2,
    this.tags,
    this.rating,
  });

  final String title;
  final String subtitle;
  final String description;
  final String? badge;
  final Color? badgeColor;
  final List<String>? tags;
  final int maxLines;
  final bool enableTranslate;
  final double? rating;

  @override
  Widget build(BuildContext context) {
    // Create a new filtered list instead of mutating the original.
    final processedTags = tags
        ?.where((element) => element.removeAllBlank != "")
        .map((s) => s.replaceAll("\n", " "))
        .toList();
    var enableTranslate =
        App.locale.languageCode == 'zh' && this.enableTranslate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title.trim(),
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: kcBody),
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
        ),
        if (subtitle != "")
          Text(
            subtitle,
            style: TextStyle(
              fontSize: kcCaption,
              color: context.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            maxLines: 1,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 4),
        if (processedTags != null && processedTags.isNotEmpty)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 一行的实际高度 = 标签 21 + 行间距 8 = 29。高度只按「能完整放下的
                // 行数」给，多出来的空间留白 —— 以前用 21 + cnt * 25 估算（把
                // runSpacing 当成 4），容器比内容矮 4px/行，于是最后一行总是被
                // 裁掉一截：标题折成两行、可用高度变小的时候，第二排标签的底部
                // 就缺一块。宁可少显示一行，也不要显示半截。
                const double tagHeight = 21;
                const double tagRunSpacing = 8;
                final rows =
                    ((constraints.maxHeight + tagRunSpacing) /
                            (tagHeight + tagRunSpacing))
                        .floor();
                if (rows <= 0) {
                  return Container();
                }
                return Container(
                  clipBehavior: Clip.antiAlias,
                  height: rows * tagHeight + (rows - 1) * tagRunSpacing,
                  width: double.infinity,
                  decoration: const BoxDecoration(),
                  child: Wrap(
                    runAlignment: WrapAlignment.start,
                    clipBehavior: Clip.antiAlias,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 8,
                    runSpacing: tagRunSpacing,
                    children: [
                      for (var s in processedTags)
                        Builder(
                          builder: (context) {
                            final brightness = Theme.of(context).brightness;
                            final amoled = appdata.isAmoledMode;
                            final bg = s == "Unavailable"
                                ? context.colorScheme.surfaceContainerHighest
                                : kcTagColor(
                                    kcStableHash(s.split(':').last),
                                    brightness,
                                    amoled: amoled,
                                  );
                            return Container(
                              height: tagHeight,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth * 0.45,
                              ),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(kcRadius10),
                              ),
                              child: Center(
                                widthFactor: 1,
                                child: Text(
                                  enableTranslate
                                      ? TagsTranslation.translateTag(s)
                                      : s.split(':').last,
                                  style: TextStyle(
                                    fontSize: kcCaption,
                                    color: s == "Unavailable"
                                        ? context.colorScheme.onSurfaceVariant
                                        : kcTagTextColor(bg),
                                  ),
                                  softWrap: true,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ).toAlign(Alignment.topCenter);
              },
            ),
          )
        else
          const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (rating != null) StarRating(value: rating!, size: 18),
                  Text(
                    description,
                    style: const TextStyle(fontSize: kcCaption),
                    maxLines: (tags == null || tags!.isEmpty) ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (badge != null)
              AppBadge(
                "${badge![0].toUpperCase()}${badge!.substring(1).toLowerCase()}",
                type: AppBadgeType.neutral,
                backgroundColor: badgeColor,
                fontSize: kcCaption,
              ),
          ],
        ),
      ],
    );
  }
}

class SliverGridComics extends StatefulWidget {
  const SliverGridComics({
    super.key,
    required this.comics,
    this.onLastItemBuild,
    this.badgeBuilder,
    this.menuBuilder,
    this.onTap,
    this.onLongPressed,
    this.selections,
    this.allFavorite = false,
    this.showSourceOnCover = true,
    this.showBottomSourceDate = false,
    this.badgeAsTopLeftSource = false,
    this.openLocalIfAvailable = false,
  });

  final List<Comic> comics;

  /// favorites folders where all listed comics are already in a favorite
  /// folder). Skips the LocalFavoritesManager lookup.
  final bool allFavorite;

  /// When false, the brief-mode top-right metadata pill is hidden entirely.
  final bool showSourceOnCover;

  /// When true, the brief-mode shows source/date as a bottom pill above the
  /// history progress bar.
  final bool showBottomSourceDate;

  /// When true and [badgeBuilder] returns non-null, use that badge as the
  /// top-left source pill instead of the comic subtitle (author).
  final bool badgeAsTopLeftSource;

  /// When true, tap opens a locally-downloaded copy if available (offline).
  final bool openLocalIfAvailable;

  final Map<Comic, bool>? selections;

  final void Function()? onLastItemBuild;

  final String? Function(Comic)? badgeBuilder;

  final List<MenuEntry> Function(Comic)? menuBuilder;

  final void Function(Comic, int heroID)? onTap;

  final void Function(Comic, int heroID)? onLongPressed;

  @override
  State<SliverGridComics> createState() => _SliverGridComicsState();
}

class _SliverGridComicsState extends State<SliverGridComics>
    with AutoListenMixin {
  List<Comic> comics = [];
  List<int> heroIDs = [];

  /// Pre-computed favorite status, keyed by comic.id.
  /// Populated by [_precomputeStatus] to avoid per-tile DB lookups in build().
  Map<String, bool> _favoriteStatus = {};

  /// Pre-computed history records, keyed by comic.id.
  /// Populated by [_precomputeStatus] via a single batch SQL query.
  Map<String, History> _historyStatus = {};

  static int _nextHeroID = 0;

  void generateHeroID() {
    heroIDs.clear();
    for (var i = 0; i < comics.length; i++) {
      heroIDs.add(_nextHeroID++);
    }
  }

  /// Batch pre-compute favorite and history status for all visible comics.
  /// Replaces N individual isExist()/find() calls with O(1) HashMap lookups
  /// and a single batch SQL query.
  void _precomputeStatus() {
    _favoriteStatus = {};
    _historyStatus = {};
    if (comics.isEmpty) return;

    bool showFavorite = appdata.settings['showFavoriteStatusOnTile'] == true;
    bool showHistory = appdata.settings['showHistoryStatusOnTile'] == true;

    if (showFavorite) {
      for (var comic in comics) {
        _favoriteStatus[comic.id] =
            widget.allFavorite ||
            LocalFavoritesManager().isExist(
              comic.id,
              ComicType.fromKey(comic.sourceKey),
            );
      }
    }

    if (showHistory) {
      _historyStatus = HistoryManager().findBatch(comics.map((c) => c.id));
    }
  }

  @override
  void didUpdateWidget(covariant SliverGridComics oldWidget) {
    if (!comics.isEqualTo(widget.comics)) {
      comics.clear();
      for (var comic in widget.comics) {
        if (isBlocked(comic) == null) {
          comics.add(comic);
        }
      }
      generateHeroID();
      _precomputeStatus();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void initState() {
    for (var comic in widget.comics) {
      if (isBlocked(comic) == null) {
        comics.add(comic);
      }
    }
    generateHeroID();
    _precomputeStatus();
    listen(HistoryManager(), update);
    listen(LocalFavoritesManager(), update);
    super.initState();
  }

  void update() {
    setState(() {
      comics.clear();
      for (var comic in widget.comics) {
        if (isBlocked(comic) == null) {
          comics.add(comic);
        }
      }
      _precomputeStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SliverGridComics(
      comics: comics,
      heroIDs: heroIDs,
      selection: widget.selections,
      onLastItemBuild: widget.onLastItemBuild,
      badgeBuilder: widget.badgeBuilder,
      menuBuilder: widget.menuBuilder,
      onTap: widget.onTap,
      onLongPressed: widget.onLongPressed,
      favoriteStatus: _favoriteStatus,
      historyStatus: _historyStatus,
      allFavorite: widget.allFavorite,
      showSourceOnCover: widget.showSourceOnCover,
      showBottomSourceDate: widget.showBottomSourceDate,
      badgeAsTopLeftSource: widget.badgeAsTopLeftSource,
      openLocalIfAvailable: widget.openLocalIfAvailable,
    );
  }
}

class _SliverGridComics extends StatelessWidget {
  const _SliverGridComics({
    required this.comics,
    required this.heroIDs,
    this.onLastItemBuild,
    this.badgeBuilder,
    this.menuBuilder,
    this.onTap,
    this.onLongPressed,
    this.selection,
    this.favoriteStatus,
    this.historyStatus,
    this.allFavorite = false,
    this.showSourceOnCover = true,
    this.showBottomSourceDate = false,
    this.badgeAsTopLeftSource = false,
    this.openLocalIfAvailable = false,
  });

  final List<Comic> comics;

  final List<int> heroIDs;

  final Map<Comic, bool>? selection;

  final void Function()? onLastItemBuild;

  final String? Function(Comic)? badgeBuilder;

  final List<MenuEntry> Function(Comic)? menuBuilder;

  final void Function(Comic, int heroID)? onTap;

  final void Function(Comic, int heroID)? onLongPressed;

  final Map<String, bool>? favoriteStatus;

  final Map<String, History>? historyStatus;

  final bool allFavorite;

  final bool showSourceOnCover;

  final bool showBottomSourceDate;

  final bool badgeAsTopLeftSource;

  final bool openLocalIfAvailable;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appdata.settings,
      builder: (context, _) => SliverGrid(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index == comics.length - 1) {
            onLastItemBuild?.call();
          }
          var badge = badgeBuilder?.call(comics[index]);
          var isSelected = selection == null
              ? false
              : selection![comics[index]] ?? false;
          var comic = ComicTile(
            comic: comics[index],
            badge: badge,
            menuOptions: menuBuilder?.call(comics[index]),
            onTap: onTap != null
                ? () => onTap!(comics[index], heroIDs[index])
                : null,
            onLongPressed: onLongPressed != null
                ? () => onLongPressed!(comics[index], heroIDs[index])
                : null,
            heroID: heroIDs[index],
            isFavorite: favoriteStatus?[comics[index].id],
            history: historyStatus?[comics[index].id],
            showSourceOnCover: showSourceOnCover,
            showBottomSourceDate: showBottomSourceDate,
            badgeAsTopLeftSource: badgeAsTopLeftSource,
            openLocalIfAvailable: openLocalIfAvailable,
          );
          if (selection == null) {
            return RepaintBoundary(child: comic);
          }
          return AnimatedContainer(
            key: ValueKey(comics[index].id),
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(
                      context,
                    ).colorScheme.secondaryContainer.withValues(alpha: 0.72)
                  : null,
              borderRadius: BorderRadius.circular(kcCardRadius),
            ),
            margin: const EdgeInsets.all(kcSpaceXs),
            child: RepaintBoundary(child: comic),
          );
        }, childCount: comics.length),
        gridDelegate: SliverGridDelegateWithComics(),
      ),
    );
  }
}

/// return the first blocked keyword, or null if not blocked
String? isBlocked(Comic item) {
  for (var word in appdata.settings['blockedWords']) {
    if (item.title.contains(word)) {
      return word;
    }
    if (item.subtitle?.contains(word) ?? false) {
      return word;
    }
    if (item.description.contains(word)) {
      return word;
    }
    for (var tag in item.tags ?? <String>[]) {
      if (tag == word) {
        return word;
      }
      if (tag.contains(':')) {
        tag = tag.split(':')[1];
        if (tag == word) {
          return word;
        }
      }
    }
  }
  return null;
}

/// 网格首屏骨架屏（shimmer），替换裸 spinner，长网格等待不再显空。
class _ComicGridSkeleton extends StatelessWidget {
  const _ComicGridSkeleton();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    // 与 SliverGridDelegateWithComics 列数估算接近，占位与真实网格同尺寸
    final crossAxisCount = (w / 150).floor().clamp(2, 6);
    // 弱网时骨架屏也会挂十秒，叠一层慢网络提示，让用户知道不是在卡死。
    return SlowLoadingOverlay(
      child: GridView.count(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.7,
        padding: const EdgeInsets.all(kcSpaceMd),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: List.generate(12, (_) => const _ShimmerCard()),
      ),
    );
  }
}

class _ShimmerCard extends StatefulWidget {
  const _ShimmerCard();

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1.0).animate(_controller),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(kcCardInnerRadius),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 10,
            width: double.infinity,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(kcRadius4),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class ComicList extends StatefulWidget {
  const ComicList({
    super.key,
    this.loadPage,
    this.loadNext,
    this.leadingSliver,
    this.trailingSliver,
    this.errorLeading,
    this.menuBuilder,
    this.controller,
    this.refreshHandlerCallback,
    this.enablePageStorage = false,
    this.allFavorite = false,
    this.showSourceOnCover = true,
    this.showBottomSourceDate = false,
    this.badgeAsTopLeftSource = false,
    this.openLocalIfAvailable = false,
  });

  final Future<Res<List<Comic>>> Function(int page)? loadPage;

  final Future<Res<List<Comic>>> Function(String? next)? loadNext;

  final Widget? leadingSliver;

  final Widget? trailingSliver;

  final Widget? errorLeading;

  final List<MenuEntry> Function(Comic)? menuBuilder;

  final ScrollController? controller;

  final void Function(VoidCallback c)? refreshHandlerCallback;

  final bool enablePageStorage;

  /// When true, every comic is treated as favorited (used by network
  /// favorites folders). Skips the LocalFavoritesManager lookup.
  final bool allFavorite;

  /// When false, the brief-mode top-right metadata pill is hidden entirely.
  final bool showSourceOnCover;

  /// When true, the brief-mode shows source/date as a bottom pill above the
  /// history progress bar.
  final bool showBottomSourceDate;

  /// When true and [badgeBuilder] returns non-null, use that badge as the
  /// top-left source pill instead of the comic subtitle (author).
  final bool badgeAsTopLeftSource;

  /// When true, tap opens a locally-downloaded copy if available (offline).
  final bool openLocalIfAvailable;

  @override
  State<ComicList> createState() => ComicListState();
}

class ComicListState extends State<ComicList> {
  int? _maxPage;

  final Map<int, List<Comic>> _data = {};

  int _page = 1;

  String? _error;

  final Map<int, bool> _loading = {};

  String? _nextUrl;

  late bool enablePageStorage = widget.enablePageStorage;

  Map<String, dynamic> get state => {
    'maxPage': _maxPage,
    'data': _data,
    'page': _page,
    'error': _error,
    'loading': _loading,
    'nextUrl': _nextUrl,
  };

  void restoreState(Map<String, dynamic>? state) {
    if (state == null || !enablePageStorage) {
      return;
    }
    _maxPage = state['maxPage'];
    _data.clear();
    _data.addAll(state['data']);
    _page = state['page'];
    _error = state['error'];
    _loading.clear();
    _loading.addAll(state['loading']);
    _nextUrl = state['nextUrl'];
  }

  void storeState() {
    if (enablePageStorage) {
      PageStorage.of(context).writeState(context, state);
    }
  }

  void refresh() {
    _data.clear();
    _page = 1;
    _maxPage = null;
    _error = null;
    _nextUrl = null;
    _loading.clear();
    storeState();
    setState(() {});
  }

  /// 下拉刷新（`RefreshIndicator.onRefresh`）回调。
  ///
  /// 与 [refresh] 的区别：本方法返回「首页加载完成」的 Future，让下拉刷新的
  /// 转圈能正确等到首屏数据回来再收起；[refresh] 是同步清空，供外部按钮 /
  /// 数据变更即时触发、由 build 里的 `_loadPage` 重新拉取。
  ///
  /// 清空后立刻 `await _loadPage(1)`：`setState` 只标记脏、不会同步重建，
  /// 所以这一句的 `_loadPage(1)` 先跑、置上 `_loading[1]=true`；随后重建时
  /// build 里再调 `_loadPage(1)` 会被守卫挡掉，不会双拉。
  Future<void> _handleRefresh() async {
    if (widget.loadPage == null && widget.loadNext == null) return;
    _maxPage = null;
    _data.clear();
    _loading.clear();
    _error = null;
    _nextUrl = null;
    _page = 1;
    storeState();
    setState(() {});
    await _loadPage(1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    restoreState(PageStorage.of(context).readState(context));
    widget.refreshHandlerCallback?.call(refresh);
  }

  void remove(Comic c) {
    if (_data[_page] == null || !_data[_page]!.remove(c)) {
      for (var page in _data.values) {
        if (page.remove(c)) {
          break;
        }
      }
    }
    setState(() {});
  }

  /// 分页条：`‹  12 / 90 ⌄  ›` 三段式胶囊，居中。
  ///
  /// 老实现是「84dp 后退按钮 + 页码胶囊 + 84dp 前进按钮」占满一整行，两端固定
  /// 宽度把中间挤成一条缝；跳转还要走「点胶囊 → 弹窗 → 键盘 → 输入 → 确认」。
  /// 现在收成一颗胶囊：两侧箭头翻页，中间页码区点开页码网格，一次点击直达。
  ///
  /// 箭头统一用中性色而不是「前进=品牌红实心」：分页条在列表顶部和底部各出现
  /// 一次，两颗红按钮同屏太吵，而且它只是导航而不是主 CTA。
  Widget _buildPageSelector() {
    final maxPage = _maxPage;
    // 取数期间在页码后面挂个小转圈，替代原来「整条消失 → 骨架屏」的跳变。
    final loading = _data[_page] == null && _error == null;
    return Center(
      child: ToolsPill(
        height: 38,
        children: [
          ToolsPillButton(
            icon: HugeIcons.strokeRoundedArrowLeft01,
            tooltip: "Previous page".tl,
            onPressed: _page > 1 ? () => _goToPage(_page - 1) : null,
          ),
          _buildPageLabel(loading: loading),
          ToolsPillButton(
            icon: HugeIcons.strokeRoundedArrowRight01,
            tooltip: "Next page".tl,
            onPressed: maxPage == null || _page < maxPage
                ? () => _goToPage(_page + 1)
                : null,
          ),
        ],
      ),
    ).paddingVertical(8).paddingHorizontal(16);
  }

  Widget _buildPageLabel({required bool loading}) {
    final cs = Theme.of(context).colorScheme;
    final maxPage = _maxPage;
    return InkWell(
      borderRadius: BorderRadius.circular(kcPillRadius),
      onTap: _showPagePicker,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Page @page / @maxPage".tlParams({
                "page": _page,
                "maxPage": maxPage ?? '?',
              }),
              style: TextStyle(
                fontSize: kcBody,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
                // 等宽数字：「1 / 90」翻到「2 / 90」时胶囊不会左右抖一下。
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            if (loading)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: cs.onSurfaceVariant,
                ),
              )
            else
              HugeIcon(
                icon: HugeIcons.strokeRoundedArrowDown01,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }

  /// 跳到 [page] 并清掉错误态。
  ///
  /// 滚动位置不用手动复位：滚动视图挂着 `PageStorageKey('scroll$_page')`，
  /// key 一变整棵子树重建，新页面自然从顶部开始，不会停在上一页的半山腰。
  void _goToPage(int page) {
    final maxPage = _maxPage;
    if (page < 1 || (maxPage != null && page > maxPage) || page == _page) {
      return;
    }
    setState(() {
      _error = null;
      _page = page;
    });
    storeState();
  }

  Future<void> _showPagePicker() async {
    final maxPage = _maxPage;
    // 只有一页时列出来没有意义（错误态下顶部分页条仍会渲染）。
    if (maxPage != null && maxPage < 2) return;
    final picked = maxPage == null
        ? await _showPageInputDialog()
        : await showDialog<int>(
            context: App.rootContext,
            builder: (_) => _PagePickerDialog(current: _page, maxPage: maxPage),
          );
    if (picked != null && mounted) {
      _goToPage(picked);
    }
  }

  /// 源没上报总页数时的兜底：只能输入，不猜。
  Future<int?> _showPageInputDialog() async {
    final controller = TextEditingController(text: "$_page");
    try {
      return await showDialog<int>(
        context: App.rootContext,
        builder: (context) {
          void submit() {
            final page = int.tryParse(controller.text);
            if (page == null || page < 1) {
              // 保持弹窗开着让用户改，而不是关掉再从头点一遍。
              context.showMessage(message: "Invalid page".tl);
              return;
            }
            Navigator.of(context).pop(page);
          }

          return ContentDialog(
            title: "Jump to page".tl,
            headerIcon: HugeIcons.strokeRoundedGrid02,
            showClose: false,
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: "Page".tl),
              onSubmitted: (_) => submit(),
            ).paddingHorizontal(16),
            actions: [Button.filled(onPressed: submit, child: Text("Jump".tl))],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  /// 钉在屏幕底部的分页栏。
  ///
  /// 翻页是这一屏唯一的导航动作，也是最需要「按一下」的动作。放在列表顶部
  /// 意味着大屏单手要换手；钉在底部后，拇指原地就能翻，顺带省掉了「滚到底
  /// 才有下一页」的来回。分页条因此只保留这一条，顶部那条已删除。
  Widget _buildPageBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant, width: kcHairline),
        ),
      ),
      // 手势条 / 三键栏占的高度，避免分页条被系统条压住。
      padding: EdgeInsets.only(bottom: context.padding.bottom),
      child: _buildPageSelector(),
    );
  }

  /// 预取下一页。
  ///
  /// 分类页一页要等一次完整的网络往返，老实现点「下一页」必闪一次骨架屏。当前
  /// 页渲染完再悄悄把下一页取下来，翻页基本瞬时。失败保持静默：不写 [_error]，
  /// 用户真翻过去时走正常加载，该提示的错误一条不少。
  void _prefetch(int page) {
    // 总页数未知时不预取：把返回的空页错记成总页数，分页条会凭空多出一页。
    final maxPage = _maxPage;
    if (maxPage == null || page > maxPage) return;
    if (_data[page] != null || _loading[page] == true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final maxPage = _maxPage;
      if (maxPage == null || page > maxPage) return;
      if (_data[page] != null || _loading[page] == true) return;
      _loadPage(page, silent: true);
    });
  }

  Future<void> _loadPage(int page, {bool silent = false}) async {
    if (widget.loadPage == null && widget.loadNext == null) {
      _error =
          "This source is misconfigured: loadPage and loadNext cannot both be null"
              .tl;
      Future.microtask(() {
        setState(() {});
      });
      return;
    }
    if (_data[page] != null || _loading[page] == true) {
      return;
    }
    _loading[page] = true;
    try {
      if (widget.loadPage != null) {
        var res = await widget.loadPage!(page);
        if (!mounted) return;
        if (res.success) {
          if (res.data.isEmpty) {
            setState(() {
              _data[page] = const [];
              _maxPage ??= page;
            });
          } else {
            setState(() {
              _data[page] = res.data;
              if (res.subData != null && res.subData is int) {
                _maxPage = res.subData;
              }
            });
          }
        } else if (!silent) {
          setState(() {
            _error = friendlyError(res.errorMessage ?? "Unknown error".tl);
          });
        }
      } else {
        try {
          while (_data[page] == null) {
            await _fetchNext();
          }
          if (mounted) {
            setState(() {});
          }
        } catch (e) {
          if (mounted && !silent) {
            setState(() {
              _error = friendlyError(e);
            });
          }
        }
      }
    } catch (e) {
      // 源脚本 / 网络层抛异常（不是返回 Res.error）时，以前这里没有任何兜底：
      // _data[page] 一直是 null、_error 一直为 null，build 里再调 _loadPage
      // 又立刻抛一次 —— 界面就永久卡在骨架屏。这是断网进分类列表的实际表现。
      if (mounted && !silent) {
        setState(() {
          _error = friendlyError(e);
        });
      }
    } finally {
      _loading[page] = false;
      storeState();
      // 只在「用户主动翻到的页」加载成功后预取，静默加载自己不再触发预取，
      // 否则会顺着 2、3、4… 一路把整本分类全下完。
      if (!silent && _error == null && _data[page] != null) {
        _prefetch(page + 1);
      }
    }
  }

  Future<void> _fetchNext() async {
    var res = await widget.loadNext!(_nextUrl);
    _data[_data.length + 1] = res.data;
    if (res.subData == null) {
      _maxPage = _data.length;
    } else {
      _nextUrl = res.subData;
    }
  }

  @override
  Widget build(BuildContext context) {
    var type = appdata.settings['comicListDisplayMode'];
    return type == 'paging' ? buildPagingMode() : buildContinuousMode();
  }

  Widget buildPagingMode() {
    final body = _buildPagingBody();
    // 只有一页时不留那条 54dp 的底栏。`_maxPage == null`（源不上报总页数）
    // 必须留：这种源只能靠「下一页」往后翻，把底栏藏了就没法翻页了。
    final showBar = _maxPage != 1;
    if (!showBar) {
      return body;
    }
    return Column(
      children: [
        Expanded(child: body),
        _buildPageBar(),
      ],
    );
  }

  Widget _buildPagingBody() {
    if (_error != null) {
      return Column(
        children: [
          if (widget.errorLeading != null) widget.errorLeading!,
          Expanded(
            child: NetworkError(
              withAppbar: false,
              message: _error!,
              retry: () {
                setState(() {
                  _error = null;
                });
              },
            ),
          ),
        ],
      );
    }
    if (_data[_page] == null) {
      _loadPage(_page);
      return Column(
        children: [
          if (widget.errorLeading != null) widget.errorLeading!,
          const Expanded(child: _ComicGridSkeleton()),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: kcBrandAdaptive(context),
      child: SmoothCustomScrollView(
        // 换页回到顶部。`enablePageStorage` 默认是 false，以前这里是 `null`，
        // key 不变 → 滚动位置被沿用，从上一页底部翻页会直接落在新页的半山腰，
        // 顶上前几部漫画被跳过。带上页码的 key 让滚动视图跟着页码重建。
        key: enablePageStorage
            ? PageStorageKey('scroll$_page')
            : ValueKey('scroll$_page'),
        controller: widget.controller,
        slivers: [
          if (widget.leadingSliver != null) widget.leadingSliver!,
          SliverGridComics(
            comics: _data[_page] ?? const [],
            menuBuilder: widget.menuBuilder,
            allFavorite: widget.allFavorite,
            showSourceOnCover: widget.showSourceOnCover,
            showBottomSourceDate: widget.showBottomSourceDate,
            badgeAsTopLeftSource: widget.badgeAsTopLeftSource,
            openLocalIfAvailable: widget.openLocalIfAvailable,
          ),
          if (widget.trailingSliver != null) widget.trailingSliver!,
        ],
      ),
    );
  }

  Widget buildContinuousMode() {
    if (_error != null && _data.isEmpty) {
      return Column(
        children: [
          if (widget.errorLeading != null) widget.errorLeading!,
          // 这里原本还挂着分页条，但连续模式渲染的是 `_data.values` 的拼接，
          // `_page` 完全不参与渲染 —— 两颗箭头点了没有任何反应，是死控件。
          Expanded(
            child: NetworkError(
              withAppbar: false,
              message: _error!,
              retry: () {
                setState(() {
                  _error = null;
                });
              },
            ),
          ),
        ],
      );
    }
    if (_data[1] == null) {
      _loadPage(1);
      return Column(
        children: [
          if (widget.errorLeading != null) widget.errorLeading!,
          const Expanded(child: _ComicGridSkeleton()),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: kcBrandAdaptive(context),
      child: SmoothCustomScrollView(
        key: enablePageStorage ? PageStorageKey('scroll$_page') : null,
        controller: widget.controller,
        slivers: [
          if (widget.leadingSliver != null) widget.leadingSliver!,
          SliverGridComics(
            comics: _data.values.expand((element) => element).toList(),
            menuBuilder: widget.menuBuilder,
            allFavorite: widget.allFavorite,
            showSourceOnCover: widget.showSourceOnCover,
            showBottomSourceDate: widget.showBottomSourceDate,
            badgeAsTopLeftSource: widget.badgeAsTopLeftSource,
            openLocalIfAvailable: widget.openLocalIfAvailable,
            onLastItemBuild: () {
              if (_error == null &&
                  (_maxPage == null || _data.length < _maxPage!)) {
                _loadPage(_data.length + 1);
              }
            },
          ),
          if (_error != null)
            SliverToBoxAdapter(
              child: Column(
                children: [
                  Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedAlertCircle,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, maxLines: 3)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Button.outlined(
                      onPressed: () {
                        setState(() {
                          _error = null;
                        });
                      },
                      child: Text("Retry".tl),
                    ),
                  ),
                ],
              ).paddingHorizontal(16).paddingVertical(8),
            )
          else if (_maxPage == null || _data.length < _maxPage!)
            const SliverListLoadingIndicator(),
          if (widget.trailingSliver != null) widget.trailingSliver!,
        ],
      ),
    );
  }
}

/// 页码网格：一次点击直达目标页。
///
/// 相比「弹窗 + 键盘 + 输入 + 确认」，少两步、不弹键盘、也不遮住列表。90 页
/// 的分类一屏能看到四十多页，打开时自动滚到当前页上方一点。
class _PagePickerDialog extends StatefulWidget {
  const _PagePickerDialog({required this.current, required this.maxPage});

  final int current;

  final int maxPage;

  @override
  State<_PagePickerDialog> createState() => _PagePickerDialogState();
}

class _PagePickerDialogState extends State<_PagePickerDialog> {
  static const _columns = 6;
  static const _cellHeight = 44.0;
  static const _gap = 8.0;

  /// 与 [ContentDialog] 的正文左右内边距一致，格子才不会贴到弹窗边缘。
  static const _hPadding = 16.0;

  late final ScrollController _controller = ScrollController(
    initialScrollOffset: _initialOffset(),
  );

  /// 让当前页落在可视区偏上，而不是贴在最顶端或最底端。
  double _initialOffset() {
    final row = (widget.current - 1) ~/ _columns;
    final offset = row * (_cellHeight + _gap) - 88;
    return offset > 0 ? offset : 0;
  }

  /// 弹窗宽度由 `ContentDialog` 定成 `min(400, 屏宽 - 16)`，这里照着算，
  /// 让 6 列刚好铺满 —— 写死列宽会留下一大块右侧空白。
  double _gridWidth(BuildContext context) {
    final dialogWidth = math.min(400.0, context.width - 16);
    return dialogWidth - _hPadding * 2;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gridWidth = _gridWidth(context);
    final cellWidth = (gridWidth - (_columns - 1) * _gap) / _columns;
    return ContentDialog(
      title: "Jump to page".tl,
      headerIcon: HugeIcons.strokeRoundedGrid02,
      showClose: false,
      content: SizedBox(
        // 固定宽度：ContentDialog 外面是 IntrinsicWidth，不给尺寸它会去问
        // Wrap 的固有宽度，而 Wrap 会回答「全部格子排一行」。
        width: gridWidth + _hPadding * 2,
        child: ConstrainedBox(
          // 高度刻意不取整行：底部露出半行格子，用户才知道下面还有页。
          // 取 320 时正好塞下 6 整行，看起来像「一共就 36 页」。
          constraints: const BoxConstraints(maxHeight: 292),
          child: Scrollbar(
            controller: _controller,
            child: SingleChildScrollView(
              controller: _controller,
              padding: const EdgeInsets.symmetric(
                horizontal: _hPadding,
                vertical: 4,
              ),
              child: Wrap(
                spacing: _gap,
                runSpacing: _gap,
                children: [
                  for (var page = 1; page <= widget.maxPage; page++)
                    _buildCell(context, page, cellWidth),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCell(BuildContext context, int page, double width) {
    final cs = Theme.of(context).colorScheme;
    final selected = page == widget.current;
    return SizedBox(
      width: width,
      height: _cellHeight,
      child: Material(
        color: selected ? kcAccentColor(context) : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kcRadius8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(page),
          child: Center(
            child: Text(
              "$page",
              style: TextStyle(
                fontSize: kcBody,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                // 红底前景一律 kcOnAccentColor（恒白）；onPrimary 在 AMOLED 下是黑。
                color: selected ? kcOnAccentColor : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.value,
    this.onTap,
    this.size = 20,
  });

  final double value; // 0-5

  final VoidCallback? onTap;

  final double size;

  @override
  Widget build(BuildContext context) {
    var interval = size * 0.1;
    var value = this.value;
    if (value.isNaN) {
      value = 0;
    }
    var child = SizedBox(
      height: size,
      width: size * 5 + interval * 4,
      child: Row(
        children: [
          for (var i = 0; i < 5; i++)
            _Star(
              value: (value - i).clamp(0.0, 1.0),
              size: size,
            ).paddingRight(i == 4 ? 0 : interval),
        ],
      ),
    );
    return onTap == null ? child : GestureDetector(onTap: onTap, child: child);
  }
}

class _Star extends StatelessWidget {
  const _Star({required this.value, required this.size});

  final double value; // 0-1

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedStar,
            size: 18,
            color: context.colorScheme.secondary,
          ),
          ClipRect(
            clipper: _StarClipper(value),
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedStar,
              size: 18,
              color: context.colorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StarClipper extends CustomClipper<Rect> {
  final double value;

  _StarClipper(this.value);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * value, size.height);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) {
    return oldClipper is! _StarClipper || oldClipper.value != value;
  }
}

class RatingWidget extends StatefulWidget {
  /// star number
  final int count;

  /// Max score
  final double maxRating;

  /// Current score value
  final double value;

  /// Star size
  final double size;

  /// Space between the stars
  final double padding;

  /// Whether the score can be modified by sliding
  final bool selectable;

  /// Callbacks when ratings change
  final ValueChanged<double> onRatingUpdate;

  const RatingWidget({
    super.key,
    this.maxRating = 10.0,
    this.count = 5,
    this.value = 10.0,
    this.size = 20,
    required this.padding,
    this.selectable = false,
    required this.onRatingUpdate,
  });

  @override
  State<RatingWidget> createState() => _RatingWidgetState();
}

class _RatingWidgetState extends State<RatingWidget> {
  double value = 10;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (PointerDownEvent event) {
        double x = event.localPosition.dx;
        if (x < 0) x = 0;
        pointValue(x);
      },
      onPointerMove: (PointerMoveEvent event) {
        double x = event.localPosition.dx;
        if (x < 0) x = 0;
        pointValue(x);
      },
      onPointerUp: (_) {},
      behavior: HitTestBehavior.deferToChild,
      child: buildRowRating(),
    );
  }

  pointValue(double dx) {
    if (!widget.selectable) {
      return;
    }
    if (dx >=
        widget.size * widget.count + widget.padding * (widget.count - 1)) {
      value = widget.maxRating;
    } else {
      for (double i = 1; i < widget.count + 1; i++) {
        if (dx > widget.size * i + widget.padding * (i - 1) &&
            dx < widget.size * i + widget.padding * i) {
          value = i * (widget.maxRating / widget.count);
          break;
        } else if (dx > widget.size * (i - 1) + widget.padding * (i - 1) &&
            dx < widget.size * i + widget.padding * i) {
          value =
              (dx - widget.padding * (i - 1)) /
              (widget.size * widget.count) *
              widget.maxRating;
          break;
        }
      }
    }
    if (value % 1 >= 0.5) {
      value = value ~/ 1 + 1;
    } else {
      value = (value ~/ 1).toDouble();
    }
    if (value < 0) {
      value = 0;
    } else if (value > 10) {
      value = 10;
    }
    setState(() {
      widget.onRatingUpdate(value);
    });
  }

  int fullStars() {
    return (value / (widget.maxRating / widget.count)).floor();
  }

  double star() {
    if (widget.count / fullStars() == widget.maxRating / value) {
      return 0;
    }
    return (value % (widget.maxRating / widget.count)) /
        (widget.maxRating / widget.count);
  }

  List<Widget> buildRow() {
    int full = fullStars();
    List<Widget> children = [];
    for (int i = 0; i < full; i++) {
      children.add(
        HugeIcon(
          icon: HugeIcons.strokeRoundedStar,
          size: 18,
          color: context.colorScheme.secondary,
        ),
      );
      if (i < widget.count - 1) {
        children.add(SizedBox(width: widget.padding));
      }
    }
    if (full < widget.count) {
      children.add(
        ClipRect(
          clipper: _SMClipper(rating: star() * widget.size),
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedStar,
            size: 18,
            color: context.colorScheme.secondary,
          ),
        ),
      );
    }

    return children;
  }

  List<Widget> buildNormalRow() {
    List<Widget> children = [];
    for (int i = 0; i < widget.count; i++) {
      children.add(
        HugeIcon(
          icon: HugeIcons.strokeRoundedStar,
          size: 18,
          color: context.colorScheme.secondary,
        ),
      );
      if (i < widget.count - 1) {
        children.add(SizedBox(width: widget.padding));
      }
    }
    return children;
  }

  Widget buildRowRating() {
    return Stack(
      children: <Widget>[
        Row(children: buildNormalRow()),
        Row(children: buildRow()),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    value = widget.value;
  }
}

class _SMClipper extends CustomClipper<Rect> {
  final double rating;

  _SMClipper({required this.rating});

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0.0, 0.0, rating, size.height);
  }

  @override
  bool shouldReclip(_SMClipper oldClipper) {
    return rating != oldClipper.rating;
  }
}

class SimpleComicTile extends StatelessWidget {
  const SimpleComicTile({
    super.key,
    required this.comic,
    this.onTap,
    this.withTitle = false,
    this.heroID,
    this.heroRadius = 8,
  });

  final Comic comic;

  final void Function()? onTap;

  final bool withTitle;

  final int? heroID;

  final double heroRadius;

  @override
  Widget build(BuildContext context) {
    var image = _findImageProvider(comic);

    Widget child = image == null
        ? const SizedBox()
        : AnimatedImage(
            key: ValueKey(image.hashCode),
            image: image,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            cacheWidth: (98 * MediaQuery.of(context).devicePixelRatio)
                .ceil()
                .clamp(24, 400),
            cacheHeight: (136 * MediaQuery.of(context).devicePixelRatio)
                .ceil()
                .clamp(24, 400),
          );

    child = Container(
      width: 98,
      height: 136,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(heroRadius),
        color: Theme.of(context).colorScheme.secondaryContainer,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    if (heroID != null) {
      child = Hero(tag: "cover$heroID", child: child);
    }

    child = AnimatedTapRegion(
      borderRadius: 8,
      onTap:
          onTap ??
          () {
            context.to(
              () => ComicPage(
                id: comic.id,
                sourceKey: comic.sourceKey,
                cover: comic.cover,
                title: comic.title,
                heroID: heroID,
              ),
            );
          },
      child: child,
    );

    if (withTitle) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 4),
          SizedBox(
            width: 92,
            child: Center(
              child: Text(
                comic.title.replaceAll('\n', ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      );
    }

    return child;
  }
}

/// A paginated sliver grid that loads comics incrementally.
///
/// Unlike [SliverGridComics] which takes a pre-loaded [List<Comic]], this widget
/// accepts a [pageLoader] callback and loads pages lazily as the user scrolls.
/// This avoids loading thousands of comics into memory on page open.
///
/// For [selectAll] support, the parent should load all comics separately
/// (one-time operation) and populate the [selections] map. The widget only
/// checks [selections] for currently visible items, so the map may contain
/// more entries than are displayed.
class PaginatedSliverGridComics extends StatefulWidget {
  const PaginatedSliverGridComics({
    super.key,
    required this.pageLoader,
    this.pageSize = 30,
    this.selections,
    this.badgeBuilder,
    this.menuBuilder,
    this.onTap,
    this.onLongPressed,
    this.onLoadedComicsChanged,
    this.allFavorite = false,
    this.emptySubtitle,
    this.badgeColorBuilder,
    this.showSourceOnCover = true,
    this.showBottomSourceDate = false,
    this.badgeAsTopLeftSource = false,
    this.openLocalIfAvailable = false,
  });

  /// Loads a page of comics starting at [offset].
  /// Return an empty list to signal no more pages.
  final Future<List<Comic>> Function(int offset, int limit) pageLoader;

  /// Number of comics to load per page.
  final int pageSize;

  /// Selection map. May contain more entries than currently loaded.
  /// Keys are checked by identity (Comic does not override == by default,
  /// but FavoriteItem and History do).
  final Map<Comic, bool>? selections;

  final String? Function(Comic)? badgeBuilder;

  /// 可选：返回 badge 自定义底色，用于按业务维度（如漫画源）区分颜色。
  final Color? Function(Comic)? badgeColorBuilder;

  final List<MenuEntry> Function(Comic)? menuBuilder;

  final void Function(Comic, int heroID)? onTap;

  final void Function(Comic, int heroID)? onLongPressed;

  /// Called whenever the loaded comics list changes (page loaded or refresh).
  /// The parent can use this to track loaded comics for invertSelection etc.
  final void Function(List<Comic> loadedComics)? onLoadedComicsChanged;

  /// When true, every comic is treated as favorited (network favorites folders).
  final bool allFavorite;

  /// Subtitle shown in the empty state.
  final String? emptySubtitle;

  /// When false, the brief-mode top-right metadata pill is hidden entirely.
  final bool showSourceOnCover;

  /// When true, the brief-mode shows source/date as a bottom pill above the
  /// history progress bar.
  final bool showBottomSourceDate;

  /// When true and [badgeBuilder] returns non-null, use that badge as the
  /// top-left source pill instead of the comic subtitle (author).
  final bool badgeAsTopLeftSource;

  /// When true, tap opens a locally-downloaded copy if available (offline).
  final bool openLocalIfAvailable;

  @override
  State<PaginatedSliverGridComics> createState() =>
      PaginatedSliverGridComicsState();
}

class PaginatedSliverGridComicsState extends State<PaginatedSliverGridComics>
    with AutoListenMixin {
  final List<Comic> _comics = [];
  final List<int> _heroIDs = [];
  final Map<String, bool> _favoriteStatus = {};
  final Map<String, History> _historyStatus = {};

  bool _isLoading = false;
  bool _hasMore = true;
  bool _initialized = false;
  Object? _error;

  static int _nextHeroID = 0;

  @override
  void initState() {
    super.initState();
    // Watch favorites/history so a change made elsewhere — e.g. favoriting a
    // comic from its detail page and popping back — reloads this paginated grid
    // and refreshes the status badges. Previously the grid relied solely on its
    // parent page's listener, which could silently skip the refresh when the
    // grid's GlobalKey state was null (not yet mounted / just rebuilt).
    listen(HistoryManager(), _onFavoritesChanged);
    listen(LocalFavoritesManager(), _onFavoritesChanged);
    _loadNextPage();
  }

  void _onFavoritesChanged() {
    if (mounted) refresh();
  }

  Future<void> _loadNextPage() async {
    // `_error` has to gate re-entry too: when a page throws, `_isLoading` goes
    // back to false in `finally`, so without this check the footer slot below
    // would re-request the same failing page every single frame. That both
    // hammered the network and left the user staring at an endless spinner
    // with no way to retry. Recovery goes exclusively through `retry()`.
    if (_isLoading || !_hasMore || _error != null) return;
    _isLoading = true;
    if (_initialized) {
      setState(() {});
    }
    try {
      final newComics = await widget.pageLoader(
        _comics.length,
        widget.pageSize,
      );
      if (!mounted) return;
      if (newComics.isEmpty) {
        _hasMore = false;
      } else {
        for (var comic in newComics) {
          if (isBlocked(comic) == null) {
            _comics.add(comic);
            _heroIDs.add(_nextHeroID++);
          }
        }
        _precomputeStatusForNew(newComics);
        widget.onLoadedComicsChanged?.call(List.unmodifiable(_comics));
      }
      _initialized = true;
    } catch (e) {
      _error = friendlyError(e);
    } finally {
      _isLoading = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _precomputeStatusForNew(List<Comic> newComics) {
    final showFavorite = appdata.settings['showFavoriteStatusOnTile'] == true;
    final showHistory = appdata.settings['showHistoryStatusOnTile'] == true;

    if (showFavorite) {
      for (var comic in newComics) {
        if (isBlocked(comic) == null) {
          _favoriteStatus[comic.id] =
              widget.allFavorite ||
              LocalFavoritesManager().isExist(
                comic.id,
                ComicType.fromKey(comic.sourceKey),
              );
        }
      }
    }

    if (showHistory) {
      final batch = HistoryManager().findBatch(newComics.map((c) => c.id));
      _historyStatus.addAll(batch);
    }
  }

  /// Clear a failed page state and try again. This is the only supported way
  /// out of an error, see the guard at the top of [_loadNextPage].
  void retry() {
    setState(() {
      _error = null;
    });
    _loadNextPage();
  }

  /// Reset and reload from page 1.
  Future<void> refresh() async {
    _comics.clear();
    _heroIDs.clear();
    _favoriteStatus.clear();
    _historyStatus.clear();
    _hasMore = true;
    _initialized = false;
    _error = null;
    await _loadNextPage();
  }

  @override
  Widget build(BuildContext context) {
    // Initial loading state
    if (!_initialized && _isLoading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Error on first load
    if (_error != null && _comics.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle, size: 48),
              const SizedBox(height: 8),
              Text(_error.toString()),
            ],
          ),
        ),
      );
    }

    // Empty state
    if (_comics.isEmpty && !_hasMore) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedClock01, size: 18),
          title: 'No comics'.tl,
          subtitle:
              (widget.emptySubtitle ??
                      "No comics yet? Add a comic source or favorite some comics.")
                  .tl,
        ),
      );
    }

    // Main grid: childCount = comics + 1 (footer slot)
    final showFooter = _hasMore || _isLoading;

    return AnimatedBuilder(
      animation: appdata.settings,
      builder: (context, _) => SliverGrid(
        delegate: SliverChildBuilderDelegate((context, index) {
          // Footer slot
          if (index == _comics.length) {
            // A failed page must be *visible*, otherwise the user only sees a
            // spinner where the rest of the list should have arrived.
            if (_error != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(kcSpaceLg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error.toString(), textAlign: TextAlign.center),
                      const SizedBox(height: kcSpaceSm),
                      Button.text(onPressed: retry, child: Text("Retry".tl)),
                    ],
                  ),
                ),
              );
            }
            if (showFooter) {
              if (!_isLoading) {
                // Trigger next page load
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _loadNextPage();
                });
              }
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(kcSpaceLg),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }

          final comic = _comics[index];
          final badge = widget.badgeBuilder?.call(comic);
          final isSelected = widget.selections == null
              ? false
              : widget.selections![comic] ?? false;

          final tile = ComicTile(
            comic: comic,
            badge: badge,
            badgeColor: widget.badgeColorBuilder?.call(comic),
            menuOptions: widget.menuBuilder?.call(comic),
            onTap: widget.onTap != null
                ? () => widget.onTap!(comic, _heroIDs[index])
                : null,
            onLongPressed: widget.onLongPressed != null
                ? () => widget.onLongPressed!(comic, _heroIDs[index])
                : null,
            heroID: _heroIDs[index],
            isFavorite: _favoriteStatus[comic.id],
            history: _historyStatus[comic.id],
            showSourceOnCover: widget.showSourceOnCover,
            showBottomSourceDate: widget.showBottomSourceDate,
            badgeAsTopLeftSource: widget.badgeAsTopLeftSource,
            openLocalIfAvailable: widget.openLocalIfAvailable,
          );

          if (widget.selections == null) {
            return RepaintBoundary(child: tile);
          }
          return AnimatedContainer(
            key: ValueKey(comic.id),
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(
                      context,
                    ).colorScheme.secondaryContainer.withValues(alpha: 0.72)
                  : null,
              borderRadius: BorderRadius.circular(kcCardRadius),
            ),
            margin: const EdgeInsets.all(kcSpaceXs),
            child: RepaintBoundary(child: tile),
          );
        }, childCount: _comics.length + (showFooter ? 1 : 0)),
        gridDelegate: SliverGridDelegateWithComics(),
      ),
    );
  }
}
