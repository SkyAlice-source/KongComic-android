import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/image_provider/cached_image.dart';
import 'package:kong_comic/foundation/listen_mixin.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/network/download.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:kong_comic/utils/translations.dart';

class DownloadingPage extends StatefulWidget {
  const DownloadingPage({super.key});

  @override
  State<DownloadingPage> createState() => _DownloadingPageState();
}

class _DownloadingPageState extends State<DownloadingPage>
    with AutoListenMixin {
  DownloadTask? firstTask;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Guard against re-registering the same listener: this hook can fire
    // several times, which would make [update] run (and setState) once per
    // duplicate registration.
    final current = LocalManager().downloadingTasks.firstOrNull;
    // DownloadTask 重写了 ==（按 id/comicType）：队头任务取消后重新添加
    // 同一漫画时是「新实例、相等值」，用 != 会误判未变，监听仍挂在已移出
    // 队列的旧实例上 → 新任务进度不刷新、旧监听泄漏。必须比 identical。
    if (!identical(current, firstTask)) {
      firstTask?.removeListener(update);
      firstTask = current;
      firstTask?.addListener(update);
    }
  }

  @override
  void initState() {
    listen(LocalManager(), update);
    super.initState();
  }

  @override
  void dispose() {
    firstTask?.removeListener(update);
    super.dispose();
  }

  void update() {
    var currentFirstTask = LocalManager().downloadingTasks.firstOrNull;
    if (!identical(currentFirstTask, firstTask)) {
      firstTask?.removeListener(update);
      firstTask = currentFirstTask;
      firstTask?.addListener(update);
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = LocalManager().downloadingTasks;
    return PopUpWidgetScaffold(
      title: "Downloads".tl,
      body: tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedDownload01,
                    size: 48,
                    color: context.colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "No active downloads".tl,
                    style: TextStyle(fontSize: kcSubtitle),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: tasks.length + 1,
              itemBuilder: (BuildContext context, int i) {
                if (i == 0) {
                  return buildTop();
                }
                i--;
                return _DownloadTaskTile(
                  key: ValueKey(tasks[i]),
                  task: tasks[i],
                );
              },
            ),
    );
  }

  Widget buildTop() {
    int speed = 0;
    if (LocalManager().downloadingTasks.isNotEmpty) {
      speed = LocalManager().downloadingTasks.first.speed;
    }
    var first = LocalManager().downloadingTasks.firstOrNull;
    final cs = Theme.of(context).colorScheme;
    // 顶部速度 / 暂停区收成一张胶囊卡：之前是「裸行 + 一条 0.6 发丝底线」，
    // 细到几乎看不见，列表看起来仍然是一整块。现在每张卡独立成面，
    // 靠卡与卡之间的间隙 + 发丝描边分隔，比压线明显得多。
    return Container(
      height: 52,
      margin: const EdgeInsets.fromLTRB(kcSpaceMd, kcSpaceSm, kcSpaceMd, kcSpaceXs),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kcRadius16),
        border: Border.all(color: kcHairlineColor(context), width: kcHairline),
      ),
      child: Row(
        children: [
          if (first?.isError == true)
            Text("Error".tl, style: TextStyle(fontSize: kcSectionTitle).bold)
          else if (first?.isPaused == true)
            Text("Paused".tl, style: TextStyle(fontSize: kcSectionTitle).bold)
          else
            Text(
              "${bytesToReadableString(speed)}/s",
              style: TextStyle(fontSize: kcSectionTitle).bold,
            ),
          const Spacer(),
          if (first?.isPaused == true || first?.isError == true)
            Button.outlined(
              child: Row(
                children: [
                  HugeIcon(icon: HugeIcons.strokeRoundedPlay, size: 18),
                  const SizedBox(width: 4),
                  Text("Start".tl),
                ],
              ),
              onPressed: () {
                first!.resume();
              },
            )
          else if (first != null)
            Button.outlined(
              child: Row(
                children: [
                  HugeIcon(icon: HugeIcons.strokeRoundedPause, size: 18),
                  const SizedBox(width: 4),
                  Text("Pause".tl),
                ],
              ),
              onPressed: () {
                first.pause();
              },
            ),
        ],
      ),
    );
  }
}

