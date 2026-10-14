# KongComic 功能正确性与性能专项审计（10月15日）

在 10月14日完成多分辨率布局审计后，本轮从「功能正确性」与「性能」两个维度对 App 做端到端审计：
在真机（模拟器 `emulator-5554`，1344×2992 @480dpi，Flutter 3.44.0 debug）上用**真数据**
走完漫画浏览、搜索、下载、翻页全流程，结合 `logcat` 与 `uiautomator` 语义树取证。

> 配套布局审计见 `AUDIT-multi-resolution-2026-10-14.md`。本轮发现并修复 3 个功能性缺陷，
> 其中 1 个为严重回归（下载永不自动开始），1 个为搜索输入即崩溃。

## 一、审计方法

1. **真机端到端**：冷启动 → 浏览漫画源 → 进入详情 → 翻页 → 搜索 → 下载 → 回看下载列表。
2. **网络取证**：`adb logcat` 抓 dio 的 `POST/GET http://...` 与 `Response ... <code>`，直接看请求头（含 `Content-Type`/`User-Agent`/`Referer`）与响应码。
3. **崩溃取证**：`logcat` 抓 Flutter framework 断言（`RenderViewport`/`RenderSliver`/`_elements.contains(element)`/`Failed assertion`）。
4. **语义树取证**：`uiautomator dump` 解析搜索结果页的标题节点，确认搜索真的返回了漫画条目（而非空结果/错误态）。
5. **隔离验证**：为单独验证 4399 搜索，临时把 `appdata.settings` 的 `disabledSources` 设为 `["manga51"]`（验证后已还原），避免被 51manga 的 `idMatcher` 把关键词当漫画 ID 直接打开。

## 二、功能正确性发现

### 2.1 下载任务永不自动开始（严重回归，已修复 ✅）

**现象**：在下载页加入新章节后，任务卡在「已暂停」，必须手动点「开始」才会下载；「下载中」列表里新任务不会自动跑。

**根因**：提交 `0fadd83`（多漫画源仓库管理 + 更新/下载链路硬化）把 `LocalManager._resumeHead()` 从
`downloadingTasks.firstOrNull?.resume()` 改为 `if (head != null && !head.isPaused) head.resume();`。
而 `DownloadTask.isPaused => !_isRunning`（来自 `4d963db` v1.2.13 的重命名），**新加入队列的任务 `_isRunning=false`
⇒ `isPaused=true` ⇒ 永远不满足 `!head.isPaused` ⇒ 永远不会被 `_resumeHead` 自动 `resume`**。
队列自动续跑逻辑就这样被「新任务也被视为已暂停」这个语义吞掉了。

**修复**：引入与 `isPaused` 分离的显式标记 `pausedByUser`（仅用户主动 `pause()` 时置 `true`），
`_resumeHead()` 改为 `if (head != null && !head.pausedByUser && !head.isError) head.resume();`。
保留原意：失败任务（`isError`）不自动重试、用户手动暂停的任务不被偷偷恢复，但**新加入的队列任务会正常自动开始**。

- `lib/network/download.dart`：`DownloadTask.pausedByUser` 字段；`ImagesDownloadTask`/`ArchiveDownloadTask` 的 `pause()` 置 `true`、`resume()` 置 `false`。
- `lib/foundation/local.dart`：`_resumeHead()` 判定逻辑（影响 `completeTask`/`addTask`/`restoreDownloadingTasks` 三处调用点）。

**验证**：前轮已在真机端到端验证——加入第02话后**不点开始**，3 秒内 `downloading_tasks.json` 出现 `chapter:1`、
目录 `2/` 落盘 11/11 张 jpg 并生成 `…第02话.cbz`，任务自动完成。本轮该修复随新构建一并回归安装，行为保持一致。

### 2.2 4399 搜索返回空结果且误报「需登录」（功能性 bug，已修复 ✅）

