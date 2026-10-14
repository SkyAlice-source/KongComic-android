# 图片收藏重构方案：本地离线图库

目标（用户原话）：图片收藏做成本地浏览风格，收藏直接下载到软件本地设置的文件夹里，离线也能秒开，菜单加个跳转漫画页，也能直接到漫画里。

代码现状摸底时间：2026-10-14，基线 `v1.3.12`（`17d2c3f`）。

---

## 1. 现在到底是什么样（代码事实）

### 数据层
- `lib/foundation/image_favorites.dart`
  - `ImageFavorite`：`eid / id / ep / epName / sourceKey / imageKey / page / isAutoFavorite`
  - `ImageFavoritesEp`：`eid / ep / maxPage / epName / imageFavorites[]`
  - `ImageFavoritesComic`：`id / title / subTitle / author / sourceKey / maxPage / tags / translatedTags / time / imageFavoritesEp[] / other`
  - 存储：SQLite 表 `image_favorites`，主键 `(id, source_key)`，章节图片以 JSON 塞在 `image_favorites_ep` 列；
    复用 `HistoryManager()._db`（不是独立库）。
  - `ImageFavoriteManager` 单例 + `ChangeNotifier`，页面靠 listener 刷新。

### 图片加载（`lib/foundation/image_provider/image_favorites_provider.dart`）
`load()` 的查找顺序已经是四级：
1. `App.dataPath/image_favorites_local/{id}_{sourceKey}_{eid}_{page}` —— 持久离线副本
2. 本地已下载漫画（`LocalManager.getImages`）—— 如果这本整本下载过
3. `App.cachePath/image_favorites/{md5}` —— 普通缓存
4. 网络（`getImageFromNetwork` → `ImageDownloader.loadComicImage`）

即：**"离线秒开"的机制已经存在**，缺的是"自动落盘"和"像本地图库一样浏览"。

### 落盘动作目前是手动的
- `ImageFavoritesProvider.cacheImage(f)`：下载单张 → 写 `localImageFile(f)`，并镜像进 `CacheManager`。
- 只有两个入口调用它：
  - `image_favorites_item.dart:135` —— 卡片菜单「Cache All Images」
  - `image_favorites_photo_view.dart:274 / 295` —— 大图页菜单「Cache Image」/「Cache All」
- 没有"收藏时自动下载"，没有后台队列，没有重试，没有失败状态展示。

### UI（`lib/pages/image_favorites_page/`）
- `image_favorites_page.dart`（573 行，含排序/时间筛选/数量筛选/搜索/多选）
- `image_favorites_item.dart`（392 行）—— 卡片：每本漫画一张卡，横向缩略图条
  - 卡片单击 → 漫画详情（`goComicInfo`）
  - 缩略图单击 → 阅读器对应页（`goReaderPage`）
  - 缩略图长按 → 大图浏览
  - 卡片菜单：Copy Title / Select All / Photo View / Cache All Images
- `image_favorites_photo_view.dart`（308 行）—— 大图页：菜单有 Read（进阅读器当前页）、Cache Image、Cache All
- 结论：**跳转漫画详情和进阅读器其实都已有入口**，缺的是菜单里没有明确列出「打开漫画详情」，且入口位置不直观。

### 存储位置
- `App.dataPath = getApplicationSupportDirectory()`（`lib/foundation/app.dart:115`）—— **写死，不可配置**。
- `lib/pages/settings/download.dart` 只有：CBZ 打包开关、打包后删文件夹、下载线程数。**没有目录选择**。
- 离线文件命名：`{id}_{sourceKey}_{eid}_{page}`，**无扩展名**，无法被文件管理器/其他 App 识别。

### SAF 能力：已经接上了（更正上一版的说法）
`packages/flutter_saf` **不是零引用**，它已经深度接入，只是没用在图片收藏上：

- `lib/utils/io.dart:7` 直接 `import 'package:flutter_saf/flutter_saf.dart'`
- `lib/main.dart:73` 用 `overrideIO(() { runZonedGuarded(...) })` 把**整个 App 包进 IOOverrides zone**，
  于是全 App 任何 `Directory(path)` / `File(path)` 都会先过 `_IOOverrides`：
  路径以 `android://` 开头 → 返回 `AndroidDirectory` / `AndroidFile`（背后是原生 `DocumentsContract`），
  否则回退 dart:io。**所以业务代码不用关心 SAF，拼接路径照写即可。**
