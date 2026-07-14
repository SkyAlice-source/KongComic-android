---
name: kongcomic-dev
description: KongComic（空漫）Flutter 漫画阅读器。版本管理规则、项目结构、阅读器代码规范、构建流程。
---

# KongComic 开发指南

## 版本管理（重要！）

项目有三个版本号，**两个要改一个不能动**：

| 位置 | 字段 | 示例 | 说明 |
|------|------|------|------|
| `pubspec.yaml:5` | `version` | `1.2.17+137` | **改** — 构建版本号 |
| `lib/foundation/app.dart:19` | `appVersion` | `"1.2.17"` | **改** — 设置→关于页显示用 |
| `lib/foundation/app.dart:18` | `version` | `"1.6.4"` | **不改** — 漫画源认证版本，动会导致认证失效 |

提版本步骤（三步）：
1. `pubspec.yaml` 改版本号（`version: x.y.z+build`）
2. `app.dart:appVersion` 同步改成 `"x.y.z"`
3. 提交推送触发构建

## 项目结构

```
lib/
├── main.dart                         # 入口
├── foundation/                       # 核心基础设施
│   ├── app.dart                      # App 全局常量（version/appVersion）
│   ├── appdata.dart                  # 设置持久化
│   ├── comic_source/                 # 漫画源引擎
│   ├── history.dart                  # 阅读历史
│   ├── local.dart                    # 本地漫画管理
│   ├── cache_manager.dart            # 图片缓存
│   ├── image_provider/               # 图片加载器
│   ├── favorites.dart                # 收藏
│   ├── image_favorites.dart          # 图片收藏
│   └── global_state.dart             # 全局状态/ GlobalState 模式
├── pages/
│   ├── reader/                       # 阅读器（多文件 part of）
│   ├── settings/                     # 设置页
│   ├── comic_details_page/           # 漫画详情
│   ├── favorites/                    # 收藏页
│   ├── image_favorites_page/         # 图片收藏页
│   └── ...
├── components/                       # 通用组件
│   ├── navigation_bar.dart           # 主页导航 + 退出确认逻辑
│   ├── side_bar.dart                 # 侧边栏路由
│   ├── button.dart                   # Button 组件
│   └── ...
├── network/                          # 网络层（dio）
│   └── images.dart                   # ImageDownloader
└── utils/                            # 工具函数
    ├── translations.dart             # 翻译系统（.tl）
    └── ext.dart                      # 扩展方法
```

## 阅读器（`lib/pages/reader/`）

使用 `part of 'reader.dart'` 多文件结构：

| 文件 | 职责 |
|------|------|
| `reader.dart` | 主 State：`_ReaderState`，页面/章节切换、阅读模式、窗口、音量键 |
| `images.dart` | 图片显示：`_GalleryMode`（画廊）、`_ContinuousMode`（连续滚动） |
| `gesture.dart` | 手势识别：点击翻页、双击缩放、长按/拖拽 |
| `comic_image.dart` | 单张漫画图片渲染，错误/加载状态 |
| `scaffold.dart` | UI 框架：顶部/底部工具栏、进度条、收藏/分享 |
| `chapters.dart` | 章节列表面板 |
| `chapter_comments.dart` | 章节评论 |
| `loading.dart` | 阅读器数据加载 |

关键约定：
- 通过 `context.reader` 获取 `_ReaderState`（extension on BuildContext）
- 通过 `context.readerScaffold` 获取 `_ReaderScaffoldState`
- 手势通过 `_ReaderGestureDetectorState` + `_tapGestureRecognizer` 实现
- `_ImageViewController` 接口：图片控制器统一协议（`toPage`, `animateToPage`, `handleDoubleTap` 等）

## 手势系统特点

- 外层 `_ReaderGestureDetector` 用 `Listener(behavior: HitTestBehavior.translucent)` 拦截指针事件
- `_tapGestureRecognizer` 手动管理，手动 `addPointer`
- 内层 widget 需要处理 tap 时**必须用 `GestureDetector` 而不是 `Listener(onPointerDown:)`**：
  - `Listener` 的 `onPointerDown` 在外层之后触发，`ignoreNextTap()` 来不及
  - `GestureDetector` 在 hit test 阶段加入竞技场，先加入的外层会被 reject
  - 参见 v1.2.17 的 `comic_image.dart` 修复

## 构建与发布

- 推送 `main` 分支触发 GitHub Actions 自动构建
- 构建配置在 `.github/workflows/`
- 版本号格式 `major.minor.patch+buildNumber`

## 常用操作

### 更新版本号
```bash
# 改 pubspec.yaml 的 version
# 改 app.dart 的 appVersion
# app.dart 的 version 不要动
```

### 查找定义
```bash
grep -rn "目标" lib/ --include="*.dart"
```

## References

- [Flutter](https://docs.flutter.dev/)
- 项目 GitHub：`https://github.com/SkyAlice-source/KongComic-android`
