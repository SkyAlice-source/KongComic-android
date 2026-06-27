<h1 align="center">KongComic 🎨</h1>

<p align="center"><a href="README.md"><b>English</b></a> | <a href="README.zh-CN.md">中文</a></p>

<p align="center">
  <a href="https://github.com/SkyAlice-source/KongComic-android/stargazers"><img src="https://img.shields.io/github/stars/SkyAlice-source/KongComic-android" alt="Stars"></a>
  <a href="https://github.com/SkyAlice-source/KongComic-android/releases"><img src="https://img.shields.io/github/v/release/SkyAlice-source/KongComic-android" alt="Release"></a>
  <a href="https://github.com/SkyAlice-source/KongComic-android/blob/main/LICENSE"><img src="https://img.shields.io/github/license/SkyAlice-source/KongComic-android" alt="License"></a>
  <a href="https://github.com/SkyAlice-source/KongComic-android/blob/main/pubspec.yaml"><img src="https://img.shields.io/badge/version-1.1.4-blue" alt="Version"></a>
</p>

<p align="center">Based on <a href="https://github.com/venera-app/venera">Venera</a>, UI overhaul + bug fixes + performance improvements.</p>

<div align="center">
  <img src="doc/Screenshot_20260625_030823.png" width="280" alt="Home (light)" />
  &nbsp;&nbsp;
  <img src="doc/Screenshot_20260625_030912.png" width="280" alt="Home (dark)" />
  <br/>
  <em>Home — light theme (left) and dark theme (right)</em>
</div>

---

## ✨ What's New in v1.1.4

### 🐛 Bug Fixes
- **Local storage migration crash** — `LocalManager.setNewPath` no longer crashes when copying into a SAF directory; file writes now route through `AndroidFile` for SAF URIs (dart:io's `File.copySync` doesn't understand `content://` / `android://`)
- **CBZ packaging silently failed on SAF** — Replaced `zip_flutter` (uses dart:io `File.open` internally) with pure-Dart `archive` + `ZipEncoder`; CBZ bytes built in memory and written via `AndroidFile.writeAsBytesSync`
- **Comment avatar `dio` crash** — `ImageDownloader.loadThumbnail` now rejects empty URLs; comment renderers check `== null || isEmpty` for `avatar`
- **Battery widget `setState` after dispose** — `_BatteryWidgetState` checks `mounted` and cancels its periodic timer on unmount
- **Comments / favorites / vote `setState` after dispose** — Added `if (!mounted) return;` guards to all `await`+`setState` paths

### 🎨 UI & UX Improvements
- **CBZ file naming** — Downloaded `.cbz` files now use `<manga title> - <chapter title>.cbz` instead of the chapter ID

### 🧹 Cleanup
- Removed duplicate `archive: any` in `dev_dependencies`
- i18n audit — All 587 zh_CN / zh_TW keys verified

---

## ✨ What's New in v1.1.0

### 🐛 Bug Fixes
- **Swipe-back gesture restored on side pages** — Removed conflicting `GestureDetector(onHorizontalDragEnd)` from `SideBarRoute`; the fork's custom gesture competed with Android's predictive back, requiring 2–3 swipes to pop. The route now uses Venera's standard click-absorber pattern, swipe-back works on the first attempt (comments, download page, etc.)
- **Download settings page crash** — Added missing default value for `deleteFolderAfterCbz` in `appdata.dart`; opening download settings no longer throws an `assert` on `null`
- **Download status wrongly shows "Paused" on error** — `buildTop()` now checks `isError` before `isPaused`, so failed downloads correctly display "Error" instead of "Paused"
- **Duplicate Language entry in Settings** — Removed the legacy hardcoded Language picker from the APP settings page; the "Appearance → Language" entry is now the only one (with proper translations and live reload)

### 🎨 UI & UX Improvements
- **Download settings page refactored** — Section headers ("CBZ Packaging" / "Download Performance"), conditional visibility of `deleteFolderAfterCbz` (only shown when CBZ is enabled), thread-count hint
- **Settings page two-pane mode polish** — Selected category uses `primary.withValues(alpha: 0.3)` border, `cs.primary` icon color, `cs.onSurface` title — clearer focus indicator

### 🚀 Performance
- **Async I/O in download pipeline** — `existsSync` / `deleteSync` / `writeAsBytesSync` replaced with async equivalents; CBZ packaging and cover writes no longer block the UI thread

---

## ✨ What's New in v1.0.5

### 🚀 Performance & Optimization
- **Reader image preload concurrency control** — Semaphore limits to 3 concurrent loads, preventing OOM crashes
- **Download I/O moved to async** — `writeAsBytesSync` replaced with async `writeAsBytes`, UI thread no longer blocked
- **Download progress notification throttling** — `notifyListeners()` throttled to max 1 per 500ms, reducing unnecessary rebuilds
- **Search suggestions optimized** — Prefix index (`_searchIndex`) replaces full linear scan, significantly faster on large tag dictionaries
- **Image loading concurrency control** — `CachedImageProvider` uses semaphore instead of polling, more efficient
- **App init priority split** — Critical path (UI rendering) separated from deferred path (tags, OpenCC), faster first frame
- **History cache LRU** — FIFO → LRU, cache size 10 → 20, fewer cache misses
- **`forceRebuild()` optimized** — Simplified to `setState(() {})`, leverages Flutter diffing

### 🎨 UI & UX Improvements
- **Tag color contrast fix** — Title tags now use `useTextColor()` for proper dark mode contrast; tag values use `primaryContainer` for better visibility
- **Chapter list color optimization** — Current reading chapter highlighted with `primaryContainer` + bold; read chapters use `onSurfaceVariant` instead of `outline`; normal/grouped chapters visually distinguished
- **Home page pull-to-refresh** — `RefreshIndicator` added to home page, Banner reloads on refresh
- **Home timer fix** — Removed recursive `_startTimer()` call inside `Timer.periodic` callback, preventing timer leak

### 🐛 Bug Fixes
- **Home timer not properly cancelled** — `_startTimer()` now cancels previous timer before creating a new one
- **`forceRebuild()` performance issue** — Removed full Element tree traversal, now uses `setState`

---

## 🔧 Build

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

## 📄 License

[GPL-3.0](LICENSE)
