import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_source/source_repositories.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/pages/comic_source_page.dart';
import 'package:kong_comic/utils/translations.dart';

/// Installs a script from [url] and returns the resulting source.
typedef SourceInstaller = Future<ComicSource?> Function(String url);

/// Catalog filters, mirroring the source-management page.
enum _CatalogFilter { all, notInstalled, installed, updatable }

/// Source repository management.
///
/// The user keeps a list of repositories (each one an `index.json` URL) and can
/// browse any of them to install sources. Every installed source remembers
/// which repository it came from, so "check for updates" only has to look at
/// the correct repositories.
class SourceRepositoriesPage extends StatefulWidget {
  const SourceRepositoriesPage({required this.install, super.key});

  final SourceInstaller install;

  @override
  State<SourceRepositoriesPage> createState() => _SourceRepositoriesPageState();
}

class _SourceRepositoriesPageState extends State<SourceRepositoriesPage> {
  final repositories = SourceRepositories.instance;

  SourceRepository? _opened;
  SourceCatalog? _catalog;
  String? _error;
  bool _loading = false;
  bool _selecting = false;
  final Set<String> _selected = {};
  bool _busy = false;
  _CatalogFilter _catalogFilter = _CatalogFilter.all;

  /// 正在更新的源（key），用于在条目按钮上显示进度。
  final Set<String> _updating = {};

  @override
  void initState() {
    super.initState();
    repositories.addListener(_update);
  }

