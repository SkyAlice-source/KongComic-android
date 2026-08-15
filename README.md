# KongComic 🎨

> 基于 [Venera](https://github.com/venera-app/venera) 二次开发 | UI 翻新 · Bug 修复 · 性能优化

<p align="center">
  <a href="README.en.md">English</a> | <b>中文</b>
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

<!-- 截图暂隐藏
<p align="center">
  <img src="doc/Screenshot_20260625_030823.png" width="200" />
  <img src="doc/Screenshot_20260625_030912.png" width="200" />
</p>
-->

---

## 🚀 快速安装

从 [Releases](https://github.com/SkyAlice-source/KongComic-android/releases) 下载 APK 安装即可。

## ✨ 功能

- **多源搜索** — 聚合搜索，一键找到
- **离线下载** — 支持 CBZ 打包
- **本地收藏** — 多级文件夹 + 自定义封面
- **阅读器** — 多种翻页模式 + 自动滚动
- **备份恢复** — 设置、收藏、封面一键打包

## 🔧 自行构建

环境要求：
- Flutter 3.44+（Dart 3.8+）
- JDK 17

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

> 推送 `v*` 标签后，GitHub Actions 会自动构建并发布带签名的 Release APK，无需本地手动打包。

## 📄 许可

[GPL-3.0](LICENSE)

