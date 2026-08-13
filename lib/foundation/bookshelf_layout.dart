import 'package:uuid/uuid.dart';
import 'package:kong_comic/foundation/appdata.dart';

/// Local bookshelf organization: user-defined categories (分区) that group
/// local favorite folders, plus a hidden-folders set.
///
/// All state lives in [appdata.settings] (JSON-serializable) so it never
/// touches the per-folder SQLite tables. Folders are referenced by name; the
/// [onFolderRenamed] hook keeps the mapping keys in sync when a folder is
/// renamed.
class BookshelfLayout {
  BookshelfLayout._();

  static const _kCategories = 'bookshelfCategories';
  static const _kFolderCategory = 'folderCategory';
  static const _kHidden = 'hiddenFolders';

  /// Ordered list of categories: `[{"id": "...", "name": "..."}]`.
  static List<Map<String, String>> get categories {
    final raw = appdata.settings[_kCategories];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, String>.from(e))
        .toList();
  }

  /// Hidden local folder names.
  static List<String> get hiddenFolders {
    final raw = appdata.settings[_kHidden];
    if (raw is! List) return [];
    return raw.whereType<String>().toList();
  }

  /// Category id a folder belongs to, or null if uncategorized.
  static String? categoryOf(String folder) {
    final raw = appdata.settings[_kFolderCategory];
    if (raw is Map && raw[folder] is String) {
      return raw[folder] as String;
    }
    return null;
  }

  /// Assign (or unassign with [categoryId] == null) a folder to a category.
  static void setCategory(String folder, String? categoryId) {
    final raw = appdata.settings[_kFolderCategory];
    final map =
        (raw is Map) ? Map<String, String>.from(raw) : <String, String>{};
    if (categoryId == null) {
      map.remove(folder);
    } else {
      map[folder] = categoryId;
    }
    appdata.settings[_kFolderCategory] = map;
    appdata.saveData();
  }

  static void createCategory(String name) {
    final list = categories;
    list.add({'id': 'cat_${const Uuid().v4()}', 'name': name});
    appdata.settings[_kCategories] = list;
    appdata.saveData();
  }

  static void renameCategory(String id, String name) {
    final list = categories;
    final idx = list.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    list[idx] = {'id': id, 'name': name};
    appdata.settings[_kCategories] = list;
    appdata.saveData();
  }

  /// Deletes a category and moves its folders back to uncategorized.
  static void deleteCategory(String id) {
    final list = categories.where((c) => c['id'] != id).toList();
    appdata.settings[_kCategories] = list;

    final raw = appdata.settings[_kFolderCategory];
    if (raw is Map) {
      final map = Map<String, String>.from(raw);
      map.removeWhere((_, v) => v == id);
      appdata.settings[_kFolderCategory] = map;
    }
    appdata.saveData();
  }

  /// Reorders categories to match the given [ids] order.
  static void reorderCategories(List<String> ids) {
    final list = categories;
    list.sort((a, b) =>
        ids.indexOf(a['id']!).compareTo(ids.indexOf(b['id']!)));
    appdata.settings[_kCategories] = list;
    appdata.saveData();
  }

  static void hideFolder(String folder) {
    final list = hiddenFolders;
    if (!list.contains(folder)) list.add(folder);
    appdata.settings[_kHidden] = list;
    appdata.saveData();
  }

  static void unhideFolder(String folder) {
    final list = hiddenFolders..remove(folder);
    appdata.settings[_kHidden] = list;
    appdata.saveData();
  }

  static bool isHidden(String folder) => hiddenFolders.contains(folder);

  /// Keeps mapping + hidden-set keys valid after a folder rename.
  static void onFolderRenamed(String oldName, String newName) {
    var changed = false;
    final raw = appdata.settings[_kFolderCategory];
    if (raw is Map && raw.containsKey(oldName)) {
      final map = Map<String, String>.from(raw);
      map[newName] = map.remove(oldName)!;
      appdata.settings[_kFolderCategory] = map;
      changed = true;
    }
    final hidden = hiddenFolders;
    if (hidden.contains(oldName)) {
      hidden.remove(oldName);
      hidden.add(newName);
      appdata.settings[_kHidden] = hidden;
      changed = true;
    }
    if (changed) appdata.saveData();
  }
}