  @override
  void dispose() {
    repositories.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  Future<void> _open(SourceRepository repository) async {
    setState(() {
      _opened = repository;
      _catalog = null;
      _error = null;
      _selecting = false;
      _selected.clear();
      _catalogFilter = _CatalogFilter.all;
    });
    await _load();
  }

  void _closeCatalog() {
    setState(() {
      _opened = null;
      _catalog = null;
      _error = null;
      _selecting = false;
      _selected.clear();
      _catalogFilter = _CatalogFilter.all;
    });
  }

  void _goBack() {
    if (_opened != null) {
      _closeCatalog();
    } else if (context.canPop()) {
      context.pop();
    } else {
      App.pop();
    }
  }

  Future<void> _load() async {
    final repository = _opened;
    if (repository == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await repositories.load(repository);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _edit([SourceRepository? repository]) async {
    final nameController = TextEditingController(text: repository?.name ?? '');
    final urlController = TextEditingController(text: repository?.url ?? '');
    final result = await showDialog<(String, String)?>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: repository == null ? "Add repository".tl : "Edit repository".tl,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: "Name".tl,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: "URL".tl,
                  hintText: "https://.../index.json",
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text("Cancel".tl),
          ),
          Button.filled(
            onPressed: () => Navigator.of(dialogContext).pop((
              nameController.text,
              urlController.text,
            )),
            child: Text("Save".tl),
          ),
        ],
      ),
    );
    if (result == null) return;
    try {
      await repositories.save(
        id: repository?.id,
        name: result.$1,
        url: result.$2,
      );
      // Catalog URL may have changed; keep the opened page in sync.
      final current = _opened;
      if (current != null) {
        final updated = repositories.find(current.id);
        if (updated == null) {
          _closeCatalog();
        } else if (updated.url != current.url) {
          setState(() {
            _opened = updated;
            _catalog = null;
          });
          await _load();
        }
      }
    } catch (e) {
      if (mounted) context.showMessage(message: e.toString());
    }
  }

  Future<void> _remove(SourceRepository repository) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: "Delete".tl,
        content: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "Delete repository '@name' ?".tlParams({'name': repository.name}),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text("Cancel".tl),
          ),
          Button.filled(
            color: context.colorScheme.error,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text("Delete".tl),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (_opened?.id == repository.id) _closeCatalog();
    await repositories.remove(repository);
  }

  Future<void> _install(SourceCatalogEntry entry) async {
    final repository = _opened;
    if (repository == null) return;
    final source = await widget.install(entry.url);
    if (source == null) return;
    try {
      await repositories.link(source.key, repository, entry);
    } catch (e) {
      if (mounted) context.showMessage(message: e.toString());
    }
    setState(() {});
  }

  /// 更新单个源：无论成功还是失败都给出明确结果。
  Future<void> _updateEntry(
    SourceCatalogEntry entry,
    ComicSource installed,
  ) async {
    setState(() => _updating.add(entry.key));
    try {
      await ComicSourcePage.update(installed, false);
      if (!mounted) return;
      context.showMessage(
        message: "Updated to @v".tlParams({'v': entry.version}),
      );
    } catch (e, s) {
      Log.error("Comic source", e, s);
      if (mounted) {
        context.showMessage(message: updateFailureMessage(e));
      }
    } finally {
      if (mounted) setState(() => _updating.remove(entry.key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// 与 [PopUpWidgetScaffold] / 全局 [Appbar] 保持同一套头部语言：
  /// 56dp + 状态栏、18px HugeIcon 图标、22px 中等字重标题。
  Widget _buildHeader(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      height: 56 + top,
      padding: EdgeInsets.only(top: top),
      width: double.infinity,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Tooltip(
            message: "Back".tl,
            child: IconButton(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedArrowLeft01,
                size: 18,
              ),
              onPressed: _goBack,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _opened?.name ?? "Repositories".tl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: kcFont22,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_opened != null)
            Tooltip(
              message: "Refresh".tl,
              child: IconButton(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
                onPressed: _selecting ? null : _load,
              ),
            ),
          if (_opened != null)
            Tooltip(
              message: _selecting ? "Cancel selection".tl : "Select".tl,
              child: IconButton(
                icon: HugeIcon(
                  icon: _selecting
                      ? HugeIcons.strokeRoundedCancelCircle
                      : HugeIcons.strokeRoundedCheckList,
                  size: 18,
                ),
                onPressed: _selecting ? _exitSelect : _enterSelect,
              ),
            ),
          Tooltip(
            message: _opened == null ? "Add repository".tl : "Edit".tl,
            child: IconButton(
              icon: HugeIcon(
                icon: _opened == null
                    ? HugeIcons.strokeRoundedAdd01
                    : HugeIcons.strokeRoundedEdit02,
                size: 18,
              ),
              onPressed: () => _edit(_opened),
            ),
          ),
          Tooltip(
            message: "Help".tl,
            child: IconButton(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedHelpCircle, size: 18),
              onPressed: () => launchUrlString(
                "https://github.com/venera-app/venera/blob/master/doc/comic_source.md",
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_opened != null) return _buildCatalogView();
    return _buildRepositoryList();
  }

  /// 圆角方底的图标徽章，与源卡片同一套视觉。
  Widget _iconBadge(List<List<dynamic>> icon) {
    final scheme = context.colorScheme;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(kcRadius10),
      ),
      child: Center(
        child: HugeIcon(icon: icon, size: 18, color: scheme.primary),
      ),
    );
  }

  Widget _card({required Widget child, VoidCallback? onTap}) {
    final scheme = context.colorScheme;
    final radius = BorderRadius.circular(kcCardRadius);
    return Padding(
      padding: const EdgeInsets.only(bottom: kcSpaceSm),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: scheme.outlineVariant, width: 0.6),
            ),
            padding: const EdgeInsets.fromLTRB(kcSpaceMd, kcSpaceMd, kcSpaceMd, kcSpaceMd),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildRepositoryList() {
    final all = repositories.all;
    if (all.isEmpty) return _buildEmpty();
    // 长按拖动排序：仓库的先后顺序即用户优先级，持久化在设置里。
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(kcSpaceMd, kcSpaceSm, kcSpaceMd, kcSpaceLg),
      itemCount: all.length,
      proxyDecorator: _dragProxy,
      onReorderItem: repositories.reorder,
      itemBuilder: (context, index) => KeyedSubtree(
        key: ValueKey(all[index].id),
        child: _buildRepositoryCard(all[index]),
      ),
    );
  }

  /// 拖动中的浮起效果：只加阴影，不改卡片本身的玻璃观感。
  Widget _dragProxy(Widget child, int index, Animation<double> animation) {
    return Material(
      color: Colors.transparent,
      elevation: 6 * animation.value,
      shadowColor: Colors.black26,
      child: child,
    );
  }

  Widget _buildRepositoryCard(SourceRepository repository) {
    final scheme = context.colorScheme;
    final stats = repositories.stats(repository.id);
    final subtitle = stats == null
        ? repository.url
        : stats.updatable > 0
            ? "${"N sources".tlParams({'count': stats.total})} · "
                "${"sources updatable".tlParams({'count': stats.updatable})}"
            : "N sources".tlParams({'count': stats.total});
    return _card(
      onTap: () => _open(repository),
      child: Row(
        children: [
          _iconBadge(HugeIcons.strokeRoundedFolder01),
          const SizedBox(width: kcSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  repository.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: kcFont15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: kcFont13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: kcSpaceXs),
          IconButton(
            tooltip: "Edit".tl,
            visualDensity: VisualDensity.compact,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedEdit02, size: 18),
            onPressed: () => _edit(repository),
          ),
          IconButton(
            tooltip: "Delete".tl,
            visualDensity: VisualDensity.compact,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete02, size: 18),
            onPressed: () => _remove(repository),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final scheme = context.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedFolder01,
              size: 44,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: kcSpaceLg),
            Text(
              "No source repositories yet.".tl,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: kcSubtitle, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: kcSpaceSm),
            Text(
              "Add a repository to browse and install comic source scripts.".tl,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: kcFont13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: kcSpaceLg),
            FilledButton.tonal(
              onPressed: () => _edit(),
              child: Text("Add repository".tl),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogView() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) return _buildError();
    final catalog = _catalog;
    if (catalog == null) return const SizedBox();
    final filtered = _catalogEntriesForDisplay();
    return Column(
      children: [
        if (!_selecting && catalog.entries.isNotEmpty) _buildCatalogFilterChips(),
        Expanded(
          child: filtered.isEmpty
              ? _buildCatalogEmpty()
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    kcSpaceMd,
                    kcSpaceSm,
                    kcSpaceMd,
                    kcSpaceLg,
                  ),
                  itemCount: filtered.length,
                  proxyDecorator: _dragProxy,
                  // 筛选 / 选择模式下顺序没有意义，直接关掉拖动。
                  buildDefaultDragHandles:
                      !_selecting && _catalogFilter == _CatalogFilter.all,
                  onReorderItem: _reorderCatalogEntries,
                  itemBuilder: (context, index) => KeyedSubtree(
                    key: ValueKey(filtered[index].key),
                    child: _buildEntry(filtered[index]),
                  ),
                ),
        ),
        if (_selecting) _buildBatchBar(),
      ],
    );
  }

  /// 目录按「用户拖出来的顺序 → 仓库原始顺序」展示。
  ///
  /// 同一个 key 在仓库里出现多次时只保留第一条：App 本来就按 key 去重，
  /// 重复条目既没法安装也没法区分（还会让拖动列表的 key 冲突）。
  List<SourceCatalogEntry> _catalogEntriesForDisplay() {
    final catalog = _catalog;
    if (catalog == null) return const [];
    final seen = <String>{};
    final unique = <SourceCatalogEntry>[];
    for (final entry in _applyCatalogFilter(catalog.entries)) {
      if (seen.add(entry.key)) unique.add(entry);
    }
    return repositories.applyCatalogOrder(_opened?.id, unique);
  }

  Future<void> _reorderCatalogEntries(int oldIndex, int newIndex) async {
    final repository = _opened;
    if (repository == null) return;
    final entries = _catalogEntriesForDisplay();
    if (oldIndex < 0 || oldIndex >= entries.length) return;
    final moved = entries.removeAt(oldIndex);
    entries.insert(newIndex, moved);
    await repositories.setCatalogOrder(
      repository.id,
      [for (final entry in entries) entry.key],
    );
    if (mounted) setState(() {});
  }

  Widget _buildCatalogEmpty() {
    final scheme = context.colorScheme;
    final label = switch (_catalogFilter) {
      _CatalogFilter.notInstalled => "All sources are installed.".tl,
      _CatalogFilter.installed => "No sources installed yet.".tl,
      _CatalogFilter.updatable => "Everything is up to date.".tl,
      _CatalogFilter.all => "No sources in this repository.".tl,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: kcFont13, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildCatalogFilterChips() {
    final scheme = context.colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(kcSpaceMd, kcSpaceXs, kcSpaceMd, 0),
      child: Row(
        children: _CatalogFilter.values.map((filter) {
          final selected = _catalogFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: kcSpaceXs),
            child: ChoiceChip(
              label: Text(_catalogFilterLabel(filter)),
              selected: selected,
              onSelected: (_) => setState(() => _catalogFilter = filter),
              selectedColor: kcBrandColor,
              labelStyle: TextStyle(
                color: selected ? Colors.white : scheme.onSurface,
                fontSize: kcFont13,
              ),
              visualDensity: VisualDensity.compact,
            ),
          );
        }).toList(),
      ),
    );
  }

  String _catalogFilterLabel(_CatalogFilter filter) => switch (filter) {
        _CatalogFilter.all => "All".tl,
        _CatalogFilter.notInstalled => "Not installed".tl,
        _CatalogFilter.installed => "Installed".tl,
        _CatalogFilter.updatable => "Updatable".tl,
      };

  List<SourceCatalogEntry> _applyCatalogFilter(
    List<SourceCatalogEntry> entries,
  ) {
    switch (_catalogFilter) {
      case _CatalogFilter.all:
        return entries;
      case _CatalogFilter.notInstalled:
        return entries
            .where((e) => ComicSource.find(e.key) == null)
            .toList();
      case _CatalogFilter.installed:
        return entries
            .where((e) => ComicSource.find(e.key) != null)
            .toList();
      case _CatalogFilter.updatable:
        return entries.where((e) {
          final source = ComicSource.find(e.key);
          return source != null && compareSemVer(e.version, source.version);
        }).toList();
    }
  }

  Widget _buildBatchBar() {
    final scheme = context.colorScheme;
    final anyInstall = _selected.any((k) => ComicSource.find(k) == null);
    final anyUpdate = _selected.any((k) {
      final source = ComicSource.find(k);
      return source != null &&
          _catalog != null &&
          _catalog!.entries.any(
            (e) => e.key == k && compareSemVer(e.version, source.version),
          );
    });
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 4,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          kcSpaceMd,
          kcSpaceSm,
          kcSpaceMd,
          kcSpaceMd,
        ),
        child: Row(
          children: [
            Text(
              "Selected @n".tlParams({'n': _selected.length.toString()}),
              style: const TextStyle(fontSize: kcFont13),
            ),
            const Spacer(),
            if (_busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              TextButton(
                onPressed: anyInstall ? _batchInstall : null,
                child: Text("Batch install".tl),
              ),
              const SizedBox(width: kcSpaceXs),
              TextButton(
                onPressed: anyUpdate ? _batchUpdate : null,
                child: Text("Batch update".tl),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _enterSelect() => setState(() {
        _selecting = true;
        _selected.clear();
      });

  void _exitSelect() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  void _toggleSelect(String key) => setState(() {
        if (_selected.contains(key)) {
          _selected.remove(key);
        } else {
          _selected.add(key);
        }
      });

  Future<void> _batchInstall() async {
    final catalog = _catalog;
    final repository = _opened;
    if (catalog == null || repository == null || _busy) return;
    final keys = _selected.toList();
    final targets = catalog.entries
        .where((e) => keys.contains(e.key) && ComicSource.find(e.key) == null)
        .toList();
    if (targets.isEmpty) {
      _exitSelect();
      return;
    }
    setState(() => _busy = true);
    var ok = 0;
    var fail = 0;
    for (final entry in targets) {
      try {
        final source = await widget.install(entry.url);
        if (source != null) {
          await repositories.link(source.key, repository, entry);
          ok++;
        } else {
          fail++;
        }
      } catch (e, s) {
        Log.error('Comic source', e, s);
        fail++;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    context.showMessage(
      message: "Installed @ok, failed @fail".tlParams({
        'ok': ok.toString(),
        'fail': fail.toString(),
      }),
    );
    _exitSelect();
  }

  Future<void> _batchUpdate() async {
    final catalog = _catalog;
    if (catalog == null || _busy) return;
    final keys = _selected.toList();
    final targets = <ComicSource>[];
    for (final entry in catalog.entries) {
      if (!keys.contains(entry.key)) continue;
      final installed = ComicSource.find(entry.key);
      if (installed != null && compareSemVer(entry.version, installed.version)) {
        targets.add(installed);
      }
    }
    if (targets.isEmpty) {
      _exitSelect();
      return;
    }
    setState(() => _busy = true);
    var ok = 0;
    var fail = 0;
    for (final source in targets) {
      try {
        await ComicSourcePage.update(source, false);
        ok++;
      } catch (e, s) {
        Log.error('Comic source', e, s);
        fail++;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    context.showMessage(
      message: "Updated @ok, failed @fail".tlParams({
        'ok': ok.toString(),
        'fail': fail.toString(),
      }),
    );
    // Versions changed, refresh the snapshot so the badges update.
    setState(() => _catalog = null);
    await _load();
    _exitSelect();
  }

  Widget _buildError() {
    final scheme = context.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedAlertCircle,
              size: 40,
              color: scheme.error,
            ),
            const SizedBox(height: kcSpaceMd),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: kcFont13, color: scheme.error),
            ),
            const SizedBox(height: kcSpaceLg),
            FilledButton.tonal(
              onPressed: _load,
              child: Text("Retry".tl),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntry(SourceCatalogEntry entry) {
    final scheme = context.colorScheme;
    final installed = ComicSource.find(entry.key);

    // Selection mode: tapping toggles membership, no install/update action.
    if (_selecting) {
      final selected = _selected.contains(entry.key);
      return _card(
        onTap: () => _toggleSelect(entry.key),
        child: Row(
          children: [
            _iconBadge(HugeIcons.strokeRoundedSourceCode),
            const SizedBox(width: kcSpaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: kcFont15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (entry.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: kcFont13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (entry.version.isNotEmpty) ...[
                    const SizedBox(height: kcSpaceXxs),
                    AppBadge(
                      entry.version,
                      type: AppBadgeType.neutral,
                      fontSize: kcFont13,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: kcSpaceSm),
            Icon(
              selected ? Icons.check : Icons.circle_outlined,
              color: selected ? scheme.primary : scheme.outline,
              size: 22,
            ),
          ],
        ),
      );
    }

    final Widget action;
    if (installed == null) {
      action = FilledButton.tonal(
        onPressed: () => _install(entry),
        child: Text("Add".tl),
      );
    } else if (compareSemVer(entry.version, installed.version)) {
      final updating = _updating.contains(entry.key);
      action = FilledButton.tonal(
        // 点下去立刻变成进度圈：之前没有加载状态，网络慢时看起来像「点了没反应」。
        onPressed: updating ? null : () => _updateEntry(entry, installed),
        child: updating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text("Update".tl),
      );
    } else {
      action = HugeIcon(
        icon: HugeIcons.strokeRoundedCheckmarkCircle01,
        size: 20,
        color: scheme.primary,
      );
    }
    return _card(
      child: Row(
        children: [
          _iconBadge(HugeIcons.strokeRoundedSourceCode),
          const SizedBox(width: kcSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: kcFont15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (entry.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: kcFont13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (installed != null) ...[
                  const SizedBox(height: kcSpaceXxs),
                  Text(
                    "Installed @v".tlParams({'v': installed.version}),
                    style: TextStyle(
                      fontSize: kcFont13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (entry.version.isNotEmpty) ...[
                  const SizedBox(height: kcSpaceXxs),
                  AppBadge(
                    entry.version,
                    type: AppBadgeType.neutral,
                    fontSize: kcFont13,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: kcSpaceSm),
          action,
        ],
      ),
    );
  }
}