- 隔离的 isolate 不继承 zone，因此 `Isolate.run` 里都显式再包一层 `overrideIO(...)`
  （`local.dart:277/431`、`io.dart:185`、`import_comic.dart:362` 等 7 处）。
- 权限持久化已做：`FlutterSafPlugin.kt:277` 调了 `takePersistableUriPermission(READ|WRITE)`，
  `init()`（:237）从 `contentResolver.persistedUriPermissions` 重建 `_roots` → **杀进程/重启后仍可访问**。

这对方案 A 是重大利好：**P0 从"打通 SAF"降级为"验证 + 抽一层接口"**，风险大幅下降。
唯一新写的是 `SafStorage` 之外的真正缺口：图片收藏目录不参与 `LocalManager.path`，见第 7 节。

- Manifest 已声明 `MANAGE_EXTERNAL_STORAGE` / `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE`。
  注意：Android 11+ 上 `MANAGE_EXTERNAL_STORAGE` 需要商店侧特殊声明，普通分发应走 SAF；
  该权限本身就是 ISSUES 清单里 P2-1 标记待处理的项（审查结论见 7.4）。

---

## 2. 业界做法（参考 Mihon / Tachiyomi 系）

查证要点（`mihon.app/docs/faq/storage`）：
- **存储位置由用户用 SAF 选一个顶层文件夹**，App 在它下面自建结构：
  `[存储位置]/downloads/<源>/<作品>/<章节>.cbz`、`[存储位置]/local/`、`[存储位置]/autobackup/`
- **明确警告不要选系统目录**（`Documents` / `Downloads`），Android 会限制、权限会被系统收回，导致"下载位置无效"。
- **重新索引（Reindex）**：用户在外部挪动/删除文件后，App 提供"重新索引下载"按钮，扫描目录重建索引。
  这是作用域存储下的必备功能，不是可选项。
- 作用域存储下 SAF 有固有延迟，删除/列目录会变慢；内部存储优于 SD 卡。
- 单文件用 fd 读写（我们 `flutter_saf` 的思路与之一致）。

可借鉴到本项目的三条：
1. 目录结构按「源 → 作品 → 章节 → 页」，用户一眼能认、能备份、能手动清理。
2. 必须提供「重新索引」入口。
3. 别把数据放在系统受限目录；首次进入引导用户选一个自建文件夹。

---

## 3. 三个方案

### 方案 A（推荐）：完整重构 —— 可配置目录 + 收藏即落盘 + 本地浏览
- 存储位置可在设置里选（默认 App 私有目录，可选 SAF 目录）
- 收藏时入后台队列自动下载，支持仅 Wi-Fi / 重试 / 失败可见
- 目录结构 `KongComic/image_favorites/<sourceKey>/<comicId>/<epName>/<page>.<ext>` + `meta.json`
- 索引表记录路径与状态，提供「重新索引」
- UI 双视图：现有「漫画卡片」视图 + 新增「文件夹/网格」本地浏览视图
- 菜单补齐：打开漫画详情、进阅读器对应页、导出/删除本地副本
- 一次性迁移旧 `image_favorites_local` 散文件

### 方案 B：只做"自动落盘 + 本地浏览 UI"，目录仍写死私有目录
- 不改存储位置，改命名与目录层级（`image_favorites/<sourceKey>/<cid>/<eid>/<page>.jpg`）
- 收藏即下载、索引、重新索引、UI 双视图、菜单补齐都做
- 优点：避开 SAF 全部坑，dart:io 直写，速度快、实现短
- 缺点：卸载即丢、文件管理器看不到、换机只能靠备份

### 方案 C：最小改动
- 菜单加「打开漫画详情」「进阅读器」两项
- 缩略图上加离线状态角标（已缓存/未缓存）
- 保留手动 Cache All
- 半天工作量，解决"入口不明显"，不解决"自动离线"

---

## 4. 方案 A 的分阶段实施

### P0：验证 SAF 存储 + 抽象存储层（先做，做不通就退到方案 B）
> 风险已下调：`flutter_saf` 已在用（见第 1 节更正），`takePersistableUriPermission` 与重启恢复都已实现，
> 本阶段主要是**真机验证**与**抽接口**，不再是"从零打通"。

0. **真机验证**（半天）：临时入口跑一遍 —— `ACTION_OPEN_DOCUMENT_TREE` 选目录 →
   建子目录 → 写文件 → 列目录 → 读回 → 删除 → 杀进程重进仍可访问 → 重启手机后仍可访问
