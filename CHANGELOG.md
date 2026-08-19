# Changelog

## [1.3.0] - 2026-08-20

### ✨ 新功能
- 接入 Sentry 崩溃上报（线上崩溃可追踪，DSN 经构建参数注入）

### 🔧 依赖与底层
- SQLite 迁移至 3.x（build hooks 原生加载，移除已停维护的 sqlite3_flutter_libs）
- flutter_local_notifications 升级至 22.3.0
- 9 个 fork 依赖 vendor 到本地 packages/（防上游删库，仓库自包含）
- flutter_markdown 迁移至 flutter_markdown_plus
- 小版本依赖升级（archive / workmanager / synchronized / vm_service）

### 🐛 修复
- Cloudflare 验证失效修复（Turnstile 轮询检测 + cookie 抓取 URL + 并发竞态）
- 修复 4 个 channel 名不匹配（文本分享 / 音量翻页 / 代理 / 装 APK）
- 应用更新错过安装弹窗后可重装、通知点击重新拉起安装器
- manual 代理用户名密码认证生效
- 漫画更新完成通知点击跳转追更页
- i18n 补全（@count/@total 占位符、Refresh Failed 大小写）

### 🎨 UI
- 漫画源卡片紧凑化（编辑/更新/删除收进更多菜单、version badge 迁移）
- 进度/加载对话框统一（去冗余关闭入口 + 更轻盈的取消按钮）
- 阅读器底栏减负（低频操作收进更多溢出菜单）
- 品牌色抽成 kcBrandColor token、section 标题字重统一
- 图片收藏缓存加进度条

## [1.2.40] - 2026-08

### 🐛 修复
- 详情页取色移除回归全局主题、长描述折叠/下拉刷新/收藏防闪烁
- 分类页横向滑动误触发底栏抖动修复、顶部导航栏固定

## [1.2.37] - 2026-08

### 📝 文档与翻译
- README 完善
- 补全翻译（含 `MB` 单位、分类组名、追更间隔等）
- 版本号升级

## [1.2.36] - 2026-08

### 🔧 修复
- 合并 Reasonix 工作区改动并恢复漫画源功能
- 错误提示全面友好化（friendlyError 兜底 32 处）
- 历史页新增搜索
- 追更检查间隔可配置（每天/每 3 天/每周）

## [1.2.35] - 2026-08

### ✨ 新功能
- **自动备份**
- **通知栏后台**（追更检查/下载进度通知）
- **多文件夹追更**
- 关于页版本动态化
- 软件更新通知栏
- 图片收藏返回栈与离线秒开
- i18n 与错误提示优化

## [1.2.34] - 2026-08

### 🛠 工具链
- 升级 Android toolchain：Gradle 8.14.2 / AGP 8.11.1 / Kotlin 2.3.20

## [1.2.33] - 2026-08

### ✨ 功能
- 主题系统重构
- 收藏离线缓存
- 收藏标签优化

## [1.2.32] - 2026-08

### ✨ 体验
- 布局切换 / 主题与更新体验打磨

## [1.2.31] - 2026-08

### 🐛 修复
- UI 打磨
- 阅读器返回栈修复
- 错误提示优化

## [1.2.30] - 2026-08

### 🎨 UI
- UI 一致性改进
- 翻译与错误提示优化

## [1.2.29] - 2026-08

### 🐛 修复
- 修复 leakcanary debug manifest 冲突
- 依赖供应链收敛
- 关于页图标/URL/翻译

## [1.2.28] - 2026-08

### 🐛 修复
- 修复 monochrome 图标导致 CI 构建失败

## [1.2.27] - 2026-08

### 🎨 重构
- 设计系统重构
- 搜索整合
- 图标暖白底
- 版本号修正

## [1.2.26] - 2026-07

### 🎨 UI
- 新图标与书签配色
- 翻译补全
- 控制器泄漏修复

## [1.2.6] - 2026-07-02

### 🐛 Bug Fixes (45+ fixes)

#### Critical Fixes
- **Fixed resource leaks**: Timer, Isolate, and StreamSubscription leaks in multiple components
  - WindowPlacement.loop() Timer leak
  - Heartbeat Timer leak in init()
  - DownloadTask.cancel() not stopping timer
  - JsEngine Isolate leak
  - FollowUpdatesService Timer leak

#### Data Integrity Fixes
- **Fixed concurrent write race condition** in LocalManager.saveCurrentDownloadingTasks()
- **Added transaction support** for database operations in appdata.dart and favorites.dart
- **Enabled WAL mode** for SQLite databases (cache_manager.dart, cookie_jar.dart)
- **Fixed version number management** in data_sync.dart

#### Null Safety Fixes
- Fixed unsafe type casts in appdata.dart, cache_manager.dart
- Fixed null assertion crashes in volume.dart, comic_type.dart, navigation_bar.dart
- Fixed null safety issues in image_favorites.dart, data_sync.dart, import_comic.dart

#### Code Quality Improvements
- Removed 13 unused imports
- Updated deprecated APIs (Share, TickerMode, onReorder)
- Fixed code style issues (curly_braces, unnecessary_string_interp)

### 🔒 Security
- Improved error handling in file operations
- Added proper resource cleanup in dispose methods

---

## [1.2.5] - 2026-06-30

### Changes
- Full Changelog: https://github.com/SkyAlice-source/KongComic-android/compare/v1.2.4...v1.2.5

---

## [1.2.4] - Previous Release

### Changes
- See GitHub Releases for details
