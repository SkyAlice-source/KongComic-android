part of 'reader.dart';

class ReaderWithLoading extends StatefulWidget {
  const ReaderWithLoading({
    super.key,
    required this.id,
    required this.sourceKey,
    this.initialEp,
    this.initialPage,
    this.imageFavoritesComic,
  });

  final String id;

  final String sourceKey;

  final int? initialEp;

  final int? initialPage;

  /// When set, the reader was opened from an image favorite. The image_favorites
  /// DB already stores the chapter structure, so [loadData] builds [ReaderProps]
  /// locally (instant, fully offline) instead of a network loadComicInfo call.
  final ImageFavoritesComic? imageFavoritesComic;

  @override
  State<ReaderWithLoading> createState() => _ReaderWithLoadingState();
}

class _ReaderWithLoadingState
    extends LoadingState<ReaderWithLoading, ReaderProps> {
  @override
  Widget buildContent(BuildContext context, ReaderProps data) {
    return Reader(
      type: data.type,
      cid: data.cid,
      name: data.name,
      chapters: data.chapters,
      history: data.history,
      initialChapter: widget.initialEp ?? data.history.ep,
      initialPage: widget.initialPage ?? data.history.page,
      initialChapterGroup: data.history.group,
      author: data.author,
      tags: data.tags,
      imageFavoritesComic: widget.imageFavoritesComic,
    );
  }

  @override
  Future<Res<ReaderProps>> loadData() async {
    // Local-first path for image favorites: the image_favorites DB already
    // stores the chapter structure (ep/eid/epName/maxPage), so we can build
    // ReaderProps without a network loadComicInfo call. This makes opening a
    // cached favorite instant and fully offline-capable. Any missing data
    // still falls through to the network path below (unchanged behavior).
    if (widget.imageFavoritesComic != null) {
      final fav = widget.imageFavoritesComic!;
      final chaptersMap = <String, String>{};
      for (final ep in fav.imageFavoritesEp) {
        chaptersMap[ep.eid] = ep.epName.isEmpty ? "Ep ${ep.ep}" : ep.epName;
      }
      final history = HistoryManager().find(
            widget.id,
            ComicType.fromKey(widget.sourceKey),
          ) ??
          History.fromMap({
            'type': ComicType.fromKey(widget.sourceKey).value,
            'title': fav.title,
            'subtitle': fav.subTitle,
            'cover': '',
            'id': widget.id,
            'ep': widget.initialEp ?? 0,
            'page': widget.initialPage ?? 0,
            'readEpisode': <String>[],
            'max_page': fav.maxPage,
          });
      return Res(
        ReaderProps(
          type: ComicType.fromKey(widget.sourceKey),
          cid: widget.id,
          name: fav.title,
          chapters: ComicChapters(chaptersMap),
          history: history,
          author: fav.author,
          tags: fav.tags,
        ),
      );
    }

    var comicSource = ComicSource.find(widget.sourceKey);
    var history = HistoryManager().find(
      widget.id,
      ComicType.fromKey(widget.sourceKey),
    );
    if (comicSource == null) {
      var localComic = LocalManager().find(
        widget.id,
        ComicType.fromKey(widget.sourceKey),
      );
      if (localComic == null) {
        return Res.error("comic not found".tl);
      }
      return Res(
        ReaderProps(
          type: ComicType.fromKey(widget.sourceKey),
          cid: widget.id,
          name: localComic.title,
          chapters: localComic.chapters,
          history: history ??
              History.fromModel(
                model: localComic,
                ep: 0,
                page: 0,
              ),
          author: localComic.subtitle,
          tags: localComic.tags,
        ),
      );
    } else {
      var comic = await comicSource.loadComicInfo!(widget.id);
      if (comic.error) {
        return Res.fromErrorRes(comic);
      }
      return Res(
        ReaderProps(
          type: ComicType.fromKey(widget.sourceKey),
          cid: widget.id,
          name: comic.data.title,
          chapters: comic.data.chapters,
          history: history ??
              History.fromModel(
                model: comic.data,
                ep: 0,
                page: 0,
              ),
          author: comic.data.findAuthor() ?? "",
          tags: comic.data.plainTags,
        ),
      );
    }
  }
}

class ReaderProps {
  final ComicType type;

  final String cid;

  final String name;

  final ComicChapters? chapters;

  final History history;

  final String author;

  final List<String> tags;

  const ReaderProps({
    required this.type,
    required this.cid,
    required this.name,
    required this.chapters,
    required this.history,
    required this.author,
    required this.tags,
  });
}
