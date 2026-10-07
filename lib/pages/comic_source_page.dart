import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_source/source_repositories.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/network/app_dio.dart';
import 'package:kong_comic/network/cookie_jar.dart';
import 'package:kong_comic/pages/source_repositories_page.dart';
import 'package:kong_comic/pages/webview.dart';
import 'package:kong_comic/utils/ext.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:kong_comic/utils/translations.dart';

/// 更新失败时展示给用户的文案：异常自带可读说明时直接用它。
String updateFailureMessage(Object error) {
  if (error is String && error.trim().isNotEmpty) return error;
  // 网络异常不是 String，以前一律被压成一句「Failed to update source」。
  // 批量更新时用户只看到「N 个源更新失败」，既不知道是超时、404 还是别的，
  // 也没法反馈。这里把状态码 / 失败类型带出来。
  if (error is DioException) {
    final code = error.response?.statusCode;
    if (code != null) {
      return "Server returned @code".tlParams({"code": code.toString()});
    }
    return "${"Network error".tl} (${error.type.name})";
  }
  final text = error.toString().trim();
  if (text.isEmpty || text.length > 160) return "Failed to update source".tl;
  return text;
}

/// What an update actually did.
///
/// [installed] is the version the app ends up with, [target] the version the
/// repository advertised. They disagree when the repository bumped its
/// `index.json` but the script file itself still declares the old version —
/// either the source author forgot to bump it, or a CDN is still serving a
/// cached copy. Reporting the real number stops the app from claiming success
/// while the list keeps offering the same update forever.
typedef SourceUpdateOutcome = ({String? installed, String? target});

/// Message for a finished update, given what was installed and advertised.
String sourceUpdateMessage(SourceUpdateOutcome outcome) {
  final installed = outcome.installed;
  final target = outcome.target;
  if (installed != null) {
    if (target != null &&
        installed != target &&
        !compareSemVer(installed, target)) {
      return "Script is still @v, but the repository lists @new (the repository may be out of sync)"
          .tlParams({"v": installed, "new": target});
    }
    return "Updated to @v".tlParams({"v": installed});
  }
  return "Updated sources".tl;
}

class ComicSourcePage extends StatelessWidget {
  const ComicSourcePage({super.key});

  /// Updates [source].
  ///
  /// [reloadNow] controls whether the source list is rebuilt right away. Set it
  /// to `false` when several sources are updated back to back: [reload] re-parses
  /// *every* script on disk, so a batch of N sources used to mean N full reloads
  /// (N² script parses) — slow enough on a large batch to look like everything
  /// failed at once. Those callers do one reload at the end instead.
  static Future<SourceUpdateOutcome?> update(
    ComicSource source, [
    bool showLoading = true,
    bool reloadNow = true,
  ]) async {
    // Resolve through the repository catalog (if the source is linked to one)
    // so a changed folder layout upstream does not break the update.
    SourceUpdateTarget target;
    try {
      target = await SourceRepositories.instance.resolveUpdate(source);
    } catch (e, s) {
      Log.error("Update comic source", e, s);
      if (showLoading) {
        // 把具体原因透出来（例如「找不到下载地址」），否则用户只看到
        // 「更新失败」，无从判断该怎么做。
        App.rootContext.showMessage(message: updateFailureMessage(e));
        return null;
      } else {
        rethrow;
      }
    }
    return applyUpdate(
      source,
      target,
      showLoading: showLoading,
      reloadNow: reloadNow,
    );
  }

  /// Updates [source] from one specific catalog entry.
  ///
  /// The repository page has to use this instead of [update]: the user tapped
  /// the button of *that* row, so the download must come from *that* row's URL.
  /// [update] resolves the source's own recorded link, which can point at a
  /// different repository — the row shows the version of the repository being
  /// browsed while the download quietly installs the same old file from where
  /// the source originally came, leaving the row "updatable" forever.
  static Future<SourceUpdateOutcome?> updateFromEntry(
    ComicSource source,
    SourceRepository repository,
    SourceCatalogEntry entry, [
    bool showLoading = true,
    bool reloadNow = true,
  ]) {
    return applyUpdate(
      source,
      SourceUpdateTarget(url: entry.url, repository: repository, entry: entry),
      showLoading: showLoading,
      reloadNow: reloadNow,
    );
  }

  /// Downloads [target] over [source] and reports what actually got installed.
  static Future<SourceUpdateOutcome?> applyUpdate(
    ComicSource source,
    SourceUpdateTarget target, {
    bool showLoading = true,
    bool reloadNow = true,
  }) async {
    final url = target.url;
    if (!url.isURL) {
      if (showLoading) {
        App.rootContext.showMessage(message: "Invalid url config".tl);
        return null;
      } else {
        throw Exception("Invalid url config");
      }
    }
    // 旧版本安装的源没有归属记录（显示「未关联源仓库」）。这次是从某个仓库
    // 目录里解析到下载地址的，顺手把归属补上：以后更新直接走该仓库，不必再
    // 全量扫描，页面上也能看到它属于哪个仓库。
    final adoptRepository = target.repository;
    final adoptEntry = target.entry;
    // 归属指向别的仓库（或别的下载地址）时也要改过来。否则会出现「在 A 仓库
    // 的页面点了更新，装上的却是 B 仓库的旧脚本」：源永远停在 B 的版本上，
    // A 的页面每次都显示可更新，用户点了又点，什么也没发生。
    final origin = SourceRepositories.instance.originFor(source.key);
    final linkedRepository = SourceRepositories.instance.linkedRepository(
      source.key,
    );
    final needsLink = adoptRepository != null &&
        adoptEntry != null &&
        (linkedRepository?.id != adoptRepository.id ||
            origin?.url != adoptEntry.url);
    ComicSourceManager().remove(source.key);
    bool cancel = false;
    LoadingDialogController? controller;
    if (showLoading) {
      controller = showLoadingDialog(
        App.rootContext,
        onCancel: () => cancel = true,
        barrierDismissible: false,
      );
    }
    var updated = false;
    try {
      // 加一次性参数绕过 CDN 缓存：jsDelivr 对 `@main` 分支按文件分别缓存
      // 十二小时，仓库的 index.json 已经宣布 1.0.6、脚本文件仍返回缓存的
      // 1.0.5 是很常见的状态。那时「更新」会一路成功，版本号却纹丝不动，
      // 卡片上的「更新到 1.0.6」也就永远消不掉。
      var res = await AppDio().get<String>(
        SourceRepositories.bypassCache(url),
        options: Options(
          responseType: ResponseType.plain,
          headers: {"cache-time": "no"},
        ),
      );
      if (cancel) return null;
      controller?.close();
      await ComicSourceParser().parse(res.data!, source.filePath);
      await io.File(source.filePath).writeAsString(res.data!);
      // 必须走 manager：availableUpdates 返回的是副本，在副本上 remove
      // 等于什么都没做，源会一直挂着「有更新」的角标。同时把这个目标版本
      // 记为「已取过」，避免仓库 index 与脚本版本不一致时反复提示同一个更新。
      ComicSourceManager().acknowledgeUpdate(source.key, adoptEntry?.version);
      if (needsLink) {
        try {
          await SourceRepositories.instance.link(
            source.key,
            adoptRepository,
            adoptEntry,
          );
        } catch (e, s) {
          // 补归属只是顺手优化，失败不该让一次已经成功的更新变成报错。
          Log.error("Link comic source", e, s);
        }
      }
      updated = true;
    } catch (e, s) {
      if (cancel) return null;
      if (showLoading) {
        Log.error("Update comic source", e, s);
        App.rootContext.showMessage(message: updateFailureMessage(e));
      } else {
        rethrow;
      }
    } finally {
      // Always put the source back: it was removed from the manager above, so
      // leaving this out would make it disappear from the UI until the next
      // app restart whenever the update fails *or* the user cancels.
      if (reloadNow) {
        try {
          await ComicSourceManager().reload();
        } catch (e, s) {
          // `finally` 里抛出的异常会替换掉 try/catch 正在往外抛的那个：失控的
          // reload 会把真正的失败原因顶掉，用户看到的永远是 reload 的错误。
          Log.error("Reload comic source", e, s);
        }
      }
      _syncSourceOrder();
      _addAllPagesWithComicSource(source);
      if (showLoading) {
        App.forceRebuild();
      }
    }
    if (!updated) return null;
    final outcome = (
      installed: ComicSource.find(source.key)?.version,
      target: adoptEntry?.version,
    );
    if (showLoading) {
      App.rootContext.showMessage(message: sourceUpdateMessage(outcome));
    }
    return outcome;
  }

