# KongComic 🎨

> A comic reader based on [Venera](https://github.com/venera-app/venera) | UI overhaul · Bug fixes · Performance

<p align="center">
  <b>English</b> | <a href="README.md">中文</a>
</p>

<p align="center">
  <a href="https://github.com/SkyAlice-source/KongComic-android/releases">
    <img src="https://img.shields.io/github/v/release/SkyAlice-source/KongComic-android" alt="Release">
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/github/license/SkyAlice-source/KongComic-android" alt="License">
  </a>
  <a href="https://github.com/SkyAlice-source/KongComic-android/releases">
    <img src="https://img.shields.io/github/downloads/SkyAlice-source/KongComic-android/total" alt="Downloads">
  </a>
</p>

<!-- Screenshots hidden for now
<p align="center">
  <img src="doc/Screenshot_20260625_030823.png" width="200" />
  <img src="doc/Screenshot_20260625_030912.png" width="200" />
</p>
-->

---

## 🚀 Quick Install

Download APK from [Releases](https://github.com/SkyAlice-source/KongComic-android/releases).

## ✨ Features

- **Multi-source search** — Aggregate search across sources
- **Offline download** — CBZ packaging support
- **Local favorites** — Multi-level folders + custom covers
- **Reader** — Multiple page modes + auto-scroll
- **Backup & restore** — Settings, favorites, covers in one click
- **Crash reporting** — Sentry monitoring for trackable issues

## 🔧 Build from source

Requirements:
- Flutter 3.44+ (Dart 3.8+)
- JDK 17

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

> Pushing a `v*` tag triggers GitHub Actions to build and publish a signed Release APK automatically.

## 📄 License

[GPL-3.0](LICENSE)
