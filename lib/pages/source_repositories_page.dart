import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_source/source_repositories.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/pages/comic_source_page.dart';
import 'package:kong_comic/utils/translations.dart';

/// Installs a script from [url] and returns the resulting source.
typedef SourceInstaller = Future<ComicSource?> Function(String url);

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
    });
    await _load();
  }

  void _closeCatalog() {
    setState(() {
      _opened = null;
      _catalog = null;
      _error = null;
    });
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
      builder: (dialogContext) => AlertDialog(
        title: Text(
          repository == null ? "Add repository".tl : "Edit repository".tl,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: "Name".tl),
              autofocus: true,
            ),
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: "URL".tl,
                hintText: "https://.../index.json",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text("Cancel".tl),
          ),
          FilledButton.tonal(
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
      builder: (dialogContext) => AlertDialog(
        title: Text("Delete".tl),
        content: Text(
          "Delete repository '@name' ?".tlParams({'name': repository.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text("Cancel".tl),
          ),
          TextButton(
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

  Widget _buildHeader(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      height: 56 + top,
      padding: EdgeInsets.only(top: top),
      width: double.infinity,
      child: Row(
        children: [
          const SizedBox(width: 8),
          IconButton(
            tooltip: "Back".tl,
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () {
              if (_opened != null) {
                _closeCatalog();
              } else if (context.canPop()) {
                context.pop();
              } else {
                App.pop();
              }
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _opened?.name ?? "Repositories".tl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_opened != null)
            IconButton(
              tooltip: "Refresh".tl,
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _load,
            ),
          IconButton(
            tooltip: _opened == null ? "Add repository".tl : "Edit".tl,
            icon: Icon(_opened == null ? Icons.add : Icons.edit, size: 20),
            onPressed: () => _edit(_opened),
          ),
          IconButton(
            tooltip: "Help".tl,
            icon: const Icon(Icons.help_outline, size: 20),
            onPressed: () => launchUrlString(
              "https://github.com/venera-app/venera/blob/master/doc/comic_source.md",
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_opened != null) return _buildCatalog();
    return _buildRepositoryList();
  }

  Widget _buildRepositoryList() {
    final all = repositories.all;
    if (all.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "No source repositories yet.".tl,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              "Add a repository to browse and install comic source scripts."
                  .tl,
              style: TextStyle(
                fontSize: 14,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => _edit(),
              child: Text("Add repository".tl),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: all.length,
      itemBuilder: (context, index) {
        final repository = all[index];
        return ListTile(
          leading: const Icon(Icons.source_outlined, size: 20),
          title: Text(repository.name),
          subtitle: Text(
            repository.url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: "Edit".tl,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _edit(repository),
              ),
              IconButton(
                tooltip: "Delete".tl,
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _remove(repository),
              ),
            ],
          ),
          onTap: () => _open(repository),
        );
      },
    );
  }

  Widget _buildCatalog() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 32),
          Icon(
            Icons.error_outline,
            size: 40,
            color: context.colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colorScheme.error),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.tonal(
              onPressed: _load,
              child: Text("Retry".tl),
            ),
          ),
        ],
      );
    }
    final catalog = _catalog;
    if (catalog == null) return const SizedBox();
    return ListView.builder(
      itemCount: catalog.entries.length,
      itemBuilder: (context, index) => _buildEntry(catalog.entries[index]),
    );
  }

  Widget _buildEntry(SourceCatalogEntry entry) {
    final installed = ComicSource.find(entry.key);
    final Widget action;
    if (installed == null) {
      action = FilledButton.tonal(
        onPressed: () => _install(entry),
        child: Text("Add".tl),
      );
    } else if (compareSemVer(entry.version, installed.version)) {
      action = FilledButton.tonal(
        onPressed: () async {
          try {
            await ComicSourcePage.update(installed, false);
          } catch (e, s) {
            Log.error("Comic source", e, s);
            if (mounted) {
              context.showMessage(message: "Failed to update source".tl);
            }
          }
          if (mounted) setState(() {});
        },
        child: Text("Update".tl),
      );
    } else {
      action = Icon(
        Icons.check_circle_outline,
        size: 22,
        color: context.colorScheme.primary,
      );
    }
    final description = entry.description.isEmpty
        ? entry.version
        : "${entry.version}\n${entry.description}";
    return ListTile(
      title: Text(entry.name),
      subtitle: Text(description),
      trailing: action,
    );
  }
}