  /// Checks every linked repository for newer versions.
  ///
  /// Returns details about what was checked and what failed, instead of a bare
  /// count, so a broken repository can be reported without hiding the rest.
  static Future<SourceUpdateCheck> checkComicSourceUpdate() async {
    if (ComicSource.all().isEmpty) {
      return const SourceUpdateCheck(
        updates: {},
        failures: [],
        checked: 0,
        skipped: 0,
      );
    }
    try {
      final result = await SourceRepositories.instance.checkUpdates(
        ComicSource.all(),
      );
      // 已经下载过的目标版本不再报：仓库 index 与脚本内容不同步时（index
      // 1.6.7 / 脚本 1.6.6），否则每次检查都会把同一个更新重新挂上去。
      final manager = ComicSourceManager();
      final pending = Map<String, String>.from(result.updates)
        ..removeWhere((key, version) => manager.hasAcknowledgedUpdate(key, version));
      // 替换而不是合并：合并会让曾经报过的源在这个列表里永久残留。仓库不再
      // 提供某个更新（已经装好了 / 条目被下架）时它本轮不会出现在
      // result.updates 里，合并却把它留在原处；而「有更新」筛选只按 key 判断，
      // 于是源会被钉在这个筛选里直到重启。
      manager.replaceAvailableUpdates(pending);
      return SourceUpdateCheck(
        updates: pending,
        failures: result.failures,
        checked: result.checked,
        skipped: result.skipped,
        repositoryFailures: result.repositoryFailures,
      );
    } catch (e) {
      return SourceUpdateCheck(
        updates: const {},
        failures: [e.toString()],
        checked: 0,
        skipped: 0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: const _Body());
  }
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

/// Source list filters shown as a chip row above the list.
enum _SourceFilter { all, enabled, disabled, unreachable, update }

class _BodyState extends State<_Body> {
  var url = "";

  /// Selection mode for batch operations.
  bool _selecting = false;
  final Set<String> _selected = {};

  /// Connectivity test result per source key: '', 'testing', 'ok', 'fail'.
  final Map<String, String> _health = {};

  /// Optional detail for a failed connectivity test (e.g. HTTP status code).
  final Map<String, String> _healthDetail = {};

  /// True while a "test all" run is in progress.
  bool _testingAll = false;

  /// True while an "update all" run is in progress.
  bool _updatingAll = false;

  /// True while the automatic update check (triggered by the 「有更新」 filter
  /// or by "update all") is running.
  bool _checkingUpdates = false;

  /// Active source list filter. When not [all], reordering is disabled because
  /// the visible subset no longer maps 1:1 onto the global source order.
  _SourceFilter _filter = _SourceFilter.all;

  void updateUI() {
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ComicSourceManager().addListener(updateUI);
    // Repair sources added before auto-enable existed (e.g. a source whose
    // discover/category tab was missing from the enabled lists).
    _ensureAllPagesEnabled();
  }

  @override
  void dispose() {
    super.dispose();
    ComicSourceManager().removeListener(updateUI);
  }

  @override
  Widget build(BuildContext context) {
    final sources = orderedComicSources();
    final filtered = _applyFilter(sources);
    final filtering = _filter != _SourceFilter.all;
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(
          title: _selecting
              ? Text("Selected @n sources"
                  .tlParams({"n": _selected.length.toString()}))
              : Text('Comic Source'.tl),
          style: AppbarStyle.shadow,
          actions: [
            if (_selecting) ...[
              TextButton(
                onPressed: () {
                  setState(() {
                    _selected.addAll(sources.map((s) => s.key));
                  });
                },
                child: Text("Select all".tl),
              ),
              TextButton(
                onPressed: _exitSelection,
                child: Text("Cancel selection".tl),
              ),
            ] else ...[
              Tooltip(
                message: "Test all".tl,
                child: IconButton(
                  onPressed: _testingAll ? null : _testAll,
                  icon: _testingAll
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : HugeIcon(
                          icon: HugeIcons.strokeRoundedLink01,
                          size: 18,
                        ),
                ),
              ),
              // 带文字的「全部更新」：原来只有一个刷新图标挂在工具栏里，
              // 不看 tooltip 根本认不出是干什么的。
              TextButton.icon(
                onPressed: _updatingAll ? null : _updateAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: _updatingAll
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
                label: Text("Update all".tl),
              ),
              Tooltip(
                message: "Select".tl,
                child: IconButton(
                  onPressed: _enterSelection,
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                    size: 18,
                  ),
                ),
              ),
            ],
          ],
        ),
        buildCard(context),
        if (!_selecting) _buildFilterChips(),
        if (filtered.isEmpty)
          SliverToBoxAdapter(child: _buildEmptySources()),
        SliverReorderableList(
          itemCount: filtered.length,
          onReorderItem: (_selecting || filtering) ? (_, __) {} : onReorderItem,
          itemBuilder: (context, index) {
            final source = filtered[index];
            return _ComicSourceCard(
              key: ValueKey(source.key),
              source: source,
              index: index,
              edit: edit,
              update: update,
              delete: delete,
              selecting: _selecting,
              selected: _selected.contains(source.key),
              onToggleSelect: _toggleSelect,
              health: _health[source.key] ?? '',
              healthDetail: _healthDetail[source.key] ?? '',
              disabled: ComicSourceManager().isDisabled(source.key),
              onToggleDisabled: _toggleDisabled,
              onTest: _testSource,
              pinToTop: pinToTop,
            );
          },
        ),
        if (_selecting) SliverToBoxAdapter(child: _buildBatchBar(context)),
        SliverPadding(padding: EdgeInsets.only(bottom: context.padding.bottom)),
      ],
    );
  }

  void onReorderItem(int oldIndex, int newIndex) {
    final sources = orderedComicSources();
    final moved = sources.removeAt(oldIndex);
    sources.insert(newIndex, moved);
    appdata.settings['sourceOrder'] = sources.map((s) => s.key).toList();
    _syncSourceOrder();
    setState(() {});
  }

  List<ComicSource> _applyFilter(List<ComicSource> sources) {
    switch (_filter) {
      case _SourceFilter.all:
        return sources;
      case _SourceFilter.enabled:
        return sources
            .where((s) => !ComicSourceManager().isDisabled(s.key))
            .toList();
      case _SourceFilter.disabled:
        return sources
            .where((s) => ComicSourceManager().isDisabled(s.key))
            .toList();
      case _SourceFilter.unreachable:
        return sources
            .where((s) {
              final h = _health[s.key] ?? '';
              return h == 'fail' ||
                  h == 'proxy' ||
                  h == 'timeout' ||
                  h == 'http';
            })
            .toList();
      case _SourceFilter.update:
        final updates = ComicSourceManager().availableUpdates;
        return sources.where((s) => updates.containsKey(s.key)).toList();
    }
  }

  /// Switching to 「有更新」 has to actually look for updates: nothing else
  /// fills [ComicSourceManager.availableUpdates] until an explicit check, so the
  /// filter would otherwise show an empty list that looks like "nothing to
  /// update" even though we never asked.
  Future<void> _setFilter(_SourceFilter f) async {
    setState(() => _filter = f);
    if (f != _SourceFilter.update) return;
    if (ComicSourceManager().availableUpdates.isNotEmpty) return;
    await _refreshUpdates();
  }

  Future<void> _refreshUpdates() async {
    if (_checkingUpdates) return;
    setState(() => _checkingUpdates = true);
    try {
      await ComicSourcePage.checkComicSourceUpdate();
    } finally {
      if (mounted) {
        setState(() => _checkingUpdates = false);
      } else {
        _checkingUpdates = false;
      }
    }
  }

  /// Shown instead of an empty list, so "no rows" never reads as a bug.
  Widget _buildEmptySources() {
    final scheme = Theme.of(context).colorScheme;
    final String message;
    if (_checkingUpdates) {
      message = "Checking for updates".tl;
    } else if (_filter == _SourceFilter.update) {
      message = "All sources up to date".tl;
    } else {
      message = "No sources match this filter.".tl;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
      child: Column(
        children: [
          if (_checkingUpdates) ...[
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: kcFont13, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            for (final f in _SourceFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_filterLabel(f)),
                  selected: _filter == f,
                  onSelected: (_) => _setFilter(f),
                  selectedColor: kcBrandColor,
                  labelStyle: TextStyle(
                    color: _filter == f ? Colors.white : scheme.onSurfaceVariant,
                    fontSize: kcFont13,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _filterLabel(_SourceFilter f) {
    return switch (f) {
      _SourceFilter.all => "All".tl,
      _SourceFilter.enabled => "Enabled".tl,
      _SourceFilter.disabled => "Disabled".tl,
      _SourceFilter.unreachable => "Unreachable".tl,
      _SourceFilter.update => "Update available".tl,
    };
  }

  void pinToTop(ComicSource source) {
    final sources = orderedComicSources();
    if (sources.isEmpty || sources.first.key == source.key) return;
    sources.remove(source);
    sources.insert(0, source);
    appdata.settings['sourceOrder'] = sources.map((s) => s.key).toList();
    _syncSourceOrder();
    setState(() {});
  }

  void delete(ComicSource source) {
    showConfirmDialog(
      context: App.rootContext,
      title: "Delete".tl,
      content: "Delete comic source '@n' ?".tlParams({"n": source.name}),
      btnColor: context.colorScheme.error,
      onConfirm: () {
        var file = File(source.filePath);
        file.delete();
        ComicSourceManager().remove(source.key);
        SourceRepositories.instance.setOrigin(source.key, null);
        _syncSourceOrder();
        _validatePages();
        App.forceRebuild();
      },
    );
  }

  void edit(ComicSource source) async {
    if (App.isDesktop) {
      try {
        await Process.run("code", [source.filePath], runInShell: true);
        await showDialog(
          context: App.rootContext,
          builder: (context) => ContentDialog(
            title: "Reload Configs".tl,
            content: const SizedBox.shrink(),
            actions: [
              TextButton(
                onPressed: () => context.pop(),
                child: Text("Cancel".tl),
              ),
              TextButton(
                onPressed: () async {
                  await ComicSourceManager().reload();
                  App.forceRebuild();
                },
                child: Text("Continue".tl),
              ),
            ],
          ),
        );
        return;
      } catch (e) {
        //
      }
    }
    context.to(
      () => _EditFilePage(source.filePath, () async {
        await ComicSourceManager().reload();
        setState(() {});
      }),
    );
  }

  void update(ComicSource source, [bool showLoading = true]) {
    ComicSourcePage.update(source, showLoading);
  }

  void _enterSelection() {
    setState(() => _selecting = true);
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleSelect(ComicSource source) {
    setState(() {
      if (_selected.contains(source.key)) {
        _selected.remove(source.key);
      } else {
        _selected.add(source.key);
      }
    });
  }

  Widget _buildBatchBar(BuildContext context) {
    final compact = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      textStyle: const TextStyle(fontSize: 13),
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)
          .add(EdgeInsets.only(bottom: context.padding.bottom)),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: _selected.isEmpty ? null : () => batchSetDisabled(false),
            icon: HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle01, size: 18),
            label: Text("Batch enable".tl),
            style: compact,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _selected.isEmpty ? null : () => batchSetDisabled(true),
            icon: HugeIcon(icon: HugeIcons.strokeRoundedCancelCircle, size: 18),
            label: Text("Batch disable".tl),
            style: compact,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _selected.isEmpty ? null : batchUpdate,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
            label: Text("Batch update".tl),
            style: compact,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _selected.isEmpty ? null : batchDelete,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
            label: Text("Batch delete".tl),
            style: FilledButton.styleFrom(
              backgroundColor: context.colorScheme.error,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _exitSelection,
            child: Text("Cancel selection".tl),
          ),
        ],
      ),
    );
  }

  Future<void> batchUpdate() async {
    final keys = _selected.toList();
    final controller = showLoadingDialog(
      App.rootContext,
      barrierDismissible: false,
    );
    var failed = 0;
    for (final k in keys) {
      final s = ComicSource.find(k);
      if (s != null) {
        try {
          // reloadNow=false：reload 会把磁盘上每个脚本重新解析一遍，批量的话
          // 等于 N 个源 × N 次解析，一轮下来慢到像全部失败。
          await ComicSourcePage.update(s, false, false);
        } catch (e, s2) {
          // `update` rethrows when `showLoading` is false. Never let one broken
          // script abort the batch — and never leave the loading dialog up.
          failed++;
          Log.error("Update comic source", e, s2);
        }
      }
    }
    try {
      await ComicSourceManager().reload();
    } catch (e, s2) {
      Log.error("Reload comic source", e, s2);
    }
    controller.close();
    if (mounted) {
      if (failed > 0) {
        App.rootContext.showMessage(
          message: "@n sources could not be updated"
              .tlParams({"n": failed.toString()}),
        );
      }
      setState(() {
        _selecting = false;
        _selected.clear();
      });
    }
  }

  void batchDelete() {
    if (_selected.isEmpty) return;
    final keys = _selected.toList();
    showConfirmDialog(
      context: App.rootContext,
      title: "Delete".tl,
      content: "Delete @n comic sources?"
          .tlParams({"n": keys.length.toString()}),
      btnColor: context.colorScheme.error,
      onConfirm: () {
        for (final k in keys) {
          final s = ComicSource.find(k);
          if (s != null) {
            File(s.filePath).delete();
            ComicSourceManager().remove(s.key);
            SourceRepositories.instance.setOrigin(s.key, null);
          }
        }
        _syncSourceOrder();
        _validatePages();
        App.forceRebuild();
        if (mounted) {
          setState(() {
            _selecting = false;
            _selected.clear();
          });
        }
      },
    );
  }

  /// Enables (disabled = false) or disables every selected source at once.
  void batchSetDisabled(bool disabled) {
    if (_selected.isEmpty) return;
    final keys = _selected.toList();
    for (final k in keys) {
      ComicSourceManager().setSourceDisabled(k, disabled);
    }
    _validatePages();
    App.forceRebuild();
    if (mounted) {
      setState(() {
        _selecting = false;
        _selected.clear();
      });
    }
  }

  void _toggleDisabled(ComicSource source) {
    final disabled = ComicSourceManager().isDisabled(source.key);
    ComicSourceManager().setSourceDisabled(source.key, !disabled);
    _validatePages();
    App.forceRebuild();
    setState(() {});
  }

  Future<void> _testSource(ComicSource source) async {
    if (source.explorePages.isEmpty) {
      setState(() => _health[source.key] = 'fail');
      return;
    }
    setState(() {
      _health[source.key] = 'testing';
      _healthDetail.remove(source.key);
    });
    var category = 'fail';
    try {
      final page = source.explorePages.first;
      dynamic res;
      if (page.loadPage != null) {
        res = await page.loadPage!(0);
      } else if (page.loadMultiPart != null) {
        res = await page.loadMultiPart!();
      } else if (page.loadMixed != null) {
        res = await page.loadMixed!(0);
      } else {
        if (!mounted) return;
        setState(() => _health[source.key] = category);
        return;
      }
      // res 为 null（脚本直接返回空）时按失败处理，避免 NoSuchMethodError。
      if (res == null || res.error) {
        // 源返回了错误结果，按错误信息细分失败类型
        final msg = (res?.errorMessage as String? ?? '').toLowerCase();
        if (msg.contains('timeout')) {
          category = 'timeout';
        } else if (msg.contains('proxy') || msg.contains('connect')) {
          category = 'proxy';
        } else if (RegExp(r'http\s*\d{3}').hasMatch(msg) ||
            msg.contains('status code')) {
          category = 'http';
          final code = RegExp(r'(\d{3})').firstMatch(msg)?.group(1);
          if (code != null) _healthDetail[source.key] = code;
        } else {
          category = 'fail';
        }
      } else {
        category = 'ok';
      }
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          category = 'timeout';
        case DioExceptionType.connectionError:
          category = 'proxy';
        case DioExceptionType.badResponse:
          category = 'http';
          final code = e.response?.statusCode;
          if (code != null) _healthDetail[source.key] = code.toString();
        default:
          category = 'fail';
      }
    } catch (_) {
      category = 'fail';
    }
    // 测试是异步的，用户可能中途退出本页。
    if (!mounted) return;
    setState(() => _health[source.key] = category);
  }

  Future<void> _testAll() async {
    if (_testingAll) return;
    setState(() => _testingAll = true);
    // finally：任何一次 _testSource 抛错（例如页面已销毁时的 setState）
    // 都不能把 _testingAll 永久留在 true，否则按钮会一直卡在加载态。
    try {
      for (final s in orderedComicSources()) {
        await _testSource(s);
      }
    } finally {
      if (mounted) {
        setState(() => _testingAll = false);
      } else {
        _testingAll = false;
      }
    }
  }

  Future<void> _updateAll() async {
    if (_updatingAll) return;
    setState(() => _updatingAll = true);
    final result = await ComicSourcePage.checkComicSourceUpdate();
    // 用 manager 里的待更新表（已剔除本次会话取过的版本），而不是检查结果
    // 的原始表，否则每次「更新全部」都会重下同一个永远不前进的脚本。
    final updates =
        Map<String, String>.from(ComicSourceManager().availableUpdates);
    final n = updates.length;
    // 失败不能只记个数：光报「N 个源更新失败」，用户不知道该重试谁、我们
    // 也没法定位是超时、404 还是脚本解析失败。把源名和原因一起收起来。
    final failures = <(String name, String reason)>[];
    if (n > 0) {
      for (final key in updates.keys) {
        final s = ComicSource.find(key);
        if (s == null) continue;
        try {
          // reloadNow=false：每个源单独 reload 一次等于把全部脚本重新解析 N 遍。
          await ComicSourcePage.update(s, false, false);
        } catch (e, s2) {
          // `update` rethrows when `showLoading` is false; without this the
          // first broken script would skip the `setState` below and leave
          // the button stuck in its loading state forever.
          failures.add((s.name, updateFailureMessage(e)));
          Log.error("Update comic source", e, s2);
        }
      }
      // 整批结束统一重建一次：中间每个源都跳过 reload，源列表到这里才恢复。
      try {
        await ComicSourceManager().reload();
      } catch (e, s2) {
        Log.error("Reload comic source", e, s2);
      }
    }
    App.forceRebuild();
    // 顺序不能反：先确认还挂载着再 setState。反过来的话，若用户在批量更新
    // 期间退出了本页，setState 会抛 "called after dispose()"，后面的提示
    // 逻辑也全部被跳过。
    if (!mounted) return;
    setState(() => _updatingAll = false);
    // Keep repository-level problems and per-source ones apart, otherwise
    // "N repositories failed to load" also counts things like "multiple
    // variants found" and points the user at the wrong thing.
    if (result.repositoryFailures.isNotEmpty) {
      App.rootContext.showMessage(
        message: "@n repositories failed to load".tlParams({
          "n": result.repositoryFailures.length.toString(),
        }),
      );
    } else if (failures.isNotEmpty) {
      await _showUpdateFailures(failures);
    } else if (result.failures.isNotEmpty) {
      App.rootContext.showMessage(
        message: "@n sources could not be updated".tlParams({
          "n": result.failures.length.toString(),
        }),
      );
    } else {
      App.rootContext.showMessage(
        message: n > 0 ? "Updated sources".tl : "All sources up to date".tl,
      );
    }
  }

  /// 列出每个更新失败的源和原因。
  ///
  /// 只报一个数字没法行动：用户不知道该重试哪个，也没法把问题反馈清楚。
  Future<void> _showUpdateFailures(
    List<(String name, String reason)> failures,
  ) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: "@n sources could not be updated".tlParams({
          "n": failures.length.toString(),
        }),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: failures.length,
              itemBuilder: (context, index) {
                final (name, reason) = failures[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reason,
                        style: TextStyle(
                          fontSize: kcFont13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          Button.filled(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text("OK".tl),
          ),
        ],
      ),
    );
  }

  Widget buildCard(BuildContext context) {
    return SliverToBoxAdapter(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text("Add comic source".tl),
              leading: HugeIcon(icon: HugeIcons.strokeRoundedDashboardCircle, size: 18),
            ),
            TextField(
              decoration: InputDecoration(
                hintText: "URL".tl,
                border: const UnderlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                suffix: IconButton(
                  onPressed: () => handleAddSource(url),
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle01, size: 18),
                ),
              ),
              onChanged: (value) {
                url = value;
              },
              onSubmitted: handleAddSource,
            ).paddingHorizontal(16).paddingBottom(8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    onPressed: () {
                      showPopUpWidget(
                        App.rootContext,
                        SourceRepositoriesPage(install: handleAddSource),
                      );
                    },
                    child: Text("Repositories".tl),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    onPressed: _selectFile,
                    child: Text("Use a config file".tl),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    onPressed: help,
                    child: Text("Help".tl),
                  ),
                ),
              ],
            ).paddingHorizontal(12).paddingVertical(8),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _selectFile() async {
    final file = await selectFile(ext: ["js"]);
    if (file == null) return;
    try {
      var fileName = file.name;
      var bytes = await file.readAsBytes();
      var content = utf8.decode(bytes);
      await addSource(content, fileName, fromFile: true);
    } catch (e, s) {
      App.rootContext.showMessage(message: "Failed to add source".tl);
      Log.error("Add comic source", "$e\n$s");
    }
  }

  void help() {
    launchUrlString(
      "https://github.com/venera-app/venera/blob/master/doc/comic_source.md",
    );
  }

  /// Installs a single script from [url]. Returns the installed source, or
  /// null when the user cancelled or the download failed.
  Future<ComicSource?> handleAddSource(String url) async {
    if (url.isEmpty) {
      return null;
    }
    var splits = url.split("/");
    splits.removeWhere((element) => element == "");
    var fileName = splits.last;
    bool cancel = false;
    var controller = showLoadingDialog(
      App.rootContext,
      onCancel: () => cancel = true,
      barrierDismissible: false,
    );
    try {
      var res = await AppDio().get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {"cache-time": "no"},
        ),
      );
      if (cancel) return null;
      controller.close();
      return await addSource(res.data!, fileName, originUrl: url);
    } catch (e, s) {
      if (cancel) return null;
      context.showMessage(message: "Failed to add source".tl);
      Log.error("Add comic source", "$e\n$s");
      return null;
    }
  }

  /// Installs a script and records where it came from.
  ///
  /// [fromFile] sources are marked as imported, everything else is assumed to
  /// come from [originUrl] (falling back to the URL inside the script). Callers
  /// installing from a repository should use [SourceRepositories.link] instead.
  Future<ComicSource> addSource(
    String js,
    String fileName, {
    String? originUrl,
    bool fromFile = false,
  }) async {
    // Re-installing a key that is already present overwrites it; if the new
    // version is not newer, confirm first so a downgrade is never silent.
    final key = ComicSourceParser.extractKey(js);
    ComicSource? existing;
    if (key != null) existing = ComicSource.find(key);
    if (existing != null) {
      final newVersion = ComicSourceParser.extractVersion(js) ?? "1.0.0";
      if (!compareSemVer(newVersion, existing.version)) {
        final ok = await _confirmOverwrite(existing, newVersion);
        if (!ok) return existing;
      }
    }
    var comicSource = await ComicSourceParser().createAndParse(js, fileName);
    ComicSourceManager().add(comicSource);
    var recordedUrl = originUrl ?? comicSource.url;
    await SourceRepositories.instance.setOrigin(
      comicSource.key,
      SourceOrigin(
        kind: fromFile ? 'file' : 'url',
        url: recordedUrl.isEmpty ? null : recordedUrl,
      ),
    );
    _syncSourceOrder();
    _addAllPagesWithComicSource(comicSource);
    appdata.saveData();
    App.forceRebuild();
    return comicSource;
  }

  /// Asks the user whether to overwrite an already-installed source whose new
  /// version is not newer than the installed one. Returns false if declined.
  Future<bool> _confirmOverwrite(ComicSource existing, String newVersion) async {
    final completer = Completer<bool>();
    if (!mounted) return false;
    showDialog(
      context: App.rootContext,
      builder: (ctx) => ContentDialog(
        title: "Overwrite source".tl,
        content: Text(
          "A source '@n' (v@old) is already installed. Install the older or same version v@new over it?"
              .tlParams({
            "n": existing.name,
            "old": existing.version,
            "new": newVersion,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctx.pop();
              completer.complete(false);
            },
            child: Text("Cancel".tl),
          ),
          FilledButton(
            onPressed: () {
              ctx.pop();
              completer.complete(true);
            },
            child: Text("Overwrite".tl),
          ),
        ],
      ),
    );
    return completer.future;
  }
}

