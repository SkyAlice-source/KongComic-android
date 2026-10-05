import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/network/app_dio.dart';
import 'package:kong_comic/utils/ext.dart';
import 'package:kong_comic/utils/translations.dart';

import 'comic_source.dart';

/// A remote source repository, i.e. a URL pointing at an `index.json` file.
class SourceRepository {
  const SourceRepository({
    required this.id,
    required this.name,
    required this.url,
  });

  final String id;
  final String name;
  final String url;

  Map<String, String> toJson() => {'id': id, 'name': name, 'url': url};
}

/// One entry inside a repository catalog.
class SourceCatalogEntry {
  const SourceCatalogEntry({
    required this.key,
    required this.name,
    required this.version,
    required this.url,
    this.description = '',
  });

  final String key;
  final String name;
  final String version;
  final String url;
  final String description;
}

/// A loaded catalog. Invalid entries are skipped and reported instead of
/// making the whole repository unusable.
class SourceCatalog {
  const SourceCatalog(this.entries, this.skipped);

  final List<SourceCatalogEntry> entries;

  /// Labels of the entries that were skipped, in catalog order.
  final List<String> skipped;
}

/// Where an installed source came from. Keeping this around means a source
/// survives its repository being removed instead of turning into an orphan.
class SourceOrigin {
  const SourceOrigin({
    required this.kind,
    this.repositoryId,
    this.repositoryName,
    this.url,
  });

  /// One of `repository`, `file`, `url`.
  final String kind;
  final String? repositoryId;
  final String? repositoryName;
  final String? url;

  Map<String, String?> toJson() => {
    'kind': kind,
    'repositoryId': repositoryId,
    'repositoryName': repositoryName,
    'url': url,
  };
}

/// What a source should be updated from.
///
/// [repository]/[entry] are set when the download link was resolved through a
/// repository catalog. They let the caller adopt a legacy source (one with no
/// origin recorded) into that repository, so later updates no longer need the
/// slow "scan every catalog" fallback.
class SourceUpdateTarget {
  const SourceUpdateTarget({
    required this.url,
    this.repository,
    this.entry,
  });

  final String url;

  final SourceRepository? repository;

  final SourceCatalogEntry? entry;
}

class SourceUpdateCheck {
  const SourceUpdateCheck({
    required this.updates,
    required this.failures,
    required this.checked,
    required this.skipped,
    this.repositoryFailures = const [],
  });

  /// Source key -> new version.
  final Map<String, String> updates;

  /// Per-source problems (for example "multiple variants found").
  final List<String> failures;

  /// Repositories whose catalog could not be downloaded, with the reason.
  ///
  /// Kept separate from [failures] so the UI can say "N repositories failed to
  /// load" without also counting individual source problems.
  final List<String> repositoryFailures;

  final int checked;
  final int skipped;
}

/// Stores the list of source repositories and remembers, for every installed
/// source, which repository it came from.
///
/// Catalogs are always loaded on demand, so editing a URL never leaves a
/// stale snapshot behind.
class SourceRepositories extends ChangeNotifier {
  SourceRepositories._();

  static final SourceRepositories instance = SourceRepositories._();

  /// Repositories that ship with the app, added automatically on first launch.
  ///
  /// Kept on jsDelivr rather than `raw.githubusercontent.com` because GitHub
  /// raw is unreliable from mainland China.
  ///
  /// Users stay in control: anything they delete stays deleted (see
  /// [ensureDefaults]) and they can add/remove/edit freely afterwards.
  static const List<({String name, String url})> defaultRepositories = [
    (
      name: 'KongComic Official',
      url:
          'https://cdn.jsdelivr.net/gh/SkyAlice-source/venera-configs@main/index.json',
    ),
    (
      name: 'Community Sources',
      url:
          'https://cdn.jsdelivr.net/gh/handahao666-boop/venera_comic_source@main/index.json',
    ),
  ];

  /// How long a fetched catalog stays valid.
  ///
  /// Updating N sources from one repository must not mean N downloads of the
  /// same `index.json`; the entries themselves rarely change within a session.
  static const Duration catalogTtl = Duration(minutes: 5);

  final Map<String, ({SourceCatalog catalog, DateTime expiresAt})>
      _catalogCache = {};

  /// Drop a cached catalog, e.g. after its URL was edited.
  void invalidate(String? repositoryId) {
    if (repositoryId == null) {
      _catalogCache.clear();
    } else {
      _catalogCache.remove(repositoryId);
    }
  }

