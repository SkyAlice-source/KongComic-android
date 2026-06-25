<h1 align="center">KongComic 🎨</h1>

<p align="center"><a href="README.md"><b>English</b></a> | <a href="README.zh-CN.md">中文</a></p>

<p align="center">
  <a href="https://github.com/SkyAlice-source/KongComic-android/stargazers"><img src="https://img.shields.io/github/stars/SkyAlice-source/KongComic-android" alt="Stars"></a>
  <a href="https://github.com/SkyAlice-source/KongComic-android/releases"><img src="https://img.shields.io/github/v/release/SkyAlice-source/KongComic-android" alt="Release"></a>
  <a href="https://github.com/SkyAlice-source/KongComic-android/blob/main/LICENSE"><img src="https://img.shields.io/github/license/SkyAlice-source/KongComic-android" alt="License"></a>
</p>

<p align="center">A comic reader based on <a href="https://github.com/venera-app/venera">Venera</a>, with revamped UI and bug fixes.</p>

---

## ✨ What's Different

- **UI Overhaul** — Reorganized home layout, 5-tab bottom nav, all icons replaced with HugeIcons
- **Bug Fixes** — Keyboard lag, reader mis-tap, overflow text, bottom bar white strip
- **Performance** — Removed all BackdropFilter blur, 1300+ lines of dead code

## 🔧 Build

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

## 📄 License

[GPL-3.0](LICENSE)