/// Returns all comic sources ordered by the user-defined [sourceOrder]
/// setting. Sources not yet present in [sourceOrder] (e.g. newly added)
/// are appended in their natural (filesystem) order.
List<ComicSource> orderedComicSources() {
  final order = appdata.settings['sourceOrder'];
  final all = ComicSource.all();
  if (order is! List || order.isEmpty) return all;
  final map = <String, ComicSource>{for (var s in all) s.key: s};
  final result = <ComicSource>[];
  for (var k in order) {
    if (k is String && map.containsKey(k)) {
      result.add(map[k]!);
      map.remove(k);
    }
  }
  result.addAll(map.values);
  return result;
}

/// Reconciles [appdata.settings]['sourceOrder'] with the currently loaded
/// sources: drops keys for removed sources and appends keys for new ones.
void _syncSourceOrder() {
  final all = ComicSource.all();
  final currentKeys = all.map((s) => s.key).toSet();
  final order = List<String>.from(appdata.settings['sourceOrder'] ?? []);
  // 一个都没加载出来通常意味着这次 reload 出了问题（脚本解析临时失败就会被
  // 静默跳过）。照常“清理”会把用户排好的顺序整份清空，之后所有源都按文件顺
  // 序重新排列。宁可什么都不做。
  if (all.isEmpty) return;
  order.removeWhere((k) => !currentKeys.contains(k));
  for (var s in all) {
    if (!order.contains(s.key)) order.add(s.key);
  }
  appdata.settings['sourceOrder'] = order;
  appdata.saveData();
}

