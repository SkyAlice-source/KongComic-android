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
  late List<ImageFavorite> imageFavorites =
      widget.imageFavoritesComic.images.toList();
  bool _expanded = true;

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

  void goPhotoView(ImageFavorite imageFavorite) {
    // Push onto the main navigator so the photo view sits above the image
    // favorites page; popping it returns to the favorites list instead of the
    // home page.
    App.mainNavigatorKey?.currentContext?.to(
      () => ImageFavoritesPhotoView(
        comic: widget.imageFavoritesComic,
        imageFavorite: imageFavorite,
      ),
    );
  }

  void copyTitle() {
    Clipboard.setData(ClipboardData(text: widget.imageFavoritesComic.title));
    App.rootContext.showMessage(message: 'Copy the title successfully'.tl);
  }

  Offset _menuLocation(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    return renderBox.localToGlobal(
      Offset((size.width - 242) / 2, size.height / 2),
    );
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
          icon: HugeIcon(
              icon: HugeIcons.strokeRoundedCheckmarkCircle01, size: 18),
          text: 'Select All'.tl,
          onClick: () {
            for (var ele in imageFavorites) {
              widget.addSelected(ele);
            }
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedBookOpen01, size: 18),
          text: 'Photo View'.tl,
          onClick: () {
            if (imageFavorites.isNotEmpty) {
              goPhotoView(imageFavorites.first);
            }
          },
        ),
        MenuEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 18),
          text: 'Cache All Images'.tl,
          onClick: () async {
            final images = imageFavorites.toList();
            if (images.isEmpty) return;
            final controller = showLoadingDialog(
              App.rootContext,
              message: "Cache All Images".tl,
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

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(context),
        if (_expanded) _buildGrid(context),
      ],
    ).paddingHorizontal(8).paddingVertical(4);
  }

  Widget _buildHeader(BuildContext context) {
    final comicSource =
        ComicSource.find(widget.imageFavoritesComic.sourceKey);
    final time =
        DateFormat('yyyy-MM-dd').format(widget.imageFavoritesComic.time);
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (widget.multiSelectMode) {
            for (var ele in imageFavorites) {
              widget.addSelected(ele);
            }
          } else {
            goComicInfo(widget.imageFavoritesComic);
          }
        },
        onLongPress: () => showMenu(_menuLocation(context), context),
        onSecondaryTapDown: onSecondaryTap,
        borderRadius: BorderRadius.circular(kcRadius8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.imageFavoritesComic.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: kcSubtitle,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "$time | ${comicSource?.name ?? "Unknown".tl}",
                      style: const TextStyle(fontSize: kcCaption),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(kcRadius8),
                ),
                child: Text(
                  "${imageFavorites.length}/${widget.imageFavoritesComic.maxPageFromEp}",
                  style: TextStyle(fontSize: kcCaption),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowDown01,
                    size: 18,
                  ),
                ),
                color: cs.onSurfaceVariant,
                tooltip: 'Collapse'.tl,
                onPressed: () {
                  setState(() {
                    _expanded = !_expanded;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cross = ((width - 32) / 110).floor().clamp(3, 6);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cross,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 96 / 128,
      ),
      itemCount: imageFavorites.length,
      itemBuilder: (c, i) => _buildThumb(c, imageFavorites[i]),
    );
  }

  Widget _buildThumb(BuildContext context, ImageFavorite image) {
    final isSelected = widget.selectedImageFavorites[image] ?? false;
    final cs = Theme.of(context).colorScheme;
    final cached = ImageFavoritesProvider.localImageFile(image).existsSync();
    final curPage = image.page;
    final pageText = curPage == firstPage
        ? '@a Cover'.tlParams({"a": image.epName})
        : curPage.toString();
    return InkWell(
      onTap: () {
        if (widget.multiSelectMode) {
          widget.addSelected(image);
        } else {
          goPhotoView(image);
        }
      },
      onLongPress: () => showMenu(_menuLocation(context), context),
      onSecondaryTapDown: onSecondaryTap,
      borderRadius: BorderRadius.circular(kcRadius8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kcRadius8),
          color: cs.secondaryContainer,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Hero(
                tag: "${image.sourceKey}@${image.id}@${image.ep}@${image.page}",
                child: AnimatedImage(
                  key: ValueKey(
                      "favimg_${image.sourceKey}_${image.ep}_${image.page}"),
                  image: ImageFavoritesProvider(image),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  cacheWidth: (96 * MediaQuery.of(context).devicePixelRatio)
                      .round(),
                  cacheHeight: (128 * MediaQuery.of(context).devicePixelRatio)
                      .round(),
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
                    color: kcBrandAdaptive(context),
                    shape: BoxShape.circle,
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                    size: 12,
                    color: kcOnAccentColor,
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
                          ? kcBrandAdaptive(context)
                          : cs.outline.withValues(alpha: 0.45),
                      width: isSelected ? 2.5 : 1,
                    ),
                    color: isSelected
                        ? cs.onSurface.withValues(alpha: 0.25)
                        : cs.onSurface.withValues(alpha: 0.05),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: kcBrandAdaptive(context),
                              shape: BoxShape.circle,
                            ),
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedTick01,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2),
                color: Colors.black.withValues(alpha: 0.45),
                child: Text(
                  pageText,
                  style: TextStyle(fontSize: kcCaption).copyWith(color: Colors.white),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
