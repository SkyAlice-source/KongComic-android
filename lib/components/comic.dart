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
      // 卡片封面：失败即报错，交给占位 + 重试按钮，不在这里干等退避。
      failFast: true,
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

/// brief 模式标题字号：方案 J 的「按列宽分档」。
///
/// 3 列窄卡（~120dp）只能给正文档单行；2 列宽卡（~185dp）给 16sp 并放开
/// 两行，长中文标题才不会只露出前 6 个字。极窄（<120dp）仍退回 12sp。
double comicTileTitleFontSize(double cardWidth) => cardWidth < 120
    ? kcCaption
    : cardWidth < 160
    ? kcBody
    : kcSubtitle;

/// 宽列给两行，窄列保持单行（窄卡两行会把封面压成一条）。
int comicTileTitleMaxLines(double cardWidth) => cardWidth < 160 ? 1 : 2;

/// brief 模式卡片里「封面下方标题行」的垂直开销（不含封面本身）。
///
/// 收藏书架按这条公式给每个卡槽预留高度。之前书架把卡高写死成封面高，
/// 书名叠在封面底部又被「第 X 话 · 进度」胶囊挤掉，看起来就是「名字没了、
/// 一排下面空一大截」。字号档位与 [ComicTile] 内部保持一致，行高也统一
/// 锁在 1.3，两端算出来的值才对得上；J 之后宽列按两行预留。
double comicTileTitleBlock(double cardWidth, TextScaler scaler) {
  final fontSize = comicTileTitleFontSize(cardWidth);
  // 上内边距 4 + 标题行数 × 一行文字。
  return 4 +
      scaler.scale(fontSize) * 1.3 * comicTileTitleMaxLines(cardWidth);
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
    // 页面自带的菜单项里已经有同名动作时，不再插入内置的那一条。
    // 历史页 / 本地漫画页都想把「添加到收藏」放在自己那组的首位（高频动作），
    // 而内置项固定排在「复制标题」之后，于是同一份菜单里出现两条一模一样的
    // 「添加到收藏」——用户不知道该点哪条，两条做的事还都一样。
    final customTexts = {
      for (final entry in menuOptions ?? const <MenuEntry>[])
        if (entry.text.isNotEmpty) entry.text,
    };
    final favoriteText = 'Add to favorites'.tl;
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
      if (!customTexts.contains(favoriteText))
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedFavourite, size: 18),
          text: favoriteText,
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
        // 统一走 CoverBox：加载中显示书名首字、失败给重试，不再是一块白。
        // 首字字号按封面宽度走（列表 60dp 封面 ≈20，网格 120dp ≈40），
        // 小缩略图（<90）不给重试按钮——那么小的胶囊点不准，收益也低。
        final coverWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 120.0;
        return CoverBox(
          key: ValueKey(customKey ?? '${comic.sourceKey}_${comic.id}'),
          image: image,
          label: comic.title,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          retryable: coverWidth >= 90,
          initialFontSize: (coverWidth * 0.32).clamp(16.0, 52.0),
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

  /// 收藏角标：封面右上角悬浮的「胶囊『已收藏』」（C 案）。
  ///
  /// 白心 + 「已收藏」文字 + 品牌红胶囊底——B站「追」/Apple Books
  /// 「阅读中」的文字角标签。信息零学习成本：图标负责瞬间识别，
  /// 文字负责确认语义，红色胶囊从任何封面上跳出来。胶囊是这一轮
  /// 实测七版（丝带/方tile/白环/红圆/黑片书签/白片书签）之后
  /// 用户回选的设计稿原始方向——「有文字的状态标签」比任何纯
  /// 图形徽章都更直白。高度固定 19dp 不随封面缩放：文字可读性
  /// 有下限，窄列表封面（60dp）上胶囊占比高但仍在设计稿比例内。
  /// AMOLED 下沿用入口卡的「页面级品牌标记」豁免保持品牌红。
  Widget _buildFavoriteCornerBadge(BuildContext context, double side) {
    // 距右上边缘留呼吸缝：贴边会跟封面圆角打架，悬浮一点才像徽章。
    return Padding(
      padding: EdgeInsets.only(top: side * 0.36, right: side * 0.22),
      child: Container(
        height: 19,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kcRadius8),
          color: kcAccentColor(context),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite, size: 11, color: kcOnAccentColor),
            const SizedBox(width: 3),
            Text(
              'Favorited'.tl,
              style: TextStyle(
                // 图片上的徽标下限是 kcFont11：10 在 3x 屏上中文只有约 3mm 高。
                fontSize: kcFont11,
                fontWeight: FontWeight.w600,
                height: 1.0,
                color: kcOnAccentColor,
              ),
            ),
          ],
        ),
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

    // Floor the size at 11pt so the cover caption stays legible even on the
    // narrowest cards — the old 8pt floor was effectively unreadable.
    final fontSize = constraints.maxWidth < 80
        ? 11.0
        : constraints.maxWidth < 150
        ? 12.0
        : 13.0;

    final style = TextStyle(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      height: 1.2,
      shadows: [
        Shadow(color: Colors.black.withValues(alpha: 0.60), blurRadius: 2),
      ],
    );

    var parts = text
        ?.split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts == null || parts.isEmpty) {
      return const SizedBox();
    }
    // 窄卡片上「来源 · 日期」整串放不下时，原来一律省略号收尾 —— 于是最该
    // 读的日期被截成「2026-1…」，剩个没用的来源名。这里改成按段裁剪：放不下
    // 就从**前面**丢，优先保住末尾的日期（收藏时间才是这一行的信息价值）。
    parts = _fitMetadataParts(context, parts, style, constraints.maxWidth);
    final resolved = parts.join(' · ');

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
            resolved,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  /// 从前往后丢段，直到整串能塞进 [maxWidth]；只剩一段时原样返回（交给
  /// 省略号处理，不会再切）。
  List<String> _fitMetadataParts(
    BuildContext context,
    List<String> parts,
    TextStyle style,
    double maxWidth,
  ) {
    final available = math.max(0.0, maxWidth - 8);
    var current = parts;
    while (current.length > 1) {
      final painter = TextPainter(
        text: TextSpan(text: current.join(' · '), style: style),
        maxLines: 1,
        textDirection: Directionality.of(context),
      )..layout(maxWidth: available);
      if (!painter.didExceedMaxLines && painter.width <= available) {
        break;
      }
      current = current.sublist(1);
    }
    return current;
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
            padding: const EdgeInsets.fromLTRB(kcSpaceLg, kcSpaceSm, 24, kcSpaceSm),
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
        // 方案 J：字号与行数都按列宽分档，和 [comicTileTitleBlock] 同源，
        // 收藏书架预留的槽位高度才不会和这里实际画出来的标题对不上。
        final titleFont = comicTileTitleFontSize(constraints.maxWidth);
        final titleMaxLines = comicTileTitleMaxLines(constraints.maxWidth);
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
                              ? const EdgeInsets.fromLTRB(kcSpaceXs, 2, kcSpaceXs, 2)
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
                                ? const EdgeInsets.fromLTRB(kcSpaceXs, 2, kcSpaceXs, 2)
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
                              // 封面底部渐变上叠白字的投影：35% 黑 scrim，
                              // 语义同上（可读性投影，非主题色）。不再把
                              // 带 alpha 的字面色值写进 const 列表里。
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 2,
                                ),
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
                  padding: const EdgeInsets.fromLTRB(kcSpaceXs, kcSpaceXs, kcSpaceXs, 0),
                  child: Text(
                    comic.title.replaceAll('\n', ''),
                    maxLines: titleMaxLines,
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
          // 卡座内衬只留 4dp：之前 6/8 再叠 _SelectableComicCell 的 6dp
          // margin + 2dp 透明边，一本封面上下各空出 16dp，看起来就是「框没
          // 填满」。收紧后封面向卡座四边撑开，相邻两卡之间仍有 8dp 呼吸。
          ).paddingHorizontal(kcSpaceXs).paddingVertical(kcSpaceXs),
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
                    // 弹窗开着期间 tile 可能已被网格 update() 卸载
                    // （收藏/历史监听触发），对 defunct element 做
                    // ancestor lookup 会抛断言。
                    if (comicTileContext.mounted) {
                      comicTileContext
                          .findAncestorStateOfType<_SliverGridComicsState>()
                          ?.update();
                    }
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
            // badge 可能为空串（Comic.language 来自 JS 源，无校验），
            // badge![0] 对空串抛 RangeError 会让整个列表页崩。
            if (badge != null && badge!.isNotEmpty)
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