/// Ensures every loaded source's explore pages and category are present in the
/// enabled lists. Runs once at startup to repair sources that were added before
/// auto-enable existed (e.g. a source whose discover/category tab was missing).
void _ensureAllPagesEnabled() {
  bool changed = false;
  final explorePages =
      List<String>.from(appdata.settings['explore_pages'] ?? []);
  final categoryPages =
      List<String>.from(appdata.settings['categories'] ?? []);
  for (final s in ComicSource.all()) {
    for (final p in s.explorePages) {
      if (!explorePages.contains(p.title)) {
        explorePages.add(p.title);
        changed = true;
      }
    }
    final cat = s.categoryData?.key;
    if (cat != null && !categoryPages.contains(cat)) {
      categoryPages.add(cat);
      changed = true;
    }
  }
  if (changed) {
    appdata.settings['explore_pages'] = explorePages.toSet().toList();
    appdata.settings['categories'] = categoryPages.toSet().toList();
    appdata.saveData();
  }
}

void _validatePages() {
  List explorePages = appdata.settings['explore_pages'];
  List categoryPages = appdata.settings['categories'];
  List networkFavorites = appdata.settings['favorites'];

  var totalExplorePages = ComicSource.all()
      .map((e) => e.explorePages.map((e) => e.title))
      .expand((element) => element)
      .toList();
  var totalCategoryPages = ComicSource.all()
      .map((e) => e.categoryData?.key)
      .where((element) => element != null)
      .map((e) => e!)
      .toList();
  var totalNetworkFavorites = ComicSource.all()
      .map((e) => e.favoriteData?.key)
      .where((element) => element != null)
      .map((e) => e!)
      .toList();

  for (var page in List.from(explorePages)) {
    if (!totalExplorePages.contains(page)) {
      explorePages.remove(page);
    }
  }
  for (var page in List.from(categoryPages)) {
    if (!totalCategoryPages.contains(page)) {
      categoryPages.remove(page);
    }
  }
  for (var page in List.from(networkFavorites)) {
    if (!totalNetworkFavorites.contains(page)) {
      networkFavorites.remove(page);
    }
  }

  appdata.settings['explore_pages'] = explorePages.toSet().toList();
  appdata.settings['categories'] = categoryPages.toSet().toList();
  appdata.settings['favorites'] = networkFavorites.toSet().toList();

  appdata.saveData();
}

