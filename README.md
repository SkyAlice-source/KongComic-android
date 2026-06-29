# KongComic 🎨

> 基于 [Venera](https://github.com/venera-app/venera) 二次开发的漫画阅读器，UI 翻新 + Bug 修复 + 性能优化。

[![GitHub Stars](https://img.shields.io/github/stars/SkyAlice-source/KongComic-android)](https://github.com/SkyAlice-source/KongComic-android/stargazers)
[![GitHub Release](https://img.shields.io/github/v/release/SkyAlice-source/KongComic-android)](https://github.com/SkyAlice-source/KongComic-android/releases)
[![License](https://img.shields.io/github/license/SkyAlice-source/KongComic-android)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.44.0-blue?logo=flutter)](https://flutter.dev)
[![Version](https://img.shields.io/badge/version-1.1.6-blue)](https://github.com/SkyAlice-source/KongComic-android/releases)

---

## 📖 目录

- [项目简介](#-项目简介)
- [功能特性](#-功能特性)
- [安装指南](#-安装指南)
- [使用指南](#-使用指南)
- [开发环境搭建](#-开发环境搭建)
- [项目结构](#-项目结构)
- [贡献指南](#-贡献指南)
- [开源许可](#-开源许可)
- [致谢](#-致谢)

---

## 📖 项目简介

KongComic 是一款基于 Flutter 开发的跨平台漫画阅读器，继承自 [Venera](https://github.com/venera-app/venera) 项目，通过 AI 辅助深度二次开发。应用支持多漫画源聚合搜索、本地漫画管理、在线阅读等功能。

### 🖼️ 应用截图

<div align="center">
  <img src="doc/Screenshot_20260625_030823.png" width="280" alt="主页（浅色）" />
  &nbsp;&nbsp;
  <img src="doc/Screenshot_20260625_030912.png" width="280" alt="主页（深色）" />
  <br/>
  <em>主页 — 浅色主题（左）与深色主题（右）</em>
</div>

---

## ✨ 功能特性

### 🏠 主页
- Banner 卡片轮播自动切换
- 漫画信息面板：标题、作者、阅读进度、总话数、「立即阅读」按钮
- 快捷入口：追更更新、本地漫画、图片收藏、漫画源管理

### 🗺️ 导航
- 5 个标签页：分类 / 收藏 / 主页 / 发现 / 历史
- 激活状态：紫色圆形背景 + 紫色图标 + 加粗文字
- 悬浮毛玻璃底部导航栏，圆角设计

### 🔍 搜索
- 多源搜索 + 聚合搜索
- 漫画 ID 直接跳转
- 标签建议（带防抖优化）
- 搜索历史（支持逐条删除）

### 📚 漫画源系统
- 基于 JavaScript 的漫画源插件系统
- 支持从远程仓库加载漫画源
- 内置漫画源配置管理器

### 📖 阅读器
- 触摸翻页（左侧/右侧 30% 区域，中间 40% 区域调出菜单）
- 进度条 + ShaderMask 双色文字
- 支持 CBZ / CB7 / EPUB / PDF 格式
- 图片预加载并发控制（防止 OOM）

### 🎨 UI 设计
- Geist 风格的扁平化设计
- HugeIcons（5000+ 线性图标）替代所有 FluentIcons/Material Icons
- 浅色/深色双主题

### 📦 下载与本地管理
- 支持漫画下载（CBZ 打包）
- 本地漫画导入（支持目录结构和压缩包）
- 下载进度通知节流（500ms 间隔）

### 🔄 备份与恢复
- 导出/导入包含：历史记录、收藏、设置、Cookies、源脚本、自定义封面

### ⚙️ 设置
- 9 大分类：阅读器 / 外观 / 发现 / 收藏 / 网络 / 下载 / 导入 / 通用 / 关于
- 按使用频率排序
- 语言选择器（跟随系统 / 简体中文 / 繁体中文 / English）

---

## 🔧 安装指南

### 📱 方式一：下载预构建 APK（推荐）

1. 前往 [Releases](https://github.com/SkyAlice-source/KongComic-android/releases) 页面
2. 根据设备架构下载对应的 APK：

| APK 文件 | 大小 | 适用设备 |
|---------|------|----------|
| `KongComic-1.1.6-arm64-v8a.apk` | ~17 MB | 现代 Android 手机（ARM64） |
| `KongComic-1.1.6-armeabi-v7a.apk` | ~16 MB | 较旧的 Android 设备（ARM32） |
| `KongComic-1.1.6-x86_64.apk` | ~17 MB | 模拟器 / x86 平板 |
| `KongComic-1.1.6-universal.apk` | ~41 MB | 所有架构（通用） |

3. 将 APK 文件传输到 Android 设备
4. 在设备上打开 APK 文件，按照提示完成安装
   - 如果提示「未知来源」，请在系统设置中允许此次安装

### 🛠️ 方式二：从源码构建

#### 环境要求

| 依赖 | 版本要求 | 说明 |
|------|----------|------|
| Flutter SDK | 3.44.0+ | [安装指南](https://docs.flutter.dev/get-started/install) |
| Dart SDK | 3.8.0+ | 随 Flutter 一同安装 |
| Android SDK | 21+ | API Level 21 (Android 5.0) 及以上 |
| Git | 最新版 | 用于获取依赖和子模块 |

#### 构建步骤

```bash
# 1. 克隆仓库
git clone https://github.com/SkyAlice-source/KongComic-android.git
cd KongComic-android

# 2. 获取依赖（首次运行会自动获取 Flutter QJS 等 git 依赖）
flutter pub get

# 3. 构建 Release APK（按架构拆分）
flutter build apk --release --split-per-abi

# 或使用以下命令跳过构建依赖校验（推荐）
flutter build apk --release --android-skip-build-dependency-validation
```

构建完成后，APK 文件位于：
```
build/app/outputs/flutter-apk/KongComic-{version}-{abi}.apk
```

#### 直接运行（开发/调试）

```bash
# 连接 Android 设备或启动模拟器后执行
flutter run
```

### 🪟 Windows 平台构建（实验性）

```bash
# 构建 Windows 桌面应用
flutter build windows --release
```

> ⚠️ Windows 版本为实验性功能，部分功能可能不可用。

---

## 📘 使用指南

### 🚀 快速上手

#### 1. 首次启动

首次启动应用后，建议按以下顺序进行配置：

1. **设置漫画源**：前往「发现」→ 点击右上角「+」→ 添加漫画源仓库 URL
   ```
   https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/index.json
   ```
2. **选择漫画源**：在漫画源列表中启用需要的数据源
3. **配置下载路径**：前往「设置」→「下载」→ 设置本地存储路径

#### 2. 搜索与阅读

```
# 基本搜索流程
1. 点击底部「搜索」标签
2. 输入关键词或漫画 ID
3. 选择搜索结果中的漫画
4. 查看详情 → 选择章节 → 开始阅读
```

#### 3. 下载漫画

1. 在漫画详情页点击「下载」按钮
2. 选择需要下载的章节
3. 可在「设置」→「下载」中配置：
   - 同时下载线程数
   - 是否打包为 CBZ
   - CBZ 打包后是否删除原文件夹

> 💡 下载的 CBZ 文件命名格式：`<漫画名> - <章节名>.cbz`（如 `海贼王 - 第01话.cbz`）

#### 4. 本地漫画导入

KongComic 支持导入本地漫画文件，支持以下格式：

**支持的压缩包格式**：`.cbz`、`.cb7`、`.zip`、`.7z`

**目录结构规范**：

不含章节：
```
漫画目录/
├── cover.jpg       # 封面（可选）
├── img1.jpg
├── img2.jpg
└── ...
```

含章节：
```
漫画目录/
├── cover.jpg       # 封面（可选）
├── 第01话/
│   ├── img1.jpg
│   └── img2.jpg
├── 第02话/
│   ├── img1.jpg
│   └── img2.jpg
└── ...
```

导入步骤：
1. 将漫画文件/目录放置到设置的本地存储路径
2. 打开应用 →「本地」→ 点击「导入」
3. 选择「扫描本地文件」或「恢复本地下载」

#### 5. WebDAV 同步（可选）

1. 前往「设置」→「网络」→「WebDAV」
2. 填写服务器地址、用户名、密码
3. 启用自动同步

### ⌨️ 实用技巧

| 操作 | 说明 |
|------|------|
| 阅读时点击左侧/右侧 30% | 翻页 |
| 阅读时点击中间 40% | 显示/隐藏菜单 |
| 长按漫画封面 | 快速添加到收藏 |
| 搜索框输入漫画 ID | 直接跳转到对应漫画 |
| 双指缩放 | 放大/缩小图片（阅读器） |
| 侧滑返回 | 返回上一页（Android 预测性返回手势） |

---

## 💻 开发环境搭建

### 前置条件

1. **安装 Flutter SDK**
   ```bash
   # 推荐使用 FVM 管理 Flutter 版本
   dart pub global activate fvm
   fvm install 3.44.0
   fvm use 3.44.0
   ```

2. **配置 Android 开发环境**
   - 安装 [Android Studio](https://developer.android.com/studio)
   - 安装 Android SDK（API Level 21+）
   - 配置 `ANDROID_HOME` 环境变量

3. **验证环境**
   ```bash
   flutter doctor
   ```

### 运行项目

```bash
# 获取依赖
flutter pub get

# 启动调试（连接设备或启动模拟器）
flutter run

# 指定架构运行（加快构建速度）
flutter run --target-platform android-arm64
```

### 调试技巧

- **查看日志**：`flutter logs`
- **性能分析**：`flutter run --profile`
- **热重载**：在运行中的终端按 `r`
- **热重启**：在运行中的终端按 `R`

### 项目配置

部分依赖通过 Git 引用，首次 `flutter pub get` 时会自动克隆。如遇网络问题，可配置代理：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

---

## 📁 项目结构

```
KongComic-android/
├── lib/                          # Dart 源码
│   ├── components/               # UI 组件库
│   │   ├── appbar.dart           # 自定义 AppBar
│   │   ├── button.dart           # 按钮组件
│   │   ├── comic.dart            # 漫画卡片组件
│   │   ├── image.dart            # 图片组件
│   │   ├── navigation_bar.dart   # 底部导航栏
│   │   └── ...
│   ├── foundation/               # 基础框架层
│   │   ├── app.dart              # 应用入口
│   │   ├── appdata.dart          # 应用数据管理
│   │   ├── comic_source/         # 漫画源系统
│   │   │   ├── comic_source.dart # 漫画源基类
│   │   │   ├── models.dart       # 数据模型
│   │   │   └── parser.dart       # JS 解析器
│   │   ├── cache_manager.dart    # 缓存管理
│   │   ├── history.dart          # 历史记录
│   │   └── ...
│   ├── pages/                    # 页面
│   │   ├── main_page.dart        # 主页面（标签页容器）
│   │   ├── reader/               # 阅读器页面
│   │   ├── settings/             # 设置页面
│   │   ├── search_page.dart      # 搜索页面
│   │   └── ...
│   └── utils/                    # 工具类
│       ├── cbz.dart              # CBZ 打包工具
│       ├── io.dart               # I/O 工具
│       ├── translations.dart     # 国际化
│       └── ...
├── android/                      # Android 平台代码
│   ├── app/
│   ├── build.gradle
│   └── ...
├── assets/                       # 资源文件
│   ├── translation.json          # 翻译文件
│   ├── tags.json                 # 标签数据
│   └── ...
├── doc/                          # 项目文档
│   ├── comic_source.md           # 漫画源开发文档
│   ├── import_comic.md          # 本地漫画导入文档
│   └── js_api.md                # JS API 文档
├── pubspec.yaml                  # Flutter 项目配置
└── README.md                    # 项目说明（本文件）
```

---

## 🤝 贡献指南

感谢你考虑为 KongComic 做出贡献！

### 🌟 贡献方式

- 🐛 **提交 Bug 报告**：在 [Issues](https://github.com/SkyAlice-source/KongComic-android/issues) 页面新建 Issue
- 💡 **提出功能建议**：同样通过 Issues 提交，请使用 `feature request` 标签
- 📝 **改进文档**：直接提交 PR 修改 `doc/` 目录下的文档
- 🔧 **提交代码**：Fork 本仓库并提交 Pull Request
- 🌐 **添加漫画源**：向 [venera-configs](https://github.com/venera-app/venera-configs) 提交漫画源脚本

### 🔄 代码提交流程

#### 1. Fork & Clone

```bash
# Fork 本仓库后，克隆你的 Fork
git clone https://github.com/你的用户名/KongComic-android.git
cd KongComic-android

# 添加上游仓库
git remote add upstream https://github.com/SkyAlice-source/KongComic-android.git
```

#### 2. 创建分支

```bash
# 从 main 分支创建功能分支
git checkout -b feature/你的功能描述
# 或
git checkout -b fix/修复的问题描述
```

#### 3. 开发规范

**代码风格**：
- 遵循 [Dart Style Guide](https://dart.dev/effective-dart/style)
- 使用 `dart format` 格式化代码
- 使用 `flutter analyze` 检查代码质量

**提交信息规范**（参考 [Conventional Commits](https://www.conventionalcommits.org/)）：

```
feat: 添加 XX 功能
fix: 修复 XX 问题
docs: 更新 XX 文档
style: 代码格式调整（不影响功能）
refactor: 代码重构
perf: 性能优化
chore: 构建/工具链调整
```

#### 4. 测试

```bash
# 运行静态分析
flutter analyze

# 运行单元测试（如有）
flutter test

# 手动测试关键流程
# - 应用启动
# - 漫画搜索
# - 阅读器功能
# - 下载功能
# - 设置页面
```

#### 5. 提交 Pull Request

```bash
# 提交代码
git add .
git commit -m "feat: 添加 XX 功能"

# 推送到你的 Fork
git push origin feature/你的功能描述
```

然后在 GitHub 上创建 Pull Request，并：

1. 填写清晰的 PR 描述
2. 关联相关的 Issue（如有）
3. 添加截图（如涉及 UI 变更）
4. 等待代码审查

### 📋 Issue 报告模板

**Bug 报告**：
```
### 环境信息
- 应用版本：v1.1.6
- 设备型号：XXX
- Android 版本：XXX
- 问题描述：...

### 复现步骤
1. ...
2. ...

### 预期行为
...

### 实际行为
...

### 截图（可选）
...
```

### 🔒 代码审查要求

- 所有 PR 至少需要 1 次审查通过才能合并
- 确保没有引入新的 `mounted` 检查遗漏（防止 setState-after-dispose）
- 异步 I/O 操作必须使用 async/await，避免阻塞 UI 线程
- 新增依赖需要在 `pubspec.yaml` 中注明原因

### 📜 开发者协议

提交代码即表示你同意：
- 你的贡献将以 GPL-3.0 许可证发布
- 你有权利分享这些代码（不侵犯第三方知识产权）

---

## 📄 开源许可

本项目基于 [GPL-3.0](LICENSE) 许可证开源。

```
GNU GENERAL PUBLIC LICENSE
Version 3, 29 June 2007
```

---

## 🙏 致谢

- [Venera](https://github.com/venera-app/venera) — 原始项目，由 [@wgh136](https://github.com/wgh136) 开发
- [Reasonix](https://reasonix.ai) — AI 编码助手
- [Flutter](https://flutter.dev) — 跨平台 UI 框架
- [flutter_qjs](https://github.com/wgh136/flutter_qjs) — JavaScript 引擎
- 所有开源依赖的维护者们
- 所有提交 Issue 和 PR 的贡献者们

---

## 📮 联系方式

- GitHub Issues：[提交问题](https://github.com/SkyAlice-source/KongComic-android/issues)
- 讨论区：[Discussions](https://github.com/SkyAlice-source/KongComic-android/discussions)（如有）

---

<p align="center">⭐ 如果这个项目对你有帮助，请给它一个 Star！</p>
