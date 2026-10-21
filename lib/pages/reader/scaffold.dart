part of 'reader.dart';

class _ReaderScaffold extends StatefulWidget {
  const _ReaderScaffold({required this.child});

  final Widget child;

  @override
  State<_ReaderScaffold> createState() => _ReaderScaffoldState();
}

class _ReaderScaffoldState extends State<_ReaderScaffold>
    with AutoListenMixin {
  bool _isOpen = false;

  // 顶栏的「最小高度」基准。真实高度见 [topBarHeight]：系统字号放大后
  // 标题 + 章节副标题两行会超过 56dp，此时顶栏必须跟着长高。
  static const kTopBarHeight = 56.0;

  // 底栏内容高度：原先 125dp，但实际内容（两行 40dp 按钮）只有 ~88dp，
  // 多出的空白让整条工具栏显得又高又空、压缩阅读区。收紧到 100dp。
  static const kBottomBarHeight = 100.0;

  // 横屏时竖向空间本来就紧张，底栏再吃掉 100dp 会让漫画只剩窄窄一条。
  // 横屏改为单行（翻章按钮 + 进度条 + 功能按钮横排），高度压到 56dp。
  static const kLandscapeBottomBarHeight = 56.0;

  /// 当前实际使用的底栏高度（横屏单行 / 竖屏两行）。
  ///
  /// [build] 的收起位移与手势层的点击区域判定（gesture.dart）都必须用它，
  /// 不能用常量，否则横屏下会出现「点了底栏却翻页」的穿透。
  double get bottomBarHeight =>
      MediaQuery.of(context).orientation == Orientation.landscape
          ? kLandscapeBottomBarHeight
          : kBottomBarHeight;

  /// 当前章节标题（章节数据缺失时为 null）。
  String? get _currentEpName =>
      context.reader.widget.chapters?.titles.elementAtOrNull(
        context.reader.chapter - 1,
      );

  /// 顶栏实际高度。
  ///
  /// 顶栏内容在「书名 + 章节副标题」两行时高度随系统字号线性增长
  /// （fs1.0 约 39dp，fs2.0 约 78dp）。原先写死 56dp，于是 fs≥1.5 起就
  /// RenderFlex 下溢（fs2.0 实测 BOTTOM OVERFLOWED BY 22 PIXELS，副标题整行被裁）。
  /// 这里按当前 textScaler 估算内容高度并取 [kTopBarHeight] 为下限。
  ///
  /// 注意：build() 已不再给 AnimatedPositioned 传 height —— 真实高度由内容
  /// 决定，本 getter 只用于「收起」动画的位移量，估算偏差最多让动画多移一点。
  double get topBarHeight {
    final scaler = MediaQuery.textScalerOf(context);
    final content = _currentEpName == null
        ? scaler.scale(kcSectionTitle) * kcLineHeightFactor
        : scaler.scale(kcSubtitle) * kcLineHeightFactor +
            scaler.scale(kcCaption) * kcLineHeightFactor;
    final estimated = content + 8;
    return estimated > kTopBarHeight ? estimated : kTopBarHeight;
  }

  /// 横屏时底栏排成单行。
  bool get _isLandscape =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  bool get isOpen => _isOpen;

  bool get isReversed =>
      context.reader.mode == ReaderMode.galleryRightToLeft ||
      context.reader.mode == ReaderMode.continuousRightToLeft;

  _ReaderGestureDetectorState? _gestureDetectorState;

  _DragListener? _imageFavoriteDragListener;

  void addDragListener() async {
    if (!mounted) return;
    var readerMode = context.reader.mode;

    // 横向阅读的时候, 如果纵向滑就触发收藏, 纵向阅读的时候, 如果横向滑动就触发收藏
    if (appdata.settings['quickCollectImage'] == 'Swipe') {
      if (_imageFavoriteDragListener == null) {
        double distance = 0;
        _imageFavoriteDragListener = _DragListener(
          onMove: (offset) {
            switch (readerMode) {
              case ReaderMode.continuousTopToBottom:
              case ReaderMode.galleryTopToBottom:
                distance += offset.dx;
              case ReaderMode.continuousLeftToRight:
              case ReaderMode.galleryLeftToRight:
              case ReaderMode.galleryRightToLeft:
              case ReaderMode.continuousRightToLeft:
                distance += offset.dy;
            }
          },
          onEnd: () {
            if (distance.abs() > 150) {
              addImageFavorite();
            }
            distance = 0;
          },
        );
      }
      _gestureDetectorState!.addDragListener(_imageFavoriteDragListener!);
    } else if (_imageFavoriteDragListener != null) {
      _gestureDetectorState!.removeDragListener(_imageFavoriteDragListener!);
    }
  }

  @override
  void initState() {
    sliderFocus.canRequestFocus = false;
    listen(sliderFocus, () {
      if (sliderFocus.hasFocus) {
        sliderFocus.nextFocus();
      }
    });
    if (rotation != null) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    // Apply keep screen on
    if (appdata.settings['keepScreenOn'] == true) {
      WakelockPlus.enable();
    }
    // Apply screen orientation
    _applyScreenOrientation();
    super.initState();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      addDragListener();
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    // Restore orientation to follow system
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (_imageFavoriteDragListener != null &&
        _gestureDetectorState?.mounted == true) {
      _gestureDetectorState!.removeDragListener(_imageFavoriteDragListener!);
    }
    sliderFocus.dispose();
    super.dispose();
  }

  void _applyScreenOrientation() {
    var orientation = appdata.settings['screenOrientation'] ?? 'unspecified';
    switch (orientation) {
      case 'portrait':
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      case 'landscape':
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      default:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
    }
  }

  void openOrClose() {
    setState(() {
      _isOpen = !_isOpen;
    });
    // 打开/关闭都遵循「隐藏系统状态栏」设置，避免翻页时状态栏突然弹出。
    // 用 immersiveSticky：普通 immersive 会被旋转等配置变更重置。
    if (!appdata.settings['showSystemStatusBar']) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  bool? rotation;

  void update() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isOnChapterCommentsPage = context.reader.isOnChapterCommentsPage;
    return Stack(
      children: [
        Positioned.fill(
          child: AbsorbPointer(
            absorbing: context.reader.isPageAnimating,
            child: widget.child,
          ),
        ),
        // 页码 / 时钟 / 电量是「无工具栏时的 HUD」：它固定在屏幕左下、右下
        // （bottom: 13），而底栏打开后正好盖住这两处。以前底栏是 0.6 薄玻璃，
        // HUD 会从底栏后面透出来，看着像文字重叠的渲染错误；工具栏打开期间
        // 直接隐藏，两者永不共存。
        if (!_isOpen) ...[
          if (appdata.settings['showPageNumberInReader'] == true &&
              !isOnChapterCommentsPage)
            buildPageInfoText(),
          if (!isOnChapterCommentsPage) buildStatusInfo(),
        ],
        AnimatedPositioned(
          duration: AppAnimations.duration(const Duration(milliseconds: 180)),
          top: _isOpen ? 0 : -(topBarHeight + context.padding.top),
          left: 0,
          right: 0,
          // 不传 height：顶栏高度必须由内容决定，否则放大系统字号后
          // 「书名 + 章节副标题」两行会撑破固定高度而被裁（见 topBarHeight）。
          child: buildTop(),
        ),
        AnimatedPositioned(
          duration: AppAnimations.duration(const Duration(milliseconds: 180)),
          bottom: _isOpen
              ? 0
              : -(bottomBarHeight + MediaQuery.of(context).padding.bottom),
          left: 0,
          right: 0,
          child: buildBottom(),
        ),
      ],
    );
  }

  Widget buildTop() {
    final epName = _currentEpName;

    // 阅读器不做玻璃 —— 全站唯一一处刻意「不合群」的界面。
    //
    // 玻璃质感依赖一个稳定的底：导航栏背后是列表和封面，颜色分布可预期，
    // 6% 的透光只加一层氛围。阅读器背后是任意黑白漫画页：同一块蒙层在白页
    // 上是「一层雾」，压到黑底网点页上又变成「一层灰膜」，同一条顶栏会随翻页
    // 不停变色，书名/章节名的对比度也跟着飘。0.6 时页码和标题直接糊进画面；
    // 即使提到 0.94，纯黑页边缘仍能透出 8 级灰差。
    //
    // 所以这里 `blurSigma: 0` + 实心 surface：换成一块边界明确、对比恒定的
    // 界面层，同时省掉整帧 BackdropFilter 的开销。
    return BlurEffect(
      blurSigma: 0,
      child: Container(
        padding: EdgeInsets.only(top: context.padding.top),
        decoration: BoxDecoration(
          color: context.colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: context.colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: context.padding.left,
            right: context.padding.right,
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              const BackButton(),
              const SizedBox(width: 8),
              Expanded(
                child: epName == null ? Text(
                  context.reader.widget.name,
                  style: TextStyle(fontSize: kcSectionTitle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ) : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      context.reader.widget.name,
                      style: TextStyle(fontSize: kcSubtitle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      epName,
                      style: TextStyle(fontSize: kcCaption),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (shouldShowChapterComments())
                Tooltip(
                  message: "Chapter Comments".tl,
                  child: IconButton(
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedComment01, size: 20),
                    onPressed: openChapterComments,
                  ),
                ),
              if (context.reader.widget.forCoverSelection)
                Tooltip(
                  message: "Set as Cover".tl,
                  child: IconButton(
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedImage02, size: 20),
                    onPressed: pickPageForCover,
                  ),
                ),
              Tooltip(
                message: "Settings".tl,
                child: IconButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings01, size: 20),
                  onPressed: openSetting,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  bool isLiked() {
    return ImageFavoriteManager().has(
      context.reader.cid,
      context.reader.type.sourceKey,
      context.reader.eid,
      context.reader.page,
      context.reader.chapter,
    );
  }

  void addImageFavorite() async {
    try {
      var images = context.reader.images;
      if (images == null || images.isEmpty) return;
      if (images[0].contains('file://')) {
        showToast(
          message: "Local comic collection is not supported at present".tl,
          context: context,
        );
        return;
      }
      String id = context.reader.cid;
      int ep = context.reader.chapter;
      String eid = context.reader.eid;
      String title = context.reader.history!.title;
      String subTitle = context.reader.history!.subtitle;
      int maxPage = context.reader.images!.length;
      int? page = await selectImage();
      if (page == null) return;
      page += 1;
      String sourceKey = context.reader.type.sourceKey;
      String imageKey = context.reader.images![page - 1];
      List<String> tags = context.reader.widget.tags;
      String author = context.reader.widget.author;

      var epName =
          context.reader.widget.chapters?.titles.elementAtOrNull(
            context.reader.chapter - 1,
          ) ??
          "E${context.reader.chapter}";
      var translatedTags = tags.map((e) => e.translateTagIfNeed).toList();

      if (isLiked()) {
        if (page == firstPage) {
          showToast(
            message: "The cover cannot be uncollected here".tl,
            context: context,
          );
          return;
        }
        ImageFavoriteManager().deleteImageFavorite([
          ImageFavorite(page, imageKey, null, eid, id, ep, sourceKey, epName),
        ]);
        showToast(
          message: "Uncollected the image".tl,
          context: context,
          seconds: 1,
        );
      } else {
        var imageFavoritesComic =
            ImageFavoriteManager().find(id, sourceKey) ??
            ImageFavoritesComic(
              id,
              [],
              title,
              sourceKey,
              tags,
              translatedTags,
              DateTime.now(),
              author,
              {},
              subTitle,
              maxPage,
            );
        ImageFavorite imageFavorite = ImageFavorite(
          page,
          imageKey,
          null,
          eid,
          id,
          ep,
          sourceKey,
          epName,
        );
        ImageFavoritesEp? imageFavoritesEp = imageFavoritesComic
            .imageFavoritesEp
            .firstWhereOrNull((e) {
              return e.ep == ep;
            });
        if (imageFavoritesEp == null) {
          if (page != firstPage) {
            var copy = imageFavorite.copyWith(
              page: firstPage,
              isAutoFavorite: true,
              imageKey: context.reader.images![0],
            );
            // 不是第一页的话, 自动塞一个封面进去
            imageFavoritesEp = ImageFavoritesEp(
              eid,
              ep,
              [copy, imageFavorite],
              epName,
              maxPage,
            );
          } else {
            imageFavoritesEp = ImageFavoritesEp(
              eid,
              ep,
              [imageFavorite],
              epName,
              maxPage,
            );
          }
          imageFavoritesComic.imageFavoritesEp.add(imageFavoritesEp);
        } else {
          if (imageFavoritesEp.eid != eid) {
            // 空字符串说明是从pica导入的, 那我们就手动刷一遍保证一致
            if (imageFavoritesEp.eid == "") {
              imageFavoritesEp.eid = eid;
            } else {
              // 避免多章节漫画源的章节顺序发生变化, 如果情况比较多, 做一个以eid为准更新ep的功能
              showToast(
                message:
                    "The chapter order of the comic may have changed, temporarily not supported for collection"
                        .tl,
                context: context,
              );
              return;
            }
          }
          imageFavoritesEp.imageFavorites.add(imageFavorite);
        }

        ImageFavoriteManager().addOrUpdateOrDelete(imageFavoritesComic);
        showToast(
          message: "Successfully collected".tl,
          context: context,
          seconds: 1,
        );
      }
      update();
    } catch (e, stackTrace) {
      Log.error("Image Favorite", e, stackTrace);
      showToast(message: "Failed to favorite image".tl, context: context, seconds: 1);
    }
  }

  void _toggleRotation() {
    if (rotation == null) {
      setState(() => rotation = false);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      showToast(message: "Portrait lock enabled".tl, context: context, seconds: 1);
    } else if (rotation == false) {
      setState(() => rotation = true);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      showToast(message: "Landscape lock enabled".tl, context: context, seconds: 1);
    } else {
      setState(() => rotation = null);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      showToast(message: "Rotation unlocked".tl, context: context, seconds: 1);
    }
  }

  void _toggleAutoPage() {
    var wasOn = context.reader.autoPageTurningTimer != null;
    context.reader.autoPageTurning(
      context.reader.cid,
      context.reader.type,
    );
    update();
    showToast(
      message: wasOn ? "Auto page turning stopped".tl : "Auto page turning started".tl,
      context: context,
      seconds: 1,
    );
  }

  /// 低频操作收进"更多"溢出菜单，底栏只保留常用 4 项。
  Widget _buildMoreMenu() {
    return Tooltip(
      message: "More".tl,
      child: PopupMenuButton<String>(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedMoreHorizontal, size: 24),
        onSelected: (v) {
          switch (v) {
            case 'rotate':
              _toggleRotation();
            case 'autopage':
              _toggleAutoPage();
            case 'fullscreen':
              context.reader.fullscreen();
          }
        },
        itemBuilder: (_) => [
          if (App.isAndroid)
            PopupMenuItem(
              value: 'rotate',
              child: Row(
                children: [
                  HugeIcon(
                    icon: rotation == null
                        ? HugeIcons.strokeRoundedRotate01
                        : HugeIcons.strokeRoundedPhoneLock,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    rotation == null
                        ? "Screen Rotation".tl
                        : rotation == false
                            ? "Locked: Portrait".tl
                            : "Locked: Landscape".tl,
                  ),
                ],
              ),
            ),
          PopupMenuItem(
            value: 'autopage',
            child: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedTimer01,
                  size: 20,
                  color: context.reader.autoPageTurningTimer != null
                      ? Colors.green
                      : null,
                ),
                const SizedBox(width: 12),
                Text(
                  context.reader.autoPageTurningTimer != null
                      ? "${"Auto Page Turning".tl} (${"On".tl})"
                      : "Auto Page Turning".tl,
                ),
              ],
            ),
          ),
          if (App.isDesktop)
            PopupMenuItem(
              value: 'fullscreen',
              child: Row(
                children: [
                  HugeIcon(icon: HugeIcons.strokeRoundedFullScreen, size: 20),
                  const SizedBox(width: 12),
                  Text("${"Full Screen".tl}(F12)"),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget buildBottom() {
    // Use maxPage for display (excluding chapter comments page)
    final displayPage = context.reader.page.clamp(1, context.reader.maxPage);
    var text = "E${context.reader.chapter} : P$displayPage";
    if (context.reader.widget.chapters == null) {
      text = "P$displayPage";
    }

    final buttons = [
      Tooltip(
        message: isLiked() ? "Favorited".tl : "Collect the image".tl,
        child: IconButton(
          // 已收藏用 Material 实心红心，与漫画详情页收藏按钮
          // (comic_details_page/comic_page.dart 的 activeIcon) 保持一致的视觉语言。
          icon: isLiked()
              ? Icon(Icons.favorite, size: 24, color: kcBrandAdaptive(context))
              : HugeIcon(icon: HugeIcons.strokeRoundedFavourite, size: 24),
          onPressed: addImageFavorite,
          style: isLiked()
              ? IconButton.styleFrom(
                  backgroundColor: kcBrandAdaptive(context).withValues(alpha: 0.12),
                )
              : null,
        ),
      ),
      if (context.reader.widget.chapters != null)
        Tooltip(
          message: "Chapters".tl,
          child: IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedBook01, size: 24),
            onPressed: openChapterDrawer,
          ),
        ),
      Tooltip(
        message: "Save Image".tl,
        child: IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 24),
          onPressed: saveCurrentImage,
        ),
      ),
      Tooltip(
        message: "Share".tl,
        child: IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedShare01, size: 24),
          onPressed: share,
        ),
      ),
      _buildMoreMenu(),
    ];

    // 单页章节时进度条不渲染（max-min<=0），页码胶囊顶上，避免信息丢失。
    final showPageChip = context.reader.maxPage <= 1;

    Widget child = SizedBox(
      height: bottomBarHeight,
      child: _isLandscape
          ? _buildLandscapeBar(buttons, text)
          : Column(
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      _chapterJumpButton(false),
                      Expanded(child: buildSlider()),
                      _chapterJumpButton(true),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                // 功能键行：进度条已写明「章节名 · 页码」，此处不再重复页码胶囊，
                // 5 个键均分整行，图标 24dp、点击区 48dp。
                Expanded(
                  child: showPageChip
                      ? Row(
                          children: [
                            _buildPageChip(text).paddingLeft(16),
                            const Spacer(),
                            for (var button in buttons) _bottomAction(button),
                            const SizedBox(width: 8),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (var button in buttons) _bottomAction(button),
                          ],
                        ),
                ),
              ],
            ),
    );

    // 与顶栏同一块实心 surface：底栏承载进度条、页码胶囊和 6 个功能键，背景
    // 必须是稳定底，否则漫画网点会从按钮缝隙里透出来（0.6 玻璃版实测很脏）。
    return BlurEffect(
      blurSigma: 0,
      child: Container(
        decoration: BoxDecoration(
          color: context.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: context.colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
        ),
        padding: EdgeInsets.only(bottom: context.padding.bottom),
        child: Padding(
          padding: EdgeInsets.only(
            left: context.padding.left,
            right: context.padding.right,
          ),
          child: child,
        ),
      ),
    );
  }

  /// 功能键外壳：底栏本身不是 Material，不套一层的话 IconButton 的水波纹会画到
  /// 底色下面（完全看不见）。裁成圆形，和左右翻章按钮的观感一致。
  Widget _bottomAction(Widget button) {
    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: const CircleBorder(),
      child: button,
    );
  }

  /// 翻章按钮。[forward]=true 为下一章；阅读方向反转（右到左）时对调。
  Widget _chapterJumpButton(bool forward) {
    return IconButton.filledTonal(
      onPressed: () {
        final reader = context.reader;
        final wantNext = isReversed ? !forward : forward;
        if (wantNext) {
          if (reader.chapter < reader.maxChapter) {
            reader.toNextChapter();
          } else {
            reader.toPage(reader.maxPage);
          }
        } else {
          if (reader.chapter > 1) {
            reader.toPrevChapter();
          } else {
            reader.toPage(1);
          }
        }
      },
      icon: HugeIcon(
        icon: forward
            ? HugeIcons.strokeRoundedForward01
            : HugeIcons.strokeRoundedBackward01,
        size: 22,
      ),
    );
  }

  /// 页码胶囊（"E1 : P5"）。
  Widget _buildPageChip(String text) {
    return Container(
      height: 24,
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(kcRadius8),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onTertiaryContainer,
          ),
        ),
      ),
    );
  }

  /// 横屏单行底栏：翻章按钮 + 进度条 + 页码 + 功能按钮全部横排，
  /// 把竖向占用从 100dp 压到 [kLandscapeBottomBarHeight]（56dp）。
  Widget _buildLandscapeBar(List<Widget> buttons, String text) {
    return LayoutBuilder(
      builder: (context, constrains) {
        // 极窄横屏（小平板、折叠屏外屏）优先保证按钮不溢出，页码让位
        // —— 章节名与进度本来就在进度条上显示，丢掉页码不损失信息。
        final compact = constrains.maxWidth < 640;
        return Row(
          children: [
            const SizedBox(width: 8),
            _chapterJumpButton(false),
            Expanded(child: buildSlider()),
            _chapterJumpButton(true),
            const SizedBox(width: 8),
            if (!compact)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _buildPageChip(text),
              ),
            for (var button in buttons)
              SizedBox(width: 48, height: 48, child: button),
            const SizedBox(width: 8),
          ],
        );
      },
    );
  }

  var sliderFocus = FocusNode();

  Widget buildSlider() {
    final displayPage = context.reader.page.clamp(1, context.reader.maxPage);
    final maxPage = context.reader.maxPage;
    var epName =
        context.reader.widget.chapters?.titles.elementAtOrNull(
          context.reader.chapter - 1,
        ) ??
        "E${context.reader.chapter}";
    // 章节标题常带「[繁体]」「[简体]」这类尾部标签。进度胶囊很窄，先去掉这些
    // 元数据标签再按长度截断，否则会截出「[繁体…」这种缺右括号的残缺标签。
    epName = epName
        .replaceFirst(RegExp(r"\s*[\[［][^\]］]*[\]］]\s*$"), "")
        .trim();
    if (epName.length > 14) {
      epName = "${epName.substring(0, 14)}...";
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 48,
        child: CustomSlider(
          focusNode: sliderFocus,
          value: displayPage.toDouble(),
          min: 1,
          max: maxPage.clamp(displayPage, 1 << 16).toDouble(),
          reversed: isReversed,
          divisions: (maxPage - 1).clamp(2, 1 << 16),
          chapterText: epName,
          onChanged: (i) {
            context.reader.toPage(i.toInt());
          },
        ),
      ),
    );
  }

  Widget buildPageInfoText() {
    var epName =
        context.reader.widget.chapters?.titles.elementAtOrNull(
          context.reader.chapter - 1,
        ) ??
        "E${context.reader.chapter}";
    if (epName.length > 8) {
      epName = "${epName.substring(0, 8)}...";
    }
    var pageText = "${context.reader.page}/${context.reader.maxPage}";
    var remaining = context.reader.estimatedRemainingSeconds;
    var timeText = remaining > 0 ? "  ~${(remaining / 60).ceil()}${"min".tl}" : "";
    var text = context.reader.widget.chapters != null
        ? "$epName : $pageText$timeText"
        : "$pageText$timeText";

    return Positioned(
      bottom: 13,
      left: 25,
      child: Stack(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: kcBody,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.4
                ..color = context.colorScheme.onInverseSurface,
            ),
          ),
          Text(
            text,
            style: TextStyle(
              fontSize: kcBody,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black54,
                  blurRadius: 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildStatusInfo() {
    if (appdata.settings['enableClockAndBatteryInfoInReader']) {
      return Positioned(
        bottom: 13,
        right: 25,
        child: Row(
          children: [
            _ClockWidget(),
            const SizedBox(width: 10),
            _BatteryWidget(),
          ],
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  void openChapterDrawer() {
    showCenteredPanel(
      context,
      context.reader.widget.chapters!.isGrouped
          ? _GroupedChaptersView(context.reader)
          : _ChaptersView(context.reader),
    );
  }

  void saveCurrentImage() async {
    var result = await selectImageToData();
    if (result == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    var (imageIndex, data) = result;
    // 弹窗要显示「原格式」下的真实后缀，先嗅探一次（带上图片 URL 兜底：
    // 极少数图片没有可识别头部，但 URL 上的扩展名可信）。
    final hint = imageIndex >= 0 && imageIndex < (context.reader.images?.length ?? 0)
        ? context.reader.images![imageIndex]
        : null;
    final originalExt = detectImageExt(data, nameHint: hint);
    // 先让用户确认文件名（默认「漫画名_EP{话数}_P{页数}」）与输出格式再决定是否重新编码。
    final choice = await showImageSaveDialog(
      context,
      initialName: buildImageSaveName(
        comicTitle: context.reader.widget.name,
        ep: context.reader.chapter,
        page: imageIndex + 1,
      ),
      originalExt: originalExt,
    );
    if (choice == null) {
      return;
    }
    final saved = await prepareImageForSave(data, choice.format);
    saveFile(data: saved.data, filename: "${choice.name}${saved.type.ext}");
  }

  void share() async {
    try {
      final images = context.reader.images;
      if (images == null || images.isEmpty) {
        await Share.shareText(context.reader.widget.name);
        return;
      }
      final result = await Navigator.of(context).push<_ImagePickerResult?>(
        MaterialPageRoute(
          builder: (_) => _ChapterImagePickerPage(
            images: images,
            sourceKey: context.reader.type.sourceKey,
            cid: context.reader.cid,
            eid: context.reader.eid,
            currentPage: (context.reader.page - 1).clamp(0, images.length - 1),
            title: "Select Image to Share".tl,
            allowSelectAll: true,
          ),
        ),
      );
      if (!mounted || result == null) return;
      if (result.paths != null && result.paths!.isNotEmpty) {
        await Share.shareFiles(
          paths: result.paths!,
          mimeTypes: result.mimes,
        );
        return;
      }
      final imageIndex = result.index;
      final data = result.data;
      if (imageIndex == null || data == null) return;
      // 带上图片地址做兜底：极少数图片没有可识别头部，但 URL 上的扩展名可信。
      final hint = imageIndex >= 0 && imageIndex < images.length
          ? images[imageIndex]
          : null;
      var fileType = detectFileType(data, nameHint: hint);
      var filename =
          "${safeShareFileName(context.reader.widget.name)}_EP${context.reader.chapter}_P${imageIndex + 1}${fileType.ext}";
      await Share.shareFile(data: data, filename: filename, mime: fileType.mime);
    } catch (e) {
      // 不再退回「分享文字」—— 那会让用户拿到一段没法看的文本却以为分享成功。
      if (mounted) {
        showToast(message: "Failed to share image".tl, context: context);
      }
    }
  }

  void setAsCover() async {
    try {
      final images = context.reader.images;
      if (images == null || images.isEmpty) {
        showToast(message: "No images available".tl, context: context);
        return;
      }

      final result = await Navigator.of(context).push<_ImagePickerResult?>(
        MaterialPageRoute(
          builder: (_) => _ChapterImagePickerPage(
            images: images,
            sourceKey: context.reader.type.sourceKey,
            cid: context.reader.cid,
            eid: context.reader.eid,
            currentPage: (context.reader.page - 1).clamp(0, images.length - 1),
            title: "Select Cover".tl,
          ),
        ),
      );

      if (!mounted || result == null) return;
      final data = result.data!;

      final success = await CustomCoverManager.setCustomCover(
        context.reader.type.sourceKey,
        context.reader.cid,
        null,
        data: data,
      );

      if (!mounted) return;
      if (success) {
        showToast(
          message: "Cover updated successfully".tl,
          context: context,
          seconds: 1,
        );
        update();
      } else {
        showToast(
          message: "Failed to update cover".tl,
          context: context,
          seconds: 1,
        );
      }
    } catch (e, s) {
      if (!mounted) return;
      Log.error("Update cover", e, s);
      showToast(
        message: "Failed to update cover".tl,
        context: context,
        seconds: 1,
      );
    }
  }

  /// Opens the image picker from within the reader (cover-selection mode)
  /// and pops the reader after a successful cover update.
  void pickPageForCover() async {
    try {
      final images = context.reader.images;
      if (images == null || images.isEmpty) {
        showToast(message: "No images available".tl, context: context);
        return;
      }

      final result = await Navigator.of(context).push<_ImagePickerResult?>(
        MaterialPageRoute(
          builder: (_) => _ChapterImagePickerPage(
            images: images,
            sourceKey: context.reader.type.sourceKey,
            cid: context.reader.cid,
            eid: context.reader.eid,
            currentPage: (context.reader.page - 1).clamp(0, images.length - 1),
            title: "Select Cover".tl,
          ),
        ),
      );

      if (!mounted || result == null) return;
      final data = result.data!;

      final success = await CustomCoverManager.setCustomCover(
        context.reader.type.sourceKey,
        context.reader.cid,
        null,
        data: data,
      );

      if (!mounted) return;
      if (success) {
        showToast(
          message: "Cover updated successfully".tl,
          context: context,
          seconds: 1,
        );
        Navigator.of(context).pop();
      } else {
        showToast(
          message: "Failed to update cover".tl,
          context: context,
          seconds: 1,
        );
      }
    } catch (e, s) {
      if (!mounted) return;
      Log.error("Update cover", e, s);
      showToast(
        message: "Failed to update cover".tl,
        context: context,
        seconds: 1,
      );
    }
  }

  void openSetting() {
    showCenteredPanel(
      context,
      ReaderSettings(
        comicId: context.reader.cid,
        comicSource: context.reader.type.sourceKey,
        // 浮层面板卡片是 surfaceContainerHigh，头部必须同色才不会出现「贴纸」头。
        appbarColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        onChanged: (key) {
          if (key == "readerMode") {
            context.reader.mode = ReaderMode.fromKey(
              appdata.settings.getReaderSetting(
                context.reader.cid,
                context.reader.type.sourceKey,
                key,
              ),
            );
          }
          if (key == "enableTurnPageByVolumeKey") {
            if (appdata.settings.getReaderSetting(
              context.reader.cid,
              context.reader.type.sourceKey,
              key,
            )) {
              context.reader.handleVolumeEvent();
            } else {
              context.reader.stopVolumeEvent();
            }
          }
          if (key == "quickCollectImage") {
            addDragListener();
          }
          if (key == "showChapterComments" || key == "showChapterCommentsAtEnd") {
            update();
          }
          context.reader.update();
        },
      ),
    );
  }

  bool shouldShowChapterComments() {
    // Check if chapters exist
    if (context.reader.widget.chapters == null) return false;

    // Check if setting is enabled
    var showChapterComments = appdata.settings.getReaderSetting(
      context.reader.cid,
      context.reader.type.sourceKey,
      'showChapterComments',
    );
    if (showChapterComments != true) return false;

    // Check if comic source supports chapter comments
    var source = ComicSource.find(context.reader.type.sourceKey);
    if (source == null || source.chapterCommentsLoader == null) return false;

    return true;
  }

  void openChapterComments() {
    var source = ComicSource.find(context.reader.type.sourceKey);
    if (source == null) return;

    var chapters = context.reader.widget.chapters;
    if (chapters == null) return;

    var chapterIndex = context.reader.chapter - 1;
    var epId = chapters.ids.elementAt(chapterIndex);
    var chapterTitle = chapters.titles.elementAt(chapterIndex);

    Navigator.of(context).push(
      SideBarRoute(
        ChapterCommentsPage(
          comicId: context.reader.cid,
          epId: epId,
          source: source,
          comicTitle: context.reader.widget.name,
          chapterTitle: chapterTitle,
        ),
        width: 500,
      ),
    );
  }

  /// If there is only one image on screen, return it.
  ///
  /// If there are multiple images on screen,
  /// show a thumbnail grid to let the user select an image.
  ///
  /// The return value is the index of the selected image.
  Future<int?> selectImage() async {
    var reader = context.reader;
    var imageViewController = context.reader._imageViewController;

    bool needsSelection = false;
    int? singleImageIndex;
    List<int> imageIndices = [];

    if (imageViewController is _GalleryModeState) {
      var range = imageViewController.getCurrentPageImageRange();
      if (range != null) {
        var (startIndex, endIndex) = range;
        int actualImageCount = endIndex - startIndex;
        if (actualImageCount == 1) {
          needsSelection = false;
          singleImageIndex = startIndex;
        } else {
          needsSelection = true;
          for (int i = startIndex; i < endIndex; i++) {
            imageIndices.add(i);
          }
        }
      }
    } else if (imageViewController is _ContinuousModeState) {
      needsSelection = false;
      singleImageIndex = reader.page - 1;
    }

    if (!needsSelection && singleImageIndex != null) {
      return singleImageIndex;
    } else {
      // Show thumbnail grid for selection
      return await _showImageThumbnailGrid(imageIndices);
    }
  }

  /// Show a thumbnail grid for image selection
  Future<int?> _showImageThumbnailGrid(List<int> imageIndices) async {
    if (imageIndices.isEmpty) return null;
    
    int? selectedIndex;
    final thumbnailFutures = <String, Future<Uint8List?>>{};

    await showDialog(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: "Select an image".tl,
        contentPadding: ContentDialog.hPadding,
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: imageIndices.length,
            itemBuilder: (context, index) {
              final imageIndex = imageIndices[index];
              final imageKey = context.reader.images![imageIndex];
              
              return GestureDetector(
                onTap: () {
                  selectedIndex = imageIndex;
                  Navigator.of(dialogContext).pop();
                },
                child: FutureBuilder<Uint8List?>(
                  future: thumbnailFutures.putIfAbsent(imageKey, () => _loadThumbnail(imageKey)),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                          ),
                          if (selectedIndex == imageIndex)
                            const Positioned(
                              right: 4,
                              top: 4,
                              child: HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle01, size: 24, color: Colors.white),
                            ),
                        ],
                      );
                    } else {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          Button.text(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text("Cancel".tl),
          ),
        ],
      ),
    );
    
    return selectedIndex;
  }

  /// Load thumbnail data for an image
  Future<Uint8List?> _loadThumbnail(String imageKey) async {
    Uint8List? data;
    if (imageKey.startsWith("file://")) {
      try {
        data = await File(imageKey.substring(7)).readAsBytes();
      } catch (_) {}
    } else {
      try {
        var cache = await CacheManager().findCache(
          "$imageKey@${context.reader.type.sourceKey}@${context.reader.cid}@${context.reader.eid}",
        );
        if (cache != null) {
          data = await cache.readAsBytes();
        }
      } catch (_) {}
    }
    return data;
  }

  /// Same as [selectImage], but return the image data with its index.
  /// Returns (imageIndex, imageData) or null if cancelled.
  Future<(int, Uint8List)?> selectImageToData() async {
    var i = await selectImage();
    if (i == null) {
      return null;
    }
    var imageKey = context.reader.images![i];
    Uint8List? data;
    if (imageKey.startsWith("file://")) {
      try {
        data = await File(imageKey.substring(7)).readAsBytes();
      } catch (_) {}
    } else {
      // 尝试从缓存获取
      try {
        var cache = await CacheManager().findCache(
          "$imageKey@${context.reader.type.sourceKey}@${context.reader.cid}@${context.reader.eid}",
        );
        if (cache != null) {
          data = await cache.readAsBytes();
        }
      } catch (_) {}
    }
    if (data == null) {
      return null;
    }
    return (i, data);
  }
}

class _BatteryWidget extends StatefulWidget {
  @override
  _BatteryWidgetState createState() => _BatteryWidgetState();
}

class _BatteryWidgetState extends State<_BatteryWidget> {
  late Battery _battery;
  late int _batteryLevel = 100;
  Timer? _timer;
  bool _hasBattery = false;
  BatteryState state = BatteryState.unknown;

  @override
  void initState() {
    super.initState();
    _battery = Battery();
    _checkBatteryAvailability();
  }

  void _checkBatteryAvailability() async {
    try {
      _batteryLevel = await _battery.batteryLevel;
      if (!mounted) return;
      state = await _battery.batteryState;
      if (!mounted) return;
      if (_batteryLevel > 0 && state != BatteryState.unknown) {
        if (!mounted) return;
        setState(() {
          _hasBattery = true;
        });
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          _battery.batteryLevel.then((level) {
            if (!mounted) {
              timer.cancel();
              return;
            }
            if (_batteryLevel != level) {
              setState(() {
                _batteryLevel = level;
              });
            }
          });
        });
      }
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasBattery) {
      return const SizedBox.shrink(); //Empty Widget
    }
    return _batteryInfo(_batteryLevel);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _batteryInfo(int batteryLevel) {
    Widget batteryIcon;

    if (state == BatteryState.charging) {
      batteryIcon = HugeIcon(icon: HugeIcons.strokeRoundedBatteryCharging01, size: 16, color: context.colorScheme.onSurface);
    } else if (batteryLevel >= 96) {
      batteryIcon = HugeIcon(icon: HugeIcons.strokeRoundedBatteryFull, size: 16, color: context.colorScheme.onSurface);
    } else if (batteryLevel >= 84) {
      batteryIcon = HugeIcon(icon: HugeIcons.strokeRoundedBatteryFull, size: 16, color: context.colorScheme.onSurface);
    } else if (batteryLevel >= 72) {
      batteryIcon = HugeIcon(icon: HugeIcons.strokeRoundedBatteryFull, size: 16, color: context.colorScheme.onSurface);
    } else if (batteryLevel >= 60) {
      batteryIcon = HugeIcon(icon: HugeIcons.strokeRoundedBatteryLow, size: 16, color: context.colorScheme.onSurface);
    } else if (batteryLevel >= 48) {
      batteryIcon = HugeIcon(icon: HugeIcons.strokeRoundedBatteryLow, size: 16, color: context.colorScheme.onSurface);
    } else if (batteryLevel >= 36) {
      batteryIcon = HugeIcon(icon: HugeIcons.strokeRoundedBatteryEmpty, size: 16, color: context.colorScheme.onSurface);
    } else if (batteryLevel >= 24) {
      batteryIcon = HugeIcon(icon: HugeIcons.strokeRoundedBatteryEmpty, size: 16, color: context.colorScheme.onSurface);
    } else if (batteryLevel >= 12) {
      batteryIcon = HugeIcon(icon: HugeIcons.strokeRoundedBatteryEmpty, size: 16, color: context.colorScheme.onSurface);
    } else {
      batteryIcon = HugeIcon(icon: HugeIcons.strokeRoundedBatteryLow, size: 16, color: Colors.red);
    }

    return Row(
      children: [
        batteryIcon,
        Stack(
          children: [
            Text(
              '$batteryLevel%',
              style: TextStyle(
                fontSize: kcBody,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.4
                  ..color = context.colorScheme.onInverseSurface,
              ),
            ),
            Text('$batteryLevel%'),
          ],
        ),
      ],
    );
  }
}

class _ClockWidget extends StatefulWidget {
  @override
  _ClockWidgetState createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<_ClockWidget> {
  late String _currentTime;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _currentTime = _getCurrentTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      final time = _getCurrentTime();
      if (_currentTime != time) {
        setState(() {
          _currentTime = time;
        });
      }
    });
  }

  String _getCurrentTime() {
    final now = DateTime.now();
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text(
          _currentTime,
          style: TextStyle(
            fontSize: kcBody,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = context.colorScheme.onInverseSurface,
          ),
        ),
        Text(_currentTime),
      ],
    );
  }
}

