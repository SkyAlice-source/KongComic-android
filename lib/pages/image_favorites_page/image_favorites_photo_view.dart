part of 'image_favorites_page.dart';

class ImageFavoritesPhotoView extends StatefulWidget {
  const ImageFavoritesPhotoView({
    super.key,
    required this.comic,
    required this.imageFavorite,
  });

  final ImageFavoritesComic comic;
  final ImageFavorite imageFavorite;

  @override
  State<ImageFavoritesPhotoView> createState() =>
      _ImageFavoritesPhotoViewState();
}

class _ImageFavoritesPhotoViewState extends State<ImageFavoritesPhotoView> {
  late PageController controller;
  Map<ImageFavorite, bool> cancelImageFavorites = {};

  var images = <ImageFavorite>[];

  int currentPage = 0;

  bool isAppBarShow = false;

  @override
  void initState() {
    var current = 0;
    for (var ep in widget.comic.imageFavoritesEp) {
      for (var image in ep.imageFavorites) {
        images.add(image);
        if (image == widget.imageFavorite) {
          current = images.length - 1;
        }
      }
    }
    currentPage = current;
    controller = PageController(initialPage: current);
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void onPop() {
    List<ImageFavorite> tempList = cancelImageFavorites.entries
        .where((e) => e.value == true)
        .map((e) => e.key)
        .toList();
    if (tempList.isNotEmpty) {
      ImageFavoriteManager().deleteImageFavorite(tempList);
      showToast(
          message: "Delete @a images".tlParams({'a': tempList.length}),
          context: context);
    }
  }

  PhotoViewGalleryPageOptions _buildItem(BuildContext context, int index) {
    var image = images[index];
    return PhotoViewGalleryPageOptions(
      // 图片加载器 支持本地、网络
      imageProvider: ImageFavoritesProvider(image),
      // 初始化大小 全部展示
      minScale: PhotoViewComputedScale.contained * 1.0,
      maxScale: PhotoViewComputedScale.covered * 10.0,
      onTapUp: (context, details, controllerValue) {
        setState(() {
          isAppBarShow = !isAppBarShow;
        });
      },
      heroAttributes: PhotoViewHeroAttributes(
        // Keep this in sync with the thumbnail Hero in image_favorites_item.dart:
        // the comic id is required for uniqueness (same source + ep + page can
        // belong to several comics, which would duplicate the tag).
        tag: "${image.sourceKey}@${image.id}@${image.ep}@${image.page}",
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          onPop();
        }
      },
      child: Listener(
        onPointerSignal: (event) {
          if (HardwareKeyboard.instance.isControlPressed) {
            return;
          }
          if (event is PointerScrollEvent) {
            if (event.scrollDelta.dy > 0) {
              if (controller.page! >= images.length - 1) {
                return;
              }
              controller.nextPage(
                  duration: Duration(milliseconds: 180), curve: Curves.ease);
            } else {
              if (controller.page! <= 0) {
                return;
              }
              controller.previousPage(
                  duration: Duration(milliseconds: 180), curve: Curves.ease);
            }
          }
        },
        child: Stack(children: [
          Positioned.fill(
            child: PhotoViewGallery.builder(
              backgroundDecoration: BoxDecoration(
                color: context.colorScheme.surface,
              ),
              builder: _buildItem,
              itemCount: images.length,
              loadingBuilder: (context, event) => Center(
                child: SizedBox(
                  width: 20.0,
                  height: 20.0,
                  child: CircularProgressIndicator(
                    backgroundColor: context.colorScheme.surfaceContainerHigh,
                    value: event == null || event.expectedTotalBytes == null
                        ? null
                        : event.cumulativeBytesLoaded /
                            event.expectedTotalBytes!,
                  ),
                ),
              ),
              pageController: controller,
              onPageChanged: (index) {
                setState(() {
                  currentPage = index;
                });
              },
            ),
          ),
          buildPageInfo(),
          AnimatedPositioned(
            top: isAppBarShow ? 0 : -(context.padding.top + 52),
            left: 0,
            right: 0,
            duration: Duration(milliseconds: 180),
            child: buildAppBar(),
          ),
        ]),
      ),
    );
  }

