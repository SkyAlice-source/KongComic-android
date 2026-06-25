# KongComic

> A comic reader based on [venera-app/venera](https://github.com/venera-app/venera), deeply modified by AI (Reasonix)

[![flutter](https://img.shields.io/badge/flutter-3.44.0-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/SkyAlice-source/KongComic-android)](LICENSE)

---

## 📖 Introduction

KongComic is a comic reader supporting multi-source search, local favorites, and online reading. It is a deep secondary development of the [Venera](https://github.com/venera-app/venera) project by AI.

<div align="center">
  <img src="doc/Screenshot_20260625_030823.png" width="280" alt="Home" />
  <img src="doc/Screenshot_20260625_030912.png" width="280" alt="Search" />
  <br/>
  <em>Home (left) and Search (right)</em>
</div>

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
