[**English**](README.md) | [**中文**](README.zh-CN.md)

# KongComic

> 基于 [Venera](https://github.com/venera-app/venera) 由 AI 深度二次开发

[![flutter](https://img.shields.io/badge/flutter-3.44.0-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/SkyAlice-source/KongComic-android)](LICENSE)

---

## 与 Venera 的区别

### 🎨 UI 全面翻新
- 主页布局重做：Banner 层叠轮播 → 漫画信息区（名称/作者/进度/更新/立即阅读）→ 四个扁平方框
- 底部导航 5 项（分类/收藏/主页/发现/历史），选中态圆形
- 全量图标替换为 HugeIcons（除电池图标）
- 设置页分类重排：阅读器 → 外观 → 浏览 → 收藏 → 网络 → 下载 → 导入 → 通用 → 关于

### 🐛 Bug 修复
- 搜索页键盘弹出卡顿优化（移除不必要的 setState + ListenableBuilder 隔离）
- 阅读器误触发菜单修复（触控区改为 30%/40%/30%）
- 聚合搜索页漫画名越界修复（固定宽度 + ClipRect）
- 搜索页搜索结果文字越界修复
- 底部导航白条修复（capsule 全宽 + 不透明 + 无 margin）
- 导入导出支持自定义封面备份恢复
- 语言切换即时生效（forceRebuild + visitChildren）

### ⚡ 性能优化
- BackdropFilter 高斯模糊全部移除
- 主页 `SmoothCustomScrollView` 替代 `NestedScrollView`
- 移除 1300+ 行死代码
- 移除多余依赖

---

## 🔧 构建

```bash
flutter pub get
flutter build apk --debug
```

输出：`build/app/outputs/flutter-apk/app-debug.apk`

---

## 📄 开源许可

[GPL-3.0](LICENSE)