**现象**：搜索 4399 漫画网关键词时，结果页为空；`loading.dart` 的 `isAuthError()` 把空/异常响应美化成「需登录」，
用户看到的是误导性错误而非「无结果」。

**根因**：`mh4399.js` 的 `search.load` 用 `Network.post("/search2.html", …)` 提交表单，但请求头**缺
`Content-Type: application/x-www-form-urlencoded`**。4399 服务端不解析无该头的表单体，返回空结果页
（标题 `《》查询`，无 `block-img-item` 卡片）。`js_engine.dart._http()` 不替 JS 补 `Content-Type`，
故必须源侧自己带。同类源（`bilimanga.js`/`baihehui.js`/`baozi.js`/`_template_.js`）均显式带此头，属惯例。

**修复**：扩展 `headers(ua, referer, contentType)` 助手，搜索 POST 调用改为
`this.headers(Mh4399.mobileUA, Mh4399.baseUrl + "/", Mh4399.formContentType)`，版本 `1.0.4 → 1.0.5`。

**验证（真机端到端，10月15日）**：
- `logcat`：`POST http://www.4399manhua.com/search2.html`，请求头含
  `Content-Type: application/x-www-form-urlencoded`，随后 `Response .../search2.html 200`。
- 结果页语义树出现 **12 条真实漫画标题**（Girls Scat Orchestra、GIRLS'F、舰girls、Equestria Girls 等）。
- 结果封面图后续 `GET` 均带移动 UA + Referer，正常回源。
- 对照：不发 `Content-Type` 时（curl 复现）返回空结果页，与修复前现象一致。

### 2.3 搜索框一输入就崩溃（RenderViewport/RenderSliver 断言，已修复 ✅）

**现象**：在搜索框输入任意字符，App 在 debug 下反复刷 Flutter 断言，搜索建议列表渲染失败；
汇总日志中曾出现的 `_elements.contains(element)`（framework.dart:2168）即此崩溃的错误恢复级联。

**根因**：`search_page.dart` 的 `buildSuggestions()` 把一个 **`SliverMainAxisGroup`（本身是 sliver）**
直接包进 **`RepaintBoundary`（生成 `RenderRepaintBoundary`，是 RenderBox）**，再作为
`SmoothCustomScrollView` 的 sliver 子节点 yield 出去。Viewport 要求 sliver 子节点，
收到 RenderBox 即触发 `A RenderViewport expected a child of type RenderSliver but received a child of type RenderRepaintBoundary`。
由于出错子树里的 Viewport 用了 `GlobalKey`，Flutter 错误恢复时 `GlobalKey.unregister` 又抛出
`_elements.contains(element)`，所以日志里两种断言先后出现，根因是同一个。

**修复**：移除 `buildSuggestions()` 外层的 `RepaintBoundary`，直接 `return SliverMainAxisGroup(...)`。
（全仓仅此一处 `RepaintBoundary` 包裹 sliver；`search_page.dart:366` 那个是包 `Column` 的 box 上下文，正常。）

**验证（真机端到端，10月15日）**：
- 输入 "girls" 后建议列表正常渲染（`打开漫画`/`标签`等建议节点出现），**无** `RenderViewport`/`RenderSliver`/`Failed assertion`/`_elements.contains` 断言。
- 提交搜索进入结果页，**全程 logcat 无上述断言**，结果页正常显示 4399 漫画条目。

### 2.4 51manga 源在当前网络不可达（环境问题，非 App bug）

**现象**：搜索/浏览 51manga 时请求 `https://m.51manga.com/...` 以 `Connection closed before full header`
（底层 `SocketTimeoutException`）失败，App 显示错误态。

**结论**：纯网络环境问题（与历史 51manga `HttpException` 同因），非功能性缺陷。App 对失败源**优雅降级**：
进入 `loading.dart` 的错误态（导出日志 / 重试 / 错误提示），**不崩溃、不阻断其它源**——
隔离验证时仅启用 4399，搜索正常返回结果即佐证。

