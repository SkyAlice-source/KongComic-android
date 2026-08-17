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
        tag: "${image.sourceKey}${image.ep}${image.page}",
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
      color: context.colorScheme.surface.toOpacity(0.72),
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
            var fileType = detectFileType(data);
            var fileName = "${currentPage + 1}.${fileType.ext}";
            await saveFile(filename: fileName, data: data);
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedBook01, size: 18),
          text: "Read".tl,
          onClick: () async {
            var comic = widget.comic;
            var ep = images[currentPage].ep;
            var page = images[currentPage].page;
            // Push the reader onto the main navigator FIRST (so it stacks
            // above the image favorites page), THEN pop the photo view from
            // the root navigator. The previous order (pop then push) caused
            // the reader's back button to land on the home tab because the
            // pop raced with the push and left the main navigator without
            // the image favorites page in its current route.
            App.mainNavigatorKey?.currentContext?.to(
              () => ReaderWithLoading(
                id: comic.id,
                sourceKey: comic.sourceKey,
                initialEp: ep,
                initialPage: page,
                imageFavoritesComic: comic,
              ),
            );
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 18),
          text: "Cache Image".tl,
          onClick: () async {
            var ok = await ImageFavoritesProvider.cacheImage(images[currentPage]);
            App.rootContext.showMessage(
              message: ok ? "Cached".tl : "Failed to cache".tl,
            );
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 18),
          text: "Cache All".tl,
          onClick: () async {
            int ok = 0;
            for (var img in images) {
              if (await ImageFavoritesProvider.cacheImage(img)) ok++;
            }
            App.rootContext.showMessage(
              message: "Cached @c images".tlParams({"c": ok}),
            );
          },
        ),
      ],
    );
  }
}
