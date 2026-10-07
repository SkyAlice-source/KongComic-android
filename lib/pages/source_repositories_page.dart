import 'dart:io';

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
      // fresh: 用户主动打开/下拉刷新仓库，就是要看它现在的样子。吃 12 小时
      // 的 CDN 缓存会让「已安装 1.0.5 / 可更新 1.0.6」这类状态一直停在过期
      // 版本上，点更新则装到另一个版本，看起来像更新失败。
      final catalog = await repositories.load(repository, fresh: true);
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
  ///
  /// 这里必须按「用户看到的那一条」的下载地址更新（[ComicSourcePage.updateFromEntry]），
  /// 而不是让源按自己的归属去解析：归属可能指向另一个仓库，于是页面显示
  /// 「已安装 1.0.3 / 可更新 1.1.3」，点更新却装回那个仓库的 1.0.3，按钮永远
  /// 消不掉。顺带把归属重链到本仓库，以后检查更新也走这里。
  Future<void> _updateEntry(
    SourceCatalogEntry entry,
    ComicSource installed,
  ) async {
    final repository = _opened;
    if (repository == null) return;
    setState(() => _updating.add(entry.key));
    var changed = false;
    try {
      final outcome = await ComicSourcePage.updateFromEntry(
        installed,
        repository,
        entry,
        false,
      );
      changed = outcome != null;
      if (!mounted) return;
      // 报实际装上的版本，而不是仓库宣称的版本：脚本文件可能还停在旧版本
      // （CDN 缓存 / 作者忘了改），直接报宣称值会让人以为更新成功了。
      context.showMessage(
        message: outcome == null ? "Updated source".tl : sourceUpdateMessage(outcome),
      );
    } catch (e, s) {
      Log.error("Comic source", e, s);
      if (mounted) {
        context.showMessage(message: updateFailureMessage(e));
      }
    } finally {
      if (mounted) setState(() => _updating.remove(entry.key));
    }
    // 真的装上了新版本之后重新拉一次 index。作者常常在同一次提交里既改脚本
    // 又改 index，页面却还拿更新前的快照去比「已安装 x / 可更新 y」，两个数字
    // 对不上；批量更新走的是同一条刷新，单个更新以前漏了。
    if (changed && mounted) {
      setState(() => _catalog = null);
      await _load();
    }
  }

  /// 重装确认：重装会从仓库重新拉脚本并覆盖本地文件，可能冲掉手改，先问一声。
  Future<void> _confirmReinstall(
    SourceCatalogEntry entry,
    ComicSource installed,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: "Reinstall".tl,
        content: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text("Reinstall confirm".tlParams({'name': entry.name})),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text("Cancel".tl),
          ),
          Button.filled(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text("Reinstall".tl),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _updateEntry(entry, installed);
    }
  }

  /// 逐条卸载：只移除这一个源（删文件 + 从管理器注销），不影响其它源。
  Future<void> _confirmUninstall(SourceCatalogEntry entry) async {
    final source = ComicSource.find(entry.key);
    if (source == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: "Uninstall".tl,
        content: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text("Uninstall confirm".tlParams({'name': entry.name})),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text("Cancel".tl),
          ),
          Button.filled(
            color: context.colorScheme.error,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text("Uninstall".tl),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await File(source.filePath).delete();
      ComicSourceManager().remove(entry.key);
      context.showMessage(
        message: "Source uninstalled".tlParams({'name': entry.name}),
      );
    } catch (e) {
      if (mounted) context.showMessage(message: e.toString());
    }
    setState(() {});
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
    final repository = _opened;
    if (catalog == null || repository == null || _busy) return;
    final keys = _selected.toList();
    // 记的是「条目」而不是源：更新的下载地址必须来自用户看到的这一条
    // （见 [_updateEntry] 的说明）。
    final targets = <SourceCatalogEntry>[];
    for (final entry in catalog.entries) {
      if (!keys.contains(entry.key)) continue;
      final installed = ComicSource.find(entry.key);
      if (installed != null && compareSemVer(entry.version, installed.version)) {
        targets.add(entry);
      }
    }
    if (targets.isEmpty) {
      _exitSelect();
      return;
    }
    setState(() => _busy = true);
    var ok = 0;
    var fail = 0;
    // 仓库 index 比脚本文件新的时候（作者漏改 / CDN 没同步），下载会成功、
    // 版本却纹丝不动。这种「更新成功」是假的，单独计数告诉用户。
    var stale = 0;
    for (final entry in targets) {
      final installed = ComicSource.find(entry.key);
      if (installed == null) continue;
      try {
        // reloadNow=false：逐个 reload 会把全部脚本重解析 N 遍，这里统一一次。
        final outcome = await ComicSourcePage.updateFromEntry(
          installed,
          repository,
          entry,
          false,
          false,
        );
        if (outcome != null && outcome.installed != outcome.target) {
          stale++;
        } else {
          ok++;
        }
      } catch (e, s) {
        Log.error('Comic source', e, s);
        fail++;
      }
    }
    try {
      await ComicSourceManager().reload();
    } catch (e, s) {
      Log.error('Comic source', e, s);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    var message = "Updated @ok, failed @fail".tlParams({
      'ok': ok.toString(),
      'fail': fail.toString(),
    });
    if (stale > 0) {
      message += " · "
          "${"Repository out of sync: @n".tlParams({'n': stale.toString()})}";
    }
    context.showMessage(message: message);
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
    // 已经试过、而且确认下不到仓库宣称的那个版本：index 比脚本文件新
    // （作者漏改 / CDN 未同步），再点更新也是白点。见 [update] 的确认记录。
    final outOfSync = installed != null &&
        compareSemVer(entry.version, installed.version) &&
        ComicSourceManager().hasAcknowledgedUpdate(entry.key, entry.version);

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

    final Widget primaryAction;
    if (installed == null) {
      primaryAction = FilledButton.tonal(
        onPressed: () => _install(entry),
        child: Text("Add".tl),
      );
    } else {
      // 只有「真能拿到的新版」才显示 Update；否则（已是最新、或仓库未同步）
      // 这个按钮用来「重装 / 修复」——重新拉一次脚本覆盖本地文件。重装会
      // 冲掉本地手改的脚本，所以走确认弹窗（见 [_confirmReinstall]）。
      final realUpdate =
          compareSemVer(entry.version, installed.version) && !outOfSync;
      final updating = _updating.contains(entry.key);
      primaryAction = FilledButton.tonal(
        onPressed: updating
            ? null
            : (realUpdate
                ? () => _updateEntry(entry, installed)
                : () => _confirmReinstall(entry, installed)),
        child: updating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(realUpdate ? "Update".tl : "Reinstall".tl),
      );
    }

    final Widget trailing;
    if (installed == null) {
      trailing = primaryAction;
    } else {
      // 逐条卸载：只移除这一个源，不影响其它源。带确认，避免误删。
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          primaryAction,
          const SizedBox(width: kcSpaceXs),
          IconButton(
            tooltip: "Uninstall".tl,
            visualDensity: VisualDensity.compact,
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedDelete02,
              size: 18,
              color: scheme.error,
            ),
            onPressed: () => _confirmUninstall(entry),
          ),
        ],
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
                  Wrap(
                    spacing: kcSpaceXxs,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AppBadge(
                        entry.version,
                        type: AppBadgeType.neutral,
                        fontSize: kcFont13,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                      ),
                      if (outOfSync)
                        AppBadge(
                          "Repository out of sync".tl,
                          type: AppBadgeType.warning,
                          fontSize: kcFont13,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: kcSpaceSm),
          trailing,
        ],
      ),
    );
  }
}
