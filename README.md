# KongComic

> 基于 [venera-app/venera](https://github.com/venera-app/venera) 由 AI (Reasonix) 深度修改的漫画阅读器

[![flutter](https://img.shields.io/badge/flutter-3.44.0-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/SkyAlice-source/KongComic-android)](LICENSE)

---

## 📖 简介

KongComic 是一款漫画阅读器，支持多源搜索、本地收藏、在线阅读。基于 [Venera](https://github.com/venera-app/venera) 项目由 AI 深度二次开发。

---

## ✨ 主要特性

### 🏠 主页

| 模块 | 说明 |
|------|------|
| **Banner 卡片轮播** | 层叠式卡片展示，随机从收藏抽取，4 秒自动切换，左右滑动 |
| **漫画信息区** | 漫画名（固定三行高度）+ 作者 + 阅读进度 + 共X集 + 更新时间 + 「立即阅读」按钮 |
| **功能入口** | 追更 / 本地 / 图片收藏 / 漫画源 — 统一圆角矩形卡片，数字圆形底色 |

### 🗺 导航

- **底部导航栏**：分类 / 收藏 / 主页 / 发现 / 历史
- 选中态：紫色圆角胶囊 + 紫色图标 + 加粗文字
- 非选中态：灰色图标 + 灰色文字
- 底部全宽圆角卡片 + `surface` 底色，无白条

### 🔍 搜索

- 多源搜索 + 聚合搜索（多选源）
- ID 直接跳转（匹配源 ID 格式自动打开漫画页）
- 搜索建议标签类型颜色区分
- 实时标签建议（300ms 防抖）
- 搜索历史 Chip 流（可逐条删除）

### 📚 设置

- **9 个分类**：阅读器设置 / 外观设置 / 浏览设置 / 收藏管理 / 网络设置 / 下载设置 / 导入设置 / 通用设置 / 关于
- 按使用频率排序
- 左侧导航：图标 + 粗标题 + 细副标题
- 子页面标题已中文化

### 🎨 UI 设计

- **Geist 风格**：扁平化、1px 边框、6px 圆角、字重层级
- **图标库**：HugeIcons（5000+ 线性图标），替换了全部 FluentIcons / Material Icons
- **双主题**：亮色 / 暗色，颜色值跟随 `colorScheme`
- **硬编码蓝色全部替换**：`#0EA5E9` / `#4A90E2` / `#1A365D` → `cs.primary`

### 📖 阅读器

- 触摸翻页（左右 30% 翻页，中间 40% 弹菜单）
- 进度条文字双色（ShaderMask 覆盖区白色 / 未覆盖区深色）
- 自动轮播定时器

### 📦 自定义封面

- 漫画详情页可手动更换封面（本地图片）
- 封面数据持久化存储

---

## 🔧 构建

### 构建命令

```bash
# 清除镜像环境变量，使用 Google 官方源
unset FLUTTER_STORAGE_BASE_URL
unset PUB_HOSTED_URL

flutter pub get
flutter build apk --debug --android-skip-build-dependency-validation
```

### 输出

```
build/app/outputs/flutter-apk/app-debug.apk
```

### 依赖

| 包 | 用途 |
|----|------|
| `hugeicons` | 图标库（5000+ 线性图标） |
| `flex_seed_scheme` | Material 3 颜色方案生成 |
| `cached_network_image` | 图片缓存 |
| `fluentui_system_icons` | 少量遗留图标（逐步替换中） |

---

## 🧩 项目结构

```
lib/
├── components/       # UI 组件（导航栏、卡片、按钮、菜单等）
├── foundation/        # 基础库（主题、数据、工具类）
├── pages/            # 页面
│   ├── comic_details_page/  # 漫画详情
│   ├── favorites/           # 收藏
│   ├── reader/              # 阅读器
│   ├── settings/            # 设置
│   └── ...
└── utils/            # 工具（翻译、IO 等）
```

---

## 🙏 致谢

- [Venera](https://github.com/venera-app/venera) — 原项目 [@wgh136](https://github.com/wgh136)
- [Reasonix](https://reasonix.ai) — AI 编程助手
- 所有开源依赖的维护者

---

## 📄 开源许可

[GPL-3.0](LICENSE)
