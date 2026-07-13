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
    if (!_isOpen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      if (!appdata.settings['showSystemStatusBar']) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
    setState(() {
      _isOpen = !_isOpen;
    });
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
          duration: const Duration(milliseconds: 180),
          right: 16,
          bottom: showFloatingButtonValue == 0 ? -58 : 36,
          child: buildEpChangeButton(),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
          top: _isOpen ? 0 : -(kTopBarHeight + context.padding.top),
          left: 0,
          right: 0,
          height: kTopBarHeight + context.padding.top,
          child: buildTop(),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
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
              color: Colors.grey.toOpacity(0.5),
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
      var translatedTags = tags.map((e) => e.translateTagsToCN).toList();

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
      showToast(message: e.toString(), context: context, seconds: 1);
    }
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
        message: "Collect the image".tl,
        child: IconButton(
          icon: isLiked()
              ? Icon(Icons.favorite, size: 20, color: Colors.red)
              : HugeIcon(icon: HugeIcons.strokeRoundedHeartAdd, size: 20),
          onPressed: addImageFavorite,
        ),
      ),
      if (App.isDesktop)
        Tooltip(
          message: "${\"Full Screen\".tl}(F12)",
          child: IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowExpand01, size: 20),
            onPressed: () {
              context.reader.fullscreen();
            },
          ),
        ),
      if (App.isAndroid)
        Tooltip(
          message: () {
            if (rotation == null) return "Screen Rotation".tl;
            if (rotation == false) return "Locked: Portrait".tl;
            return "Locked: Landscape".tl;
          }(),
          child: IconButton(
            icon: () {
              if (rotation == null) {
                return HugeIcon(icon: HugeIcons.strokeRounded3dRotate, size: 20);
              } else if (rotation == false) {
                return Icon(Icons.screen_lock_portrait, size: 20, color: Colors.orange);
              } else {
                return Icon(Icons.screen_lock_landscape, size: 20, color: Colors.blue);
              }
            }.call(),
            onPressed: () {
              if (rotation == null) {
                setState(() {
                  rotation = false;
                });
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.portraitUp,
                  DeviceOrientation.portraitDown,
                ]);
              } else if (rotation == false) {
                setState(() {
                  rotation = true;
                });
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]);
              } else {
                setState(() {
                  rotation = null;
                });
                SystemChrome.setPreferredOrientations(DeviceOrientation.values);
              }
            },
          ),
        ),
      Tooltip(
        message: "Share".tl,
        child: IconButton(icon: HugeIcon(icon: HugeIcons.strokeRoundedShare01, size: 20), onPressed: share),
      ),
      Tooltip(
        message: "Save Image".tl,
        child: IconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload01, size: 20),
          onPressed: saveCurrentImage,
        ),
      ),
    ];

    return BlurEffect(
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom,
        ),
        decoration: BoxDecoration(
          color: context.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Colors.grey.toOpacity(0.5),
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
              Text(
                text,
                style: ts.s12.copyWith(
                  color: context.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              ...buttons,
            ],
          ),
        ),
      ),
    );
  }

  void share() async {
    try {
      final images = context.reader.images;
      if (images == null || images.isEmpty) {
        Share.shareText(context.reader.widget.name);
        return;
      }
      final result = await Navigator.of(context).push<(int, Uint8List)?>(
        MaterialPageRoute(
          builder: (_) => _ChapterImagePickerPage(
            images: images,
            sourceKey: context.reader.type.sourceKey,
            cid: context.reader.cid,
            eid: context.reader.eid,
            currentPage: (context.reader.page - 1).clamp(0, images.length - 1),
            title: "Select Image to Share".tl,
          ),
        ),
      );
      if (!mounted || result == null) return;
      var (imageIndex, data) = result;
      var fileType = detectFileType(data);
      var filename =
          "${context.reader.widget.name}_EP${context.reader.chapter}_P${imageIndex + 1}${fileType.ext}";
      await Share.shareFile(data: data, filename: filename, mime: fileType.mime);
    } catch (e) {
      // fallback: 分享文字
      Share.shareText(context.reader.widget.name);
    }
  }

  void setAsCover() async {
    try {
      final images = context.reader.images;
      if (images == null || images.isEmpty) {
        showToast(message: "No images available".tl, context: context);
        return;
      }

      final result = await Navigator.of(context).push<(int, Uint8List)?>(
        MaterialPageRoute(
          builder: (_) => _ChapterImagePickerPage(
            images: images,
            sourceKey: context.reader.type.sourceKey,
            cid: context.reader.cid,
            eid: context.reader.eid,
            currentPage: (context.reader.page - 1).clamp(0, images.length - 1),
            title: "Select Cover Image",
          ),
        ),
      );
      if (!mounted || result == null) return;
      var (imageIndex, data) = result;
      var fileType = detectFileType(data);
      var filename =
          "${context.reader.widget.name}_EP${context.reader.chapter}_P${imageIndex + 1}${fileType.ext}";
      saveFile(data: data, filename: filename);
    } catch (e) {
      showToast(message: e.toString(), context: context);
    }
  }

  void saveCurrentImage() async {
    try {
      final images = context.reader.images;
      if (images == null || images.isEmpty) return;
      var imageKey = images[context.reader.page - 1];
      if (imageKey.startsWith("file://")) {
        file = File(imageKey.substring(7));
        var fileName = "${context.reader.widget.name}_EP${context.reader.chapter}_P${context.reader.page}.${file.extension}";
        saveFile(file: file, filename: fileName);
        return;
      }
      Uint8List? data;
      try {
        var cache = await CacheManager().findCache(
          "$imageKey@${context.reader.type.sourceKey}@${context.reader.cid}@${context.reader.eid}",
        );
        if (cache != null) {
          data = await cache.readAsBytes();
        }
      } catch (_) {}
      if (data == null) return;
      var fileType = detectFileType(data);
      var filename =
          "${context.reader.widget.name}_EP${context.reader.chapter}_P${context.reader.page}${fileType.ext}";
      saveFile(data: data, filename: filename);
    } catch (e) {
      showToast(message: e.toString(), context: context);
    }
  }

  void saveCurrentPageAsCover() async {
    try {
      final images = context.reader.images;
      if (images == null || images.isEmpty) return;
      var imageKey = images[context.reader.page - 1];
      if (imageKey.startsWith("file://")) {
        file = File(imageKey.substring(7));
        await CustomCoverManager.setCustomCover(
          context.reader.type.sourceKey,
          context.reader.cid,
          file.path,
        );
        return;
      }
      Uint8List? data;
      try {
        var cache = await CacheManager().findCache(
          "$imageKey@${context.reader.type.sourceKey}@${context.reader.cid}@${context.reader.eid}",
        );
        if (cache != null) {
          data = await cache.readAsBytes();
        }
      } catch (_) {}
      if (data == null) return;
      var fileType = detectFileType(data);
      var filename =
          "${context.reader.widget.name}_EP${context.reader.chapter}_P${context.reader.page}${fileType.ext}";
      var cache = FilePath.join(App.cachePath, filename);
      await File(cache).writeAsBytes(data);
      await CustomCoverManager.setCustomCover(
        context.reader.type.sourceKey,
        context.reader.cid,
        cache,
      );
    } catch (e) {
      showToast(message: e.toString(), context: context);
    }
  }

  /// Show a full-screen page to let user choose a page number.
  ///
  /// Returns the 0-based index of the selected image, or null if cancelled.
  Future<int?> selectImage() async {
    if (context.reader.images == null || context.reader.images!.isEmpty) {
      return null;
    }

    // If in gallery mode, let user pick from visible pages
    if (context.reader.mode == ReaderMode.galleryLeftToRight ||
        context.reader.mode == ReaderMode.galleryRightToLeft) {
      // Build list of currently visible image indices
      final imageIndices = <int>[];
      for (int i = 0; i < context.reader.images!.length; i++) {
        imageIndices.add(i);
      }

      // If only one page, return directly
      if (imageIndices.length == 1) {
        return imageIndices[0];
      }

      // Determine whether to show a simple page picker or thumbnail grid
      if (imageIndices.length <= 20) {
        // Show simple page number picker
        final page = await showDialog<int>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text("Select an image".tl),
            children: [
              SizedBox(
                width: 280,
                height: 400,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: imageIndices.length,
                  itemBuilder: (context, index) {
                    final pageIndex = imageIndices[index];
                    return Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(0),
                        ),
                        onPressed: () => Navigator.of(context).pop(pageIndex),
                        child: Text("${pageIndex + 1}"),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
        return page ?? singleImageIndex;
      } else {
        // Show thumbnail grid for selection
        return await _showImageThumbnailGrid(imageIndices);
      }
    } else {
      // Continuous mode: show thumbnail grid
      final imageIndices = <int>[];
      for (int i = 0; i < context.reader.images!.length; i++) {
        imageIndices.add(i);
      }
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
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 24,
                              ),
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
    IconData batteryIcon;
    Color batteryColor = context.colorScheme.onSurface;

    if (state == BatteryState.charging) {
      batteryIcon = Icons.battery_charging_full;
    } else if (batteryLevel >= 96) {
      batteryIcon = Icons.battery_full_sharp;
    } else if (batteryLevel >= 84) {
      batteryIcon = Icons.battery_6_bar_sharp;
    } else if (batteryLevel >= 72) {
      batteryIcon = Icons.battery_5_bar_sharp;
    } else if (batteryLevel >= 60) {
      batteryIcon = Icons.battery_4_bar_sharp;
    } else if (batteryLevel >= 48) {
      batteryIcon = Icons.battery_3_bar_sharp;
    } else if (batteryLevel >= 36) {
      batteryIcon = Icons.battery_2_bar_sharp;
    } else if (batteryLevel >= 24) {
      batteryIcon = Icons.battery_1_bar_sharp;
    } else if (batteryLevel >= 12) {
      batteryIcon = Icons.battery_0_bar_sharp;
    } else {
      batteryIcon = Icons.battery_alert_sharp;
      batteryColor = Colors.red;
    }

    return Row(
      children: [
        Icon(
          batteryIcon,
          size: 16,
          color: batteryColor,
          // Stroke
          shadows: List.generate(9, (index) {
            if (index == 4) {
              return null;
            }
            double offsetX = (index % 3 - 1) * 0.8;
            double offsetY = ((index / 3).floor() - 1) * 0.8;
            return Shadow(
              color: context.colorScheme.onInverseSurface,
              offset: Offset(offsetX, offsetY),
            );
          }).whereType<Shadow>().toList(),
        ),
        Stack(
          children: [
            Text(
              '$batteryLevel%',
              style: TextStyle(
                fontSize: 14,
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
            fontSize: 14,
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

/// Full-screen image picker that lets the user browse ALL pages in the
/// current chapter and select any image as the comic's cover.
class _ChapterImagePickerPage extends StatefulWidget {
  final List<String> images;
  final String sourceKey;
  final String cid;
  final String eid;
  final int currentPage;
  final String title;

  const _ChapterImagePickerPage({
    required this.images,
    required this.sourceKey,
    required this.cid,
    required this.eid,
    required this.currentPage,
    this.title = "Select Cover Image",
  });

  @override
  State<_ChapterImagePickerPage> createState() => _ChapterImagePickerPageState();
}

class _ChapterImagePickerPageState extends State<_ChapterImagePickerPage> {
  /// Cache futures so FutureBuilder doesn't re-fetch on every rebuild.
  final Map<int, Future<Uint8List?>> _futures = {};
  bool _isLoadingFull = false;

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

  Future<void> _selectImage(int index) async {
    setState(() => _isLoadingFull = true);
    final data = await _loadImage(index);
    if (!mounted) return;
    setState(() => _isLoadingFull = false);
    if (data != null) {
      Navigator.of(context).pop((index, data));
    } else {
      showToast(message: "Failed to load image".tl, context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.tl),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          GridView.builder(
            padding: const EdgeInsets.all(6),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 0.72,
            ),
            itemCount: widget.images.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => _selectImage(index),
                child: FutureBuilder<Uint8List?>(
                  future: _loadImage(index),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              snapshot.data!,
                              fit: BoxFit.cover,
                            ),
                          ),
                          // Page number badge
                          Positioned(
                            bottom: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "${index + 1}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          // Current page indicator
                          if (index == widget.currentPage)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "Current".tl,
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          "${index + 1}",
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          if (_isLoadingFull)
            Container(
              color: Colors.black38,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}