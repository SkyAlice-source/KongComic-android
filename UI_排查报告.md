# KongComic-android UI 问题排查报告

排查范围：`lib/main.dart`、`lib/pages/main_page.dart`、`lib/pages/comic_details_page/*`、`lib/pages/reader/*`、`lib/components/comic.dart`、`lib/components/*`（含 `loading.dart`、`image.dart`）。
说明：本次为**只读排查**，未修改任何项目文件。严重程度：P0=崩溃 / P1=功能异常 / P2=体验问题 / P3=建议优化。

> 结论速览：项目整体质量较高。图片/图标组件健壮（统一 `HugeIcon` + 自定义 `AnimatedImage`/`ComicImage` 均内置错误与重试）；核心页面 `Text` 几乎全部正确走 `.tl`；overflow 与嵌套滚动处理得当。**唯一成体系的问题是"引用了 `translation.json` 中不存在的 key"，导致非英文用户看到英文原文**；另有少量强制解包风险。

---

## A. 文字 / 翻译问题

### A1（P2）`history_page.dart:180` — 引用了不存在的翻译 key
```dart
"Selected @count".tlParams({"count": selectedComics.length}),
```
key `"Selected @count"` 在 `assets/translation.json` 中**不存在**（zh_CN/zh_TW 均为 `null`）。正确应为 `"Selected @a comics"`（zh_CN：`已选择 @a 部漫画`，占位符是 `@a`）。
**后果**：所有语言下都显示英文原文 `Selected 3`，中文用户也看不到翻译。
**修复**：改为 `"Selected @a comics".tlParams({"a": selectedComics.length})`。

### A2（P2）`reader/scaffold.dart:1520` — `"Select at least one page"`
不在翻译文件中。非英文用户看到英文原文。
**修复**：在 `translation.json` 的 `zh_CN`/`zh_TW` 添加对应翻译（建议 key 与文案 `"Select at least one page"` → 中文"请至少选择一页"）。

### A3（P2）`reader/scaffold.dart:1550` — `"Failed to load images"`
不在翻译文件中。同上。
**修复**：补充翻译 key。

### A4（P2）`settings/about.dart:70` — `"Download via GitHub source"`
### A5（P2）`settings/about.dart:192` — `"Choose download source:"`
### A6（P2）`settings/about.dart:210` — `"Download via CDN"`
### A7（P2）`settings/about.dart:215` — `"View on GitHub"`
这四个字符串均不在 `translation.json`（zh_CN/zh_TW 均为 `null`）。虽然 `about.dart` 不在本次严格优先级目录，但属同一类真实问题：非英文用户看到英文原文。
**修复**：在翻译文件中补充中文等翻译。

### A8（P2）`components/loading.dart:10,15,19,24,27,33` — 中文错误消息被 `.tl` 包裹
```dart
return '连接被重置，请检查网络或代理后重试'.tl;   // 第10行
...
return '服务器返回 ${status.group(1)}，请稍后重试'.tl;  // 第33行（插值字符串）
```
`translation.json` 仅含 `zh_CN`/`zh_TW`，**英文 locale 下 `.tl` 回退显示原始中文串**——英文用户会看到中文错误信息。此外第 33 行是**插值字符串**，`${...}` 使其 key 永远无法匹配任何静态翻译项，`.tl` 实际无效且无法翻译。
**修复**：将这些错误改为静态英文 key（如 `"Connection reset, check network or proxy"`）加入翻译文件；第 33 行需先拼好错误文案再整体翻译（插值串无法按 key 翻译，建议改为英文模板 key + 占位符）。

### 正面结论（A 类）
用脚本扫描 `main.dart`/`main_page.dart`/`comic_details_page/`/`reader/`/`components/` 下所有 `Text("英文")` 字面量：**除 A1–A8 外，其余均已正确使用 `.tl`/`.tlParams`/`.ts()`**，未发现裸硬编码英文 UI 文本。

---

## B. 图标 / 图片问题
未发现明显问题：
- 项目统一使用 `HugeIcon(icon: HugeIcons.xxx)`（图标名编译期校验，引用不存在的 `IconData` 会直接编译失败）。未使用裸 `Icon(Icons.x)` 误用。
- `AnimatedImage`（`components/image.dart:174`）、`ComicImage`（`reader/comic_image.dart:192`）均注册 `onError` 回调：失败时前者显示告警图标，后者显示错误文案 + `Retry` 重试按钮。
- 阅读页单图页 `PhotoViewGalleryPageOptions`（`reader/images.dart:373`）已配置 `errorBuilder`。
- 未发现 `Image.network`/`Image.asset`/`Image.file` 裸用（grep 无匹配）。
**结论**：图片/图标健壮性良好，无需修复。