/// Result of the image picker.
/// When [all] is true, [allPaths] holds temp file paths for every page.
class _ImagePickerResult {
  final int? index;
  final Uint8List? data;
  /// Multi-select share: temp file paths of all selected pages.
  final List<String>? paths;
  /// 与 [paths] 一一对应的 mime，用于分享时显式声明类型。
  final List<String>? mimes;
  const _ImagePickerResult({this.index, this.data, this.paths, this.mimes});
}

/// Full-screen image picker that lets the user browse all pages in the
/// current chapter.
/// - Single mode ([allowSelectAll] = false): tap a page to pick it (e.g. cover).
/// - Multi mode ([allowSelectAll] = true): tap to toggle selection, then share
///   the selected pages from the bottom action bar.
class _ChapterImagePickerPage extends StatefulWidget {
  final List<String> images;
  final String sourceKey;
  final String cid;
  final String eid;
  final int currentPage;
  final String title;
  final bool allowSelectAll;

  const _ChapterImagePickerPage({
    required this.images,
    required this.sourceKey,
    required this.cid,
    required this.eid,
    required this.currentPage,
    this.title = "Select Cover",
    this.allowSelectAll = false,
  });

  @override
  State<_ChapterImagePickerPage> createState() => _ChapterImagePickerPageState();
}

