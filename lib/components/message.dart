part of "components.dart";

void showToast({
  required String message,
  required BuildContext context,
  Widget? icon,
  Widget? trailing,
  int? seconds,
}) {
  var newEntry = OverlayEntry(
    builder: (context) =>
        _ToastOverlay(message: message, icon: icon, trailing: trailing),
  );

  var state = context.findAncestorStateOfType<OverlayWidgetState>();

  state?.addOverlay(newEntry);

  Timer(Duration(seconds: seconds ?? 2), () => state?.remove(newEntry));
}

/// 破坏性操作后的「撤销」提示。
///
/// 复用 [showToast] 的 Overlay 通道与外观，但窗口拉长到 5 秒并提供明确的
/// Undo 按钮：确认弹窗只能防误触，删完之后发现删错仍需重新搜索，这一步
/// 补的是「反悔」。成功撤销由调用方用界面内反馈（列表刷新）表达，不再叠
/// 第二条 Toast；只有撤销失败才提示错误。
void showUndoMessage({
  required String message,
  required VoidCallback onUndo,
  int seconds = 5,
}) {
  final context = App.rootContext;
  final state = context.findAncestorStateOfType<OverlayWidgetState>();
  if (state == null) return;

  late final OverlayEntry entry;
  Timer? timer;
  var dismissed = false;
  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    // 点了 Undo 就把自动收起的 Timer 一起取消，否则它还会挂满 5 秒并
    // 持有已移除的 entry（页面销毁后尤其容易变成悬挂回调）。
    timer?.cancel();
    state.remove(entry);
  }

  entry = OverlayEntry(
    builder: (_) => _ToastOverlay(
      message: message,
      trailing: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          dismiss();
          onUndo();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: kcMinTapTarget,
            minHeight: kcMinTapTarget,
          ),
          child: Center(
            child: Text(
              "Undo".tl,
              style: TextStyle(
                // inverseSurface 底上的强调色：M3 保证与底色有足够对比，
                // 不需要再猜浅/深色该用哪一级灰。
                color: Theme.of(context).colorScheme.inversePrimary,
                fontSize: kcSubtitle,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  state.addOverlay(entry);
  timer = Timer(Duration(seconds: seconds), dismiss);
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
            textStyle: ts.withColor(
              Theme.of(context).colorScheme.onInverseSurface,
            ),
            child: IconTheme(
              data: IconThemeData(
                color: Theme.of(context).colorScheme.onInverseSurface,
              ),
              child: IntrinsicWidth(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 16,
                  ),
                  constraints: BoxConstraints(maxWidth: context.width - 32),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) icon!.paddingRight(8),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(
                            fontSize: kcSubtitle,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (trailing != null) trailing!.paddingLeft(8),
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

  // 必须走 state.remove()：直接 OverlayEntry.remove() 只从 Overlay 摘掉，
  // 不会从 state.entries 列表移除 —— 死 entry 留在列表里，之后任何一次
  // removeAll() 再对它调 remove()（_overlay 已 null）会触发 debug 断言。
  final old = _activeUpdateBanner;
  if (old != null) {
    state.remove(old);
    _activeUpdateBanner = null;
  }

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
          // 后台触发的横幅本来就会突然滑入；「移除动画」时改为原地出现，
          // 避免整块内容从屏幕外掉下来（自动消失的 4s 计时保持不变）。
          duration: kcReduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 320),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
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
                            style: TextStyle(
                              fontSize: kcBody,
                            ).copyWith(color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      size: 18,
                      color: kcBrandAdaptive(context),
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
      actions: [Button.filled(onPressed: context.pop, child: Text("OK".tl))],
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
        // 破坏性确认必须有一个**明确的**取消按钮：只靠遮罩 / 返回键 / 左上 ×
        // 用户并不知道哪些能退出，误触的成本就是一次不可逆删除。
        // 放在确认左侧、用文字按钮，危险按钮仍由调用方传 error 色。
        Button.text(
          onPressed: context.pop,
          child: Text("Cancel".tl),
        ),
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

  Timer? _timeoutTimer;

  /// 启动一个超时看门狗：超过 [duration] 后自动关闭对话框并触发 [onTimeout]。
  ///
  /// 用于兜底「业务代码忘记调用 [close]」或「后台请求永久挂起」导致加载框
  /// 永远不消失的情况。正常完成时 [close] 会自动取消计时器，不会误触发。
  void startTimeout(Duration duration, {void Function()? onTimeout}) {
    _cancelTimeout();
    _timeoutTimer = Timer(duration, () {
      if (closed) return;
      close();
      onTimeout?.call();
    });
  }

  void _cancelTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  void close() {
    if (closed) {
      return;
    }
    closed = true;
    _cancelTimeout();
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
  Duration? timeout = const Duration(seconds: 120),
  void Function()? onTimeout,
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
      return StatefulBuilder(
        builder: (context, setState) {
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
              padding: const EdgeInsets.fromLTRB(20, kcSpaceLg, 20, kcSpaceSm),
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
                            color:
                                context.colorScheme.brightness ==
                                    Brightness.dark
                                ? Color.alphaBlend(
                                    kcAccentColor(
                                      context,
                                    ).withValues(alpha: 0.34),
                                    context.colorScheme.surface,
                                  )
                                : kcAccentColor(context),
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
        },
      );
    },
  );

  var navigator = Navigator.of(context, rootNavigator: true);

  navigator.push(loadingDialogRoute).then((value) => controller.closed = true);

  controller._closeDialog = () {
    navigator.removeRoute(loadingDialogRoute);
  };

  // 全局加载框超时看门狗：默认 120s 兜底，防止「业务忘记 close / 请求永久
  // 挂起」导致加载框永久不消失。长任务（本地漫画导入、批量导出）请在调用处
  // 显式传 `timeout: null` 豁免，避免误伤仍在进行的后台任务。
  if (timeout != null) {
    controller.startTimeout(
      timeout,
      onTimeout: () {
        onTimeout?.call();
        if (onTimeout == null && context.mounted) {
          showToast(
            message: "Operation timed out, please retry".tl,
            context: context,
          );
        }
      },
    );
  }

  return controller;
}

class ContentDialog extends StatelessWidget {
  const ContentDialog({
    super.key,
    this.title, // 如果不传 title 将不会展示
    this.subtitle,
    this.headerIcon,
    required this.content,
    this.dismissible = true,
    this.actions = const [],
    this.showClose = false,
    this.contentPadding,
  });

  final String? title;

  /// 可选：标题下方的一行说明（如「选择导入方式」）。
  ///
  /// 传了它或 [headerIcon] 之后，标题栏会从「纯标题」切换成
  /// 「图标徽章 + 标题 + 说明」的富头部：弹窗点遮罩、按返回键都能退，不需要
  /// 再放第三个关闭入口；去掉 × 后标题靠左、与正文同一条起始线，顶部不再
  /// 左重右空。徽章只是给这类选择弹窗补一个视觉锚点。
  final String? subtitle;

  /// 可选：标题栏左侧的图标徽章（品牌红薄染底 + 品牌色图标）。
  ///
  /// 传了它（或 [subtitle]）即启用富头部样式。
  final List<List<dynamic>>? headerIcon;

  final Widget content;

  final List<Widget> actions;

  final bool dismissible;

  /// 是否显示标题栏的关闭（×）按钮，默认**不显示**。
  ///
  /// 弹窗点遮罩 / 返回键即可退出，× 只是第三个关闭入口，还会把标题挤到一边、
  /// 与正文的左缘错开。只有极少数 `barrierDismissible: false` 且没有底部按钮、
  /// 必须给一个显式关闭入口的弹窗才需要传 `true`。
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
  static const EdgeInsets hPadding = EdgeInsets.symmetric(horizontal: kcSpaceLg);

  /// 富头部：图标徽章 + 标题 + 说明（见 [subtitle] / [headerIcon]）。
  ///
  /// 徽章用品牌色低透明度叠在弹窗面上（AMOLED 下随 [kcBrandAdaptive] 退成
  /// 中性灰），不做实心红块——弹窗里最重要的是标题文字，徽章只负责定位视线。
  Widget _buildRichHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = kcBrandAdaptive(context);
    return Padding(
      // 左右收到 16：与正文（contentPadding: hPadding）左缘对齐。
      padding: const EdgeInsets.fromLTRB(kcSpaceLg, kcSpaceLg, kcSpaceMd, 0),
      child: Row(
        children: [
          if (headerIcon != null)
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(kcCardRadius),
              ),
              child: HugeIcon(icon: headerIcon!, size: 22, color: accent),
            ).paddingRight(kcSpaceMd),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title!,
                  style: TextStyle(
                    fontSize: kcTitleLarge,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: kcCaption,
                      height: 1.3,
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (showClose)
            Button.icon(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
              color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
              onPressed: dismissible ? context.pop : () {},
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var content = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            if (subtitle != null || headerIcon != null)
              _buildRichHeader(context)
            else
              Padding(
                // 默认无 ×：标题左缘与正文（contentPadding: hPadding）对齐到 16；
                // 极少数显式开 showClose 的弹窗才退回 8，给图标热区留出余量。
                padding: EdgeInsets.fromLTRB(
                  showClose ? kcSpaceSm : kcSpaceLg,
                  10,
                  kcSpaceLg,
                  0,
                ),
                child: Row(
                  children: [
                    if (showClose)
                      Button.icon(
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedCancel01,
                          size: 18,
                        ),
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
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
          ? const EdgeInsets.symmetric(horizontal: kcSpaceSm)
          : const EdgeInsets.symmetric(horizontal: kcSpaceLg),
      elevation: 6,
      shadowColor: context.colorScheme.shadow.withValues(alpha: 0.18),
      backgroundColor: context.colorScheme.surfaceContainerHigh,
      child: AnimatedSize(
        duration: kcReduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
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

  // controller 是函数体局部创建的，dialog 关闭后必须释放，
  // 否则每次弹输入框泄漏一个 TextEditingController。
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
                    child: CachedNetworkImage(
                      imageUrl: image,
                      fit: BoxFit.none,
                    ),
                  ).paddingBottom(8),
                if (image == null && imageData != null)
                  SizedBox(
                    height: 108,
                    child: Image.memory(imageData, fit: BoxFit.none),
                  ).paddingBottom(8),
                TextField(
                  controller: controller,
                  decoration: kcInputDecoration(
                    context,
                    hintText: hintText,
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
                    // onConfirm 可能耗时较长（网络/磁盘）；期间对话框可能已被
                    // 关闭，StatefulBuilder 的 State 已 dispose，此时不能
                    // 再 setState / pop。
                    if (!context.mounted) return;
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
  ).whenComplete(controller.dispose);
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
          Button.filled(onPressed: context.pop, child: Text(confirmText.tl)),
        ],
      );
    },
  );
}

Future<int?> showSelectDialog({
  required String title,
  required List<String> options,
  int? initialIndex,
}) {
  // 参考式样：下拉 Select 换成整列单选 + 右下红色胶囊「确认」。
  // 调用方（设置页 / JS UI）不用改：返回仍是选中的下标，取消 / 点遮罩为 null。
  return showKcRadioDialog<int>(
    context: App.rootContext,
    title: title,
    initial: initialIndex,
    options: [
      for (var i = 0; i < options.length; i++) (value: i, label: options[i]),
    ],
  );
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

  try {
    return await showDialog<ImageSaveChoice>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final scheme = context.colorScheme;
        // 最终文件名（含扩展名）—— 输入框放不下长标题时，这行预览保证
        // 用户仍能看全后缀，而不是被输入框裁成 `..._EP1_`。
        final inputName = controller.text.trim().isEmpty
            ? initialName
            : controller.text.trim();
        final finalExt = format == ImageSaveFormat.original
            ? originalExt
            : format.ext;
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
                decoration: kcInputDecoration(
                  context,
                  labelText: "File name".tl,
                ),
              ),
              const SizedBox(height: kcSpace6),
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
                    name: _stripImageExtension(
                      safeShareFileName(input.isEmpty ? initialName : input),
                    ),
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
  } finally {
    controller.dispose();
  }
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
              color: selected ? kcAccentColor(context) : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              HugeIcon(
                icon: _icon,
                size: 20,
                color: selected
                    ? kcBrandAdaptive(context)
                    : scheme.onSurfaceVariant,
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
          color: selected ? kcAccentColor(context) : scheme.outlineVariant,
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
                  color: kcAccentColor(context),
                ),
              ),
            )
          : null,
    );
  }
}
