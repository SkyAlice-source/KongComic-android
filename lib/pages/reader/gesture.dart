part of 'reader.dart';

class _ReaderGestureDetector extends StatefulWidget {
  const _ReaderGestureDetector({required this.child});

  final Widget child;

  @override
  State<_ReaderGestureDetector> createState() => _ReaderGestureDetectorState();
}

class _ReaderGestureDetectorState extends AutomaticGlobalState<_ReaderGestureDetector> {
  late TapGestureRecognizer _tapGestureRecognizer;

  static const _kDoubleTapMaxTime = Duration(milliseconds: 200);

  static const _kLongPressMinTime = Duration(milliseconds: 500);

  static const _kDoubleTapMaxDistanceSquared = 20.0 * 20.0;


  final _dragListeners = <_DragListener>[];

  int fingers = 0;

  late _ReaderState reader;

  bool ignoreNextTag = false;

  void ignoreNextTap() {
    ignoreNextTag = true;
  }

  void clearIgnoreNextTap() {
    ignoreNextTag = false;
  }

  @override
  void initState() {
    _tapGestureRecognizer = TapGestureRecognizer()
      ..onTapUp = onTapUp
      ..onSecondaryTapUp = (details) {};
    super.initState();
    context.readerScaffold._gestureDetectorState = this;
    reader = context.reader;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.position == Offset.zero) {
          _previousEvent = null;
          return;
        }
        fingers++;
        if (ignoreNextTag) {
          ignoreNextTag = false;
          return;
        }
        _lastTapPointer = event.pointer;
        _lastTapMoveDistance = Offset.zero;
        _tapGestureRecognizer.addPointer(event);
        if (_dragInProgress) {
          for (var dragListener in _dragListeners) {
            dragListener.onStart?.call(event.position);
          }
          _dragInProgress = false;
        }
        Future.delayed(_kLongPressMinTime, () {
          if (_lastTapPointer == event.pointer && fingers == 1) {
            if (_lastTapMoveDistance!.distanceSquared < 20.0 * 20.0) {
              // long press but menu removed
            } else {
              _dragInProgress = true;
              for (var dragListener in _dragListeners) {
                dragListener.onStart?.call(event.position);
                dragListener.onMove?.call(_lastTapMoveDistance!);
              }
            }
          }
        });
      },
      onPointerMove: (event) {
        if (event.pointer == _lastTapPointer) {
          _lastTapMoveDistance = event.delta + _lastTapMoveDistance!;
        }
        if (_dragInProgress) {
          for (var dragListener in _dragListeners) {
            dragListener.onMove?.call(event.delta);
          }
        }
      },
      onPointerUp: (event) {
        fingers--;
        if (_dragInProgress) {
          for (var dragListener in _dragListeners) {
            dragListener.onEnd?.call();
          }
          _dragInProgress = false;
        }
        _lastTapPointer = null;
        _lastTapMoveDistance = null;
      },
      onPointerCancel: (event) {
        fingers--;
        if (_dragInProgress) {
          for (var dragListener in _dragListeners) {
            dragListener.onEnd?.call();
          }
          _dragInProgress = false;
        }
        _lastTapPointer = null;
        _lastTapMoveDistance = null;
      },
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          onMouseWheel(event.scrollDelta.dy > 0);
        }
      },
      child: widget.child,
    );
  }

  void onMouseWheel(bool forward) {
    if (HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    if (context.reader.mode.key.startsWith('gallery')) {
      if (forward) {
        if (!context.reader.toNextPage() && !context.reader.isLastChapterOfGroup) {
          context.reader.toNextChapter();
        }
      } else {
        if (!context.reader.toPrevPage() && !context.reader.isFirstChapterOfGroup) {
          context.reader.toPrevChapter(toLastPage: true);
        }
      }
    }
  }

  TapUpDetails? _previousEvent;

  int? _lastTapPointer;

  Offset? _lastTapMoveDistance;

  bool _dragInProgress = false;

  bool get _enableDoubleTapToZoom =>
      appdata.settings.getReaderSetting(reader.cid, reader.type.sourceKey, 'enableDoubleTapToZoom');

  void onTapUp(TapUpDetails event) {
    if (event.globalPosition == Offset.zero &&
        event.localPosition == Offset.zero) {
      _previousEvent = null;
      return;
    }
    final location = event.globalPosition;
    if (!_enableDoubleTapToZoom) {
      onTap(location);
      return;
    }
    final previousLocation = _previousEvent?.globalPosition;
    if (previousLocation != null) {
      if ((location - previousLocation).distanceSquared <
          _kDoubleTapMaxDistanceSquared) {
        onDoubleTap(location);
        _previousEvent = null;
        return;
      } else {
        onTap(previousLocation);
      }
    }
    _previousEvent = event;
    Future.delayed(_kDoubleTapMaxTime, () {
      if (_previousEvent == event) {
        onTap(location);
        _previousEvent = null;
      }
    });
  }

  void onTap(Offset location) {
    if (reader._imageViewController!.handleOnTap(location)) {
      return;
    } else if (context.readerScaffold.isOpen) {
      context.readerScaffold.openOrClose();
    } else {
      if (reader.isOnChapterCommentsPage) {
        return;
      }
      if (appdata.settings.getReaderSetting(
          reader.cid, reader.type.sourceKey, 'enableTapToTurnPages')) {
        final layout = appdata.settings['tapZoneLayout'] ?? 'default';
        final width = context.width;
        final height = context.height;
        final x = location.dx;
        final y = location.dy;
        
        bool isLeft = false, isRight = false, isTop = false, isBottom = false;
        
        switch (layout) {
          case 'leftRight':
            isLeft = x < width * 0.3;
            isRight = x > width * 0.7;
          case 'rightOnly':
            isRight = x > width * 0.5;
          case 'leftOnly':
            isLeft = x < width * 0.5;
          case 'edge':
            isLeft = x < width * 0.15;
            isRight = x > width * 0.85;
            isTop = y < height * 0.15;
            isBottom = y > height * 0.7;
          default: // 'default'
            isLeft = x < width * 0.3;
            isRight = x > width * 0.7;
            isTop = y < height * 0.3;
            isBottom = y > height * 0.7;
        }
        
        bool isCenter = false;
        var prev = () => context.reader.toPrevPage();
        var next = () => context.reader.toNextPage();
        if (appdata.settings.getReaderSetting(
            reader.cid, reader.type.sourceKey, 'reverseTapToTurnPages')) {
          prev = () => context.reader.toNextPage();
          next = () => context.reader.toPrevPage();
        }
        switch (context.reader.mode) {
          case ReaderMode.galleryLeftToRight:
          case ReaderMode.continuousLeftToRight:
            if (isLeft) {
              prev();
            } else if (isRight) {
              next();
            } else {
              isCenter = true;
            }
          case ReaderMode.galleryRightToLeft:
          case ReaderMode.continuousRightToLeft:
            if (isLeft) {
              next();
            } else if (isRight) {
              prev();
            } else {
              isCenter = true;
            }
          case ReaderMode.galleryTopToBottom:
          case ReaderMode.continuousTopToBottom:
            if (isTop) {
              prev();
            } else if (isBottom) {
              next();
            } else {
              isCenter = true;
            }
        }
        if (!isCenter) {
          return;
        }
      }
      context.readerScaffold.openOrClose();
    }
  }

  void onDoubleTap(Offset location) {
    context.reader._imageViewController?.handleDoubleTap(location);
  }

  void addDragListener(_DragListener listener) {
    _dragListeners.add(listener);
  }

  void removeDragListener(_DragListener listener) {
    _dragListeners.remove(listener);
  }

  @override
  Object? get key => "reader_gesture";

  void copyImage(Offset location) async {
    var controller = reader._imageViewController;
    var image = await controller!.getImageByOffset(location);
    if (image != null) {
      writeImageToClipboard(image);
    } else {
      context.showMessage(message: "No Image".tl.tl);
    }
  }

  void saveImage(Offset location) async {
    var controller = reader._imageViewController;
    var image = await controller!.getImageByOffset(location);
    if (image != null) {
      var filetype = detectFileType(image);
      var page = reader.page;
      var ep = reader.chapter;
      var name = reader.widget.name;
      saveFile(filename: "${name}_EP${ep}_P$page$filetype.ext", data: image);
    } else {
      context.showMessage(message: "No Image".tl.tl);
    }
  }
}

class _DragListener {
  void Function(Offset point)? onStart;
  void Function(Offset offset)? onMove;
  void Function()? onEnd;

  _DragListener({this.onMove, this.onEnd});
}
