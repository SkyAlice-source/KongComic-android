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
                            style: TextStyle(fontSize: kcSubtitle),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(fontSize: kcBody).copyWith(
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
        Button.filled(
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
        Button.filled(
          color: btnColor,
          onPressed: () {
            context.pop();
            onConfirm();
          },
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
    final closeDialog = _closeDialog;
    if (closeDialog != null) {
      closeDialog();
    } else {
      // The caller got hold of the controller before `showLoadingDialog`
      // finished attaching the route (i.e. `_closeDialog` was still null).
      // Retry once on the next microtask, by which point it is assigned.
      Future.microtask(() {
        if (closed) {
          _closeDialog?.call();
        }
      });
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
        final progress = controller._progress;
        final isDark = context.colorScheme.brightness == Brightness.dark;
        return Dialog(
          shape: RoundedRectangleBorder(
            // 与 app 统一弹窗（ContentDialog）一致：24dp 大圆角 + 极细凝光描边
            borderRadius: BorderRadius.circular(kcSurfaceRadius),
            side: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
              width: 0.5,
            ),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 48),
          elevation: 6,
          shadowColor: context.colorScheme.shadow.withValues(alpha: 0.18),
          backgroundColor: context.colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  controller._message ?? 'Loading'.tl,
                  style: const TextStyle(fontSize: kcBody),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(kcRadius6),
                        child: LinearProgressIndicator(
                          // 收敛到 [0,1]：上游镜像下载可能把 downloadedBytes 报得
                          // 大于 totalBytes（Content-Length 不准），或传入 NaN/Infinity，
                          // 越界会让 LinearProgressIndicator 抛断言。null/NaN 走不确定态。
                          value: progress == null || progress.isNaN
                              ? null
                              : progress.clamp(0.0, 1.0),
                          minHeight: 8,
                          color: context.colorScheme.brightness == Brightness.dark
                              ? Color.alphaBlend(
                                  context.colorScheme.primary.withValues(alpha: 0.34),
                                  context.colorScheme.surface,
                                )
                              : context.colorScheme.primary,
                          backgroundColor:
                              context.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    if (withProgress) ...[
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 40,
                        child: Text(
                          progress == null
                              ? ''
                              : '${(progress.clamp(0.0, 1.0) * 100).round()}%',
                          style: const TextStyle(fontSize: kcFont13),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ],
                ),
                if (allowCancel)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Button.text(
                      onPressed: () {
                        controller.close();
                        onCancel?.call();
                      },
                      child: Text(cancelButtonText.tl),
                    ),
                  ),
              ],
            ),
          ),
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
    this.showClose = true,
    this.contentPadding,
  });

  final String? title;

  final Widget content;

  final List<Widget> actions;

  final bool dismissible;

  /// 是否显示标题栏左侧的关闭（×）按钮。进度类对话框（底部已有取消/确认按钮）可设
  /// false 避免两个关闭入口重复。
  final bool showClose;

  /// 对话框正文的水平内边距。
  ///
  /// 默认 `null`——正文由调用方自己负责内边距（历史行为，保持兼容）。
  /// 但裸 `Text` / `Column` 之类**不自带内边距**的内容如果不加，文字会直接顶到
  /// 对话框左边缘，与带 `leading` 的标题栏形成"标题有留白、正文贴边"的错位观感。
  /// 这类正文请传 [hPadding]。
  ///
  /// 反之，`ListTile` / `CheckboxListTile` / `RadioListTile` / `TabBar` 等自带
  /// 16dp 左右内边距的控件请保持 `null`，否则会变成 32dp 的双层缩进。
  final EdgeInsetsGeometry? contentPadding;

  /// 对话框正文推荐的水平内边距（与 `ListTile` 默认的一致，16dp）。
  static const EdgeInsets hPadding = EdgeInsets.symmetric(horizontal: 16);

  @override
  Widget build(BuildContext context) {
    var content = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Padding(
              // 关闭键左内边距收到 8：图标自带的点击热区已经是一圈留白，
              // 再叠 16 会让标题被推得离边缘太远，正文与标题的左缘也错开。
              padding: const EdgeInsets.fromLTRB(8, 10, 16, 0),
              child: Row(
                children: [
                  if (showClose)
                    Button.icon(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedCancel01,
                        size: 18,
                      ),
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.85),
                      // 不可关闭时给一个空回调：按钮保留但点击无效，
                      // 既暗示有关闭入口，又不破坏「非 dismissible」语义。
                      onPressed: dismissible ? context.pop : () {},
                    ),
                  Expanded(
                    child: Text(
                      title!,
                      style: TextStyle(
                        fontSize: kcTitleLarge,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // 标题与正文之间留一口气：贴在一起时两段文字会挤成一坨。
            const SizedBox(height: 8),
          ],
          contentPadding == null
              ? this.content
              : Padding(padding: contentPadding!, child: this.content),
          const SizedBox(height: 14),
          // 动作区收一点左右内边距（12），让最后一颗按钮的右缘与标题右缘近似
          // 对齐；否则按钮会比正文更靠里，弹窗右下角显得塌陷。
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: actions,
          ).paddingHorizontal(12),
          const SizedBox(height: 12),
        ],
      ),
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      shape: RoundedRectangleBorder(
        // ColorOS 17 风格：对话框统一大圆角 + 极细凝光描边
        borderRadius: BorderRadius.circular(kcSurfaceRadius),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      // 窄屏下 minWidth 已是「屏宽 - 16」，边距必须 ≤8，否则卡片会比可用宽度更宽而溢出屏外。
      insetPadding: context.width < 420
          ? const EdgeInsets.symmetric(horizontal: 8)
          : const EdgeInsets.symmetric(horizontal: 16),
      elevation: 6,
      shadowColor: context.colorScheme.shadow.withValues(alpha: 0.18),
      backgroundColor: context.colorScheme.surfaceContainerHigh,
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
              Button.text(
                onPressed: () {
                  current = null;
                  context.pop();
                },
                child: Text('Cancel'.tl),
              ),
              const SizedBox(width: kcSpaceSm),
              Button.filled(
                // 未选时置灰 + 空操作，保留「必须先选再确认」的语义；
                // 选中后恢复品牌色并真正关闭。
                color: current == null
                    ? Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.4)
                    : null,
                onPressed: () {
                  if (current != null) context.pop();
                },
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

/// 「保存图片」对话框的返回结果：文件名（不含扩展名）+ 输出格式。
class ImageSaveChoice {
  const ImageSaveChoice({required this.name, required this.format});

  /// 不含扩展名的文件名，例如 `海贼王_EP3_P12`。
  final String name;

  final ImageSaveFormat format;
}

/// 去掉用户手输文件名末尾的图片扩展名，避免存成 `封面.jpg.jpg`。
///
/// 对话框会按所选格式自动补后缀，输入框里只需要名字本身。
String _stripImageExtension(String name) => name.replaceFirst(
      RegExp(r'\.(png|jpe?g|webp|gif|bmp|avif|heic|heif)$', caseSensitive: false),
      '',
    );

/// 弹出「保存图片」对话框：上半部分是文件名（可改），下半部分是格式三选一。
///
/// 返回 `null` 表示用户取消（不保存）。
///
/// - [initialName] 预填的文件名（不含扩展名），一般来自 [buildImageSaveName]。
/// - [originalExt] 原图扩展名（形如 `.webp`），用于「原格式」选项下实时显示
///   最终文件名后缀；PNG / JPG 的后缀由所选格式决定。
/// - [initialFormat] 默认选中的格式，默认「原格式」——不重新编码、画质零损失。
Future<ImageSaveChoice?> showImageSaveDialog(
  BuildContext context, {
  required String initialName,
  String originalExt = '',
  ImageSaveFormat initialFormat = ImageSaveFormat.original,
}) async {
  final controller = TextEditingController(text: initialName);
  var format = initialFormat;

  return showDialog<ImageSaveChoice>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final scheme = context.colorScheme;
        // 最终文件名（含扩展名）—— 输入框放不下长标题时，这行预览保证
        // 用户仍能看全后缀，而不是被输入框裁成 `..._EP1_`。
        final inputName =
            controller.text.trim().isEmpty ? initialName : controller.text.trim();
        final finalExt =
            format == ImageSaveFormat.original ? originalExt : format.ext;
        final finalName =
            '${_stripImageExtension(safeShareFileName(inputName))}$finalExt';
        return ContentDialog(
          title: "Save Image".tl,
          contentPadding: ContentDialog.hPadding,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                // 允许折行：漫画名 + 话数 + 页数很容易超出单行宽度，
                // 多行后至少能一眼看全自己起的名字。
                maxLines: 2,
                minLines: 1,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: "File name".tl,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: kcSpaceXxs),
              Text(
                "Will be saved as @name".tlParams({'name': finalName}),
                style: TextStyle(
                  fontSize: kcCaption,
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: kcSpaceMd),
              Text(
                "Format".tl,
                style: TextStyle(
                  fontSize: kcBody,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: kcSpaceSm),
              for (final f in ImageSaveFormat.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: kcSpaceSm),
                  child: _ImageSaveFormatTile(
                    format: f,
                    selected: f == format,
                    onTap: () => setState(() => format = f),
                  ),
                ),
            ],
          ),
          actions: [
            Button.text(
              onPressed: () => Navigator.of(context).pop(),
              child: Text("Cancel".tl),
            ),
            const SizedBox(width: kcSpaceSm),
            Button.filled(
              onPressed: () {
                final input = controller.text.trim();
                Navigator.of(context).pop(
                  ImageSaveChoice(
                    name: _stripImageExtension(safeShareFileName(
                        input.isEmpty ? initialName : input)),
                    format: format,
                  ),
                );
              },
              child: Text("Save".tl),
            ),
          ],
        );
      },
    ),
  );
}

