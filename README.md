# KongComic

> 基于 [venera-app/venera](https://github.com/venera-app/venera) 由 AI (Reasonix Code) 深度修改二次开发

[![flutter](https://img.shields.io/badge/flutter-3.44.0-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/SkyAlice-source/KongComic-android)](LICENSE)

---

## 📖 简介

KongComic 是一款漫画阅读器，支持本地漫画和网络漫画源。本仓库由 **Reasonix Code (AI Agent)** 自动生成大量修改，是对 [Venera](https://github.com/venera-app/venera) 项目的 Android 专属二次开发版本。

衷心感谢 [Venera](https://github.com/venera-app/venera) 项目（[@wgh136](https://github.com/wgh136)）提供的优秀基础。

---

## ✨ AI 修改内容

### 🎨 UI 全面翻新

| 模块 | 修改内容 |
|------|---------|
| **首页 Banner** | 层叠式卡片轮播，PageView + AnimatedSwitcher 原位缩放淡入淡出 |
| **统计胶囊** | 毛玻璃渐变胶囊，图标+标签+数字布局 |
| **底部导航栏** | 完全透明背景，线性图标 + 圆形蓝色选中态 |
| **胶囊模块** | 追更/历史/分类/本地/图片收藏/漫画源统一胶囊样式 |
| **搜索页** | 搜索栏居中，底部导航栏固定 |

### 🖼 Banner 卡片

- 层叠展示：中心完整显示，左右 2 层 50% 重叠
- 三方向阴影 + 白色发光边框
- 页漫比例 1:1.4，自适应高度

### ⚡ 性能优化

- **移除 rhttp**：用 Dart 原生 HttpClient 替代 Rust 网络库
- **CachedNetworkImage**：图片缓存
- **AnimatedBuilder** 局部重建
- **LayoutBuilder** 自适应高度
- **PageView** 消除手势冲突

### 🔧 代码清理

- 隐藏 Debug / GitHub / Telegram 页面
- 移除设置页分割线
- 移除 1300+ 行死代码
- 毛玻璃效果改为实色背景
- 状态栏 + 导航栏改为实色

### 📦 依赖

| 操作 | 包 |
|------|----|
| 移除 | flutter_to_arch, flutter_to_debian, file_selector, battery_plus, flutter_memory_info |
| 添加 | cached_network_image |

---

## 🔧 构建

```bash
flutter pub get
flutter build apk --debug
flutter build apk --split-per-abi   # 分离架构，体积更小
```

---

## 🙏 致谢

- [Venera](https://github.com/venera-app/venera) — 原项目 [@wgh136](https://github.com/wgh136)
- [Reasonix Code](https://reasonix.ai) — AI 编程助手
- 所有开源依赖的维护者

---

## 📄 开源许可

[GPL-3.0](LICENSE)