  /// The catalog still inside its TTL window, or `null` if it must be refetched.
  ///
  /// Lets the repository list show entry counts without issuing a network
  /// request — the snapshot is already in memory after the user opened it.
  SourceCatalog? cachedCatalog(String id) {
    final cached = _catalogCache[id];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      return cached.catalog;
    }
    return null;
  }

  /// At-a-glance counts for a repository card: how many sources the repository
  /// offers and how many of the installed ones have an update pending.
  ///
  /// Returns `null` until the catalog has been loaded at least once.
  ({int total, int updatable})? stats(String id) {
    final catalog = cachedCatalog(id);
    if (catalog == null) return null;
    var updatable = 0;
    for (final entry in catalog.entries) {
      final installed = ComicSource.find(entry.key);
      if (installed != null && compareSemVer(entry.version, installed.version)) {
        updatable++;
      }
    }
    return (total: catalog.entries.length, updatable: updatable);
  }

  List<SourceRepository> get all {
    final records = appdata.settings['comicSourceRepositories'];
    if (records is! List) return [];
    return records
        .whereType<Map>()
        .where(
          (record) =>
              record['id'] is String &&
              record['name'] is String &&
              record['url'] is String,
        )
        .map(
          (record) => SourceRepository(
            id: record['id'] as String,
            name: record['name'] as String,
            url: record['url'] as String,
          ),
        )
        .toList();
  }

  SourceRepository? find(String? id) =>
      all.firstWhereOrNull((r) => r.id == id);

  SourceRepository? linkedRepository(String sourceKey) =>
      find(originFor(sourceKey)?.repositoryId);

  SourceOrigin? originFor(String key) {
    final origins = appdata.settings['comicSourceOrigins'];
    final record = origins is Map ? origins[key] : null;
    if (record is! Map || record['kind'] is! String) return null;
    return SourceOrigin(
      kind: record['kind'] as String,
      repositoryId: record['repositoryId'] is String
          ? record['repositoryId'] as String
          : null,
      repositoryName: record['repositoryName'] is String
          ? record['repositoryName'] as String
          : null,
      url: record['url'] is String ? record['url'] as String : null,
    );
  }

  /// A short label describing where [key] was installed from.
  String originLabel(String key) {
    final origin = originFor(key);
    if (origin == null) return "No source repository linked".tl;
    if (origin.kind == 'file') return "Imported from file".tl;
    if (origin.kind == 'url') return "Installed from link".tl;
    final repository = find(origin.repositoryId);
    final fallbackName = origin.repositoryName;
    if (repository != null) return repository.name;
    if (fallbackName != null && fallbackName.isNotEmpty) {
      return "Repository removed: @name".tlParams({'name': fallbackName});
    }
    return "No source repository linked".tl;
  }

  /// Moves the legacy single-URL setting into the repository list.
  ///
  /// Runs once; afterwards the user is free to edit or remove that entry.
  Future<void> migrate() async {
    if (appdata.settings['comicSourceRepositoriesMigrated'] == true) return;
    if (all.isNotEmpty) {
      appdata.settings['comicSourceRepositoriesMigrated'] = true;
      appdata.saveData();
      return;
    }
    final legacy =
        appdata.settings['comicSourceListUrl']?.toString().trim() ?? '';
    if (legacy.isNotEmpty) {
      final uri = Uri.tryParse(legacy);
      appdata.settings['comicSourceRepositories'] = [
        SourceRepository(
          id: _newId(),
          name: (uri != null && uri.host.isNotEmpty)
              ? uri.host
              : "Migrated repository".tl,
          url: legacy,
        ).toJson(),
      ];
    }
    appdata.settings['comicSourceRepositoriesMigrated'] = true;
    appdata.saveData();
  }

  /// Makes sure the built-in repositories are present.
  ///
  /// Called on every launch, but each URL is only ever seeded once: after that
  /// it is remembered in `comicSourceSeededDefaults` and never forced back,
  /// even if the user deleted it. New URLs added by later app versions show up
  /// automatically because they are not in that record yet.
  Future<void> ensureDefaults() async {
    final seeded =
        (appdata.settings['comicSourceSeededDefaults'] as List? ?? [])
            .whereType<String>()
            .toSet();
    final records =
        (appdata.settings['comicSourceRepositories'] as List? ?? [])
            .whereType<Map>()
            .map((record) => Map<String, String>.from(
                  record.map((key, value) => MapEntry(key, value.toString())),
                ))
            .toList();
    final present = records
        .map((record) => record['url'] ?? '')
        .where((url) => url.isNotEmpty)
        .toSet();

    var changed = false;
    for (final entry in defaultRepositories) {
      if (seeded.contains(entry.url)) continue;
      if (!present.contains(entry.url)) {
        records.add(
          SourceRepository(
            id: _newId(),
            name: entry.name,
            url: entry.url,
          ).toJson(),
        );
        present.add(entry.url);
        changed = true;
      }
      seeded.add(entry.url);
    }

    appdata.settings['comicSourceSeededDefaults'] = seeded.toList();
    if (changed) {
      appdata.settings['comicSourceRepositories'] = records;
      await appdata.saveData();
      notifyListeners();
    }
  }

  static String _newId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = Random().nextInt(0xFFFFFFF).toRadixString(36);
    return '$stamp$salt';
  }

  static String normalizeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw "Enter a complete HTTP or HTTPS URL.".tl;
    }
    return uri.removeFragment().toString();
  }

  /// Adds a one-off parameter so a script download never comes from a cache.
  ///
  /// jsDelivr caches branch references (`@main`) per file for twelve hours, and
  /// every file is timed separately. A repository can therefore hand out an
  /// `index.json` that already announces `1.0.6` while the script file itself is
  /// still the cached `1.0.5` — from the user's side "Update" succeeds and the
  /// version number never moves. A changing query string forces jsDelivr to go
  /// back to the origin and return whatever the repository holds right now.
  static String bypassCache(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            '_': DateTime.now().millisecondsSinceEpoch.toString(),
          },
        )
        .toString();
  }

  /// The entry matching [source] inside a single [catalog], or `null`.
  ///
  /// [preferredUrl] (the download link recorded when the source was installed)
  /// wins, because the same key can legitimately appear twice in one repository
  /// — "拷贝漫画" ships both a plain and a multi-account variant. Guessing
  /// between them would silently replace the user's source with a different
  /// one, so an ambiguous match returns `null`.
  ///
  /// Note that `ComicSource.url` is *not* the download link: it is the `url`
  /// field declared inside the script, i.e. the site's homepage. Matching
  /// against it never hits a catalog entry and used to make every duplicate key
  /// look unresolvable, which surfaced as "update failed".
  static SourceCatalogEntry? matchEntry(
    List<SourceCatalogEntry> entries,
    ComicSource source, {
    String? preferredUrl,
  }) {
    final candidates = entries.where((e) => e.key == source.key).toList();
    if (candidates.isEmpty) return null;
    for (final url in [preferredUrl, source.url]) {
      if (url == null || url.isEmpty) continue;
      final exact = candidates.firstWhereOrNull((e) => e.url == url);
      if (exact != null) return exact;
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  Future<SourceCatalog> load(SourceRepository repository) async {
    final cached = _catalogCache[repository.id];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      return cached.catalog;
    }
    final url = normalizeUrl(repository.url);
    final dio = AppDio();
    final response = await dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: {"cache-time": "no"},
      ),
    );
    if (response.statusCode != 200) {
      throw "Unable to load repository.".tl;
    }
    final catalog = parseCatalog(
      response.data ?? '',
      baseUrl: response.realUri.toString(),
    );
    _catalogCache[repository.id] = (
      catalog: catalog,
      expiresAt: DateTime.now().add(catalogTtl),
    );
    return catalog;
  }

  static SourceCatalog parseCatalog(String contents, {String? baseUrl}) {
    final base = baseUrl == null ? null : Uri.parse(normalizeUrl(baseUrl));
    dynamic json;
    try {
      json = jsonDecode(contents.replaceFirst('\uFEFF', ''));
    } catch (e) {
      throw "The address must return a source list in JSON format.".tl;
    }
    if (json is! List) {
      throw "The address must return a source list in JSON format.".tl;
    }
    final entries = <SourceCatalogEntry>[];
    final skipped = <String>[];
    for (var index = 0; index < json.length; index++) {
      final record = json[index];
      final key = record is Map ? record['key'] : null;
      final label = (key is String && key.trim().isNotEmpty)
          ? key.trim()
          : '#${index + 1}';
      if (record is! Map ||
          key is! String ||
          record['name'] is! String ||
          record['version'] is! String ||
          !RegExp(r'^\w+$').hasMatch(key) ||
          !RegExp(
            r'^\d+\.\d+\.\d+(?:[.\-].+)?$',
          ).hasMatch(record['version'] as String)) {
        skipped.add(label);
        continue;
      }
      final target =
          record['url'] is String && (record['url'] as String).trim().isNotEmpty
          ? record['url'] as String
          : record['fileName'];
      if (target is! String || target.trim().isEmpty) {
        skipped.add(label);
        continue;
      }
      try {
        entries.add(
          SourceCatalogEntry(
            key: key,
            name: record['name'] as String,
            version: record['version'] as String,
            url: normalizeUrl(
              base == null
                  ? target.trim()
                  : base.resolve(target.trim()).toString(),
            ),
            description: record['description']?.toString() ?? '',
          ),
        );
      } catch (e) {
        skipped.add(label);
      }
    }
    if (entries.isEmpty && skipped.isNotEmpty) {
      throw "The repository contains no usable source entries.".tl;
    }
    return SourceCatalog(entries, skipped);
  }

  Future<SourceRepository> save({
    String? id,
    required String name,
    required String url,
    String? catalogContents,
  }) async {
    final trimmedName = name.trim();
    final normalizedUrl = normalizeUrl(url);
    if (trimmedName.isEmpty) throw "Enter a repository name.".tl;
    // Editing may change the URL, and the cache is keyed by repository id.
    invalidate(id);
    void validateDuplicate() {
      if (all.any(
        (r) =>
            r.id != id &&
            Uri.tryParse(r.url)?.removeFragment().toString() ==
                normalizedUrl,
      )) {
        throw "This repository address has already been added.".tl;
      }
    }

    validateDuplicate();
    final repository = SourceRepository(
      id: id ?? _newId(),
      name: trimmedName,
      url: normalizedUrl,
    );
    if (catalogContents == null) {
      await load(repository);
    } else {
      parseCatalog(catalogContents, baseUrl: normalizedUrl);
    }
    validateDuplicate();
    final repositories = all;
    final index = repositories.indexWhere((r) => r.id == id);
    if (id != null && index < 0) throw "Repository no longer exists.".tl;
    if (index < 0) {
      repositories.add(repository);
    } else {
      repositories[index] = repository;
    }
    appdata.settings['comicSourceRepositories'] =
        repositories.map((r) => r.toJson()).toList();
    appdata.saveData();
    notifyListeners();
    return repository;
  }

  /// Moves a repository inside the list — the stored order is the order the
  /// user sees, so dragging a card is enough to re-prioritise repositories.
  ///
  /// [newIndex] is already adjusted for the removal (i.e. the index the item
  /// should end up at after it is taken out of the list).
  Future<void> reorder(int oldIndex, int newIndex) async {
    final repositories = all;
    if (oldIndex < 0 || oldIndex >= repositories.length) return;
    if (newIndex < 0 || newIndex >= repositories.length) return;
    final moved = repositories.removeAt(oldIndex);
    repositories.insert(newIndex, moved);
    appdata.settings['comicSourceRepositories'] =
        repositories.map((r) => r.toJson()).toList();
    await appdata.saveData();
    notifyListeners();
  }

  /// The order the user dragged the entries of [repositoryId] into.
  List<String> catalogOrder(String repositoryId) {
    final orders = appdata.settings['sourceCatalogOrder'];
    if (orders is! Map) return const [];
    final order = orders[repositoryId];
    return order is List ? order.whereType<String>().toList() : const [];
  }

  Future<void> setCatalogOrder(
    String repositoryId,
    List<String> keys,
  ) async {
    final current = appdata.settings['sourceCatalogOrder'];
    final orders = current is Map
        ? Map<String, dynamic>.from(current)
        : <String, dynamic>{};
    orders[repositoryId] = keys;
    appdata.settings['sourceCatalogOrder'] = orders;
    await appdata.saveData();
  }

  /// Applies the saved drag order to [entries].
  ///
  /// Entries the user never moved keep their original relative order and are
  /// pushed after the ordered ones, so a repository refresh that adds new
  /// sources never scrambles what the user arranged.
  List<SourceCatalogEntry> applyCatalogOrder(
    String? repositoryId,
    List<SourceCatalogEntry> entries,
  ) {
    if (repositoryId == null) return entries;
    final order = catalogOrder(repositoryId);
    if (order.isEmpty) return entries;
    final rank = <String, int>{
      for (var i = 0; i < order.length; i++) order[i]: i,
    };
    final ranked = <MapEntry<SourceCatalogEntry, int>>[
      for (var i = 0; i < entries.length; i++)
        MapEntry(entries[i], rank[entries[i].key] ?? order.length + i),
    ];
    ranked.sort((a, b) => a.value.compareTo(b.value));
    return [for (final entry in ranked) entry.key];
  }

  Future<void> remove(SourceRepository repository) async {
    invalidate(repository.id);
    final currentOrigins = appdata.settings['comicSourceOrigins'];
    if (currentOrigins is Map) {
      // Drop the link but remember the name: without a repositoryId the source
      // falls back to the "scan every catalog by script URL" branch, so it keeps
      // receiving updates instead of being silently skipped forever.
      appdata.settings['comicSourceOrigins'] = {
        for (final entry in currentOrigins.entries)
          entry.key:
              entry.value is Map &&
                      entry.value['repositoryId'] == repository.id
                  ? {
                      ...entry.value as Map,
                      'repositoryId': null,
                      'repositoryName': repository.name,
                    }
                  : entry.value,
      };
    }
    appdata.settings['comicSourceRepositories'] = all
        .where((r) => r.id != repository.id)
        .map((r) => r.toJson())
        .toList();
    appdata.saveData();
    notifyListeners();
  }

  Future<void> setOrigin(String key, SourceOrigin? origin) async {
    final current = appdata.settings['comicSourceOrigins'];
    final origins = current is Map
        ? Map<String, dynamic>.from(current)
        : <String, dynamic>{};
    if (origin == null) {
      origins.remove(key);
    } else {
      origins[key] = origin.toJson();
    }
    appdata.settings['comicSourceOrigins'] = origins;
    appdata.saveData();
    notifyListeners();
  }

  /// Records that [key] was installed from [entry] inside [repository].
  Future<void> link(
    String key,
    SourceRepository repository,
    SourceCatalogEntry entry,
  ) async {
    if (entry.key != key || find(repository.id)?.url != repository.url) {
      throw "Repository changed. Refresh the list and try again.".tl;
    }
    await setOrigin(
      key,
      SourceOrigin(
        kind: 'repository',
        repositoryId: repository.id,
        repositoryName: repository.name,
        url: entry.url,
      ),
    );
  }

  Future<void> markInstalledFromUrl(String key, String url) async {
    await setOrigin(key, SourceOrigin(kind: 'url', url: url));
  }

  Future<void> markInstalledFromFile(String key, String? url) async {
    await setOrigin(key, SourceOrigin(kind: 'file', url: url));
  }

  /// The URL the given source should be updated from.
  ///
  /// 没有关联仓库时按下面的顺序兜底，保证「更新」不会用一个必然失败的地址：
  /// 1. origin 里记录的脚本地址（曾从链接 / 文件安装）；
  /// 2. 按 key 扫描所有仓库目录 —— 与 [checkUpdates] 的兜底一致。旧版本
  ///    安装的源没有 origin，之前这里会退回脚本里的站点 URL，结果下载到
  ///    一个网页、解析失败，表现为「点更新没反应」；
  /// 3. 都找不到就明确报错，而不是发一个注定失败的请求。
  Future<SourceUpdateTarget> resolveUpdate(ComicSource source) async {
    // 关联仓库只是「首选」而不是「唯一」：仓库可能临时拉不动，也可能已经把
    // 这个源改名/下架。以前这两种情况都直接抛错，用户看到的就是「更新失败」；
    // 现在先记下原因，继续走下面的兜底，实在找不到再把原因报出来。
    String? linkedFailure;
    final recordedUrl = originFor(source.key)?.url;
    final repository = linkedRepository(source.key);
    if (repository != null) {
      try {
        final catalog = await load(repository);
        final match = matchEntry(catalog.entries, source,
            preferredUrl: recordedUrl);
        if (match != null) {
          return SourceUpdateTarget(
            url: match.url,
            repository: repository,
            entry: match,
          );
        }
        final candidates = catalog.entries
            .where((e) => e.key == source.key)
            .toList();
        linkedFailure = candidates.isEmpty
            ? "This source is no longer listed in @name.".tlParams({
                "name": repository.name,
              })
            : "Multiple variants found. Choose a source in the repository again."
                .tl;
      } catch (e) {
        linkedFailure = "Could not load @name: @error".tlParams({
          "name": repository.name,
          "error": e.toString(),
        });
      }
    }
    final recorded = recordedUrl;
    if (recorded != null && recorded.isURL) {
      return SourceUpdateTarget(url: normalizeUrl(recorded));
    }
    // 逐仓库查找，而不是把所有仓库的同名条目汇总起来：一个 key 同时存在于
    // 两个仓库（很常见，社区仓库往往是我们仓库的子集）时，汇总会被判成
    // 「多变体」而直接失败，用户看到的是一批「更新失败」却什么也没发生。
    ({SourceRepository repository, SourceCatalogEntry entry})? fallback;
    for (final candidateRepository in all) {
      final SourceCatalog catalog;
      try {
        catalog = await load(candidateRepository);
      } catch (_) {
        // 单个仓库不可达不应该挡住其它仓库里的同名源。
        continue;
      }
      final exact = matchEntry(catalog.entries, source,
          preferredUrl: recordedUrl);
      if (exact != null) {
        return SourceUpdateTarget(
          url: exact.url,
          repository: candidateRepository,
          entry: exact,
        );
      }
      final candidates = catalog.entries
          .where((e) => e.key == source.key)
          .toList();
      if (candidates.length == 1) {
        fallback ??= (
          repository: candidateRepository,
          entry: candidates.single,
        );
      }
    }
    final chosen = fallback;
    if (chosen != null) {
      return SourceUpdateTarget(
        url: chosen.entry.url,
        repository: chosen.repository,
        entry: chosen.entry,
      );
    }
    throw linkedFailure ??
        "No download link for this source. Add it again from a repository.".tl;
  }

  Future<String> updateUrl(ComicSource source) =>
      resolveUpdate(source).then((t) => t.url);

  /// Checks every repository for newer versions of the installed sources.
  ///
  /// A failing repository is reported but never prevents the remaining ones
  /// from being checked.
  Future<SourceUpdateCheck> checkUpdates(List<ComicSource> sources) async {
    final repositories = all;
    final updates = <String, String>{};
    final failures = <String>[];
    var checked = 0;
    var skipped = 0;

    // Catalogs are fetched once per repository and then reused, so checking
    // many sources never means many requests.
    final catalogs = <String, SourceCatalog>{};
    final loadFailures = <String, String>{};
    for (final repository in repositories) {
      try {
        catalogs[repository.id] = await load(repository);
      } catch (e) {
        loadFailures[repository.id] = e.toString();
      }
    }

    for (final source in sources) {
      final origin = originFor(source.key);
      // 下载链接只在 origin 里：ComicSource.url 是脚本里的站点地址，拿它去
      // 匹配目录条目永远匹配不上，重复 key 的源会被误判成「无法解析」。
      final recordedUrl = origin?.url;
      final repositoryId = origin?.repositoryId;
      SourceCatalogEntry? chosen;
      if (repositoryId != null) {
        final repository = find(repositoryId);
        final catalog = catalogs[repositoryId];
        if (repository != null && catalog != null) {
          chosen =
              matchEntry(catalog.entries, source, preferredUrl: recordedUrl);
          if (chosen != null) {
            if (compareSemVer(chosen.version, source.version)) {
              updates[source.key] = chosen.version;
            }
            checked++;
            continue;
          }
          // 源可能已从这个仓库下架或改名。以前这里直接记一条失败；现在继续
          // 走下面的全仓库扫描，很多源同时存在于多个仓库。
        }
      }

      // Sources installed before repositories existed have no origin yet. Scan
      // every repository by key so they still receive updates — one repository
      // at a time, mirroring [resolveUpdate], so a source that lives in more
      // than one repository is no longer reported as an unfixable failure.
      for (final repository in repositories) {
        final entries = catalogs[repository.id]?.entries;
        if (entries == null) continue;
        final match = entries
            .where((e) => e.key == source.key)
            .toList();
        if (match.isEmpty) continue;
        final exact = matchEntry(match, source, preferredUrl: recordedUrl);
        if (exact != null) {
          chosen = exact;
          break;
        }
        if (match.length == 1) {
          chosen ??= match.single;
        }
      }
      if (chosen == null) {
        skipped++;
        continue;
      }
      if (compareSemVer(chosen.version, source.version)) {
        updates[source.key] = chosen.version;
      }
      checked++;
    }

    // One entry per broken repository, regardless of how many sources belong to
    // it. A failed repository never hides updates from the working ones.
    final repositoryFailures = <String>[];
    for (final repository in repositories) {
      final failure = loadFailures[repository.id];
      if (failure != null) repositoryFailures.add('${repository.name}: $failure');
    }

    return SourceUpdateCheck(
      updates: updates,
      failures: failures,
      checked: checked,
      skipped: skipped,
      repositoryFailures: repositoryFailures,
    );
  }
}
