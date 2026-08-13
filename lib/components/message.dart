part of "components.dart";

void showToast({
  required String message,
  required BuildContext context,
  Widget? icon,
  Widget? trailing,
  int? seconds,
}) {
  var newEntry = OverlayEntry(
      builder: (context) => _ToastOverlay(
            message: message,
            icon: icon,
            trailing: trailing,
          ));

  var state = context.findAncestorStateOfType<OverlayWidgetState>();

  state?.addOverlay(newEntry);

  Timer(Duration(seconds: seconds ?? 2), () => state?.remove(newEntry));
}

class _ToastOverlay extends StatelessWidget {
  const _ToastOverlay({required this.message, this.icon, this.trailing});

  final String message;

  final Widget? icon;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Semantics(
          liveRegion: true,
          child: Material(
          color: Theme.of(context).colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(kcRadius8),
          elevation: 2,
          textStyle:
              ts.withColor(Theme.of(context).colorScheme.onInverseSurface),
          child: IconTheme(
            data: IconThemeData(
                color: Theme.of(context).colorScheme.onInverseSurface),
            child: IntrinsicWidth(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                constraints: BoxConstraints(
                  maxWidth: context.width - 32,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) icon!.paddingRight(8),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                            fontSize: kcSubtitle, fontWeight: FontWeight.w500),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (trailing != null) trailing!.paddingLeft(8)
                  ],
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Active update banner entry, so we never stack multiple banners.
OverlayEntry? _activeUpdateBanner;

/// Shows an in-app notification banner at the top of the screen when followed
/// comics get new updates. The banner shows a cover thumbnail + title and is
/// tappable to open the Follow Updates page. It auto-dismisses after a few
/// seconds. Reuses the same [OverlayWidgetState] channel as [showToast].
void showUpdateBanner({
  required int count,
  required String? coverPath,
  required String title,
  required String subtitle,
  VoidCallback? onTap,
}) {
  final state = App.rootContext.findAncestorStateOfType<OverlayWidgetState>();
  if (state == null) return;

  _activeUpdateBanner?.remove();

  final entry = OverlayEntry(
    builder: (context) => _UpdateBannerOverlay(
      count: count,
      coverPath: coverPath,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    ),
  );
  _activeUpdateBanner = entry;
  state.addOverlay(entry);
  Timer(const Duration(seconds: 4), () {
    if (_activeUpdateBanner == entry) {
      state.remove(entry);
      _activeUpdateBanner = null;
    }
  });
}

class _UpdateBannerOverlay extends StatelessWidget {
  const _UpdateBannerOverlay({
    required this.count,
    required this.coverPath,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final int count;
  final String? coverPath;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      top: top + 8,
      left: 8,
      right: 8,
      child: SafeArea(
        top: false,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: -1.2, end: 0),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Transform.translate(
            offset: Offset(0, value * (top + 120)),
            child: child,
          ),
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(kcRadius16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    if (coverPath != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(kcRadius8),
                        child: CachedNetworkImage(
                          imageUrl: coverPath!,
                          width: 46,
                          height: 60,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: 46,
                            height: 60,
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: 46,
                            height: 60,
                            color: colorScheme.surfaceContainerHighest,
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedImage01,
                              size: 20,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ).paddingRight(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: ts.s16,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: ts.s14.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      size: 18,
                      color: colorScheme.primary,
                    ).paddingLeft(8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OverlayWidget extends StatefulWidget {
  const OverlayWidget(this.child, {super.key});

  final Widget child;

  @override
  State<OverlayWidget> createState() => OverlayWidgetState();
}

class OverlayWidgetState extends State<OverlayWidget> {
  final overlayKey = GlobalKey<OverlayState>();

  var entries = <OverlayEntry>[];

  void addOverlay(OverlayEntry entry) {
    if (overlayKey.currentState != null) {
      overlayKey.currentState!.insert(entry);
      entries.add(entry);
    }
  }

  void remove(OverlayEntry entry) {
    if (entries.remove(entry)) {
      entry.remove();
    }
  }

  void removeAll() {
    for (var entry in entries) {
      entry.remove();
    }
    entries.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(
      key: overlayKey,
      initialEntries: [OverlayEntry(builder: (context) => widget.child)],
    );
  }
}

void showDialogMessage(BuildContext context, String title, String message) {
  showDialog(
    context: context,
    builder: (context) => ContentDialog(
      title: title,
      content: Text(message).paddingHorizontal(16),
      actions: [
        FilledButton(
          onPressed: context.pop,
          child: Text("OK".tl),
        )
      ],
    ),
  );
}

Future<void> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String content,
  required void Function() onConfirm,
  String confirmText = "Confirm",
  Color? btnColor,
}) {
  return showDialog(
    context: context,
    builder: (context) => ContentDialog(
      title: title,
      content: Text(content).paddingHorizontal(16).paddingVertical(8),
      actions: [
        FilledButton(
          onPressed: () {
            context.pop();
            onConfirm();
          },
          style: FilledButton.styleFrom(
            backgroundColor: btnColor,
          ),
          child: Text(confirmText.tl),
        ),
      ],
    ),
  );
}

class LoadingDialogController {
  double? _progress;

  String? _message;

  void Function()? _closeDialog;

  void Function(double? value)? _serProgress;

  void Function(String message)? _setMessage;

  bool closed = false;

  void close() {
    if (closed) {
      return;
    }
    closed = true;
    if (_closeDialog == null) {
      Future.microtask(_closeDialog!);
    } else {
      _closeDialog!();
    }
  }

  void setProgress(double? value) {
    if (closed) {
      return;
    }
    _serProgress?.call(value);
  }

  void setMessage(String message) {
    if (closed) {
      return;
    }
    _setMessage?.call(message);
  }
}

LoadingDialogController showLoadingDialog(
  BuildContext context, {
  void Function()? onCancel,
  bool barrierDismissible = true,
  bool allowCancel = true,
  String? message,
  String cancelButtonText = "Cancel",
  bool withProgress = false,
}) {
  var controller = LoadingDialogController();
  controller._message = message;

  if (withProgress) {
    controller._progress = 0;
  }

  var loadingDialogRoute = DialogRoute(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext context) {
      return StatefulBuilder(builder: (context, setState) {
        controller._serProgress = (value) {
          setState(() {
            controller._progress = value;
          });
        };
        controller._setMessage = (message) {
          setState(() {
            controller._message = message;
          });
        };
        return ContentDialog(
          title: controller._message ?? 'Loading'.tl,
          content: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kcRadius8),
              child: LinearProgressIndicator(
                value: controller._progress,
                minHeight: 14,
                backgroundColor: context.colorScheme.surfaceContainer,
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: allowCancel
                  ? () {
                      controller.close();
                      onCancel?.call();
                    }
                  : null,
              child: Text(cancelButtonText.tl),
            )
          ],
        );
      });
    },
  );

  var navigator = Navigator.of(context, rootNavigator: true);

  navigator.push(loadingDialogRoute).then((value) => controller.closed = true);

  controller._closeDialog = () {
    navigator.removeRoute(loadingDialogRoute);
  };

  return controller;
}

class ContentDialog extends StatelessWidget {
  const ContentDialog({
    super.key,
    this.title, // 如果不传 title 将不会展示
    required this.content,
    this.dismissible = true,
    this.actions = const [],
  });

  final String? title;

  final Widget content;

  final List<Widget> actions;

  final bool dismissible;

  @override
  Widget build(BuildContext context) {
    var content = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title != null
              ? Appbar(
            leading: IconButton(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
              onPressed: dismissible ? context.pop : null,
            ),
            title: Text(title!),
            backgroundColor: Colors.transparent,
          )
              : const SizedBox.shrink(),
          this.content,
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: actions,
          ).paddingRight(12),
          const SizedBox(height: 16),
        ],
      ),
    );
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kcRadius8),
        side: context.brightness == Brightness.dark
            ? BorderSide(color: context.colorScheme.outlineVariant)
            : BorderSide.none,
      ),
      insetPadding: context.width < 400
          ? const EdgeInsets.symmetric(horizontal: 4)
          : const EdgeInsets.symmetric(horizontal: 16),
      elevation: 2,
      shadowColor: context.colorScheme.shadow,
      backgroundColor: context.colorScheme.surface,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: IntrinsicWidth(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              minWidth: math.min(400, context.width - 16),
            ),
            child: MediaQuery.removePadding(
              removeTop: true,
              removeBottom: true,
              context: context,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showInputDialog({
  required BuildContext context,
  required String title,
  String? hintText,
  required FutureOr<Object?> Function(String) onConfirm,
  String? initialValue,
  String confirmText = "Confirm",
  String cancelText = "Cancel",
  RegExp? inputValidator,
  String? image,
  Uint8List? imageData,
}) {
  var controller = TextEditingController(text: initialValue);
  bool isLoading = false;
  String? error;

  return showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return ContentDialog(
            title: title,
            content: Column(
              children: [
                if (image != null)
                  SizedBox(
                    height: 108,
                    child: CachedNetworkImage(imageUrl: image, fit: BoxFit.none),
                  ).paddingBottom(8),
                if (image == null && imageData != null)
                  SizedBox(
                    height: 108,
                    child: Image.memory(imageData, fit: BoxFit.none),
                  ).paddingBottom(8),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: hintText,
                    border: const OutlineInputBorder(),
                    errorText: error,
                  ),
                ).paddingHorizontal(12),
              ],
            ),
            actions: [
              Button.filled(
                isLoading: isLoading,
                onPressed: () async {
                  if (inputValidator != null &&
                      !inputValidator.hasMatch(controller.text)) {
                    setState(() => error = "Invalid input".tl);
                    return;
                  }
                  var futureOr = onConfirm(controller.text);
                  Object? result;
                  if (futureOr is Future) {
                    setState(() => isLoading = true);
                    result = await futureOr;
                    setState(() => isLoading = false);
                  } else {
                    result = futureOr;
                  }
                  if (result == null) {
                    context.pop();
                  } else {
                    setState(() => error = result.toString());
                  }
                },
                child: Text(confirmText.tl),
              ),
            ],
          );
        },
      );
    },
  );
}

void showInfoDialog({
  required BuildContext context,
  required String title,
  required String content,
  String confirmText = "OK",
}) {
  showDialog(
    context: context,
    builder: (context) {
      return ContentDialog(
        title: title,
        content: Text(content).paddingHorizontal(16).paddingVertical(8),
        actions: [
          Button.filled(
            onPressed: context.pop,
            child: Text(confirmText.tl),
          ),
        ],
      );
    },
  );
}

Future<int?> showSelectDialog({
  required String title,
  required List<String> options,
  int? initialIndex,
}) async {
  int? current = initialIndex;

  await showDialog(
    context: App.rootContext,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return ContentDialog(
            title: title,
            content: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Select(
                    current: current == null ? "" : options[current!],
                    values: options,
                    minWidth: 156,
                    onTap: (i) {
                      setState(() {
                        current = i;
                      });
                    },
                  )
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  current = null;
                  context.pop();
                },
                child: Text('Cancel'.tl),
              ),
              FilledButton(
                onPressed: current == null ? null : context.pop,
                child: Text('Confirm'.tl),
              ),
            ],
          );
        },
      );
    },
  );

  return current;
}
