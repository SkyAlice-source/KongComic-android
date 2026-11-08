part of 'comic_page.dart';

class _CoverViewer extends StatefulWidget {
  const _CoverViewer({
    required this.imageProvider,
    required this.title,
    required this.heroTag,
  });

  final ImageProvider imageProvider;
  final String title;
  final String heroTag;

  @override
  State<_CoverViewer> createState() => _CoverViewerState();
}

class _CoverViewerState extends State<_CoverViewer> {
  bool isAppBarShow = true;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: context.colorScheme.surface,
        body: Stack(
          children: [
            Positioned.fill(
              child: PhotoView(
                imageProvider: widget.imageProvider,
                minScale: PhotoViewComputedScale.contained * 1.0,
                maxScale: PhotoViewComputedScale.covered * 3.0,
                backgroundDecoration: BoxDecoration(
                  color: context.colorScheme.surface,
                ),
                loadingBuilder: (context, event) => Center(
                  // 和阅读器里爬行小人脚下那条横条同款：能拿到总字节就显示
                  // 真实百分比，拿不到（服务器没给 Content-Length）就退化成
                  // 流光条，不编一个假的数字。
                  child: KcTrackProgress(
                    value: event == null || event.expectedTotalBytes == null
                        ? null
                        : event.cumulativeBytesLoaded /
                              event.expectedTotalBytes!,
                  ),
                ),
                onTapUp: (context, details, controllerValue) {
                  setState(() {
                    isAppBarShow = !isAppBarShow;
                  });
                },
                heroAttributes: PhotoViewHeroAttributes(tag: widget.heroTag),
              ),
            ),
            AnimatedPositioned(
              top: isAppBarShow ? 0 : -(context.padding.top + 52),
              left: 0,
              right: 0,
              duration: const Duration(milliseconds: 180),
              child: _buildAppBar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    // 复用标准 Appbar：返回键 ArrowLeft01(←)、标题 kcAppbarTitle、玻璃模糊，
    // 与全站顶栏一致；默认 leading 即返回箭头，无需手写。
    return Appbar(
      title: Text(widget.title),
      actions: [
        Button.icon(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 18),
          onPressed: _saveCover,
        ),
      ],
    );
  }

  void _saveCover() async {
    ImageStream? imageStream;
    ImageStreamListener? listener;
    try {
      imageStream = widget.imageProvider.resolve(const ImageConfiguration());
      final completer = Completer<Uint8List>();

      // 必须持有 listener 引用才能在同一 ImageStream 上摘掉它：一次性截图用的
      // 流如果不 remove，多帧图（GIF / 动图封面）会再次回调，而 completer 只能
      // complete 一次 —— 第二次会抛 StateError，并把 State 一直挂在流上。
      listener = ImageStreamListener(
        (ImageInfo info, bool _) async {
          final byteData = await info.image.toByteData(
            format: ImageByteFormat.png,
          );
          if (completer.isCompleted) return;
          if (byteData == null) {
            // 编码失败也必须让 completer 落地，否则下面会永久 await。
            completer.completeError(StateError("Failed to encode cover image"));
          } else {
            completer.complete(byteData.buffer.asUint8List());
          }
        },
        // 流上的错误只投递给 listener 的 onError，不会进外面的 try/catch。
        // 不接的话 completer 永不完成：点保存后既没成功提示也没报错，静默挂死。
        onError: (Object e, StackTrace? s) {
          if (!completer.isCompleted) completer.completeError(e, s);
        },
      );
      imageStream.addListener(listener);

      final data = await completer.future;
      final fileType = detectFileType(data);
      await saveFile(
        filename:
            "cover_${widget.title.replaceAll(RegExp(r'[\\/:"*?<>|]'), '_')}${fileType.ext}",
        data: data,
      );
    } catch (e) {
      if (mounted) {
        context.showMessage(message: friendlyError(e));
      }
    } finally {
      if (imageStream != null && listener != null) {
        imageStream.removeListener(listener);
      }
    }
  }
}
