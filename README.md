# KongComic

> 基于 [venera-app/venera](https://github.com/venera-app/venera) 由 AI (Reasonix Code) 深度修改二次开发

[![flutter](https://img.shields.io/badge/flutter-3.44.0-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/SkyAlice-source/KongComic-android)](LICENSE)

---

## 📖 简介

KongComic 是一款漫画阅读器，支持多源搜索、本地收藏、在线阅读。基于 [Venera](https://github.com/venera-app/venera) 项目由 AI 深度二次开发。

<div align="center">
  <img src="doc/Screenshot_20260625_030823.png" width="280" alt="主页" />
  <img src="doc/Screenshot_20260625_030912.png" width="280" alt="搜索" />
  <br/>
  <em>主页（左）与搜索（右）</em>
</div>

---

## ✨ AI 修改内容

### 🎨 UI 全面翻新

| 模块 | 修改内容 |
|------|---------|
| **首页 Banner** | 层叠式卡片轮播，PageView + AnimatedSwitcher 原位缩放淡入淡出 |
| **统计胶囊** | 毛玻璃渐变胶囊，图标+标签+数字布局；Download 显示本地数量，智能跳转下载页/本地页 |
| **底部导航栏** | 完全透明背景，线性图标 + 圆形蓝色选中态 |
| **胶囊模块** | 追更/历史/分类/本地/图片收藏/漫画源统一胶囊样式 |
| **搜索页** | 搜索栏居中，底部导航栏固定 |

### 🖼 Banner 卡片

- 层叠展示：中心完整显示，左右 2 层 50% 重叠
- 三方向阴影 + 白色发光边框
- 页漫比例 1:1.4，自适应高度
- 随机从全部收藏抽取最多 7 本，不再固定取前面几个

### 📖 阅读器优化

| 功能 | 说明 |
|------|------|
| **进度条** | 粗圆条 28px，内部显示「页数 x/y」+「阅读进度 x%」，两端圆润 |
| **菜单修复** | 拖动进度条后中点点击可正常开关菜单，不再卡死 |
| **分享** | 图片获取失败自动降级为文字分享 |
| **长按菜单** | 已移除 |

### 🏠 漫画详情页

- **阅读进度条 + 上次阅读合并**：44px 全圆角进度条，内嵌两行文字（章节名 + 阅读进度百分比）
- **可点击跳转**：点击进度条直接进入继续阅读
- **文字自适应**：`onSurface` 颜色，亮暗主题自动切换

### 🏷 角标优化

- 漫画卡片左上角角标：页码 → **集数/已读集数**
- 数字大小一致，位置居中，自动适应多位数

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
- 移除阅读器长按弹出菜单

### 📦 依赖

| 操作 | 包 |
|------|----|
| 移除 | flutter_to_arch, flutter_to_debian, file_selector, battery_plus, flutter_memory_info |
| 添加 | cached_network_image |

---

## 🔧 构建

### 本地构建（国内网络）

```bash
# 清除镜像环境变量，使用 Google 官方源
unset FLUTTER_STORAGE_BASE_URL
unset PUB_HOSTED_URL

flutter pub get
flutter build apk --debug --android-skip-build-dependency-validation
```

> **注意：** 系统环境变量 `FLUTTER_STORAGE_BASE_URL` 和 `PUB_HOSTED_URL` 可能指向国内镜像（`storage.flutter-io.cn` / `pub.flutter-io.cn`），不稳定时需 unset。`--android-skip-build-dependency-validation` 跳过 Gradle/AGP 版本检查。

### 输出

```
build/app/outputs/flutter-apk/app-debug.apk
```

---

## 🙏 致谢

- [Venera](https://github.com/venera-app/venera) — 原项目 [@wgh136](https://github.com/wgh136)
- [Reasonix Code](https://reasonix.ai) — AI 编程助手
- 所有开源依赖的维护者

---

## 📄 开源许可

[GPL-3.0](LICENSE)