---

## C. 布局问题
未发现问题级 overflow：
- 详情页与阅读页大量使用 `Expanded`/`Flexible`，并对章节标题、标签、描述等统一加 `maxLines + TextOverflow.ellipsis`（如 `chapters.dart:136`、`comic.dart:653`、`comic_page.dart:579`）。
- `comic_page.dart:436` 横向 `ListView` 已用 `.fixHeight(48)` 限定高度，内部 `Row(mainAxisSize: MainAxisSize.min)`，不溢出。
- `favorite.dart:136` 的 `ListView` 是 `Scaffold` body 根滚动视图，无需 `shrinkWrap`。
- 阅读页用 `SystemUiMode.immersive`；主界面用 `edgeToEdge` + `context.padding.bottom` 处理底部安全区；`SafeArea` 仅局部使用（chapter_comments/scaffold 等），属透明状态栏设计，非 bug。

轻微建议（P3）：
- `comic_page.dart:1169` 加载占位 `_ComicPageLoadingPlaceHolder` 中 `Text(title ?? "")` 未设 `maxLines`，极端长标题有极小溢出风险（仅占位态，影响低）。

---

## D. 常见 Bug 模式

### D1（P2）`comic_details_page/comic_page.dart:8` — 强制解包 `!`
```dart
ComicSource get comicSource => ComicSource.find(comic.sourceKey)!;
```
正常情况 `sourceKey` 有效，但若漫画数据异常（对应漫画源被移除）会直接抛异常崩溃。
**修复**：改为可空处理，缺失时回退到默认源或显示错误态，而非 `!`。

### D2（P3）`comic_details_page/comic_page.dart:771` — 冗余的 `!` 强制解包
```dart
var t = int.tryParse(time);
if (t! > 1000000000000) {   // 重新解析的局部变量，语义冗余
```
虽前面有 `if (int.tryParse(time) != null)` 保护，但 `t` 是重新 `tryParse` 得到的局部变量，此处 `!` 不严谨（不会导致崩溃，但不规范）。
**修复**：复用已校验结果或改用 `t?`。

### D3（P3）`comic_details_page/cover_viewer.dart:133` — 文件名未 sanitize
```dart
await saveFile(filename: "cover_${widget.title}${fileType.ext}", data: data);
```
`widget.title` 可能包含 `/`、`\`、`:` 等非法文件名字符，导致保存失败。
**修复**：保存前对 `title` 做 sanitize（替换非法字符为 `_`）。

### D4（P3）`components/comic.dart:1286` — 分页 key 计算可能错位
```dart
_data[_data.length + 1] = res.data;   // _fetchNext 中
```
用 `_data.length + 1` 作为页号 key，连续加载下一页时若中间某页返回空，会导致页号错位（属于分页逻辑，超出本次纯 UI 范畴，仅提示）。

### 未发现的问题（已核实）
- **`notifyListeners()` 在 `dispose` 后调用**：`SliverGridComics`、`LocalManager`、`HistoryManager` 等均在 `dispose` 中 `removeListener`，且回调内多判断 `mounted`，未发现明显 dispose 后通知风险。
- **未捕获的 Future 错误**：已检查的 `.then` 多用 `try/catch` 或 `.catchError` 包裹（如 `comic_page._extractCoverTheme:138`、favorite `loadFolders`、actions `archiveDownloader` 等），关键处判断 `mounted`。
- **`await` 缺失**：主流程 async 函数（`loadData`、`read`、`download`、`_fetchNext` 等）均正确 `await`。

---

## 优先级修复建议（按影响排序）
1. A1–A7：补齐 `translation.json` 缺失 key（尤其 A1 把 `@count` 改回 `@a`，与现有"已选择 @a 部漫画"对齐）。影响所有非英文用户，工作量小、收益大。
2. A8：重构 `loading.dart` 的错误文案为静态英文 key + 占位符，解决英文用户看到中文错误的问题。
3. D1：消除 `ComicSource.find(...)!` 强制解包，避免异常数据下崩溃。
4. D2–D4：规范 `!` 解包、文件名 sanitize、分页 key 计算（低优先级）。