void _addAllPagesWithComicSource(ComicSource source) {
  var explorePages = appdata.settings['explore_pages'];
  var categoryPages = appdata.settings['categories'];
  var networkFavorites = appdata.settings['favorites'];
  var searchPages = appdata.settings['searchSources'];

  if (source.explorePages.isNotEmpty) {
    for (var page in source.explorePages) {
      if (!explorePages.contains(page.title)) {
        explorePages.add(page.title);
      }
    }
  }
  if (source.categoryData != null &&
      !categoryPages.contains(source.categoryData!.key)) {
    categoryPages.add(source.categoryData!.key);
  }
  if (source.favoriteData != null &&
      !networkFavorites.contains(source.favoriteData!.key)) {
    networkFavorites.add(source.favoriteData!.key);
  }
  if (source.searchPageData != null && !searchPages.contains(source.key)) {
    searchPages.add(source.key);
  }

  appdata.settings['explore_pages'] = explorePages.toSet().toList();
  appdata.settings['categories'] = categoryPages.toSet().toList();
  appdata.settings['favorites'] = networkFavorites.toSet().toList();
  appdata.settings['searchSources'] = searchPages.toSet().toList();

  appdata.saveData();
}

class _EditFilePage extends StatefulWidget {
  const _EditFilePage(this.path, this.onExit);

  final String path;

  final void Function() onExit;

  @override
  State<_EditFilePage> createState() => __EditFilePageState();
}

class __EditFilePageState extends State<_EditFilePage> {
  var current = '';

  @override
  void initState() {
    super.initState();
    current = File(widget.path).readAsStringSync();
  }

  @override
  void dispose() {
    File(widget.path).writeAsStringSync(current);
    widget.onExit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Appbar(title: Text("Edit".tl)),
      body: Column(
        children: [
          Container(height: 0.6, color: context.colorScheme.outlineVariant),
          Expanded(
            child: CodeEditor(
              initialValue: current,
              onChanged: (value) => current = value,
            ),
          ),
        ],
      ),
    );
  }
}

class _CallbackSetting extends StatefulWidget {
  const _CallbackSetting({required this.setting, required this.sourceKey});

  final MapEntry<String, Map<String, dynamic>> setting;

  final String sourceKey;

  @override
  State<_CallbackSetting> createState() => _CallbackSettingState();
}

class _CallbackSettingState extends State<_CallbackSetting> {
  String get key => widget.setting.key;

  String get buttonText => widget.setting.value['buttonText'] ?? "Click".tl;

  String get title => widget.setting.value['title'] ?? key;

  bool isLoading = false;

  Future<void> onClick() async {
    var func = widget.setting.value['callback'];
    var result = func([]);
    if (result is Future) {
      setState(() {
        isLoading = true;
      });
      try {
        await result;
      } finally {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title.ts(widget.sourceKey)),
      trailing: Button.normal(
        onPressed: onClick,
        isLoading: isLoading,
        child: Text(buttonText.ts(widget.sourceKey)),
      ).fixHeight(32),
    );
  }
}

class _ComicSourceCard extends StatefulWidget {
  const _ComicSourceCard({
    super.key,
    required this.source,
    required this.index,
    required this.edit,
    required this.update,
    required this.delete,
    this.selecting = false,
    this.selected = false,
    this.onToggleSelect = _noopToggle,
    this.health = '',
    this.healthDetail = '',
    this.disabled = false,
    this.onToggleDisabled = _noopDisable,
    this.onTest = _noopTest,
    required this.pinToTop,
  });

  final ComicSource source;

  /// Position of this source in the current (ordered) list; consumed by the
  /// [ReorderableDragStartListener] to start a drag.
  final int index;

  final void Function(ComicSource source) edit;
  final void Function(ComicSource source) update;
  final void Function(ComicSource source) delete;

  /// Whether the parent is in batch-selection mode.
  final bool selecting;

  /// Whether this source is currently selected.
  final bool selected;

  /// Toggles selection of this source (only used in selection mode).
  final void Function(ComicSource source) onToggleSelect;

  /// Connectivity test result for this source: '', 'testing', 'ok', 'fail'.
  final String health;

  /// Optional detail for a failed connectivity test (e.g. HTTP status code).
  final String healthDetail;

  /// Whether this source is currently disabled (hidden across the app).
  final bool disabled;

  final void Function(ComicSource source) onToggleDisabled;
  final void Function(ComicSource source) onTest;
  final void Function(ComicSource source) pinToTop;

