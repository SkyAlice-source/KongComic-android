part of 'reader.dart';

class _ReaderScaffold extends StatefulWidget {
  const _ReaderScaffold({required this.child});

  final Widget child;

  @override
  State<_ReaderScaffold> createState() => _ReaderScaffoldState();
}

class _ReaderScaffoldState extends State<_ReaderScaffold> {
  bool _isOpen = false;

  static const kTopBarHeight = 56.0;

  static const kBottomBarHeight = 125.0;

  bool get isOpen => _isOpen;

  bool get isReversed =>
      context.reader.mode == ReaderMode.galleryRightToLeft ||
      context.reader.mode == ReaderMode.continuousRightToLeft;

  int showFloatingButtonValue = 0;

  var lastValue = 0;

  _ReaderGestureDetectorState? _gestureDetectorState;

  void setFloatingButton(int value) {
    lastValue = showFloatingButtonValue;
    if (value == 0) {
      if (showFloatingButtonValue != 0) {
        showFloatingButtonValue = 0;
        update();
      }
    }
    if (value == 1 && showFloatingButtonValue == 0) {
      showFloatingButtonValue = 1;
      update();
    } else if (value == -1 && showFloatingButtonValue == 0) {
      showFloatingButtonValue = -1;
      update();
    }
  }

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
    sliderFocus.addListener(() {
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
    // 打开/关闭都遵循「隐藏系统状态栏」设置，避免翻页时状态栏突然弹出
    if (!appdata.settings['showSystemStatusBar']) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
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
        if (appdata.settings['showPageNumberInReader'] == true && !isOnChapterCommentsPage)
          buildPageInfoText(),
        if (!isOnChapterCommentsPage)
          buildStatusInfo(),
        AnimatedPositioned(
          duration: AppAnimations.duration(const Duration(milliseconds: 180)),
          right: 16,
          bottom: showFloatingButtonValue == 0 ? -58 : 36,
          child: buildEpChangeButton(),
        ),
        AnimatedPositioned(
          duration: AppAnimations.duration(const Duration(milliseconds: 180)),
          top: _isOpen ? 0 : -(kTopBarHeight + context.padding.top),
          left: 0,
          right: 0,
          height: kTopBarHeight + context.padding.top,
          child: buildTop(),
        ),
        AnimatedPositioned(
          duration: AppAnimations.duration(const Duration(milliseconds: 180)),
          bottom: _isOpen
              ? 0
              : -(kBottomBarHeight + MediaQuery.of(context).padding.bottom),
          left: 0,
          right: 0,
          child: buildBottom(),
        ),
      ],
    );
  }

  Widget buildTop() {
    final epName =
      context.reader.widget.chapters?.titles.elementAtOrNull(
        context.reader.chapter - 1,
      );

    return BlurEffect(
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
                  style: ts.s18,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ) : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      context.reader.widget.name,
                      style: ts.s16,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      epName,
                      style: ts.s12,
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
        icon: const Icon(Icons.more_horiz, size: 20),
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
                  Icon(
                    rotation == null
                        ? Icons.screen_rotation
                        : rotation == false
                            ? Icons.screen_lock_portrait
                            : Icons.screen_lock_landscape,
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
                Icon(
                  Icons.timer,
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
                  const Icon(Icons.fullscreen, size: 20),
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
          icon: isLiked()
              ? const Icon(Icons.favorite, size: 20, color: kcBrandColor)
              : HugeIcon(icon: HugeIcons.strokeRoundedFavourite, size: 20),
          onPressed: addImageFavorite,
          style: isLiked()
              ? IconButton.styleFrom(
                  backgroundColor: kcBrandColor.withValues(alpha: 0.12),
                )
              : null,
        ),
      ),
      if (context.reader.widget.chapters != null)
        Tooltip(
          message: "Chapters".tl,
          child: IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedBook01, size: 20),
            onPressed: openChapterDrawer,
          ),
        ),
      Tooltip(
        message: "Save Image".tl,
        child: IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 20),
          onPressed: saveCurrentImage,
        ),
      ),
      Tooltip(
        message: "Share".tl,
        child: IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedShare01, size: 20),
          onPressed: share,
        ),
      ),
      _buildMoreMenu(),
    ];

    Widget child = SizedBox(
      height: kBottomBarHeight,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: () => !isReversed
                    ? context.reader.chapter > 1
                          ? context.reader.toPrevChapter()
                          : context.reader.toPage(1)
                    : context.reader.chapter < context.reader.maxChapter
                    ? context.reader.toNextChapter()
                    : context.reader.toPage(context.reader.maxPage),
                icon: HugeIcon(icon: HugeIcons.strokeRoundedBackward01, size: 20),
              ),
              Expanded(child: buildSlider()),
              IconButton.filledTonal(
                onPressed: () => !isReversed
                    ? context.reader.chapter < context.reader.maxChapter
                          ? context.reader.toNextChapter()
                          : context.reader.toPage(context.reader.maxPage)
                    : context.reader.chapter > 1
                    ? context.reader.toPrevChapter()
                    : context.reader.toPage(1),
                icon: HugeIcon(icon: HugeIcons.strokeRoundedForward01, size: 20),
              ),
              const SizedBox(width: 8),
            ],
          ),
          LayoutBuilder(
            builder: (context, constrains) {
              final small = (constrains.maxWidth - buttons.length * 50) < 120;
              return Row(
                children: [
                  if (!small)
                    Container(
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
                    ).paddingLeft(16),
                  const Spacer(),
                  for (var button in buttons)
                    if (!small)
                      Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(kcRadius20),
                        clipBehavior: Clip.antiAlias,
                        child: button.paddingHorizontal(4),
                      )
                    else
                      ...[SizedBox(width: 36, height: 36, child: button), const Spacer()],
                  if (!small)
                    const SizedBox(width: 4),
                ],
              );
            },
          ),
        ],
      ),
    );

    return BlurEffect(
      child: Container(
        decoration: BoxDecoration(
          color: context.colorScheme.surface,
          border: isOpen
              ? Border(
                  top: BorderSide(
                    color: context.colorScheme.outlineVariant,
                    width: 0.5,
                  ),
                )
              : null,
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

  var sliderFocus = FocusNode();

  Widget buildSlider() {
    final displayPage = context.reader.page.clamp(1, context.reader.maxPage);
    final maxPage = context.reader.maxPage;
    var epName =
        context.reader.widget.chapters?.titles.elementAtOrNull(
          context.reader.chapter - 1,
        ) ??
        "E${context.reader.chapter}";
    if (epName.length > 10) {
      epName = "${epName.substring(0, 10)}...";
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
    _openSideBar(
      context.reader.widget.chapters!.isGrouped
          ? _GroupedChaptersView(context.reader)
          : _ChaptersView(context.reader),
      width: 400,
    );
  }

  void saveCurrentImage() async {
    var result = await selectImageToData();
    if (result == null) {
      return;
    }
    var (imageIndex, data) = result;
    var fileType = detectFileType(data);
    // Save file name: ComicName_EP{chapter}_P{page}.{ext} to avoid conflict.
    // The chapter index of different group is continuous, so we use chapter number is enough.
    var filename =
        "${context.reader.widget.name}_EP${context.reader.chapter}_P${imageIndex + 1}${fileType.ext}";
    saveFile(data: data, filename: filename);
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
        await Share.shareFiles(paths: result.paths!);
        return;
      }
      final imageIndex = result.index!;
      final data = result.data!;
      var fileType = detectFileType(data);
      var filename =
          "${context.reader.widget.name}_EP${context.reader.chapter}_P${imageIndex + 1}${fileType.ext}";
      await Share.shareFile(data: data, filename: filename, mime: fileType.mime);
    } catch (e) {
      // fallback: 分享文字
      await Share.shareText(context.reader.widget.name);
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
    _openSideBar(
      ReaderSettings(
        comicId: context.reader.cid,
        comicSource: context.reader.type.sourceKey,
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
      width: 400,
    );
  }

  void _openSideBar(Widget widget, {double width = 400}) {
    // Route chapter/settings sidebars through the main navigator (the same
    // stack the reader page lives in) so closing the drawer returns to the
    // reader instead of popping past it back to the comic source.
    showSideBar(
      context,
      widget,
      width: width,
      dismissible: true,
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

    Navigator.of(context, rootNavigator: true).push(
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

  Widget buildEpChangeButton() {
    if (context.reader.widget.chapters == null) return const SizedBox();
    final bool isNext = showFloatingButtonValue == 1;
    final bool isPrev = showFloatingButtonValue == -1;
    // Keep the same Backward01 / Forward01 icon family, swapping them when the
    // reading direction is reversed.
    HugeIcon iconFor(bool next) => HugeIcon(
          icon: isReversed
              ? (next
                  ? HugeIcons.strokeRoundedBackward01
                  : HugeIcons.strokeRoundedForward01)
              : (next
                  ? HugeIcons.strokeRoundedForward01
                  : HugeIcons.strokeRoundedBackward01),
          size: 20,
        );
    // Use the same circular, surface-tinted style as the back-to-top FAB so
    // the button is clearly visible over any comic page in both light and dark
    // themes.
    final colors = scrollTopFabColors(context);
    final buttonStyle = IconButton.styleFrom(
      backgroundColor: colors.background,
      foregroundColor: colors.foreground,
      disabledBackgroundColor:
          colors.background.withValues(alpha: colors.background.a * 0.5),
      disabledForegroundColor:
          colors.foreground.withValues(alpha: colors.foreground.a * 0.5),
      shape: CircleBorder(side: colors.side ?? BorderSide.none),
      padding: EdgeInsets.zero,
    );
    if (showFloatingButtonValue == 0) {
      // Off-screen hint that remembers the last swipe direction.
      return SizedBox(
        width: 56,
        height: 56,
        child: IconButton(
          style: buttonStyle,
          onPressed: null,
          icon: lastValue == 1 ? iconFor(true) : iconFor(false),
        ),
      );
    }
    return SizedBox(
      width: 56,
      height: 56,
      child: IconButton(
        style: buttonStyle,
        onPressed: () {
          if (isNext) {
            context.reader.toNextChapter();
          } else if (isPrev) {
            context.reader.toPrevChapter();
          }
          setFloatingButton(0);
        },
        icon: iconFor(isNext),
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
      builder: (dialogContext) => AlertDialog(
        title: Text("Select an image".tl),
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
          TextButton(
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
  const _ImagePickerResult({this.index, this.data, this.paths});
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
  final ScrollController _scrollController = ScrollController();

  /// Images already held in memory: from cache preload OR on-demand download.
  final Map<int, Uint8List> _loadedImages = {};
  /// Indices whose image came from local cache (shown, but not in [_loadedImages]).
  final Set<int> _cachedLoaded = {};
  /// Indices currently being downloaded on demand (shows a spinner).
  final Set<int> _loading = {};

  @override
  void initState() {
    super.initState();
    // Jump straight to the current page so users don't have to manually
    // scroll through hundreds of pages. Cell height is fixed by
    // childAspectRatio, so the offset can be estimated deterministically.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final width = MediaQuery.of(context).size.width;
      const padding = 6.0, spacing = 6.0, crossAxisCount = 3;
      final cellW =
          (width - padding * 2 - spacing * (crossAxisCount - 1)) / crossAxisCount;
      final cellH = cellW / 0.72;
      final rowH = cellH + spacing;
      final row = widget.currentPage ~/ crossAxisCount;
      final max = _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0.0;
      if (max > 0) {
        _scrollController.jumpTo((row * rowH - padding).clamp(0.0, max));
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
        final ext = detectFileType(data).ext;
        final name = "${widget.cid}_P${i + 1}.$ext";
        final file = File("${App.cachePath}/$name");
        await file.writeAsBytes(data);
        paths.add(file.path);
      }
      if (!mounted) return;
      if (paths.isEmpty) {
        showToast(message: "No images available".tl, context: context);
        return;
      }
      Navigator.of(context).pop(_ImagePickerResult(paths: paths));
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
      appBar: AppBar(
        title: Text(widget.title.tl),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: const CloseButton(),
        actions: null,
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
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
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
    return GestureDetector(
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
                    color: Theme.of(context).colorScheme.primary,
                    width: 2.5,
                  ),
                  borderRadius: BorderRadius.circular(kcRadius6),
                )
              : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kcRadius6),
            child: Image.memory(data, fit: BoxFit.cover),
          ),
        ),
        _pageNumberBadge(index + 1),
        if (index == widget.currentPage) _currentBadge(),
        if (selected) _selectedTick(),
      ],
    );
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
                    color: Theme.of(context).colorScheme.primary,
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
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(kcRadius4),
          ),
          child: Text(
            "Current".tl,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
              fontSize: kcFont10,
            ),
          ),
        ),
      );

  Widget _selectedTick() => Positioned(
        top: 4,
        right: 4,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(3),
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedCheckmarkCircle01,
            size: 14,
            color: Theme.of(context).colorScheme.onPrimary,
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
                  child: FilledButton.tonalIcon(
                    onPressed: () => _setCoverSelected(),
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedImage02,
                      size: 14,
                    ),
                    label: Text(
                      "Set as Cover".tl,
                      style: const TextStyle(fontSize: kcCaption),
                    ),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              if (count == 1) const SizedBox(width: 4),
              // Select All / Clear button
              SizedBox(
                height: 32,
                child: FilledButton.tonal(
                  onPressed: () => setState(() {
                    if (allSelected) {
                      _selected.clear();
                    } else {
                      _selected.addAll(List.generate(total, (i) => i));
                    }
                  }),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
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
                child: FilledButton.tonalIcon(
                  onPressed: count == 0 ? null : _shareSelected,
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedShare01,
                    size: 14,
                  ),
                  label: Text(
                    "Share (@count)".tlParams({"count": count}),
                    style: const TextStyle(fontSize: kcCaption),
                  ),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