class _DownloadTaskTile extends StatefulWidget {
  const _DownloadTaskTile({required this.task, super.key});

  final DownloadTask task;

  @override
  State<_DownloadTaskTile> createState() => _DownloadTaskTileState();
}

class _DownloadTaskTileState extends State<_DownloadTaskTile>
    with AutoListenMixin {
  late DownloadTask task;
  late AutoListenHandle _taskHandle;

  @override
  void initState() {
    task = widget.task;
    _taskHandle = listen(task, update);
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _DownloadTaskTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // DownloadTask 重写了 ==（按 id）：同 id 换实例时 ValueKey 相等、Element
    // 复用，这里会真实触发。换绑必须走 mixin 的句柄，否则新监听不进登记表，
    // dispose 时漏删 → 任务每次 notify 都对已 dispose 的 State setState。
    if (!identical(oldWidget.task, widget.task)) {
      _taskHandle.cancel();
      task = widget.task;
      _taskHandle = listen(task, update);
    }
  }

  void update() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 136,
      margin: const EdgeInsets.symmetric(horizontal: kcSpaceMd, vertical: kcSpaceXs),
      padding: const EdgeInsets.all(kcSpaceMd),
      decoration: BoxDecoration(
        // 每个任务一张独立胶囊卡：填充面 + 0.6 发丝描边 + 大圆角，
        // 卡间留 8dp 间隙。比原来那条几乎看不见的底线明显，也和主页胶囊同语言。
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kcRadius16),
        border: Border.all(color: kcHairlineColor(context), width: kcHairline),
      ),
      child: Row(
        children: [
          Container(
            width: 82,
            height: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kcRadius8),
              color: context.colorScheme.surfaceContainerLow,
            ),
            clipBehavior: Clip.antiAlias,
            child: widget.task.cover == null
                ? Center(
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedImage01,
                      size: 28,
                      color: cs.onSurfaceVariant,
                    ),
                  )
                : Image(
                    image: CachedImageProvider(widget.task.cover!),
                    filterQuality: FilterQuality.medium,
                    fit: BoxFit.cover,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.task.title,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 2,
                      ),
                    ),
                    MenuButton(
                      entries: [
                        MenuEntry(
                          icon: HugeIcon(
                            icon: widget.task.isPaused
                                ? HugeIcons.strokeRoundedPlay
                                : HugeIcons.strokeRoundedPause,
                            size: 18,
                          ),
                          text: widget.task.isPaused ? "Resume".tl : "Pause".tl,
                          onClick: () {
                            if (widget.task.isPaused) {
                              widget.task.resume();
                            } else {
                              widget.task.pause();
                            }
                          },
                        ),
                        MenuEntry(
                          icon: HugeIcon(
                            icon: HugeIcons.strokeRoundedCancel01,
                            size: 18,
                          ),
                          text: "Cancel".tl,
                          onClick: () {
                            widget.task.cancel();
                          },
                        ),
                        MenuEntry(
                          icon: HugeIcon(
                            icon: HugeIcons.strokeRoundedArrowUp01,
                            size: 18,
                          ),
                          text: "Move To First".tl,
                          onClick: () {
                            LocalManager().moveToFirst(widget.task);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                if (!widget.task.isPaused || widget.task.isError)
                  Text(
                    widget.task.message,
                    style: TextStyle(fontSize: kcCaption),
                    maxLines: 3,
                  ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  // 收敛到 [0,1]：压缩/校验阶段 current 可能短暂超过 expected。
                  value: widget.task.progress.clamp(0.0, 1.0),
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(kcPillRadius),
                  color: isDark
                      ? Color.alphaBlend(
                          kcAccentColor(context).withValues(alpha: 0.34),
                          cs.surface,
                        )
                      : kcAccentColor(context),
                  backgroundColor: isDark
                      ? Color.alphaBlend(
                          cs.onSurface.withValues(alpha: 0.08),
                          cs.surface,
                        )
                      : cs.surfaceContainerHighest,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
