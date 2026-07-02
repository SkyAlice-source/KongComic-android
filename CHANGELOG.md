# Changelog

## [1.2.6] - 2026-07-02

### 🐛 Bug Fixes (45+ fixes)

#### Critical Fixes
- **Fixed resource leaks**: Timer, Isolate, and StreamSubscription leaks in multiple components
  - WindowPlacement.loop() Timer leak
  - Heartbeat Timer leak in init()
  - DownloadTask.cancel() not stopping timer
  - JsEngine Isolate leak
  - FollowUpdatesService Timer leak

#### Data Integrity Fixes
- **Fixed concurrent write race condition** in LocalManager.saveCurrentDownloadingTasks()
- **Added transaction support** for database operations in appdata.dart and favorites.dart
- **Enabled WAL mode** for SQLite databases (cache_manager.dart, cookie_jar.dart)
- **Fixed version number management** in data_sync.dart

#### Null Safety Fixes
- Fixed unsafe type casts in appdata.dart, cache_manager.dart
- Fixed null assertion crashes in volume.dart, comic_type.dart, navigation_bar.dart
- Fixed null safety issues in image_favorites.dart, data_sync.dart, import_comic.dart

#### Code Quality Improvements
- Removed 13 unused imports
- Updated deprecated APIs (Share, TickerMode, onReorder)
- Fixed code style issues (curly_braces, unnecessary_string_interp)

### 🔒 Security
- Improved error handling in file operations
- Added proper resource cleanup in dispose methods

---

## [1.2.5] - 2026-06-30

### Changes
- Full Changelog: https://github.com/SkyAlice-source/KongComic-android/compare/v1.2.4...v1.2.5

---

## [1.2.4] - Previous Release

### Changes
- See GitHub Releases for details
