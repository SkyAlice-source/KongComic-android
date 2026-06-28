<h1 align="center">KongComic 🎨</h1>

<p align="center"><a href="README.md">English</a> | <a href="README.zh-CN.md"><b>中文</b></a></p>

<p align="center">
  <a href="https://github.com/SkyAlice-source/KongComic-android/stargazers"><img src="https://img.shields.io/github/stars/SkyAlice-source/KongComic-android" alt="Stars"></a>
  <a href="https://github.com/SkyAlice-source/KongComic-android/releases"><img src="https://img.shields.io/github/v/release/SkyAlice-source/KongComic-android" alt="Release"></a>
  <a href="https://github.com/SkyAlice-source/KongComic-android/blob/main/LICENSE"><img src="https://img.shields.io/github/license/SkyAlice-source/KongComic-android" alt="License"></a>
  <a href="https://github.com/SkyAlice-source/KongComic-android/releases"><img src="https://img.shields.io/badge/version-1.1.6-blue" alt="Version"></a>
</p>

<p align="center">基于 <a href="https://github.com/venera-app/venera">Venera</a> 二次开发的漫画阅读器，UI 翻新 + Bug 修复 + 性能优化。</p>

<div align="center">
  <img src="doc/Screenshot_20260625_030823.png" width="280" alt="主页（浅色）" />
  &nbsp;&nbsp;
  <img src="doc/Screenshot_20260625_030912.png" width="280" alt="主页（深色）" />
  <br/>
  <em>主页 — 浅色主题（左）与深色主题（右）</em>
</div>

---

## ✨ v1.1.4 更新内容

### 🐛 Bug 修复
- **本地存储迁移崩溃** — `LocalManager.setNewPath` 复制到 SAF 目录不再崩溃；文件写入走 `AndroidFile` 处理 SAF URI（dart:io 的 `File.copySync` 不认 `content://` / `android://`）
- **CBZ 打包在 SAF 下静默失败** — 用纯 Dart 的 `archive` + `ZipEncoder` 替换 `zip_flutter`（内部走 dart:io `File.open`），CBZ 字节流在内存里构好后用 `AndroidFile.writeAsBytesSync` 写入，普通路径和 SAF 路径都通吃
- **评论头像 dio 崩溃** — `ImageDownloader.loadThumbnail` 拒绝空 URL；评论渲染处把 `== null` 改为 `== null || isEmpty`（部分源如 zaimanhua 匿名用户用 `""` 而非 `null`）
- **阅读器电池组件 setState-after-dispose** — `_BatteryWidgetState` 加 `mounted` 检查并在卸载时取消定时器，离开阅读器不再因定时器触发的 setState 崩
- **评论 / 收藏 / 投票 setState-after-dispose** — 给所有 `await`+`setState` 路径加 `if (!mounted) return;` 守卫
- **生物认证开关死锁**（已知）— `onChanged: () async` 形参签名是 `VoidCallback`（fire-and-forget），await 不会真等，理论上"开"之后无验证；完全修复需把签名改成 `Future<bool> Function()?`（已记入后续任务）

### 🎨 UI & 体验改进
- **CBZ 命名优化** — 下载的 `.cbz` 文件名由 `1221144.cbz`（6位 ID）改为 `<漫画名> - <章节名>.cbz`（如 `海贼王 - 第01话.cbz`），复制出漫画文件夹后也能看懂

### 🧹 清理
- 删除 `dev_dependencies` 里重复的 `archive: any`（正式依赖已有）
- i18n 审计 — 全部 587 个 zh_CN / zh_TW 键核对完毕，无缺失无空值

---

## ✨ v1.1.0 更新内容

### 🐛 Bug 修复
- **侧滑返回手势恢复正常** — 移除 `SideBarRoute` 中与 Android 预测性返回手势冲突的 `GestureDetector(onHorizontalDragEnd)`，恢复 Venera 原版的纯点击吸收模式。侧滑页面（评论、下载等）现在一次就能成功返回
- **下载设置页面崩溃** — `appdata.dart` 补充 `deleteFolderAfterCbz` 默认值；进入下载设置不再因 `assert` 失败而闪退
- **下载出错时错误显示"已暂停"** — `buildTop()` 调整判断顺序，先检查 `isError` 再检查 `isPaused`，失败任务正确显示"Error"而非"Paused"
- **设置中重复的语言入口** — 移除 APP 设置页里遗留的硬编码 Language 选择器，"外观 → 语言"成为唯一入口（带完整翻译和实时刷新）

### 🎨 UI & 体验改进
- **下载设置页重构** — 添加分区标题（"CBZ Packaging" / "Download Performance"），`deleteFolderAfterCbz` 仅在 CBZ 开关开启时显示，补充下载线程数说明
- **设置页双栏模式细节优化** — 选中分类用 `primary.withValues(alpha: 0.3)` 边框 + `cs.primary` 图标色 + `cs.onSurface` 标题，焦点更明确

### 🚀 性能优化
- **下载流程异步 I/O** — `existsSync` / `deleteSync` / `writeAsBytesSync` 全部替换为异步版本；CBZ 打包和封面的写入不再阻塞 UI 线程

---

## ✨ v1.0.5 更新内容

### 🚀 性能优化
- **阅读器图片预加载并发控制** — 信号量限制最多 3 个并发加载，防止 OOM 崩溃
- **下载 I/O 异步化** — `writeAsBytesSync` 改为异步 `writeAsBytes`，不再阻塞 UI 线程
- **下载进度通知节流** — `notifyListeners()` 限制最多每 500ms 一次，减少不必要重建
- **搜索建议性能优化** — 前缀索引 `_searchIndex` 替代全量线性扫描，大标签字典下显著提升
- **图片加载并发控制** — `CachedImageProvider` 使用信号量替代轮询，更高效
- **应用初始化优先级拆分** — 关键路径（UI 渲染）与延迟路径（标签、OpenCC）分离，首帧更快
- **历史记录缓存 LRU** — FIFO 改为 LRU，缓存上限 10 → 20，减少缓存未命中
- **`forceRebuild()` 优化** — 简化为 `setState(() {})`，利用 Flutter diffing 机制

### 🎨 UI & 体验改进
- **标签颜色对比度修复** — 标题标签使用 `useTextColor()` 保证深色模式对比度；标签值改用 `primaryContainer` 更醒目
- **章节列表颜色优化** — 当前阅读章节高亮 `primaryContainer` + 加粗；已读章节文字色改用 `onSurfaceVariant`；普通/分组章节视觉区分更清晰
- **主页下拉刷新** — 主页添加 `RefreshIndicator`，刷新时 Banner 重新加载
- **主页定时器修复** — 移除 `Timer.periodic` 回调内多余的 `_startTimer()` 调用，防止定时器泄漏

### 🐛 Bug 修复
- **主页定时器未正确取消** — `_startTimer()` 现在创建新定时器前先取消旧的
- **`forceRebuild()` 性能问题** — 移除遍历全部 Element 树的逻辑，改为 `setState`

---

## 🔧 构建

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

## 📄 开源许可

[GPL-3.0](LICENSE)
