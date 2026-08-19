part of 'image_favorites_page.dart';

class _ImageFavoritesItem extends StatefulWidget {
  const _ImageFavoritesItem({
    super.key,
    required this.imageFavoritesComic,
    required this.selectedImageFavorites,
    required this.addSelected,
    required this.multiSelectMode,
    required this.finalImageFavoritesComicList,
  });

  final ImageFavoritesComic imageFavoritesComic;
  final Function(ImageFavorite) addSelected;
  final Map<ImageFavorite, bool> selectedImageFavorites;
  final List<ImageFavoritesComic> finalImageFavoritesComicList;
  final bool multiSelectMode;

  @override
  State<_ImageFavoritesItem> createState() => _ImageFavoritesItemState();
}

class _ImageFavoritesItemState extends State<_ImageFavoritesItem> {
  late List<ImageFavorite> imageFavorites = widget.imageFavoritesComic.images.toList();

  @override
  void didUpdateWidget(covariant _ImageFavoritesItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageFavoritesComic != widget.imageFavoritesComic) {
      imageFavorites = widget.imageFavoritesComic.images.toList();
    }
  }

  void goComicInfo(ImageFavoritesComic comic) {
    App.mainNavigatorKey?.currentContext?.to(() => ComicPage(
          id: comic.id,
          sourceKey: comic.sourceKey,
        ));
  }

  void goReaderPage(ImageFavoritesComic comic, int ep, int page) {
    // Push onto the main navigator (same stack as ImageFavoritesPage) so the
    // reader's back button returns here instead of popping to the home page.
    App.mainNavigatorKey?.currentContext?.to(
      () => ReaderWithLoading(
        id: comic.id,
        sourceKey: comic.sourceKey,
        initialEp: ep,
        initialPage: page,
        imageFavoritesComic: comic,
      ),
    );
  }

  void goPhotoView(ImageFavorite imageFavorite) {
    Navigator.of(App.rootContext).push(MaterialPageRoute(
        builder: (context) => ImageFavoritesPhotoView(
              comic: widget.imageFavoritesComic,
              imageFavorite: imageFavorite,
            )));
  }

  void copyTitle() {
    Clipboard.setData(ClipboardData(text: widget.imageFavoritesComic.title));
    App.rootContext.showMessage(message: 'Copy the title successfully'.tl);
  }

  void onLongPress() {
    var renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;
    var location = renderBox.localToGlobal(
      Offset((size.width - 242) / 2, size.height / 2),
    );
    showMenu(location, context);
  }

  void onSecondaryTap(TapDownDetails details) {
    showMenu(details.globalPosition, context);
  }

  void showMenu(Offset location, BuildContext context) {
    showMenuX(
      App.rootContext,
      location,
      [
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedBook01, size: 18),
          text: 'Details'.tl,
          onClick: () {
            goComicInfo(widget.imageFavoritesComic);
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 18),
          text: 'Copy Title'.tl,
          onClick: () {
            copyTitle();
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle01, size: 18),
          text: 'Select All'.tl,
          onClick: () {
            for (var ele in widget.imageFavoritesComic.images) {
              widget.addSelected(ele);
            }
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedBookOpen01, size: 18),
          text: 'Photo View'.tl,
          onClick: () {
            goPhotoView(widget.imageFavoritesComic.images.first);
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 18),
          text: 'Cache All Images'.tl,
          onClick: () async {
            var images = widget.imageFavoritesComic.images;
            if (images.isEmpty) return;
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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.6,
        ),
        borderRadius: BorderRadius.circular(kcRadius8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(kcRadius8),
        onSecondaryTapDown: onSecondaryTap,
        onLongPress: onLongPress,
        onTap: () {
          if (widget.multiSelectMode) {
            for (var ele in widget.imageFavoritesComic.images) {
              widget.addSelected(ele);
            }
          } else {
            // 单击跳转漫画详情
            goComicInfo(widget.imageFavoritesComic);
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildTop(),
            SizedBox(
              height: 145,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemBuilder: buildItem,
                itemCount: imageFavorites.length,
              ),
            ).paddingHorizontal(8),
            buildBottom(),
          ],
        ),
      ),
    );
  }

  Widget buildItem(BuildContext context, int index) {
    var image = imageFavorites[index];
    bool isSelected = widget.selectedImageFavorites[image] ?? false;
    final cached = ImageFavoritesProvider.localImageFile(image).existsSync();
    int curPage = image.page;
    String pageText = curPage == firstPage
        ? '@a Cover'.tlParams({"a": image.epName})
        : curPage.toString();

    return InkWell(
      onTap: () {
        // 单击去阅读页面, 跳转到当前点击的page
        if (widget.multiSelectMode) {
          widget.addSelected(image);
        } else {
          goReaderPage(widget.imageFavoritesComic, image.ep, curPage);
        }
      },
      onLongPress: () {
        goPhotoView(image);
      },
      borderRadius: BorderRadius.circular(kcRadius8),
      child: Container(
        width: 98,
        height: 128,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kcRadius8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Container(
              height: 128,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kcRadius8),
                color: Theme.of(context).colorScheme.secondaryContainer,
              ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Hero(
                        tag: "${image.sourceKey}${image.ep}${image.page}",
                        child: AnimatedImage(
                          // Key by the image's full identity so that when the
                          // list reorders after a delete, Flutter rebuilds this
                          // cell with the correct provider instead of reusing a
                          // stale cached image from a removed item.
                          key: ValueKey("favimg_${image.sourceKey}_${image.ep}_${image.page}"),
                          image: ImageFavoritesProvider(image),
                          width: 96,
                          height: 128,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                    if (cached)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                            size: 12,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    if (widget.multiSelectMode)
                      Positioned.fill(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(kcRadius8),
                            border: Border.all(
                              color: isSelected
                                  ? kcBrandColor
                                  : Theme.of(context)
                                      .colorScheme
                                      .outline
                                      .withValues(alpha: 0.45),
                              width: isSelected ? 2.5 : 1,
                            ),
                            color: isSelected
                                ? Colors.black.withValues(alpha: 0.25)
                                : Colors.black.withValues(alpha: 0.05),
                          ),
                          child: isSelected
                              ? Center(
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: const BoxDecoration(
                                      color: kcBrandColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            Text(
              pageText,
              style: ts.s10,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          ],
        ),
      ),
    ).paddingHorizontal(4);
  }

  Widget buildTop() {
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.imageFavoritesComic.title,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: kcSubtitle,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(kcRadius8),
          ),
          child: Text(
              "${imageFavorites.length}/${widget.imageFavoritesComic.maxPageFromEp}",
              style: ts.s12),
        ),
      ],
    ).paddingHorizontal(16).paddingVertical(8);
  }

  Widget buildBottom() {
    var enableTranslate = App.locale.languageCode == 'zh';
    String time =
        DateFormat('yyyy-MM-dd').format(widget.imageFavoritesComic.time);
    List<String> tags = [];
    for (var tag in widget.imageFavoritesComic.tags) {
      var text = enableTranslate ? tag.translateTagsToCN : tag;
      if (text.contains(':')) {
        text = text.split(':').last;
      }
      tags.add(text);
      if (tags.length == 5) {
        break;
      }
    }
    var comicSource = ComicSource.find(widget.imageFavoritesComic.sourceKey);
    return Row(
      children: [
        Text(
          "$time | ${comicSource?.name ?? "Unknown"}",
          textAlign: TextAlign.left,
          style: const TextStyle(
            fontSize: kcCaption,
          ),
        ).paddingRight(8),
        if (tags.isNotEmpty)
          Expanded(
            child: Text(
              tags
                  .map((e) => enableTranslate ? e.translateTagsToCN : e)
                  .join(" "),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: kcCaption,
                overflow: TextOverflow.ellipsis,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
      ],
    ).paddingHorizontal(8).paddingBottom(8);
  }
}