  @override
  State<_ComicSourceCard> createState() => _ComicSourceCardState();
}

void _noopToggle(ComicSource _) {}
void _noopDisable(ComicSource _) {}
void _noopTest(ComicSource _) {}

class _ComicSourceCardState extends State<_ComicSourceCard> {
  ComicSource get source => widget.source;

  /// Whether this source's settings/account block is expanded.
  bool _expanded = false;

  /// True while this card's own 「更新」 is running, so a second tap cannot
  /// start a concurrent update of the same source.
  bool _updating = false;

  Future<void> _updateSource() async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      await ComicSourcePage.update(source);
    } catch (e, s) {
      // ComicSourcePage.update already surfaces its own errors when it owns
      // the loading dialog; this is the belt-and-braces case.
      Log.error("Update comic source", e, s);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  /// Whether expanding this card would show anything at all. A source that is
  /// only a search endpoint would otherwise render an empty bordered panel.
  bool get _hasDetailContent =>
      source.explorePages.isNotEmpty ||
      source.categoryData != null ||
      source.favoriteData != null ||
      source.searchPageData != null ||
      source.settings != null ||
      source.account != null;

  @override
  Widget build(BuildContext context) {
    final newVersion = ComicSourceManager().availableUpdates[source.key];
    final hasUpdate =
        newVersion != null && compareSemVer(newVersion, source.version);

    return Opacity(
      opacity: widget.disabled ? 0.55 : 1.0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
        border: Border.all(
          color: context.colorScheme.outlineVariant,
          width: 0.8,
        ),
        borderRadius: BorderRadius.circular(kcRadius10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.selecting)
                Checkbox(
                  value: widget.selected,
                  onChanged: (_) => widget.onToggleSelect(source),
                )
              else
                // Drag handle: long-press to reorder this module.
                ReorderableDragStartListener(
                  index: widget.index,
                  child: Tooltip(
                    message: "Drag to reorder".tl,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedDrag01,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: InkWell(
                  onTap: widget.selecting
                      ? () => widget.onToggleSelect(source)
                      : () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              source.name,
                              style: ts.s18,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (widget.disabled)
                                  AppBadge("Disabled".tl,
                                      type: AppBadgeType.warning, fontSize: kcFont13),
                                if (source.account != null)
                                  AppBadge(
                                    source.isLogged ? "Logged in".tl : "Login required".tl,
                                    type: source.isLogged
                                        ? AppBadgeType.success
                                        : AppBadgeType.warning,
                                    fontSize: kcFont13,
                                  ),
                                if (hasUpdate)
                                  Tooltip(
                                    message: newVersion,
                                    child: AppBadge("New Version".tl, type: AppBadgeType.warning, fontSize: kcFont13),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ),
                ),
              ),
              if (!widget.selecting)
                Tooltip(
                  message: "Settings".tl,
                  child: IconButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                  icon: AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowDown01,
                      size: 18,
                    ),
                  ),
                ),
              ),
              if (!widget.selecting)
                PopupMenuButton<String>(
                  tooltip: "More".tl,
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedMoreHorizontal,
                    size: 18,
                  ),
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':
                        widget.edit(source);
                      case 'update':
                        widget.update(source);
                      case 'delete':
                        widget.delete(source);
                      case 'pin':
                        widget.pinToTop(source);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          HugeIcon(icon: HugeIcons.strokeRoundedEdit01, size: 16),
                          const SizedBox(width: 8),
                          Text("Edit".tl),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'update',
                      child: Row(
                        children: [
                          HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 16),
                          const SizedBox(width: 8),
                          Text("Update".tl),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 16),
                          const SizedBox(width: 8),
                          Text("Delete".tl),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'pin',
                      enabled: widget.index != 0,
                      child: Row(
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedAlignTop,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text("Pin to top".tl),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          _buildStatusRow(),
          if (_expanded && _hasDetailContent)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: context.colorScheme.primary.withValues(alpha: 0.4),
                    width: 3,
                  ),
                  top: BorderSide(
                    color: context.colorScheme.outlineVariant,
                    width: 0.6,
                  ),
                ),
              ),
              child: Column(
                children: [
                  ..._buildPageToggles(),
                  ...buildSourceSettings(),
                  ..._buildAccount(),
                ],
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildStatusRow() {
    final enabledExplore =
        List<String>.from(appdata.settings['explore_pages'] ?? []);
    final enabledCategory =
        List<String>.from(appdata.settings['categories'] ?? []);
    final expTotal = source.explorePages.length;
    final expOn = source.explorePages
        .where((e) => enabledExplore.contains(e.title))
        .length;
    final catTotal = source.categoryData != null ? 1 : 0;
    final catOn = (source.categoryData != null &&
            enabledCategory.contains(source.categoryData!.key))
        ? 1
        : 0;
    final health = widget.health;
    final cs = Theme.of(context).colorScheme;

    // Tapping a summary badge no longer toggles everything at once (one stray
    // tap used to switch off a whole source) — it opens the card, where each
    // entry has its own switch and the "all" buttons live.
    Widget toggleBadge(String text, bool enabled, VoidCallback onTap) {
      return Tooltip(
        message: "Tap to expand and enable pages one by one".tl,
        child: GestureDetector(
          onTap: onTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Opacity(
              opacity: enabled ? 1.0 : 0.5,
              child: AppBadge(
                text,
                backgroundColor: enabled ? kcBrandColor : null,
                foregroundColor: enabled ? Colors.white : null,
                type: AppBadgeType.neutral,
                fontSize: kcFont13,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              ),
            ),
          ),
        ),
      );
    }

    final detail = widget.healthDetail;

    Widget healthBadge() {
      if (health == 'testing') {
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      }
      if (health == 'ok') {
        return AppBadge(
          "Reachable".tl,
          type: AppBadgeType.success,
          fontSize: kcFont13,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        );
      }
      if (health == 'proxy') {
        return AppBadge(
          "Proxy required".tl,
          backgroundColor: cs.error,
          foregroundColor: cs.onError,
          fontSize: kcFont13,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        );
      }
      if (health == 'timeout') {
        return AppBadge(
          "Timeout".tl,
          type: AppBadgeType.warning,
          fontSize: kcFont13,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        );
      }
      if (health == 'http') {
        final label = detail.isNotEmpty
            ? "HTTP @code".tlParams({"code": detail})
            : "HTTP Error".tl;
        return AppBadge(
          label,
          type: AppBadgeType.warning,
          fontSize: kcFont13,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        );
      }
      // 未测试('') → 「未测试」，与已测试但失败的「未连通」区分，
      // 否则卡片显示「未连通」而「未连通」筛选却查不到（health 为空）。
      if (health.isEmpty) {
        return Opacity(
          opacity: 0.6,
          child: AppBadge(
            "Not tested".tl,
            type: AppBadgeType.neutral,
            fontSize: kcFont13,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          ),
        );
      }
      // 已测试但不可达('fail') → 未连通
      return AppBadge(
        "Unreachable".tl,
        type: AppBadgeType.neutral,
        fontSize: kcFont13,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      );
    }

    final infoChips = <Widget>[
      if (expTotal > 0)
        toggleBadge(
          "${"Explore".tl} $expOn/$expTotal",
          expOn > 0,
          _expandCard,
        ),
      if (catTotal > 0)
        toggleBadge(
          "${"Categories".tl} $catOn/$catTotal",
          catOn > 0,
          _expandCard,
        ),
      healthBadge(),
      AppBadge(
        source.version,
        type: AppBadgeType.neutral,
        fontSize: kcFont13,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      // Which repository this script was installed from.
      AppBadge(
        SourceRepositories.instance.originLabel(source.key),
        type: AppBadgeType.neutral,
        fontSize: kcFont13,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
    ];

    final actions = <Widget>[];
    if (!widget.selecting) {
      // 每个源都能直接点「更新」——之前只能长按卡片去 ⋮ 菜单里找，等于藏起来了。
      // 有可用更新时高亮并带上目标版本号，没更新时也保留（可用来重装/修复脚本）。
      final newVersion = ComicSourceManager().availableUpdates[source.key];
      final hasUpdate = newVersion != null &&
          compareSemVer(newVersion, source.version);
      actions.addAll([
        _actionChip(
          icon: HugeIcons.strokeRoundedRefresh,
          label: _updating
              ? "Updating…".tl
              : (hasUpdate
                  ? "Update to @v".tlParams({"v": newVersion})
                  : "Update".tl),
          onTap: () => _updateSource(),
          active: hasUpdate,
        ),
        _actionChip(
          icon: HugeIcons.strokeRoundedLink01,
          label: "Test".tl,
          onTap: () => widget.onTest(source),
        ),
        _actionChip(
          icon: widget.disabled
              ? HugeIcons.strokeRoundedCancelCircle
              : HugeIcons.strokeRoundedCheckmarkCircle01,
          label: widget.disabled ? "Disabled".tl : "Enabled".tl,
          onTap: () => widget.onToggleDisabled(source),
          active: !widget.disabled,
        ),
      ]);
    }

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A Wrap instead of a horizontal scroller: with several chips the old
          // row silently clipped them ("No repository lin…"), hiding exactly the
          // information it existed to show.
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: infoChips,
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 6),
            // 三个 chip（更新 / 测试 / 已启用）加上「更新到 x.y.z」的长文案，
            // 在窄屏上会撑出卡片；Wrap 让它们换行而不是被裁掉。
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }

  /// A compact pill for the row-level actions.
  ///
  /// Enable/disable changes icon, colour *and* text, so the current state is
  /// readable at a glance instead of being a single recoloured icon that means
  /// the opposite depending on a colour the user has to remember.
  Widget _actionChip({
    required List<List<dynamic>> icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final background = active ? kcBrandColor : scheme.surfaceContainerHighest;
    final foreground = active ? Colors.white : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.outlineVariant, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(icon: icon, size: 14, color: foreground),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: kcFont13,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _expandCard() => setState(() => _expanded = true);

  /// Per-entry switches for everything this source can contribute to the app:
  /// its explore (discover) tabs, its category tab, its network favorites and
  /// its search. Each row maps 1:1 onto an entry of the corresponding global
  /// setting list, so a single busy tab can be parked without losing the rest.
  Iterable<Widget> _buildPageToggles() sync* {
    yield* _pageGroup(
      "Explore Pages",
      "explore_pages",
      HugeIcons.strokeRoundedCompass,
      [
        for (final p in source.explorePages)
          (value: p.title, label: p.title.ts(source.key)),
      ],
    );
    if (source.categoryData != null) {
      yield* _pageGroup("Category Pages", "categories",
          HugeIcons.strokeRoundedGridView, [
        (value: source.categoryData!.key, label: source.categoryData!.title),
      ]);
    }
    if (source.favoriteData != null) {
      yield* _pageGroup("Network Favorite Pages", "favorites",
          HugeIcons.strokeRoundedHeartCheck, [
        (value: source.favoriteData!.key, label: source.favoriteData!.title),
      ]);
    }
    if (source.searchPageData != null) {
      yield* _pageGroup("Search Sources", "searchSources",
          HugeIcons.strokeRoundedSearch01, [
        (value: source.key, label: source.name),
      ]);
    }
  }

  /// Renders one group of per-entry switches plus an all on/off shortcut.
  Iterable<Widget> _pageGroup(
    String title,
    String settingKey,
    List<List<dynamic>> icon,
    List<({String value, String label})> entries,
  ) sync* {
    final scheme = Theme.of(context).colorScheme;
    final current = List<String>.from(appdata.settings[settingKey] ?? []);
    final onCount = entries.where((e) => current.contains(e.value)).length;
    final allOn = onCount == entries.length;

    final sorted = [...entries]
      ..sort((a, b) {
        final onA = current.contains(a.value) ? 0 : 1;
        final onB = current.contains(b.value) ? 0 : 1;
        return onA != onB ? onA - onB : a.label.compareTo(b.label);
      });

    yield Padding(
      padding: const EdgeInsets.only(left: 16, right: 8, top: 4),
      child: Row(
        children: [
          HugeIcon(icon: icon, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            "${title.tl} $onCount/${entries.length}",
            style: TextStyle(
              fontSize: kcFont13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => _setGroupEnabled(
              settingKey,
              [for (final e in entries) e.value],
              !allOn,
            ),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
            ),
            child: Text(
              (allOn ? "Disable all" : "Enable all").tl,
              style: const TextStyle(fontSize: kcFont13),
            ),
          ),
        ],
      ),
    );

    for (final entry in sorted) {
      final on = current.contains(entry.value);
      yield ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.only(left: 20, right: 8),
        title: Text(
          entry.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: kcFont15,
            color: on ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
        trailing: Switch(
          value: on,
          onChanged: (v) => _setGroupEnabled(settingKey, [entry.value], v),
        ),
      );
    }
  }

  /// Adds/removes [values] from [settingKey] and persists the result.
  void _setGroupEnabled(String settingKey, List<String> values, bool enabled) {
    final list = List<String>.from(appdata.settings[settingKey] ?? []);
    if (enabled) {
      for (final v in values) {
        if (!list.contains(v)) list.add(v);
      }
    } else {
      list.removeWhere(values.contains);
    }
    appdata.settings[settingKey] = list;
    appdata.saveData();
    setState(() {});
  }

  Iterable<Widget> buildSourceSettings() sync* {
    // Try to get dynamic settings first (for getters), fall back to cached settings
    var settingsMap = source.getSettingsDynamic() ?? source.settings;
    
    if (settingsMap == null) {
      return;
    } else if (source.data['settings'] == null) {
      source.data['settings'] = {};
    }
    for (var item in settingsMap.entries) {
      var key = item.key;
      String type = item.value['type'];
      try {
        if (type == "select") {
          var current = source.data['settings'][key];
          if (current == null) {
            var d = item.value['default'];
            for (var option in item.value['options']) {
              if (option['value'] == d) {
                current = option['text'] ?? option['value'];
                break;
              }
            }
          } else {
            current =
                item.value['options'].firstWhere(
                  (e) => e['value'] == current,
                )['text'] ??
                current;
          }
          yield ListTile(
            title: Text((item.value['title'] as String).ts(source.key)),
            trailing: Select(
              current: (current as String).ts(source.key),
              values: (item.value['options'] as List)
                  .map<String>(
                    (e) => ((e['text'] ?? e['value']) as String).ts(source.key),
                  )
                  .toList(),
              onTap: (i) {
                source.data['settings'][key] =
                    item.value['options'][i]['value'];
                source.saveData();
                setState(() {});
              },
            ),
          );
        } else if (type == "switch") {
          var current = source.data['settings'][key] ?? item.value['default'];
          yield ListTile(
            title: Text((item.value['title'] as String).ts(source.key)),
            trailing: Switch(
              value: current,
              onChanged: (v) {
                source.data['settings'][key] = v;
                source.saveData();
                setState(() {});
              },
            ),
          );
        } else if (type == "input") {
          var current =
              source.data['settings'][key] ?? item.value['default'] ?? '';
          yield ListTile(
            title: Text((item.value['title'] as String).ts(source.key)),
            subtitle: Text(
              current,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedEdit01, size: 18),
              onPressed: () {
                showInputDialog(
                  context: context,
                  title: (item.value['title'] as String).ts(source.key),
                  initialValue: current,
                  inputValidator: item.value['validator'] == null
                      ? null
                      : RegExp(item.value['validator']),
                  onConfirm: (value) {
                    source.data['settings'][key] = value;
                    source.saveData();
                    setState(() {});
                    return null;
                  },
                );
              },
            ),
          );
        } else if (type == "callback") {
          yield _CallbackSetting(setting: item, sourceKey: source.key);
        }
      } catch (e, s) {
        Log.error("ComicSourcePage", "Failed to build a setting\n$e\n$s");
      }
    }
  }

  final _reLogin = <String, bool>{};

  Iterable<Widget> _buildAccount() sync* {
    if (source.account == null) return;
    final bool logged = source.isLogged;
    if (!logged) {
      yield ListTile(
        title: Text("Log in".tl),
        trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: 18),
        onTap: () async {
          await context.to(
            () => _LoginPage(config: source.account!, source: source),
          );
          source.saveData();
          setState(() {});
        },
      );
    }
    if (logged) {
      for (var item in source.account!.infoItems) {
        if (item.builder != null) {
          yield item.builder!(context);
        } else {
          yield ListTile(
            title: Text(item.title.tl),
            subtitle: item.data == null ? null : Text(item.data!()),
            onTap: item.onTap,
          );
        }
      }
      if (source.data["account"] is List) {
        bool loading = _reLogin[source.key] == true;
        yield ListTile(
          title: Text("Re-login".tl),
          subtitle: Text("Click if login expired".tl),
          onTap: () async {
            if (source.data["account"] == null) {
              context.showMessage(message: "No data".tl);
              return;
            }
            setState(() {
              _reLogin[source.key] = true;
            });
            final List account = source.data["account"];
            if (source.account == null) {
              context.showMessage(message: "Login not supported".tl);
              setState(() {
                _reLogin[source.key] = false;
              });
              return;
            }
            var res = await source.account!.login!(account[0], account[1]);
            if (res.error) {
              context.showMessage(message: res.errorMessage!);
            } else {
              context.showMessage(message: "Success".tl);
            }
            setState(() {
              _reLogin[source.key] = false;
            });
          },
          trailing: loading
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
        );
      }
      yield ListTile(
        title: Text("Log out".tl),
        onTap: () {
          source.data["account"] = null;
          source.account?.logout();
          source.saveData();
          ComicSourceManager().notifyStateChange();
          setState(() {});
        },
        trailing: HugeIcon(icon: HugeIcons.strokeRoundedLogout01, size: 18),
      );
    }
  }
}