/// 把漫画网格收敛到统一内容列（[kcContentMaxWidth] = 900dp）并居中。
///
/// 方案 E/F 早就把「内容列最大宽度」定成了令牌，但只有主页 / 历史 / 设置真正
/// 用了它；分类 / 发现 / 收藏 / 搜索 / 本地这些「网格页」一直满宽渲染 ——
/// 平板 2560dp 会被切成 12 列、封面小到看不清，与主页的 900dp 单列并排时
/// 一眼就是两套版式。这里在两个网格出口（普通网格与分页网格）统一收口。
///
/// 用 [SliverLayoutBuilder] 而不是 `MediaQuery.sizeOf`：网格也可能落在双栏 /
/// 弹层这类「窗口宽 ≠ 可用宽」的容器里，只有 SliverConstraints 是准的。
///
/// 手机竖屏 crossAxisExtent < 900 → padding 恒为 0，与改动前逐像素一致。
Widget _kcCenteredGridSliver(Widget grid) {
  return SliverLayoutBuilder(
    builder: (context, constraints) {
      final extent = constraints.crossAxisExtent;
      final pad = (extent - kcPageContentWidth(extent)) / 2;
      if (pad <= 0) return grid;
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        sliver: grid,
      );
    },
  );
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
      builder: (context, _) => _kcCenteredGridSliver(SliverGrid(
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
          return _SelectableComicCell(
            key: ValueKey(comics[index].id),
            selected: isSelected,
            child: comic,
          );
        }, childCount: comics.length),
        gridDelegate: SliverGridDelegateWithComics(
                textScale:
                    MediaQuery.textScalerOf(context).scale(kcBody) / kcBody,
              ),
      )),
    );
  }
}

