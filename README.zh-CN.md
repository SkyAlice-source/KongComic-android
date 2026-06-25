<h1 align="center">KongComic 🎨</h1>

<p align="center"><a href="README.md">English</a> | <a href="README.zh-CN.md"><b>中文</b></a></p>

<p align="center">
  <a href="https://github.com/SkyAlice-source/KongComic-android/stargazers"><img src="https://img.shields.io/github/stars/SkyAlice-source/KongComic-android" alt="Stars"></a>
  <a href="https://github.com/SkyAlice-source/KongComic-android/releases"><img src="https://img.shields.io/github/v/release/SkyAlice-source/KongComic-android" alt="Release"></a>
  <a href="https://github.com/SkyAlice-source/KongComic-android/blob/main/LICENSE"><img src="https://img.shields.io/github/license/SkyAlice-source/KongComic-android" alt="License"></a>
</p>

<p align="center">基于 <a href="https://github.com/venera-app/venera">Venera</a> 二次开发的漫画阅读器，UI 翻新 + Bug 修复。</p>

---

## ✨ 修改内容

- **🎨 UI 翻新** — 主页布局重做、底部导航 5 项、全量图标替换为 HugeIcons、设置页分类重排
- **🐛 Bug 修复** — 搜索页键盘卡顿、阅读器误触、文字越界、底部白条、语言切换即时生效
- **⚡ 性能优化** — 移除全部 BackdropFilter 高斯模糊、1300+ 行死代码

## 🔧 构建

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

## 📄 开源许可

[GPL-3.0](LICENSE)