class _ChapterImagePickerPageState extends State<_ChapterImagePickerPage> {
  /// Cache futures so FutureBuilder doesn't re-fetch on every rebuild.
  final Map<int, Future<Uint8List?>> _futures = {};
  bool _isLoadingFull = false;

  /// Multi-select mode (only used when [widget.allowSelectAll] is true).
  final Set<int> _selected = {};
  /// 在 [didChangeDependencies] 里用 initialScrollOffset 创建（需要 MediaQuery
  /// 的宽度来估算格子高度），因此这里先留空，build 时已必然初始化完毕。
  ScrollController? _scrollController;

  /// Images already held in memory: from cache preload OR on-demand download.
  final Map<int, Uint8List> _loadedImages = {};
  /// Indices whose image came from local cache (shown, but not in [_loadedImages]).
  final Set<int> _cachedLoaded = {};
  /// Indices currently being downloaded on demand (shows a spinner).
  final Set<int> _loading = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 首帧就用 initialScrollOffset 定位到当前页，而不是「先渲染第 1 行、再
    // post-frame jumpTo 跳过去」：后者会先解码一批马上被丢弃的缩略图，长章节
    // 打开时解码量直接翻倍（体感就是顿一下）。格子高度由 childAspectRatio 固定，
    // 偏移可以确定性估算。
    _scrollController ??= ScrollController(
      initialScrollOffset: _initialScrollOffset(
        MediaQuery.of(context).size.width,
      ),
    );
  }

  /// 估算「当前页所在行」的滚动偏移。几何必须与 [build] 里的 GridView 一致：
  /// padding 左右各 6、crossAxisSpacing / mainAxisSpacing 均为 8、
  /// crossAxisCount 3、childAspectRatio 0.72。
  double _initialScrollOffset(double width) {
    const padding = 6.0, spacing = 8.0, crossAxisCount = 3;
    final cellW =
        (width - padding * 2 - spacing * (crossAxisCount - 1)) / crossAxisCount;
    final cellH = cellW / 0.72;
    final rowH = cellH + spacing;
    final row = widget.currentPage ~/ crossAxisCount;
    return (row * rowH - padding).clamp(0.0, double.infinity);
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    super.dispose();
  }

  /// Load an image from local cache only — no network. Returns null when the
  /// page was never preloaded, so its cell stays a placeholder until the user
  /// taps it to fetch on demand.
  Future<Uint8List?> _loadImage(int index) {
    return _futures.putIfAbsent(index, () async {
      final imageKey = widget.images[index];
      if (imageKey.startsWith("file://")) {
        try {
          return await File(imageKey.substring(7)).readAsBytes();
        } catch (_) {
          return null;
        }
      }
      try {
        final cache = await CacheManager().findCache(
          "$imageKey@${widget.sourceKey}@${widget.cid}@${widget.eid}",
        );
        if (cache != null) {
          return await cache.readAsBytes();
        }
      } catch (_) {}
      return null;
    });
  }

  /// Download a single page on demand when the user taps its placeholder.
  /// Only this one page is fetched — never auto-load the whole chapter, which
  /// would blow up memory and traffic.
  Future<void> _loadOnDemand(int index, {bool autoSelect = true}) async {
    if (_loading.contains(index) || _loadedImages.containsKey(index)) return;
    setState(() => _loading.add(index));
    try {
      final imageKey = widget.images[index];
      Uint8List? data;
      if (imageKey.startsWith("file://")) {
        try {
          data = await File(imageKey.substring(7)).readAsBytes();
        } catch (_) {}
      } else {
        await for (final event in ImageDownloader.loadComicImage(
          imageKey,
          widget.sourceKey,
          widget.cid,
          widget.eid,
        )) {
          if (event.imageBytes != null) {
            data = event.imageBytes;
            break;
          }
        }
      }
      if (!mounted) return;
      if (data != null) {
        _loadedImages[index] = data;
        // Tapping a page to load it usually means the user wants it, so select it.
        if (autoSelect && widget.allowSelectAll) _selected.add(index);
      } else {
        showToast(message: "Failed to load image".tl, context: context);
      }
    } catch (e, s) {
      Log.error("Load reader image", e, s);
      if (mounted) showToast(message: "Failed to load image".tl, context: context);
    } finally {
      if (mounted) setState(() => _loading.remove(index));
    }
  }

  Future<void> _selectImage(int index) async {
    Uint8List? data = _loadedImages[index];
    if (data == null && _cachedLoaded.contains(index)) {
      data = await _loadImage(index);
    }
    if (data == null) {
      await _loadOnDemand(index, autoSelect: false);
      data = _loadedImages[index];
    }
    if (!mounted) return;
    if (data != null) {
      Navigator.of(context).pop(_ImagePickerResult(index: index, data: data));
    } else {
      showToast(message: "Failed to load image".tl, context: context);
    }
  }

  /// Load each selected page and share them as multiple temp files.
  /// Memory-safe: only one page's bytes are held in memory at a time.
  Future<void> _shareSelected() async {
    final indices = _selected.toList()..sort();
    if (indices.isEmpty) {
      showToast(message: "Select at least one page".tl, context: context);
      return;
    }
    setState(() => _isLoadingFull = true);
    try {
      final paths = <String>[];
      final mimes = <String>[];
      for (final i in indices) {
        // Prefer an already-in-memory image; fall back to cache, then a single
        // on-demand download — only for the pages the user actually selected.
        Uint8List? data = _loadedImages[i];
        data ??= await _loadImage(i);
        if (data == null) {
          await _loadOnDemand(i, autoSelect: false);
          data = _loadedImages[i];
        }
        if (data == null) continue;
        // 带上图片地址兜底：部分格式（AVIF/HEIC 等）头部识别不出时会退到
        // URL 扩展名，避免生成「1670_P1.」这种没有后缀、接收方当文件处理的名字。
        final hint = i < widget.images.length ? widget.images[i] : null;
        final type = detectFileType(data, nameHint: hint);
        final name = "${safeShareFileName(widget.cid)}_P${i + 1}${type.ext}";
        final file = File(FilePath.join(App.cachePath, name));
        await file.writeAsBytes(data);
        paths.add(file.path);
        mimes.add(type.mime);
      }
      if (!mounted) return;
      if (paths.isEmpty) {
        showToast(message: "No images available".tl, context: context);
        return;
      }
      Navigator.of(context).pop(_ImagePickerResult(paths: paths, mimes: mimes));
    } catch (e) {
      if (mounted) {
        showToast(message: "Failed to load images".tl, context: context);
      }
    } finally {
      if (mounted) setState(() => _isLoadingFull = false);
    }
  }

  /// Multi-select: set the single selected image as comic cover.
  Future<void> _setCoverSelected() async {
    if (_selected.length != 1) return;
    final index = _selected.first;
    Uint8List? data = _loadedImages[index];
    if (data == null && _cachedLoaded.contains(index)) {
      data = await _loadImage(index);
    }
    if (data == null) {
      await _loadOnDemand(index, autoSelect: false);
      data = _loadedImages[index];
    }
    if (!mounted || data == null) {
      showToast(message: "Failed to load image".tl, context: context);
      return;
    }
    try {
      final success = await CustomCoverManager.setCustomCover(
        widget.sourceKey,
        widget.cid,
        null,
        data: data,
      );
      if (!mounted) return;
      if (success) {
        showToast(message: "Cover updated successfully".tl, context: context, seconds: 1);
      } else {
        showToast(message: "Failed to update cover".tl, context: context, seconds: 1);
      }
    } catch (e) {
      if (mounted) showToast(message: "Failed to update cover".tl, context: context, seconds: 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 复用标准 Appbar：返回键 ArrowLeft01(←)、玻璃模糊，与全站一致；
      // 默认 leading 即返回箭头（原 CloseButton × 改为 ←）。
      appBar: Appbar(
        title: Text(widget.title.tl),
      ),
      body: Stack(
        children: [
          GridView.builder(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              6,
              6,
              6,
              6 + kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom + 16,
            ),
            addAutomaticKeepAlives: false,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.72,
            ),
            itemCount: widget.images.length,
            itemBuilder: (context, index) {
              return _buildCell(index);
            },
          ),
          if (_isLoadingFull)
            Container(
              color: Colors.black38,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      bottomNavigationBar:
          widget.allowSelectAll ? _buildActionBar() : null,
    );
  }

  /// Build a single grid cell. Shows the image if it's already in memory
  /// (cache preload or on-demand download); otherwise a lightweight placeholder.
  /// Tapping a placeholder fetches JUST that page — never the whole chapter.
  Widget _buildCell(int index) {
    final onDemand = _loadedImages[index];
    if (onDemand != null) {
      return _cellContent(index, onDemand, true);
    }
    return FutureBuilder<Uint8List?>(
      future: _loadImage(index),
      builder: (context, snapshot) {
        final data = snapshot.hasData ? snapshot.data : null;
        if (data != null && !_cachedLoaded.contains(index)) {
          _cachedLoaded.add(index);
        }
        return _cellContent(index, data, data != null);
      },
    );
  }

  Widget _cellContent(int index, Uint8List? data, bool shown) {
    final selected = _selected.contains(index);
    final loading = _loading.contains(index);
    final content = shown && data != null
        ? _imageTile(index, data, selected)
        : _placeholderTile(index, selected, loading);
    // 每个格子独立重绘边界：勾选/滚动时只重绘变化的格子，避免整片网格重绘。
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          if (shown) {
            if (widget.allowSelectAll) {
              setState(() {
                _selected.contains(index)
                    ? _selected.remove(index)
                    : _selected.add(index);
              });
            } else {
              _selectImage(index);
            }
          } else {
            _loadOnDemand(index);
          }
        },
        child: content,
      ),
    );
  }

  Widget _imageTile(int index, Uint8List data, bool selected) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: selected
              ? BoxDecoration(
                  border: Border.all(
                    color: kcAccentColor(context),
                    width: 2.5,
                  ),
                  borderRadius: BorderRadius.circular(kcRadius6),
                )
              : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kcRadius6),
            child: Image.memory(
              data,
              fit: BoxFit.cover,
              // 缩略图按「格子物理宽度」解码，而不是按原图分辨率解码。
              // 漫画页常见 1000~1500px 宽：6 张全尺寸位图一次解码就是几十 MB，
              // 打开分享页的瞬间会明显掉帧。按格子宽解码可把位图内存降一个数量级
              // （宽度缩到 1/4 ≈ 像素量 1/16），观感在缩略图尺寸下几乎无差别。
              cacheWidth: _thumbDecodeWidth(context),
              // 缩略图不需要高质量重采样，low 更快且足够；gaplessPlayback 避免
              // 勾选重绘时短暂闪成空白。
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
            ),
          ),
        ),
        _pageNumberBadge(index + 1),
        if (index == widget.currentPage) _currentBadge(),
        if (selected) _selectedTick(),
      ],
    );
  }

  /// 缩略图解码宽度（物理像素）= 格子宽 × 设备像素比，夹在 160~540px。
  ///
  /// 上限 540 是为了避免 3x/4x 高分屏把宽度算得过大、又把内存吃掉；
  /// 下限 160 防止极窄屏/折叠屏算出过小的尺寸导致缩略图糊成一片。
  /// 网格几何必须与 [build] 里的 GridView/SliverGridDelegate 保持一致
  /// （padding 左右各 6、crossAxisCount 3、crossAxisSpacing 8）。
  int _thumbDecodeWidth(BuildContext context) {
    final mq = MediaQuery.of(context);
    final cellW = (mq.size.width - 6.0 * 2 - 8.0 * 2) / 3;
    return (cellW * mq.devicePixelRatio).round().clamp(160, 540);
  }

  Widget _placeholderTile(int index, bool selected, bool loading) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: selected
                ? Border.all(
                    color: kcAccentColor(context),
                    width: 2.5,
                  )
                : null,
            borderRadius: BorderRadius.circular(kcRadius6),
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    "${index + 1}",
                    style: TextStyle(
                      fontSize: kcSubtitle,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
          ),
        ),
        if (index == widget.currentPage) _currentBadge(),
        if (selected) _selectedTick(),
      ],
    );
  }

  Widget _pageNumberBadge(int page) => Positioned(
        bottom: 4,
        left: 4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(kcRadius4),
          ),
          child: Text(
            "$page",
            style: const TextStyle(color: Colors.white, fontSize: kcFont11),
          ),
        ),
      );

  Widget _currentBadge() => Positioned(
        top: 4,
        left: 4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: kcAccentColor(context),
            borderRadius: BorderRadius.circular(kcRadius4),
          ),
          child: Text(
            "Current".tl,
            style: TextStyle(
              color: kcOnAccentColor,
              // 徽标类下限 11sp：10sp 的中文在缩略图上几乎读不出来。
              fontSize: kcFont11,
            ),
          ),
        ),
      );

  Widget _selectedTick() => Positioned(
        top: 4,
        right: 4,
        child: Container(
          decoration: BoxDecoration(
            color: kcAccentColor(context),
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(3),
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedCheckmarkCircle01,
            size: 14,
            color: kcOnAccentColor,
          ),
        ),
      );

  Widget _buildActionBar() {
    final total = widget.images.length;
    final count = _selected.length;
    final allSelected = count == total;
    return SafeArea(
      child: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Selected count text — short and flex, won't push buttons out
              Flexible(
                child: Text(
                  count == 0
                      ? "".tl
                      : "@count/@total".tlParams({"count": count, "total": total}),
                  style: TextStyle(
                    fontSize: kcCaption,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              // Unified tonal pill style for all three action buttons
              if (count == 1)
                SizedBox(
                  height: 32,
                  child: Button.filled(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onPressed: () => _setCoverSelected(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedImage02,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Set as Cover".tl,
                          style: const TextStyle(fontSize: kcCaption),
                        ),
                      ],
                    ),
                  ),
                ),
              if (count == 1) const SizedBox(width: 4),
              // Select All / Clear button
              SizedBox(
                height: 32,
                child: Button.filled(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  onPressed: () => setState(() {
                    if (allSelected) {
                      _selected.clear();
                    } else {
                      _selected.addAll(List.generate(total, (i) => i));
                    }
                  }),
                  child: Text(
                    allSelected ? "Clear".tl : "Select All".tl,
                    style: const TextStyle(fontSize: kcCaption),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Share button
              SizedBox(
                height: 32,
                child: Button.filled(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  color: count == 0
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : null,
                  onPressed: () {
                    if (count == 0) return;
                    _shareSelected();
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedShare01,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "Share (@count)".tlParams({"count": count}),
                        style: const TextStyle(fontSize: kcCaption),
                      ),
                    ],
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