1. 抽象一层 `FavoriteStorage`（接口：`rootUri / subDir(path) / write(name, bytes) / list(path) / delete(path)`）
   - 两种实现：`PrivateDirStorage`（dart:io，默认）、`SafStorage`（flutter_saf）
   - 上层只依赖接口，SAF 不通也不影响主体
2. 抽象一层 `FavoriteStorage`（接口：`rootUri / subDir(path) / write(name, bytes) / list(path) / delete(path)`）
   - 两种实现：`PrivateDirStorage`（dart:io，默认）、`SafStorage`（flutter_saf）
   - 上层只依赖接口，SAF 不通也不影响主体
3. 设置页新增「图片收藏位置」：默认私有目录 / 选择文件夹（SAF）；显示已用空间与文件数；换目录时提示迁移

### P1：自动落盘 + 索引
4. 新表 `image_favorites_local`（或给现有表加列）：
   `(id, source_key, eid, page)` → `rel_path | size | status(pending/ok/failed) | updated_at`
   用相对路径存储，目录换了不用改表
5. 后台下载队列：复用现有下载线程配置（`downloadThreads`），新增开关
   - `收藏时自动下载`（默认开）、`仅在 Wi-Fi 下自动下载`（默认开）、`失败自动重试 N 次`
   - 队列持久化，App 重启可续；前台通知进度（现有下载页 `downloading_page.dart` 可挂）
6. `ImageFavoritesProvider.load()` 改为：查索引 → 命中直接读本地 → 未命中走原来的 4 级链路（保持兼容）
7. `meta.json`：写漫画元数据 + 章节名 + 收藏时间 + 源 key，供外部查看与重新索引
8. **重新索引**：扫描目录下所有文件，与索引表比对，补缺失/清孤儿；设置页放入口
9. **迁移**：首次升级把 `dataPath/image_favorites_local/*` 搬进新目录（按新命名），失败则保留旧路径继续可读

### P2：UI 本地浏览风格
10. 图片收藏页加视图切换（漫画卡片 / 文件夹网格）
    - 文件夹视图：复刻 `local_comics_page.dart` 的 `PaginatedSliverGridComics` 风格，
      层级为 源 → 作品 → 章节 → 图片，带面包屑返回
    - 缩略图走本地文件（`Image.file` / `FileImage`），无网络请求，滑动不卡
11. 卡片与大图页菜单补齐（三语）：
    - `Open Comic Details`（打开漫画详情）
    - `Read This Page`（进阅读器对应页，大图页已有 Read，卡片缩略图长按菜单补上）
    - `Download Offline Copy` / `Remove Offline Copy`
    - `Show in Folder`（仅 SAF 目录，用 `ACTION_VIEW` 唤起系统文件管理器）
12. 状态可视化：缩略图角标（已离线 / 下载中 / 失败可重试），卡片显示"N/M 已离线"
13. 存储统计 + 清理：设置页显示占用，支持"清理失败/孤儿文件"

---

## 5. 风险与开放问题

| 项 | 说明 |
|---|---|
| SAF 延迟 | 作用域存储下列目录/删除明显慢于 dart:io，作品多时首屏要分页 + 缓存目录树 |
| 权限被收回 | 系统目录（Downloads/Documents）会被限制；需在 UI 里提示用户选自建顶级文件夹，权限失效时引导重选 |
| `MANAGE_EXTERNAL_STORAGE` | 已在 Manifest 但普通分发不应依赖；若 Google Play 上架需移除。当前是 P2-1 待处理项 |
| 命名冲突 | `comicId` 可能含非法字符/超长；需要 sanitize + 超长时 hash 兜底；章节名同理 |
| 源失效 | 图源挂了以后，已落盘的文件仍可读（这正是本方案价值），但重新索引时无法补全缺失页 → 状态标为"源不可用" |
| 空间 | 自动下载会静默吃空间；需要默认仅 Wi-Fi + 设置页显示占用 + 可选上限 |
| 旧数据 | `image_favorites_local` 无扩展名散文件必须迁移或长期兼容读 |

---

## 6. 已拍板的决策（2026-10-14）

