import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/network/app_dio.dart';
import 'package:kong_comic/network/cookie_jar.dart';
import 'package:kong_comic/pages/webview.dart';
import 'package:kong_comic/utils/ext.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:kong_comic/utils/translations.dart';

class ComicSourcePage extends StatelessWidget {
  const ComicSourcePage({super.key});

  static Future<void> update(
    ComicSource source, [
    bool showLoading = true,
  ]) async {
    if (!source.url.isURL) {
      if (showLoading) {
        App.rootContext.showMessage(message: "Invalid url config".tl);
        return;
      } else {
        throw Exception("Invalid url config");
      }
    }
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
    try {
      var res = await AppDio().get<String>(
        source.url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {"cache-time": "no"},
        ),
      );
      if (cancel) return;
      controller?.close();
      await ComicSourceParser().parse(res.data!, source.filePath);
      await io.File(source.filePath).writeAsString(res.data!);
      if (ComicSourceManager().availableUpdates.containsKey(source.key)) {
        ComicSourceManager().availableUpdates.remove(source.key);
      }
    } catch (e, s) {
      if (cancel) return;
      if (showLoading) {
        Log.error("Update comic source", e, s);
        App.rootContext.showMessage(message: "Failed to update source".tl);
      } else {
        rethrow;
      }
    }
    await ComicSourceManager().reload();
    _syncSourceOrder();
    _addAllPagesWithComicSource(source);
    if (showLoading) {
      App.forceRebuild();
    }
  }

  static Future<int> checkComicSourceUpdate() async {
    if (ComicSource.all().isEmpty) {
      return 0;
    }
    try {
      var dio = AppDio();
      var res = await dio.get<String>(appdata.settings['comicSourceListUrl']);
      if (res.statusCode != 200) {
        return -1;
      }
      var list = jsonDecode(res.data ?? "null") as List?;
      if (list == null) return -1;
      var versions = <String, String>{};
      for (var source in list) {
        versions[source['key']] = source['version'];
      }
      var shouldUpdate = <String>[];
      for (var source in ComicSource.all()) {
        if (versions.containsKey(source.key) &&
            compareSemVer(versions[source.key]!, source.version)) {
          shouldUpdate.add(source.key);
        }
      }
      if (shouldUpdate.isNotEmpty) {
        var updates = <String, String>{};
        for (var key in shouldUpdate) {
          updates[key] = versions[key]!;
        }
        ComicSourceManager().updateAvailableUpdates(updates);
      }
      return shouldUpdate.length;
    } catch (e) {
      return -1;
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

class _BodyState extends State<_Body> {
  var url = "";

  /// Selection mode for batch operations.
  bool _selecting = false;
  final Set<String> _selected = {};

  /// Connectivity test result per source key: '', 'testing', 'ok', 'fail'.
  final Map<String, String> _health = {};

  /// True while a "test all" run is in progress.
  bool _testingAll = false;

  /// True while an "update all" run is in progress.
  bool _updatingAll = false;

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
              Tooltip(
                message: "Update all".tl,
                child: IconButton(
                  onPressed: _updatingAll ? null : _updateAll,
                  icon: _updatingAll
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : HugeIcon(
                          icon: HugeIcons.strokeRoundedRefresh,
                          size: 18,
                        ),
                ),
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
        SliverReorderableList(
          itemCount: sources.length,
          onReorderItem: _selecting ? (_, __) {} : onReorderItem,
          itemBuilder: (context, index) {
            final source = sources[index];
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
              disabled: ComicSourceManager().isDisabled(source.key),
              onToggleDisabled: _toggleDisabled,
              onTest: _testSource,
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
          builder: (context) => AlertDialog(
            title: Text("Reload Configs".tl),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
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
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)
          .add(EdgeInsets.only(bottom: context.padding.bottom)),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: _selected.isEmpty ? null : batchUpdate,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
            label: Text("Batch update".tl),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _selected.isEmpty ? null : batchDelete,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
            label: Text("Batch delete".tl),
            style: FilledButton.styleFrom(
              backgroundColor: context.colorScheme.error,
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
    for (final k in keys) {
      final s = ComicSource.find(k);
      if (s != null) {
        await ComicSourcePage.update(s, false);
      }
    }
    controller.close();
    if (mounted) {
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
    setState(() => _health[source.key] = 'testing');
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
        setState(() => _health[source.key] = 'fail');
        return;
      }
      final ok = res != null && !(res.error as bool);
      setState(() => _health[source.key] = ok ? 'ok' : 'fail');
    } catch (e) {
      setState(() => _health[source.key] = 'fail');
    }
  }

  Future<void> _testAll() async {
    if (_testingAll) return;
    setState(() => _testingAll = true);
    for (final s in orderedComicSources()) {
      await _testSource(s);
    }
    setState(() => _testingAll = false);
  }

  Future<void> _updateAll() async {
    if (_updatingAll) return;
    setState(() => _updatingAll = true);
    final n = await ComicSourcePage.checkComicSourceUpdate();
    if (n > 0) {
      final updates =
          Map<String, String>.from(ComicSourceManager().availableUpdates);
      for (final key in updates.keys) {
        final s = ComicSource.find(key);
        if (s != null) {
          await ComicSourcePage.update(s, false);
        }
      }
    }
    App.forceRebuild();
    setState(() => _updatingAll = false);
    if (mounted) {
      App.rootContext.showMessage(
        message: n > 0 ? "Updated sources".tl : "All sources up to date".tl,
      );
    }
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedSourceCode, size: 18),
                  label: Text("Comic Source list".tl),
                  onPressed: () {
                    showPopUpWidget(
                      App.rootContext,
                      _ComicSourceList(handleAddSource),
                    );
                  },
                ),
                FilledButton.tonalIcon(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedFile01, size: 18),
                  label: Text("Use a config file".tl),
                  onPressed: _selectFile,
                ),
                FilledButton.tonalIcon(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedHelpCircle, size: 18),
                  label: Text("Help".tl),
                  onPressed: help,
                ),
                _CheckUpdatesButton(),
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
      await addSource(content, fileName);
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

  Future<void> handleAddSource(String url) async {
    if (url.isEmpty) {
      return;
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
      if (cancel) return;
      controller.close();
      await addSource(res.data!, fileName);
    } catch (e, s) {
      if (cancel) return;
      context.showMessage(message: "Failed to add source".tl);
      Log.error("Add comic source", "$e\n$s");
    }
  }

  Future<void> addSource(String js, String fileName) async {
    var comicSource = await ComicSourceParser().createAndParse(js, fileName);
    ComicSourceManager().add(comicSource);
    _syncSourceOrder();
    _addAllPagesWithComicSource(comicSource);
    appdata.saveData();
    App.forceRebuild();
  }
}

class _ComicSourceList extends StatefulWidget {
  const _ComicSourceList(this.onAdd);

  final Future<void> Function(String) onAdd;

  @override
  State<_ComicSourceList> createState() => _ComicSourceListState();
}

class _ComicSourceListState extends State<_ComicSourceList> {
  List? json;
  bool changed = false;
  var controller = TextEditingController();

  void load() async {
    if (json != null) {
      setState(() {
        json = null;
      });
    }
    if (controller.text.isEmpty) {
      setState(() {
        json = [];
      });
      return;
    }
    var dio = AppDio();
    try {
      var res = await dio.get<String>(controller.text);
      if (res.statusCode != 200) {
        throw "error";
      }
      if (res.data == null) {
        throw "empty response";
      }
      if (mounted) {
        setState(() {
          json = jsonDecode(res.data!);
        });
      }
    } catch (e) {
      context.showMessage(message: "Network error".tl);
      if (mounted) {
        setState(() {
          json = [];
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    controller.text = appdata.settings['comicSourceListUrl'];
    load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
    if (changed) {
      appdata.settings['comicSourceListUrl'] = controller.text;
      appdata.saveData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(title: "Comic Source".tl, body: buildBody());
  }

  Widget buildBody() {
    var currentKey = ComicSource.all().map((e) => e.key).toList();

    return ListView.builder(
      itemCount: (json?.length ?? 1) + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 0.6,
              ),
              borderRadius: BorderRadius.circular(kcRadius8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: HugeIcon(icon: HugeIcons.strokeRoundedSourceCode, size: 18),
                  title: Text("Repo URL".tl),
                ),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: "URL".tl,
                    border: const UnderlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onChanged: (value) {
                    changed = true;
                  },
                ).paddingHorizontal(16).paddingBottom(8),
                Text(
                  "The URL should point to a 'index.json' file".tl,
                ).paddingLeft(16),
                Text(
                  "Do not report any issues related to sources to App repo.".tl,
                ).paddingLeft(16),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        launchUrlString(
                          "https://github.com/venera-app/venera/blob/master/doc/comic_source.md",
                        );
                      },
                      child: Text("Help".tl),
                    ),
                    FilledButton.tonal(
                      onPressed: load,
                      child: Text("Refresh".tl),
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        }

        if (index == 1 && json == null) {
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ).fixWidth(24).fixHeight(24),
          );
        }

        index--;

        var key = json![index]["key"];
        var action = currentKey.contains(key)
            ? HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle01, size: 20).paddingRight(8)
            : Button.filled(
                child: Text("Add".tl),
                onPressed: () async {
                  var fileName = json![index]["fileName"];
                  var url = json![index]["url"];
                  if (url == null || !(url.toString()).isURL) {
                    var listUrl =
                        appdata.settings['comicSourceListUrl'] as String;
                    if (listUrl
                        .replaceFirst("https://", "")
                        .replaceFirst("http://", "")
                        .contains("/")) {
                      url =
                          listUrl.substring(0, listUrl.lastIndexOf("/") + 1) +
                          fileName;
                    } else {
                      url = '$listUrl/$fileName';
                    }
                  }
                  await widget.onAdd(url);
                  setState(() {});
                },
              ).fixHeight(32);

        var description = json![index]["version"];
        if (json![index]["description"] != null) {
          description = "$description\n${json![index]["description"]}";
        }

        return ListTile(
          title: Text(json![index]["name"]),
          subtitle: Text(description),
          trailing: action,
        );
      },
    );
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