> **观察项（非阻塞）**：51manga 的 `idMatcher` 较宽，会把 "girls" 这类普通词当作漫画 ID 直接打开对应漫画页
> （设计内的「输 ID 直开」特性）。若用户想搜普通词却总跳到 51manga 漫画页，可视为源配置层面的体验问题，
> 但不影响核心搜索功能（4399 等无 `idMatcher` 的源搜索正常）。

### 2.5 阅读器 / 翻页 / 内存（前轮已确认无问题）

前轮验证：冷加载页图 200 张，PSS 内存 479MB → 469MB 稳定不增长；音量键翻页正常；
移动 UA 修复后封面与页图均从 oub CDN 正常 200（见 2.2 同源的 `onThumbnailLoad`/`onImageLoad` 移动 UA 修复，前轮已完成）。

## 三、性能

| 维度 | 结论 | 说明 |
|---|---|---|
| 图片加载管线 | ✅ 正常 | 4399 封面/页图均走移动 UA + Referer，oub CDN 返回 200；搜索结果封面后续 GET 均 200。无 403 退化。 |
| 内存 | ✅ 稳定 | 前轮 PSS 469MB 稳定（200 页图冷加载场景），无泄漏迹象。 |
| 翻页 / 掉帧 | ✅ 正常 | 音量键翻页、连续翻页无卡顿/掉帧报告。 |
| 下载 I/O 阻塞 UI | ✅ 已缓解 | 下载设置页的同步 I/O 阻塞问题（前轮已修）本轮未复现；下载任务在 isolate 内执行，UI 不冻。 |
| 搜索流畅度 | ⚠️ 已修复崩溃 | 修复前每键入即抛断言、建议列表无法渲染（实质是「输入即卡死」）；修复后输入/提交均流畅，无断言。 |

> 性能层面无新增瓶颈。唯一影响体感的是 2.3 的搜索崩溃（每次输入都触发断言重建子树），已修复。

## 四、遗留 / 观察项

1. **51manga 网络不可达**：仅当前测试网络；换可达网络后该源应正常，无需改代码。若需离线兜底，可考虑在源失败超过 N 次后自动置灰该源。
2. **51manga `idMatcher` 过宽**：普通词被当作漫画 ID 直开（2.4 观察项），属源配置层面，不在 App 核心逻辑。
3. **搜索分页**：4399 搜索源 `maxPage` 当前硬编码为 1（源注释已标注「搜索页未见分页控件，单页，待验证」），若 4399 实际有多页结果，需后续补充翻页。

## 五、结论

- 本轮发现 **3 个功能性缺陷，全部已修复并真机验证**：下载自动开始回归（严重）、4399 搜索空结果、搜索输入崩溃。
- 51manga 不可达为环境，App 优雅降级，无代码缺陷。
- 性能无新增瓶颈；图片管线/内存/翻页均正常。
- App 在真机上「能看漫画、能搜索、能下载、能翻页」的核心链路已确认通畅。

## 六、改动清单（待提交）

**仓库 `KongComic-android`（未提交，工作区改动）**
- `lib/network/download.dart` — 新增 `DownloadTask.pausedByUser`；`pause()/resume()` 同步该标记。
- `lib/foundation/local.dart` — `_resumeHead()` 改用 `!pausedByUser && !isError` 判定自动续跑。
- `lib/pages/search_page.dart` — `buildSuggestions()` 移除包裹 `SliverMainAxisGroup` 的 `RepaintBoundary`（修复 RenderViewport 断言）。

**仓库 `venera-configs`（未提交，工作区改动）**
- `mh4399.js` — `headers()` 助手支持 `contentType`；搜索 POST 带 `Content-Type: application/x-www-form-urlencoded`；`onThumbnailLoad` 用移动 UA（前轮，修复封面 403）；版本 `1.0.4 → 1.0.5`。