/// 打开指定漫画源的登录页（账号密码 / WebView 登录）。
///
/// 返回 [Navigator.pop] 的结果；不论登录是否成功，返回后都会保存一次源
/// 数据，使登录态对调用方立即可见。
Future<T?> navigateToSourceLogin<T>(BuildContext context, ComicSource source) async {
  final result = await context.to<T>(
    () => _LoginPage(config: source.account!, source: source),
  );
  source.saveData();
  return result;
}

class _LoginPage extends StatefulWidget {
  const _LoginPage({required this.config, required this.source});

  final AccountConfig config;

  final ComicSource source;

  @override
  State<_LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<_LoginPage> {
  String username = "";
  String password = "";
  bool loading = false;

  final Map<String, String> _cookies = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const Appbar(title: Text('')),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(kcSpaceLg),
          constraints: const BoxConstraints(maxWidth: 400),
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Login".tl, style: const TextStyle(fontSize: kcFont24)),
                const SizedBox(height: 32),
                if (widget.config.cookieFields == null)
                  TextField(
                    decoration: InputDecoration(
                      labelText: "Username".tl,
                      border: const OutlineInputBorder(),
                    ),
                    enabled: widget.config.login != null,
                    onChanged: (s) {
                      username = s;
                    },
                    autofillHints: const [AutofillHints.username],
                  ).paddingBottom(16),
                if (widget.config.cookieFields == null)
                  TextField(
                    decoration: InputDecoration(
                      labelText: "Password".tl,
                      border: const OutlineInputBorder(),
                    ),
                    obscureText: true,
                    enabled: widget.config.login != null,
                    onChanged: (s) {
                      password = s;
                    },
                    onSubmitted: (s) => login(),
                    autofillHints: const [AutofillHints.password],
                  ).paddingBottom(16),
                for (var field in widget.config.cookieFields ?? <String>[])
                  TextField(
                    decoration: InputDecoration(
                      labelText: field,
                      border: const OutlineInputBorder(),
                    ),
                    obscureText: true,
                    enabled: widget.config.validateCookies != null,
                    onChanged: (s) {
                      _cookies[field] = s;
                    },
                  ).paddingBottom(16),
                if (widget.config.login == null &&
                    widget.config.cookieFields == null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle, size: 18),
                      const SizedBox(width: 8),
                      Text("Login with password is disabled".tl),
                    ],
                  )
                else
                  Button.filled(
                    isLoading: loading,
                    onPressed: login,
                    child: Text("Continue".tl),
                  ),
                const SizedBox(height: 24),
                if (widget.config.loginWebsite != null)
                  TextButton(
                    onPressed: () {
                      if (App.isLinux) {
                        loginWithWebview2();
                      } else {
                        loginWithWebview();
                      }
                    },
                    child: Text("Login with webview".tl),
                  ),
                const SizedBox(height: 8),
                if (widget.config.registerWebsite != null)
                  TextButton(
                    onPressed: () =>
                        launchUrlString(widget.config.registerWebsite!),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(icon: HugeIcons.strokeRoundedLink01, size: 18),
                        const SizedBox(width: 8),
                        Text("Create Account".tl),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void login() {
    if (widget.config.login != null) {
      if (username.isEmpty || password.isEmpty) {
        showToast(
          message: "Cannot be empty".tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle, size: 18),
          context: context,
        );
        return;
      }
      setState(() {
        loading = true;
      });
      widget.config.login!(username, password).then((value) {
        if (value.error) {
          context.showMessage(message: value.errorMessage!);
          setState(() {
            loading = false;
          });
        } else {
          if (mounted) {
            context.pop();
          }
        }
      });
    } else if (widget.config.validateCookies != null) {
      setState(() {
        loading = true;
      });
      var cookies = widget.config.cookieFields!
          .map((e) => _cookies[e] ?? '')
          .toList();
      widget.config.validateCookies!(cookies).then((value) {
        if (value) {
          widget.source.data['account'] = 'ok';
          widget.source.saveData();
          context.pop();
        } else {
          context.showMessage(message: "Invalid cookies".tl);
          setState(() {
            loading = false;
          });
        }
      });
    }
  }

  void loginWithWebview() async {
    var url = widget.config.loginWebsite!;
    var title = '';
    bool success = false;

    void validate(InAppWebViewController c) async {
      if (widget.config.checkLoginStatus != null &&
          widget.config.checkLoginStatus!(url, title)) {
        var cookies = (await c.getCookies(url)) ?? [];
        var localStorageItems = await c.webStorage.localStorage.getItems();
        var mappedLocalStorage = <String, dynamic>{};
        for (var item in localStorageItems) {
          if (item.key != null) {
            mappedLocalStorage[item.key!] = item.value;
          }
        }
        widget.source.data['_localStorage'] = mappedLocalStorage;
        await widget.source.saveData();
        SingleInstanceCookieJar.instance?.saveFromResponse(
          Uri.parse(url),
          cookies,
        );
        success = true;
        widget.config.onLoginWithWebviewSuccess?.call();
        App.mainNavigatorKey?.currentContext?.pop();
      }
    }

    await context.to(
      () => AppWebview(
        initialUrl: widget.config.loginWebsite!,
        onNavigation: (u, c) {
          url = u;
          validate(c);
          return false;
        },
        onTitleChange: (t, c) {
          title = t;
          validate(c);
        },
      ),
    );
    if (success) {
      widget.source.data['account'] = 'ok';
      widget.source.saveData();
      context.pop();
    }
  }

  // for linux
  void loginWithWebview2() async {
    if (!await DesktopWebview.isAvailable()) {
      context.showMessage(message: "Webview is not available".tl);
    }

    var url = widget.config.loginWebsite!;
    var title = '';
    bool success = false;

    void onClose() {
      if (success) {
        widget.source.data['account'] = 'ok';
        widget.source.saveData();
        context.pop();
      }
    }

    void validate(DesktopWebview webview) async {
      if (widget.config.checkLoginStatus != null &&
          widget.config.checkLoginStatus!(url, title)) {
        var cookiesMap = await webview.getCookies(url);
        var cookies = <io.Cookie>[];
        cookiesMap.forEach((key, value) {
          cookies.add(io.Cookie(key, value));
        });
        SingleInstanceCookieJar.instance?.saveFromResponse(
          Uri.parse(url),
          cookies,
        );
        var localStorageJson = await webview.evaluateJavascript(
          "JSON.stringify(window.localStorage);",
        );
        var localStorage = <String, dynamic>{};
        try {
          var decoded = jsonDecode(localStorageJson ?? '');
          if (decoded is Map<String, dynamic>) {
            localStorage = decoded;
          }
        } catch (e) {
          Log.error("ComicSourcePage", "Failed to parse localStorage JSON\n$e");
        }
        widget.source.data['_localStorage'] = localStorage;
        await widget.source.saveData();
        success = true;
        widget.config.onLoginWithWebviewSuccess?.call();
        webview.close();
        onClose();
      }
    }

    var webview = DesktopWebview(
      initialUrl: widget.config.loginWebsite!,
      onTitleChange: (t, webview) {
        title = t;
        validate(webview);
      },
      onNavigation: (u, webview) {
        url = u;
        validate(webview);
      },
      onClose: onClose,
    );

    webview.open();
  }
}