  Widget buildPageInfo() {
    var text = "${currentPage + 1}/${images.length}";
    return Positioned(
      height: 40,
      left: 0,
      right: 0,
      bottom: 0,
      child: Center(
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
            Text(text),
          ],
        ),
      ),
    );
  }

  Widget buildAppBar() {
    return Material(
      color: context.colorScheme.surface.withValues(alpha: 0.62),
      child: BlurEffect(
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: context.colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
          ),
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 8),
              IconButton(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.comic.title,
                  style: TextStyle(fontSize: kcTitleMain),
                ),
              ),
              IconButton(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical, size: 18),
                onPressed: showMenu,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ).paddingTop(context.padding.top),
      ),
    );
  }

  void showMenu() {
    showMenuX(
      context,
      Offset(context.width, context.padding.top),
      [
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: 18),
          text: "Save Image".tl,
          onClick: () async {
            var temp = images[currentPage];
            var imageProvider = ImageFavoritesProvider(temp);
            var data = await imageProvider.load(null, null);
            if (!mounted) return;
            final choice = await showImageSaveDialog(
              context,
              // 默认「漫画名_EP{话数}_P{页数}」——每张图的 ep/page 都是收藏时
              // 记录的真实页码，比列表下标更适合当文件名。
              initialName: buildImageSaveName(
                comicTitle: widget.comic.title,
                ep: temp.ep,
                page: temp.page,
              ),
              originalExt: detectImageExt(data),
            );
            if (choice == null) return;
            final result = await prepareImageForSave(data, choice.format);
            // 注意：FileType.ext 自带前导点（`.jpg`），不要再补一个 `.`，
            // 否则会存成 `3..jpg` 这种带双点的奇怪文件名。
            var fileName = "${choice.name}${result.type.ext}";
            await saveFile(filename: fileName, data: result.data);
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedBook01, size: 18),
          text: "Open Original Comic".tl,
          onClick: () async {
            var comic = widget.comic;
            var ep = images[currentPage].ep;
            var page = images[currentPage].page;
            // 用 pushReplacement 把大图页整页换成阅读器。
            //
            // 旧实现是「先 push 阅读器，再 pop 大图页」，但两者都在
            // mainNavigator 这同一个栈上：push 之后栈顶已经是刚打开的阅读器，
            // 紧接着的 pop 弹掉的正是它 —— 大图页原地不动，用户看到的就是
            // 「点了没反应」。换成 pushReplacement 后一步到位：大图页被替换，
            // 阅读器返回时直接回到图片收藏列表。
            final navContext = App.mainNavigatorKey?.currentContext;
            if (navContext == null) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ReaderWithLoading(
                    id: comic.id,
                    sourceKey: comic.sourceKey,
                    initialEp: ep,
                    initialPage: page,
                    imageFavoritesComic: comic,
                  ),
                ),
              );
              return;
            }
            navContext.toReplacement(
              () => ReaderWithLoading(
                id: comic.id,
                sourceKey: comic.sourceKey,
                initialEp: ep,
                initialPage: page,
                imageFavoritesComic: comic,
              ),
            );
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 18),
          text: "Cache Image".tl,
          onClick: () async {
            var controller = showLoadingDialog(
              App.rootContext,
              message: "Cache Image".tl,
            );
            var ok = await ImageFavoritesProvider.cacheImage(images[currentPage]);
            controller.close();
            App.rootContext.showMessage(
              message: ok ? "Cached".tl : "Failed to cache".tl,
            );
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 18),
          text: "Cache All".tl,
          onClick: () async {
            if (images.isEmpty) return;
            var controller = showLoadingDialog(
              App.rootContext,
              message: "Cache All".tl,
              withProgress: true,
            );
            int ok = 0;
            int done = 0;
            for (var img in images) {
              if (controller.closed) break;
              if (await ImageFavoritesProvider.cacheImage(img)) ok++;
              done++;
              controller.setProgress(done / images.length);
            }
            controller.close();
            App.rootContext.showMessage(
              message: "Cached @c images".tlParams({"c": ok}),
            );
          },
        ),
      ],
    );
  }
}
