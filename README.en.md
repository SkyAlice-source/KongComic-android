# KongComic

> A comic reader based on [venera-app/venera](https://github.com/venera-app/venera), deeply modified by AI (Reasonix)

[**English**](README.en.md) | [**中文**](README.md)

[![flutter](https://img.shields.io/badge/flutter-3.44.0-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/SkyAlice-source/KongComic-android)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.1.6-blue)](https://github.com/SkyAlice-source/KongComic-android/releases)

---

## 📖 Introduction

KongComic is a comic reader supporting multi-source search, local favorites, and online reading. It is a deep secondary development of the [Venera](https://github.com/venera-app/venera) project by AI.

<div align="center">
  <img src="doc/Screenshot_20260625_030823.png" width="280" alt="Home (light)" />
  &nbsp;&nbsp;
  <img src="doc/Screenshot_20260625_030912.png" width="280" alt="Home (dark)" />
  <br/>
  <em>Home page — light theme (left) and dark theme (right)</em>
</div>

---

## 🆕 What's New in v1.1.6

### 🧹 Memory Leak Fixes
- **TextEditingController not disposed** (13 files) — Added proper `dispose()` for all text controllers in StatefulWidgets
- **ScrollController/PageController not disposed** (7 files) — Added `dispose()` for scroll controllers in explore page, comments preview, favorites, and gallery mode
- **TabController not disposed** — `_GroupedComicChaptersState` now disposes the tab controller with listener cleanup
- **Timer.periodic leak** — Added `_timer?.cancel()` to background update checker
- **StreamSubscription leak** — `app_links` stream subscription now properly cancelled

### 🛡️ ProGuard / R8 Hardening
- Added `-keepattributes Signature`, `*Annotation*` (Gson serialization)
- Added Gson keep rules (`TypeAdapterFactory`, `JsonSerializer`, `JsonDeserializer`)
- Added `leakcanary-android:2.14` for automatic leak detection in debug builds

### ⚡ Build Optimization
- `org.gradle.parallel=true` — faster builds
- `org.gradle.caching=true` — build cache enabled
- **Battery widget `setState` after dispose** — `_BatteryWidgetState._checkBatteryAvailability` and the periodic timer now check `mounted` and cancel on unmount, no more "setState() called after dispose" when leaving the reader
- **Comments / favorites / vote `setState` after dispose** — Added `if (!mounted) return;` guards to all `await`+`setState` paths in comment like, vote, send, add-favorite and aggregated-search-result loaders
- **Authorization switch dead-lock** (known) — The biometric check in `onChanged: () async` is fire-and-forget (signature is `VoidCallback`), so the switch can only be opened, never rejected; full fix requires a typed `Future<bool> Function()?` callback (tracked separately)

### 🎨 UI & UX Improvements
- **CBZ file naming** — Downloaded `.cbz` files now use `<manga title> - <chapter title>.cbz` (e.g. `海贼王 - 第01话.cbz`) instead of the chapter ID; helps when files are exported out of the per-comic folder

### 🧹 Cleanup
- **Removed duplicate `archive: any`** in `dev_dependencies` (already declared as a normal dependency)
- **i18n audit** — All 587 zh_CN / zh_TW keys verified; no missing or empty values

---

## 🆕 What's New in v1.1.0

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

## 🆕 What's New in v1.0.5

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

## ✨ Features

### 🏠 Home
- Banner card carousel with auto-switching
- Comic info panel: title, author, reading progress, total episodes, "Read Now" button
- Quick access: Follow Updates, Local, Image Favorites, Comic Source

### 🗺 Navigation
- 5 tabs: Categories / Favorites / Home / Explore / History
- Active state: purple circle + purple icon + bold text
- Floating glass bottom bar with rounded corners

### 🔍 Search
- Multi-source search + aggregated search
- ID direct jump
- Tag suggestions with debounce
- Search history with individual deletion

### 📚 Settings
- 9 categories: Reader / Appearance / Explore / Favorites / Network / Download / Import / General / About
- Sorted by usage frequency
- Language selector (System / Chinese / Traditional Chinese / English)

### 🎨 UI
- Geist-inspired flat design
- HugeIcons (5000+ line icons) replacing all FluentIcons/Material Icons
- Light/Dark dual theme

### 📖 Reader
- Touch to turn pages (30% left/right zones, 40% center menu)
- Progress bar with ShaderMask dual-color text

### 📦 Backup & Restore
- Export/import includes: history, favorites, settings, cookies, source scripts, and custom covers

---

## 🔧 Build

```bash
unset FLUTTER_STORAGE_BASE_URL
unset PUB_HOSTED_URL
flutter pub get
flutter build apk --release --android-skip-build-dependency-validation
```

Output: `build/app/outputs/flutter-apk/KongComic-{version}-{abi}.apk`

### Architectures
| APK | Size | Target |
|-----|------|--------|
| `arm64-v8a` | ~17 MB | Modern Android phones |
| `armeabi-v7a` | ~16 MB | Older Android devices |
| `x86_64` | ~17 MB | Emulators / Tablets |
| `universal` | ~41 MB | All architectures |

---

## 🙏 Credits

- [Venera](https://github.com/venera-app/venera) — Original project by [@wgh136](https://github.com/wgh136)
- [Reasonix](https://reasonix.ai) — AI coding assistant
- All open-source dependency maintainers

---

## 📄 License

[GPL-3.0](LICENSE)