| # | 决策项 | 结论 |
|---|---|---|
| 1 | 方案 | **方案 A（完整重构）** |
| 2 | 存储位置 | **默认 App 私有目录 + 可选 SAF 目录**。设置项「图片收藏位置」，默认私有；用户可主动切成 SAF 自建文件夹，切换时提示是否迁移已有文件 |
| 3 | 自动下载 | **默认开启「收藏即下载」，且默认仅 Wi-Fi**。两个独立开关：`autoDownloadImageFavorites`(默认开)、`autoDownloadImageFavoritesWifiOnly`(默认开)。关掉 Wi-Fi 限制后走流量 |
| 4 | 首次使用 | **首次进入图片收藏页弹一次引导**：说明离线副本会占空间，让用户当场选 私有 / 自定义文件夹(SAF) / 暂不离线。选过即写入 `appdata`，不再重复弹 |
| 5 | UI | **双视图**：保留现有「漫画卡片」视图，新增「文件夹网格」本地浏览视图（源 → 作品 → 章节 → 图片），顶部可切换 |
| 6 | 图片格式 | **加设置项 `imageFavoritesSaveFormat`，默认 `original`（原图直存）**，可选 `webp`（转码省 30-50%）。切换只影响后续新下载的文件，不重编码已有副本 |

由此新增/调整的实施项：

- **P0-0（新增，半天）**：写一个临时验证入口，在真机上跑一遍 SAF 建目录/写文件/列目录/删除 + 杀进程重进仍可访问。
  因为 `flutter_saf` 已在用，**P0 整体从"高风险"降为"中风险"**；这一步不通过才退回方案 B。
- **P0-3**：设置页新增「图片收藏位置」（私有 / 选择文件夹）、显示占用与文件数、换目录时提示迁移。
- **P1-5 补充**：新增 3 个设置项 + 首次引导弹窗，三语文案（en 已内建，zh_CN / zh_TW / ja_JP 各补）。
- **P1-10（新增）**：按 `imageFavoritesSaveFormat` 决定落盘前的编码；`webp` 走 `flutter_image_compress`（需新增依赖，
  纯 Dart 编码大图会卡 UI，必须放 isolate）。
- **Wi-Fi 判定**：需新增依赖 `connectivity_plus`（当前 pubspec 里**没有任何网络类型检测依赖**，全仓库搜不到 wifi/connectivity）。
  判定逻辑放队列出队时：非 Wi-Fi 且开关打开 → 任务挂起等 Wi-Fi，不失败、不重试计数。

---

## 7. 现有存储路径设置审查（2026-10-14，基线 v1.3.12）

审查范围：`LocalManager`（`lib/foundation/local.dart`）、设置页 `lib/pages/settings/app.dart:10-127`、
`lib/utils/io.dart`、`lib/foundation/app.dart`。

### 7.1 🔴 「Move to Current Storage Path」是死按钮（必现）✅ 已修（2026-10-14）
`lib/pages/settings/app.dart:119-124`：
```dart
final target = manager.path;
if (manager.directory.path == target) {   // ← 恒为 true
  context.showMessage(message: "Already in current storage path".tl);
  return;
}
```
`LocalManager.directory` 的定义是 `Directory get directory => Directory(path);`（local.dart:242），
而 `target` 就是 `manager.path` —— 两边永远相等。结果：**这个按钮点了永远只弹「已经在此目录」，什么都不会搬**。

它的本意是把散落在别处的已导入漫画归拢进当前目录 —— `import_comic.dart:343` 确实会写入绝对路径
（`useRelativePath ? directory.name : directory.path`），这些漫画的 `baseDir` 在 `LocalManager().path` 之外，正是要被搬的对象。
正确判据应是「是否存在 baseDir 不在当前 path 下的漫画」，而不是拿根目录比自己。

**修复**（`local.dart` + `pages/settings/app.dart`）：
- 新增 `LocalManager.externalComics`：遍历 db，取 `baseDir` 不在 `path` 之下的漫画
  （`_isUnderStorageRoot()` 用规范化前缀比较，避免 `/data/ComicBackup` 被误判成在 `/data/Comic` 下）。
- 新增 `LocalManager.gatherExternalComics()`：把这些漫画的文件夹复制进 `path`
  （目标名去重）→ 复制成功才删源 → 把 db 的 `directory` 改成相对目录名。
  迁移期间同样置 `_isMigrating` 并暂停/恢复下载任务。
- 设置页：`externalComics` 为空才提示「Already in current storage path」；否则弹确认框
  （显示数量与目标路径）后执行，成功提示「Comics moved into storage path」。
- 注意：不能复用 `setNewPath(target)` —— 它在 `p.equals(directory.path, newDir.path)`
  时直接 return null，即便判据改对了也依然什么都不做。

### 7.2 🟠 路径失效时静默回退，用户数据"凭空消失" ✅ 已修（2026-10-14）
`local.dart:550-560` `_checkPathValidation()`：往 `path` 写一个测试文件，失败就
`path = await findDefaultPath()`，**不通知用户、不留标记**。