/// 「保存图片」对话框里的单个格式选项：图标 + 名称 + 说明 + 右侧选中圆点。
///
/// 用卡片式选中态（primaryContainer 底 + primary 描边）替代 M3 默认 ListTile
/// 波纹，跟 App 里其它设置卡片的观感一致。
class _ImageSaveFormatTile extends StatelessWidget {
  const _ImageSaveFormatTile({
    required this.format,
    required this.selected,
    required this.onTap,
  });

  final ImageSaveFormat format;

  final bool selected;

  final VoidCallback onTap;

  // HugeIcons 的图标常量类型是 `List<List<dynamic>>`（与 HugeIcon.icon 一致）。
  List<List<dynamic>> get _icon => switch (format) {
        ImageSaveFormat.original => HugeIcons.strokeRoundedImage01,
        ImageSaveFormat.png => HugeIcons.strokeRoundedImage02,
        ImageSaveFormat.jpg => HugeIcons.strokeRoundedImage03,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final borderRadius = BorderRadius.circular(kcCardRadius);
    return Material(
      // 未选中不再垫一块比弹窗更浅的底色：surfaceContainerLow 在浅色下接近
      // 纯白，叠在 surfaceContainerHigh 的弹窗面上会浮出「盒中盒」，看起来不
      // 像同一个弹窗。改为透明底 + 发丝描边，与源仓库卡片的扁平语言一致；
      // 选中态仍用 primaryContainer 点出焦点。
      color: selected ? scheme.primaryContainer : Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: kcSpaceMd,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              HugeIcon(
                icon: _icon,
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: kcSpaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // PNG / JPG 是通用格式名，不翻译；「Original」有译文。
                      format.label.tl,
                      style: const TextStyle(
                        fontSize: kcBody,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      format.description.tl,
                      style: TextStyle(
                        fontSize: kcCaption,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: kcSpaceSm),
              _RadioDot(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

/// 选中态圆点：外圈描边 + 内部实心圆，比 M3 默认 Radio 更紧凑、更贴 App 风格。
class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
              ),
            )
          : null,
    );
  }
}