class _CheckUpdatesButton extends StatefulWidget {
  const _CheckUpdatesButton();

  @override
  State<_CheckUpdatesButton> createState() => _CheckUpdatesButtonState();
}

class _CheckUpdatesButtonState extends State<_CheckUpdatesButton> {
  bool isLoading = false;

  void check() async {
    setState(() {
      isLoading = true;
    });
    var count = await ComicSourcePage.checkComicSourceUpdate();
    if (count == -1) {
      context.showMessage(message: "Network error".tl);
    } else if (count == 0) {
      context.showMessage(message: "No updates".tl);
    } else {
      showUpdateDialog();
    }
    setState(() {
      isLoading = false;
    });
  }

  void showUpdateDialog() async {
    var text = ComicSourceManager().availableUpdates.entries
        .map((e) {
          return "${ComicSource.find(e.key)!.name}: ${e.value}";
        })
        .join("\n");
    bool doUpdate = false;
    await showDialog(
      context: App.rootContext,
      builder: (context) {
        return ContentDialog(
          title: "Updates".tl,
          content: Text(text).paddingHorizontal(16),
          actions: [
            FilledButton(
              onPressed: () {
                doUpdate = true;
                context.pop();
              },
              child: Text("Update".tl),
            ),
          ],
        );
      },
    );
    if (doUpdate) {
      var loadingController = showLoadingDialog(
        context,
        message: "Updating".tl,
        withProgress: true,
      );
      int current = 0;
      int total = ComicSourceManager().availableUpdates.length;
      try {
        var shouldUpdate = ComicSourceManager().availableUpdates.keys.toList();
        for (var key in shouldUpdate) {
          var source = ComicSource.find(key)!;
          await ComicSourcePage.update(source, false);
          current++;
          loadingController.setProgress(current / total);
        }
      } catch (e) {
        context.showMessage(message: "Failed to update sources".tl);
      }
      loadingController.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      icon: isLoading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
      label: Text("Check updates".tl),
      onPressed: check,
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
    this.disabled = false,
    this.onToggleDisabled = _noopDisable,
    this.onTest = _noopTest,
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

  /// Whether this source is currently disabled (hidden across the app).
  final bool disabled;

  final void Function(ComicSource source) onToggleDisabled;
  final void Function(ComicSource source) onTest;

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
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(source.name, style: ts.s18),
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
                        AppBadge(source.version, type: AppBadgeType.neutral, fontSize: kcFont13),
                        if (hasUpdate)
                          Tooltip(
                            message: newVersion,
                            child: AppBadge("New Version".tl, type: AppBadgeType.warning, fontSize: kcFont13),
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
                Tooltip(
                  message: "Edit".tl,
                  child: IconButton(
                    onPressed: () => widget.edit(source),
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedEdit01, size: 18),
                ),
              ),
              if (!widget.selecting)
                Tooltip(
                  message: "Update".tl,
                  child: IconButton(
                    onPressed: () => widget.update(source),
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18),
                ),
              ),
              if (!widget.selecting)
                Tooltip(
                  message: "Delete".tl,
                  child: IconButton(
                    onPressed: () => widget.delete(source),
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
                  ),
                ),
            ],
          ),
          _buildStatusRow(),
          if (_expanded)
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
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (expTotal > 0)
            AppBadge("${"Explore".tl} $expOn/$expTotal",
                type: AppBadgeType.neutral, fontSize: kcFont13),
          if (catTotal > 0)
            AppBadge("${"Categories".tl} $catOn/$catTotal",
                type: AppBadgeType.neutral, fontSize: kcFont13),
          if (health == 'testing')
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (health == 'ok')
            AppBadge("Reachable".tl,
                type: AppBadgeType.success, fontSize: kcFont13)
          else if (health == 'fail')
            AppBadge("Proxy required".tl,
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
                fontSize: kcFont13)
          else
            AppBadge("Unreachable".tl,
                type: AppBadgeType.neutral, fontSize: kcFont13),
          if (!widget.selecting) ...[
            TextButton.icon(
              onPressed: () => widget.onTest(source),
              icon: HugeIcon(icon: HugeIcons.strokeRoundedLink01, size: 16),
              label: Text("Test".tl),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
            TextButton.icon(
              onPressed: () => widget.onToggleDisabled(source),
              icon:
                  HugeIcon(icon: HugeIcons.strokeRoundedActivity01, size: 16),
              label: Text(widget.disabled ? "Enable".tl : "Disable".tl),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ],
      ),
    );
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