触发场景：SAF 权限被系统收回（用户清了 App 数据 / 超过 128 个授权上限 / 外部删掉了该文件夹）、
用户手动删了自建文件夹、SD 卡卸载。此时 App 重启后目录指针跳回默认私有目录，
**已下载的漫画全部从界面消失**（文件其实还在原处），用户只会以为"数据丢了"。

建议：回退时写一条标记（如 `local_path_invalid`），下次进设置页横幅提示
「上次使用的目录不可用，已临时切换到 XXX，点此重新选择 / 找回文件」，并保留原路径供重试。

**修复**（`local.dart` + `pages/settings/app.dart`）：
- 新增 `LocalPathFallback`（原路径 / 回退路径 / 原因 / 时间），持久化到
  `App.dataPath/local_path_invalid`（不进 appdata，避免被 WebDAV 同步到别的设备）。
- 抽 `canWrite(dir)`：可写 = 能创建且能删除测试文件（SAF 授权被收回的目录仍然"存在"但一写就抛）。
- 抽 `_fallbackToDefaultPath(previous, reason)`：`_checkPathValidation()` 写测试失败与
  `init()` 里 `!directory.existsSync()` 两处都改走它，统一记录标记；
  默认目录也不可写时兜底到 `App.dataPath/local`；回退目标与当前相同时不记标记。
- 新增 `switchPathWithoutMoving(newPath)`：**纯切换、不搬运文件**。找回时必须用它 ——
  走 `setNewPath` 会把当前空的临时目录"复制"过去并清空目标，恰好抹掉用户数据。
  成功后清除标记。
- 标记**不会**因重启后新目录可用而自动清除（否则用户永远看不到提示）：只在
  「Use original folder」/「Choose a different folder」/「Ignore」时清。
- 设置页新增 `_StoragePathFallbackBanner`（errorContainer 配色），放在存储路径项下方，
  展示原路径 + 三个操作按钮。

### 7.3 🟠 `MANAGE_EXTERNAL_STORAGE` 声明了但从不申请
- `AndroidManifest.xml:3` 声明了该权限，`local.dart:521-535 findDefaultPath()` 依赖它去写
  公共 `Download/Comic`（`detectDownloadComicPath()` :480）。
- 但**全仓库没有任何运行时申请代码**（`grep -rn "requestPermission\|MANAGE_EXTERNAL_STORAGE" lib/` 为空，
  `MainActivity.kt` 也没有）。
- 后果：Android 11+ 上用户没手动去设置页开「所有文件访问」时，探测必然失败 → 静默回退到
  app 专属外部目录；用户以为默认在 `Download/Comic`，实际不在。
- 另：Google Play 上架时这个权限需要特殊声明且大概率被拒（ISSUES 清单 P2-1 已标记）。
- 建议：要么删掉这条声明 + 明确只走 SAF，要么补一个显式引导页说明为何需要。

### 7.4 🟡 `.nomedia` 会被写进用户选的任意目录
`local.dart:254-266 _checkNoMedia()` 在**每次 init 和每次换目录后**往 `path` 根写 `.nomedia`。
若用户把目录指向自己还在用的相册/共享文件夹，其中的图片视频会**对系统相册整体隐藏**。
建议：仅在目录为空或由 App 创建时写；SAF 树下写失败也应提示而非静默。

### 7.5 🟡 根目录 Uri 匹配用的是子串查找
`FlutterSafPlugin.kt:101 getRootUriByName()` 对每个已授权 root 做 `path.indexOf(k)`，
命中第一个即认为匹配。若用户先后授权过 `primary:Comic` 和 `primary:ComicBackup`，
`android://primary:ComicBackup/...` 会被 `primary:Comic` 先命中 → 解析到错误的树。
建议：改成前缀匹配 + 取最长匹配。

### 7.6 🟡 图片收藏目录与存储路径设置完全脱钩
`ImageFavoritesProvider.localImageFile()` 写死在 `App.dataPath/image_favorites_local/`，
**不受 `LocalManager.path` 影响**，设置页里也看不到。用户改了下载目录，离线图片仍留在私有目录 ——
这正是方案 A 要解决的：把图片收藏纳入同一套「存储位置」设置（第 6 节决策 2）。

### 7.7 结论
- 必须修：**7.1**（一行判据错，功能是死的）、**7.2**（静默丢数据的观感问题）。
- 建议修：**7.3 / 7.4**（权限与副作用），其中 7.3 与上架合规相关。
- 可选：**7.5**（多目录授权的边界情况）。
- 7.6 由本次方案 A 一并解决。
