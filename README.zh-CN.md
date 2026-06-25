# KongComic

> 基于 [Venera](https://github.com/venera-app/venera) 由 AI 深度二次开发

---

## 与 Venera 的区别

### 🎨 UI 全面翻新
- 主页布局重做：Banner 层叠轮播 → 漫画信息区（名称/作者/进度/更新/立即阅读）→ 四个扁平方框
- 底部导航 5 项（分类/收藏/主页/发现/历史），选中态圆形
- 全量图标替换为 HugeIcons
- 设置页分类重排：阅读器 → 外观 → 浏览 → 收藏 → 网络 → 下载 → 导入 → 通用 → 关于

### 🐛 Bug 修复
- 搜索页键盘弹出卡顿优化
- 阅读器误触发菜单修复
- 聚合搜索页漫画名越界修复
- 底部导航白条修复
- 导入导出支持自定义封面备份恢复
- 语言切换即时生效

### ⚡ 性能优化
- 移除全部 BackdropFilter 高斯模糊
- 移除 1300+ 行死代码及多余依赖

---

## 🔧 构建

```bash
flutter pub get
flutter build apk --debug
```

---

## 📄 开源许可

[GPL-3.0](LICENSE)