/// 多选态的单元格外观：不占布局的叠加层（overlay）。
///
/// 以前用 `AnimatedContainer(margin: 3, border: 2)` 把 child 包在里面：进入
/// 多选态时封面被内缩约 10dp、退出时又弹回，整屏网格看着像「缩了一下」。
/// 现在 child 用 `Positioned.fill` 直接铺满卡座，选中框 / 染色 / 勾选标全部
/// 叠在它上面，正常态（`RepaintBoundary(child: comic)`）和多选态的卡片尺寸
/// 完全一致，切换零位移。
///
/// 视觉表达仍沿用收藏/历史那套「每本单独边框 + 品牌色勾选标」：由于底色不再
/// 露在封面外圈，改成一层很淡的 secondaryContainer 染色（不会盖掉封面），
/// 边框与勾选标负责确认选中；深色下 secondaryContainer 太接近页面底色，
/// 所以浅/深分别给 0.16 / 0.22 的 alpha。
class _SelectableComicCell extends StatelessWidget {
  const _SelectableComicCell({
    required this.selected,
    required this.child,
    super.key,
  });

  final bool selected;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: selected
                      ? cs.secondaryContainer.withValues(
                          alpha: isDark ? 0.22 : 0.16,
                        )
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(kcCardRadius),
                  border: Border.all(
                    color: selected
                        ? kcBrandAdaptive(context)
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          if (selected)
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: kcAccentColor(context),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: kcOnAccentColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// return the first blocked keyword, or null if not blocked
String? isBlocked(Comic item) {
  for (var word in appdata.settings['blockedWords']) {
    // 空串必须跳过：`title.contains("")` 恒为 true，会把整个列表判成「全屏蔽」。
    // 旧版设置页允许空提交，用户数据里可能已经存着空串，这里兜住才能自愈。
    if (word.isEmpty) continue;
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
    // 列数按**内容区**宽算：宽屏有侧栏时整屏宽会多算列，加载完成的真实
    // 网格换列会横向跳一下。LayoutBuilder 拿到的是父级给的剩余宽度。
    return LayoutBuilder(
      builder: (context, constraints) {
        // 与 SliverGridDelegateWithComics 列数估算接近，占位与真实网格同尺寸
        // 不封顶 6：平板/横屏内容宽超过 900dp 时真实网格本来就有 6+ 列，
        // 骨架封顶会让「加载完成瞬间跳列」。下限 2 防窄屏退化成单列。
        final crossAxisCount =
            math.max(2, (constraints.maxWidth / 150).floor());
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
      },
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
    // 定格在偏亮的一档，静态占位仍然可辨（不暗到像禁用态）。
    value: 0.7,
  );

  bool _animating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate = !MediaQuery.of(context).disableAnimations;
    if (shouldAnimate == _animating) return;
    _animating = shouldAnimate;
    if (shouldAnimate) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0.7;
    }
  }

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
    // loading 是瞬态：加载中写进的 true 若被恢复，_loadPage 的
    // `_loading[page] == true` 守卫会让该页永久停在骨架屏，没有任何
    // 代码会再清掉它。
    _loading.clear();
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
    // 只返回胶囊本体：定位、让位、悬浮阴影统一由 _buildPageBar 负责，
    // 之前这里自带 Center + 上下 8dp 内边距，把胶囊绑死在整宽底栏里。
    return ToolsPill(
      height: kcPagerPillHeight,
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
    );
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
              KcInlineSpinner(size: 12, color: cs.onSurfaceVariant)
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
              decoration: kcInputDecoration(context, labelText: "Page".tl),
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

  /// 悬浮在屏幕底部上方的翻页胶囊。
  ///
  /// 翻页是这一屏唯一的导航动作，也是最需要「按一下」的动作。放在列表顶部
  /// 意味着大屏单手要换手；放底部后拇指原地就能翻，顺带省掉「滚到底才有
  /// 下一页」的来回。分页条因此只保留这一条，顶部那条已删除。
  ///
  /// 旧实现是「整宽白底 + 顶部发丝线」的贴底栏，和悬浮玻璃 dock 叠成两层，
  /// 页码下半截被 dock 盖住（用户实拍）。中间版改成 Column：胶囊 + 让位
  /// padding 实占一整条底部空间，页面底色把那约 100dp 画成一整片白，胶囊
  /// 看着像「连着一块白色底板」。现在用 Stack 让网格铺满整屏，胶囊只以
  /// [Positioned] 浮在内容上方，列表末尾用等高的 [SliverPadding] 保证最后
  /// 一行仍能滚到胶囊上面来。
  ///
  /// 底栏真实显示条件是 `isRootTabPage && controller.value < 2`
  /// （navigation_bar.dart shouldShowBottomBar）：宽屏侧栏模式
  /// controller.value >= 2 时只有左侧栏、没有悬浮 dock，按 bottomBarHeight
  /// 让位会凭空把胶囊抬高约 100dp。
  double _pageBarBottomInset() {
    final pane = context.findAncestorStateOfType<NaviPaneState>();
    final showDock = pane != null &&
        pane.isRootTabPage &&
        pane.controller.value < 2;
    if (showDock) {
      // bottomBarHeight 已含系统手势区；再补一段呼吸，让胶囊底边完全离开
      // dock 的玻璃体（实测旧版仍重叠约 15dp）。
      return pane.bottomBarHeight + kcPageBottomGap;
    }
    // 子页面没有 dock：只要避开系统手势区再留一点呼吸。原实现无 dock 也照叠
    // kcPageBottomGap + kcSpaceLg 两段，胶囊下方空出约 56dp 纯白，正是
    // 「连着一大片空白」的另一半来源。
    return context.padding.bottom + kcSpaceSm;
  }

  /// 胶囊本体 + 底部让位，由 [buildPagingMode] 以 [Positioned] 悬浮。
  Widget _buildPageBar() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: _pageBarBottomInset()),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kcPillRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: cs.brightness == Brightness.dark ? 0.32 : 0.14,
                ),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: _buildPageSelector(),
        ),
      ),
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
            _error = friendlySourceError(res.errorMessage);
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
    //
    // 错误态一并藏掉：主体此时整屏是重试提示，底栏还挂着「页面 1 / ?」和两颗
    // 箭头，点了只会再失败一次 —— 是死控件，还占了错误说明的垂直空间。
    if (!_showPageBar) {
      return body;
    }
    // 胶囊是 overlay，不再吃掉一整条底部布局高度：网格可以铺到屏幕底边，
    // 原先那片跟着胶囊出现的白色底板随之消失。
    return Stack(
      children: [
        Positioned.fill(child: body),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildPageBar(),
        ),
      ],
    );
  }

  /// 分页条是否可见（body 末尾要按它预留等高滚动余量）。
  bool get _showPageBar => _maxPage != 1 && _error == null;

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
    // 分页模式同理：本页 0 条时别让用户对着白屏。分页胶囊由外层 Stack 负责，
    // 这里只替换主体，翻页箭头仍然可用。
    if (_data[_page]!.isEmpty && _error == null && _loading[_page] != true) {
      return Column(
        children: [
          if (widget.errorLeading != null) widget.errorLeading!,
          Expanded(child: EmptyState(title: "No results".tl)),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: kcBrandAdaptive(context),
      child: SmoothCustomScrollView(
        // SmoothCustomScrollView 默认会在末尾再补一段 context.padding.bottom；
        // 悬浮胶囊的让位 [inset] 本身已经含了系统底部 padding，有胶囊时关掉
        // 自动让位，避免两段叠加把最后一行推得离胶囊太远。无胶囊时保留默认。
        bottomPadding: _showPageBar ? 0 : null,
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
          if (_showPageBar)
            // 胶囊悬浮后不再压缩视口，末尾补一段不少于胶囊占位的空白，最后
            // 一行仍能滚到胶囊上方完整露出，不会被永久压在胶囊底下。
            SliverPadding(
              padding: EdgeInsets.only(
                bottom: _pageBarBottomInset() + kcPagerPillHeight + kcSpaceSm,
              ),
            ),
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
    final allComics = _data.values.expand((element) => element).toList();
    // 源返回「0 条」时 `_data[page]` 是**空列表**（不是 null）：不满足上面的
    // 骨架分支，`_maxPage` 又被 `??= page` 定成 1，把底部的「加载中」也关掉，
    // 于是整页纯白 —— 用户以为卡死（分类列表点进冷门标签的实测表现）。
    // 这里补一个明确空态，并保留顶部筛选条，让用户能直接换条件重试。
    if (allComics.isEmpty &&
        _error == null &&
        !_loading.values.any((element) => element)) {
      return SmoothCustomScrollView(
        key: enablePageStorage ? PageStorageKey('scroll$_page') : null,
        controller: widget.controller,
        slivers: [
          if (widget.leadingSliver != null) widget.leadingSliver!,
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(title: "No results".tl),
          ),
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

  /// 世代号：refresh() 自增作废在途的「加载更多」请求，见 [_loadNextPage]。
  int _refreshToken = 0;

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

  Future<void> _loadNextPage({int? token}) async {
    final requestToken = token ?? _refreshToken;
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
      // 刷新已经发生：这一页属于上一世代，直接丢弃（否则旧的第 2 页会被
      // 追加到新列表里，或把空列表填成「从中间开始」）。
      if (requestToken != _refreshToken) return;
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
    // 刷新与「加载更多」可能同时在跑：以前 refresh 先清空列表，再调
    // _loadNextPage()，而后者开头有 `if (_isLoading) return;` —— 在途请求
    // 存在时直接返回，列表被清空却不会重拉第一页；旧请求回来又把第 2 页
    // 塞进空列表，页面就变成「从第 31 条开始」。
    // 用世代号作废旧请求，并清掉 _isLoading 让本次重拉真正执行。
    final token = ++_refreshToken;
    _comics.clear();
    _heroIDs.clear();
    _favoriteStatus.clear();
    _historyStatus.clear();
    _hasMore = true;
    _initialized = false;
    _error = null;
    _isLoading = false;
    await _loadNextPage(token: token);
  }

  @override
  Widget build(BuildContext context) {
    // Initial loading state
    if (!_initialized && _isLoading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: KcPageLoading(),
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
      builder: (context, _) => _kcCenteredGridSliver(SliverGrid(
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
              // 分页「加载更多」曾经是这里唯一还在转圈的列表底部：同一个文件
              // 里 2157 行的另一条列表已经用 ListLoadingIndicator 爬小人了，
              // 两个网格滚到底看到的却是两套动画。
              return const ListLoadingIndicator();
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
          return _SelectableComicCell(
            key: ValueKey(comic.id),
            selected: isSelected,
            child: tile,
          );
        }, childCount: _comics.length + (showFooter ? 1 : 0)),
        gridDelegate: SliverGridDelegateWithComics(
                textScale:
                    MediaQuery.textScalerOf(context).scale(kcBody) / kcBody,
              ),
      )),
    );
  }
}
