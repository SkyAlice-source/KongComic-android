# 项目快照

## 当前版本
- v1.2.18+138（2026-07-14）
- Android 端，Flutter 3.44.0

## 最近改动

### v1.2.18 — 状态栏重叠修复 + 翻译完善
- `navigation_bar.dart`：上滑隐藏顶部栏后 `removeTop` 不再移除 padding，修复内容与状态栏重叠
- `translation.json`：补齐所有缺失的 .tl 多语言翻译（30条），zh_CN/zh_TW 完全一致
- 退出确认文字简化："Exit KongComic?" → "Exit?"
- 主题颜色名称优化：朱红/玫红/罗兰紫/翠绿/暖橙/蔚蓝

### v1.2.17 — 阅读器重试修复
- `comic_image.dart`：错误区域 `Listener(onPointerDown:)` → `GestureDetector(onTap:)`，解决点击错误区域触发翻页/菜单的问题
- `gesture.dart`：删除 `ignoreNextTag` 死代码

### v1.2.16 — 退出确认 + 阅读器重试 + 版本号修复
- 根页面退出确认对话框（仅 Android）
- `comic_image.dart`：错误区域可整块点击重试（force resolve），但当时用 `Listener` 方案有问题
- 设置页版本号同步

### v1.2.15 — 回退至 v1.2.13 并叠加分享修复
### v1.2.14 — 分享图片修复 + UX/性能优化
