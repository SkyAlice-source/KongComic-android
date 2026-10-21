# KongComic 设计规范审计（2026-10-22）

> 范围：`lib/` 全库 156 个 Dart 文件（71k 行）+ `tools/` 门禁脚本 + `assets/translation.json`。
> 方法：静态扫描（组件/颜色/圆角/间距/字号/图标/弹窗）+ 抽样读码核实上下文，误报已剔除。

## 一、正面基线（已经做得好的）

| 维度 | 现状 | 证据 |
|---|---|---|
| 弹窗统一 | **全站 0 处 AlertDialog**，30 处页面级 `showDialog` 全部返回 `ContentDialog` | 弹窗语言（标题栏/按钮/圆角 kcSurfaceRadius=24）已单点收口 |
| 字号门禁 | 裸 `fontSize: 数字` **0 处**；旧 `ts.sNN`/`AppFontSizes` 表已清零并删除文件 | `tools/check_font_sizes.py` 通过（ts 0、literal 0、kcFont 31/39 只减不增） |
| 图标统一 | 真 Material `Icons.*` 仅 **12 处**（阅读器播放/暂停等无等价物场景），其余全部 HugeIcons stroke 系 | 视觉风格单一 |
| 强调色 | 品牌红体系已铺开：`kcAccentColor` 56 处、`kcBrandAdaptive` 55 处、`kcAccentSurface` 23 处 | 主 CTA/选中/开关不再依赖 `cs.primary` |
| 裸圆角 | `Radius.circular(数字)` 字面量仅 **7 处** | 主体已 token 化 |
| 翻译覆盖 | zh_CN / zh_TW 各 937 键（完备） | — |

**结论：单项规范完成度普遍在 90%+，剩下的问题集中在「体系之间的裂缝」而非「没人遵守」。**

---

## 二、P1 —— 体系性缺陷（会产生真 bug 或已经产生）

### P1-1 翻译门禁脚本自身损坏，日文缺 6 键无人发现 ⚠️

- `tools/check_translations.py` 运行即崩：`TypeError: 'set' object is not subscriptable`（第 69 行 `used[k][0]`，`used[k]` 是 set）。
- 脚本崩在打印缺口之前，导致门禁形同虚设——**ja_JP 实际缺 6 个键**（v1.5.0 引入后从未补译）：
  - `Auto update sources result`
  - `Auto-update comic sources`
  - `Automatically clear a comic from Read Later once you start reading it`
  - `Automatically update installed sources on WiFi. Overrides local source edits.`
  - `Backup Retention`
  - `Read Later`
- 日文用户在这些位置会看到英文原文。zh_CN / zh_TW 无缺口。
- **且两个门禁脚本（check_font_sizes / check_translations）都没有挂 CI**，只有发版时想起来才手动跑。

**方案：**
1. 修脚本：`used[k]` 改为 `sorted(used[k])` 迭代或让 `used` 收集为 `dict[str, list]`；输出改为「每语言缺口计数 + 明细」。
2. 补齐 ja_JP 6 键。
3. 新增 `.github/workflows/lint.yml`：push/PR 时跑两个门禁脚本 + `flutter analyze`，发版 tag 前自然拦截。

### P1-2 两套设计令牌并存，其中一套是死代码

- `lib/design_tokens.dart`：kc* 体系（活跃，全站引用）。
- `lib/foundation/design_tokens.dart`：`AppRadii` / `AppSpacing` 体系 —— **全库 0 引用**，且语义与 kc* 重叠（`AppSpacing.xs=4` vs `kcSpaceXs=4`、`AppRadii.medium=12` vs `kcCardRadius=12`）。
- 两套并存的结果：新人/后续改动不知道哪套是事实来源，随时可能「复活」死的那套造成分叉。
- 同类问题：kc 体系内部也有死 token——`kcRadius11`（0 引用）、`kcChipRadius`（0 引用）。

**方案：**
1. 直接删除 `lib/foundation/design_tokens.dart`（无引用，零风险）。
2. 删除 `kcRadius11`、`kcChipRadius` 两个死 token。
3. 在 `design_tokens.dart` 头部加一句「本文件是唯一令牌来源」的排他声明，并在 CI 里加一条 grep 断言（`AppRadii|AppSpacing` 不允许再次出现）。

### P1-3 `appdata.settings` 无默认值防护（踩过的坑没有机制兜底）

- 已发生过：新增 `autoUpdateSourcesEnabled` 漏写 `Settings._create()` 默认值表 → 老用户升级后设置页红字崩溃（`type 'Null' is not a subtype of type 'bool'`）。
- 目前的防线只有「纪律 + 事后记忆」，**没有任何机制**阻止下一次再犯。

**方案（机制化）：**
1. 新增 `tools/check_settings_keys.py`：扫描全库 `settings['...']` / `settings[...]` 字面量键，与 `Settings._create()` 默认值表 diff，缺一即失败——与字号门禁同一思路。
2. 或更狠一点：debug 构建启动时对「本轮读到的所有 settings key」做断言校验（读时兜底 + 上报缺失键名）。
3. 读开关统一 `settings[k] == true` 的既有约定写进 lint。

### P1-4 死代码 + 「看似在刷新、实际永远不执行」的链路

- `FollowUpdatesWidget`（follow_updates_page.dart）：**除定义外全库无任何构造调用**，从未挂载。
- 但 `updateFollowUpdatesUI()` 里仍保留 `GlobalState.findOrNull<_FollowUpdatesWidgetState>()?.updateCount();` —— 恒为 null，`?.` 静默吞掉，**这行代码永远不执行任何事**。
- 主页追更红点目前靠 `LocalFavoritesManager().notifyChanges()` 广播 + `didChangeAppLifecycleState` 兜底刷新，恰好没炸；但任何人读到 `updateFollowUpdatesUI` 都会误以为「widget 链路在工作」，改红点逻辑时必然踩坑。

**方案：**
1. 删除 `FollowUpdatesWidget` / `_FollowUpdatesWidgetState` 及 `updateCount()` 调用行。
2. 红点刷新统一到**显式订阅**：`LocalFavoritesManager` 本身是 ChangeNotifier，主页 `_FlatBox` 改为 `ListenableBuilder` / 显式 listener，删除「findOrNull 反射式找 State」的模式（全库仅剩 7 处 GlobalState 使用，目标是清零这种隐式刷新）。

---

## 三、P2 —— 一致性缺陷（观感/可维护性）

### P2-1 「两种红」并存：品牌红与 error 派生红没有显式切割

- 品牌红 `#D4381B`（kcAccentColor）承担强调；`colorScheme.error` 由种子派生（未显式 copyWith 钉值），承担危险/错误。
- 浅色下两者色相接近、明度接近，用户无法区分「这个红是可点的强调，还是不可逆的危险」。
- 抽查 24 处 error 使用：删除按钮占绝大多数（语义正确），但 `comic.dart:1056` 用 `errorContainer` 渲染「Unavailable」标签属于**状态灰误用成错误红**；`about.dart:280/771` 用 error 表达「版本状态」同理。

**方案：**
1. 在两套 ColorScheme 的 `copyWith` 里**显式钉死 error**（建议浅色 `#B3261E`、深色拉亮到 `#F2B8B5` 系），与品牌红 `#D4381B` 拉开明度档，并在 `design_tokens.dart` 写明分工：「品牌红 = 强调/可点/选中；error = 破坏性/失败，永远不用于强调」。
2. 「Unavailable」标签、版本状态文案改中性灰（`onSurfaceVariant`）——不可用是状态，不是错误。
3. 后续给危险按钮补「视觉双保险」：红字之外加 error 图标（历史页删除已这么做，推广到收藏页/源管理页）。

### P2-2 圆角「双轨制」：语义 token 与数字 token 并行，无归位规则

- 语义档：`kcCardRadius`(29) / `kcPillRadius`(25) / `kcSurfaceRadius`(11) / `kcCardInnerRadius`(9) —— 用得多、语义清。
- 数字档：13 个 `kcRadiusN`，实际在用的 11 个（8→52、16→25、10→17、20→7、4→8、18→6、22→5、6→4、24→3、32→2、3→1），外加 2 个死档（11、以及 kcChipRadius）。
- 问题不在「有数字档」，在于**没有规则说什么场景用哪一档**：`kcRadius16` 的 25 处里，评论区气泡、设置行、下载页卡片混用，同层级组件有的 12 有的 16。
- 另有 7 处字面量漏网：`circular(999)`×2、`circular(1000)`×1（reading images，与 kcPillRadius 同义漂移）、`circular(5)`×2（main.dart 复选框/单选）、`circular(2)`×2。

**方案：**
1. 定「层级即圆角」映射并写进 design_tokens 注释：
   - 弹层/大浮面 24（kcSurfaceRadius）
   - 卡片 12（kcCardRadius）/ 卡内嵌套 10（kcCardInnerRadius）
   - 小徽章/输入 8（kcRadius8）
   - 胶囊 999（kcPillRadius，消灭 1000 漂移）
   - 微圆角 4（kcRadius4）
2. `kcRadius16` 逐处归位：是卡片的归 12，是弹层的归 24，是徽章的归 8——按语义迁完再删 16 档；其余低频档（3/6/18/20/22/24/32）同理收编或标注「仅限 X 组件」。
3. 7 处字面量直接替换为 token。

### P2-3 间距令牌命名反直觉：`kcSpaceXs=4` < `kcSpaceXxs=6`

- 常识里 xxs 应比 xs 小，这里恰好反过来，写新代码必点错一次。
- 现用量：Sm(8)=38、Md(12)=28、Lg(16)=28、Xs(4)=17、Xxs(6)=9。

**方案：** token 的使命本来就是「收编魔法数字」，直接改成诚实命名 `kcSpace4/6/8/12/16`（或 4dp 网格语义 `kcPad1/kcPad1.5/...`，但数字名信息密度最高）。一次性 sed 迁移 + 删旧名，零视觉变化。

### P2-4 列表行双轨：64 处原生 `ListTile` vs 刚建立的 `KcListTile`

- 收藏页已迁移示范，但设置页、源管理页、搜索页等仍是原生 ListTile：行高、水平缩进、选中色、按压态与 KcListTile 各是各的。
- 上轮新加的「统一 list 行」只覆盖了收藏链路，尚未铺开。

**方案：**
1. `KcListTile` 补齐高频 API：`trailing` 开关（KcSwitch）、`subtitle`、多行、左滑操作，让设置页能无痛迁移。
2. 迁移顺序：settings 三页（最规整）→ source 两页 → 弹窗内的选择行。
3. 字号门禁同款策略：把「裸 ListTile 数量」写进门禁基线，只减不增。

### P2-5 23 处 M3 `Card` 与 token 卡片观感不一致

- M3 Card 自带 shape/elevation 默认值，与 `kcCardRadius + kcCardShadow + outlineVariant 描边` 的卡片语言是两套。
- 全库替换为 `Material + InkWell` 或提供 `KcCard`（一次封装圆角/阴影/描边三件套）。

### P2-6 Read Now 按钮特例 + main.dart 里四套 M3 按钮主题

- `home_page.dart` 的 Read Now 用 `ElevatedButton.icon + surfaceTintColor: transparent` 绕开暗色洗白（有注释、是有意的 hack）。
- 但 main.dart 里为此保留 `filled/elevated/outlined/text` 四套 ButtonTheme 覆盖，多数已无调用方。

**方案：** 在 App `Button` 上增加品牌实心变体（`Button.filledBrand`：红底 + `kcOnAccentColor` 白字 + 无 surfaceTint），Read Now 收编后删掉 main.dart 四套主题覆盖（保留确有调用方的那套），消灭「全站唯一不用自家按钮的按钮」。

---

## 四、P3 —— 打磨项

| # | 问题 | 现状 | 方案 |
|---|---|---|---|
| P3-1 | 真 Material 图标 12 处 | `Icons.favorite`(3)、play/pause(4)、check 等，多在阅读器 | 无等价物时保留，其余替换；约定「新代码一律 HugeIcons」 |
| P3-2 | `Icons.strokeRounded*` 与 `HugeIcons.strokeRounded*` 双前缀混写 | hugeicons 包同时导出两个名字，全库两种写法各 430+ 处 | 定一种（建议 `HugeIcons.*`，避免与 Material Icons 同名混淆），sed 统一 |
| P3-3 | 43 处手动 `addListener`（initState/dispose 配对） | 收藏角标 bug 的根因模式：漏 dispose / 忘调用 | 提供 `AutoListenMixin`（自动登记/注销）或改 `ListenableBuilder`；新代码禁手写配对 |
| P3-4 | `showModalBottomSheet` 仅 2 处且无统一容器 | aggregated_search / search 的底部弹层 | 若后续底部弹层增多，封一个 `KcBottomSheet`（kcSurfaceRadius 顶圆角 + 把手条） |
| P3-5 | design_tokens 注释引用的配套文档不存在 | `design/kongcomic-design/kongcomic-ui-improvement-proposal.md` 是死链 | 本报告已存入 `design/kongcomic-design/`，更新注释指向 |
| P3-6 | `topBarHiddenPages: [1, 4]` 页面索引白名单 | 顶栏归属由 main_page 用魔法数字集中维护 | 给页面状态类加 `hasOwnTopBar` 自声明，NaviPane 按当前路由查询，白名单消失 |

---

## 五、落地顺序建议

1. **一轮机械修（半天，零视觉风险，可进 1.5.2）**：P1-1 修脚本+补 ja 6 键+挂 CI；P1-2 删死 token 文件；P1-3 加 settings 门禁；P1-4 删死 widget；P3-2 图标前缀统一；7 处圆角字面量替换。
2. **视觉决策轮（改前截图对比）**：P2-1 error 钉色（两种红对比图）、P2-2 kcRadius16 归位（受影响页面截图）。
3. **长线铺开（跟功能迭代顺手做）**：P2-4 ListTile 迁移、P2-5 Card 替换、P3-3 监听机制化——每完成一项就写进门禁基线。
4. **每项完成即把对应检查固化进 `.github/workflows/lint.yml`**，让规范从「记忆」变成「机器」。

## 六、门禁基线快照（2026-10-22，迁移起点）

```
AlertDialog: 0          裸 fontSize: 0        ts.sNN: 0
真 Material Icons: 12   Icons/HugeIcons 前缀混写: ~430/433
裸 Radius.circular: 7   ListTile: 64         Card: 23
showModalBottomSheet: 2  GlobalState 使用: 7  手动 addListener: 43
kcRadiusN 死档: kcRadius11, kcChipRadius
死文件: lib/foundation/design_tokens.dart (0 引用)
ja_JP 缺口: 6 键
```

## 七、实施修订（2026-10-22，Wave 1 机械修已落地）

按第五节第一波（零视觉风险）已全部执行并通过 `flutter analyze`：

- **P1-1**：修 `tools/check_translations.py`（第 55 行 `set(used)` → `used`，崩在 `used[k][0]` 的 TypeError 已解决）；实测权威缺口仅 **3 键**（报告写的 6 键里另 3 键 ja_JP 已存在），已补 `ja_JP` 的 `Auto-update comic sources` / `Automatically update installed sources on WiFi. Overrides local source edits.` / `Backup Retention`，缺口归零；新建 `.github/workflows/lint.yml`（push/PR 跑四门禁 + analyze）。
- **P1-2**：删 `lib/foundation/design_tokens.dart`（AppRadii/AppSpacing，0 引用）；删 `kcRadius11` / `kcChipRadius` 两个死 token；新增 `tools/check_tokens.py`（断言旧体系与死 token 不复活）。
- **P1-3**：新增 `tools/check_settings_keys.py`，扫 `appdata.settings['字面量键']` 与 `_data` 默认值表 diff；5 个动态/迁移遗留键（`followUpdatesFolder` 等）入豁免清单，当前 0 真缺口。
- **P1-4**：删从未挂载的死代码 `FollowUpdatesWidget` / `_FollowUpdatesWidgetState`；`updateFollowUpdatesUI()` 仅保留活的 `_FollowUpdatesPageState` 刷新（`findOrNull<_FollowUpdatesWidgetState>()` 恒 null 的假刷新已删）。
- **P2-2（部分）**：7 处裸 `Radius.circular` 字面量全部 token 化（999/1000→`kcPillRadius`；5→`kcRadius6`、2→`kcRadius3`，均 +1px 取最邻近、肉眼不可见）。**`kcRadius16` 25 处归位属 Wave 2（需截图拍板），未做。**
- **P3-2 更正（审计误报）**：报告称 `Icons.strokeRounded*` 与 `HugeIcons.strokeRounded*` 各 430+ 处混写。实测用 `\bIcons\.strokeRounded` 全库 **0 匹配**——"430/433 混写" 是被子串 `HugeIcons` 包含 `Icons` 污染的假阳性（正是报告方法论自己警告过的坑）。全库早已统一 `HugeIcons.strokeRounded`，**无需改动**，避免了 800+ 处无意义 sed。

- **P2-3**：`kcSpaceXxs`(6) 命名反直觉（比 `kcSpaceXs`(4) 还大），重命名为诚实值名 `kcSpace6`，更新令牌注释，`lib` 全库 9 处引用（side_bar / source_repositories_page / favorite / message / button）同步替换，零视觉改动。
- **P2-1（具体 bug 项）**：`comic.dart` 的「Unavailable」状态标签原用 `errorContainer`/`onErrorContainer` 渲染（状态灰误用成错误红），改为 `surfaceContainerHighest` 底 + `onSurfaceVariant` 字（中性灰），与同文件彩色 tag 一致。
- **P3-5**：死链 `kongcomic-ui-improvement-proposal.md` 已在 Wave 1 改头注释时替换掉（当前注释指向本审计报告），经 grep 确认工程内（除本报告外）已无该死链。

> 待办（Wave 2/3，需视觉决策或顺手迭代，未动）：
> - **P2-1 error 钉色**：全局 `ColorScheme.error` 显式钉死（浅色 `#B3261E` / 深色拉亮红）属报告明确的「改前截图对比」项，需你 eyeball 拍板后再改（当前 `error` 由 flex seed 派生，与品牌红同色调难区分）。
> - **P2-2 kcRadius16 归位**：25 处按「卡片→12 / 弹层→24 / 徽章→8」语义迁，需截图前后对比。
> - **P3-6** `topBarHiddenPages` 白名单自声明。
>
> 上面三项仍待办；**P2-4 / P2-5 / P3-3 已于 Wave 3 铺开完成**（见第八节）。

## 八、Wave 3 长线铺开（2026-10-22，已完成）

### 8.1 共建脚手架

| 件 | 位置 | 作用 |
|---|---|---|
| `AutoListenMixin` / `AutoListenHandle` | `lib/foundation/listen_mixin.dart`（新） | `listen(listenable, cb)` 登记，`dispose` 统一 `removeListener`；根治「手写 addListener / removeListener 配对、漏 dispose」 |
| `KcCard` | `lib/components/card.dart`（新），由 `components.dart` export | M3 `Card` 的 token 化封装，半径恒走 `kcCardRadius`，描边/阴影变显式开关 |
| `KcListTile.contentPadding` | `lib/components/list_tile.dart`（增强） | 让「父级已做内缩」的行能无损迁移（默认仍 20dp/12dp） |
| `tools/check_components.py` | `tools/`（新），已挂 `lint.yml` | 原生 ListTile / M3 Card / 手写 addListener **只减不增** |

### 8.2 实际收敛结果

| 项 | 前 | 后 | 说明 |
|---|---:|---:|---|
| 原生 `ListTile(` | 49 | **0** | 全部迁 `KcListTile`（含 `dense`/`visualDensity` 剥离、`contentPadding` 保留、单行场景 `showDivider: false`） |
| 原生 M3 `Card(` | 1 | **1** | 仅 `KcCard` 自身封装；审计原报 23 处是把 `_XCard`/`buildCard` 误算 |
| 手写 `addListener` | 68 | **27** | 见 8.3；共 41 处机制化 |

### 8.3 剩余 27 处 `addListener` 的定性（**刻意不迁移**）

不是「没做完」，而是这类站点套 mixin 会引入错误，故保留：

1. **动态换绑**（`didChangeDependencies` / `didUpdateWidget` / callback 内先 remove 再 add）：`appbar.dart`（3 个 State 共 4 处）、`downloading_page.dart`（2 个 State 共 3 处）、`comic_page.dart:97`、`images.dart:1284/1780/1790`。mixin 的 `_entries` 是只增列表，重复注册会触发重复 setState。
2. **`ImageStream` 监听**：`image.dart`(2)、`reader/comic_image.dart`(2)、`comic_page.dart:973`、`cover_viewer.dart:91`。走 `ImageStreamListener` 协议，需要按同一闭包移除，非 `VoidCallback` 生命周期。
3. **`WindowListener`**：`window_frame.dart`(2)。`windowManager.addListener(this)` 参数是 `WindowListener` 不是 `VoidCallback`。
4. **定义点**：`navigation_bar.dart:960`（`NaviObserver` 自己实现 `Listenable`）。
5. **单例 / service 自管理生命周期**：`utils/data_sync.dart`(2，`DataSync` 本体)、`utils/notifications.dart`(2，`DownloadNotifier`)、`follow_updates_page.dart:1147`（`FollowUpdatesService` 静态生命周期）。

### 8.4 交叉验证要点

- `part of` 文件（`components.dart` / `favorites_page.dart` / `reader.dart` / `comic_page.dart` 的 part）**不能自带 import**，`listen_mixin` 的 import 必须加在父库；这是本轮唯一的编译事故来源，已修正。
- `KcListTile` 默认带发丝分隔线；`ListView.separated` 或「父级已有分隔」处必须 `showDivider: false`，否则双线。
- 门禁脚本原先把 `(?<![\w])ListTile\(` 的计数又减了一次 `KcListTile(` —— 后顾已排除，**重复扣减会算成负数**，已改为不扣减。


## 九、Wave 3 复核追加修复（2026-10-22，监听生命周期专项）

第八节把 `appbar.dart` 的 4 处 `addListener` 一律判为「动态换绑、健康保留」是**误判**。复核后确认其中 2 处是真实缺陷，另发现 1 处资源泄漏与 4 处 `dispose` 顺序错误。

| 位置 | 问题 | 修复 |
|---|---|---|
| `_AppTabBarState` | `didChangeDependencies` 无条件 `animation.addListener`（`ChangeNotifier` 不去重 → 重复注册）；`didUpdateWidget` 换 controller 只 add 新不摘旧；`dispose` **完全没有 removeListener**。`onTabChanged` 会走 `bucket.writeState(context)` → 销毁后回调抛「deactivated widget's ancestor」 | 新增 `_bindController(next)` + `bool _controllerBound`：同实例跳过、换人先摘旧、`dispose` 必摘且置于 `super.dispose()` 之前 |
| `_TabViewBodyState` | 同上（`didChangeDependencies` 裸 add、`dispose` 里 `super.dispose()` 在 `removeListener` 之前） | 同款 `_bindController` + `updateIndex` 加 `if (!mounted) return` |
| `cover_viewer._saveCover()` | 一次性 `ImageStream.addListener` 从不 remove；`completer.complete` 无 `isCompleted` 守卫 → 动图/多帧封面会二次 complete 抛 `StateError` | 持有 `listener` 引用，`finally` 中 `removeListener`；complete 前加 `!completer.isCompleted` |
| `_MultiPagesFilterState` | 自建 `ScrollController` 未释放（已传给 `ReorderableListView`，不会被自动 dispose） | 补 `scrollController.dispose()` |
| `global_state` / `categories_page` / `local` / `setting_components` | `dispose` 里 `super.dispose()` 不在最后 | 统一调整为资源先释放、`super.dispose()` 收尾 |
| `list_tile.dart` / `card.dart` | 新文件未按 `dart format` 规范缩进 | 已格式化 |

**复核结论**：全局再扫「`didChangeDependencies` 里裸 `addListener`」= 0 处；`flutter analyze` No issues；五门禁全绿；arm64 debug 构建成功，模拟器走查（分类页多 Tab 切换 + PageStorage 恢复、详情页错误态、本地漫画阅读器）异常计数 0。

**仍然待拍板（未动）**：
1. `KcListTile` 单行高度 = `kcBody(14) × 1.35 + 2 × 12 ≈ 43dp`，低于 48dp 无障碍最小点击区（M3 `ListTile` one-line 为 56dp）。修法：`Padding` 外包 `ConstrainedBox(minHeight: 48)` 或 `vertical: 12 → 16`，后者会让 49 行整体长高 8dp。
2. ~~8 处「容器内末行」保留 `showDivider` 默认 `true`~~ → 已修，见第十节（实际 10 处）。
3. P2-1 全局 `error` 钉色、P2-2 `kcRadius16` 归位、P3-6 `topBarHiddenPages` 自声明 —— 仍需截图对比后决定。

## 十、发丝尾线清理（2026-10-22，已完成）

第九节记的「8 处」是目测粗估。用脚本做括号匹配、筛出「`KcListTile(...)` 后面紧接 `]`」的调用点后，实际是 **10 处**：

| # | 位置 | 场景 | 判定方式 |
|---:|---|---|---|
| 1 | `comic_details_page/favorite.dart` `_buildSingleFolder` | 收藏面板「网络收藏」单文件夹 | `showDivider: false` |
| 2 | `comic_details_page/favorite.dart` `_buildMultiFolder` | 多文件夹 map | `entry.key != folders!.entries.last.key` |
| 3 | `favorites/side_bar.dart` 分类弹窗首行 | Uncategorized | `cats.isNotEmpty`（无分类时它就是末行） |
| 4 | `favorites/side_bar.dart` 分类弹窗 for | 分类列表 | `cat != cats.last` |
| 5 | `image_favorites_page.dart` 筛选弹窗 | 「图片数大于」末行 | `showDivider: false` |
| 6 | `settings/network.dart` 手动代理表单 | Password 行（下一项是按钮） | `showDivider: false` |
| 7 | `settings/explore_settings.dart` 关键词屏蔽 | `ListView.builder` | `index < len - 1` |
| 8 | `settings/explore_settings.dart` 评论关键词屏蔽 | `ListView.builder` | `index < len - 1` |
| 9 | `comic_source_page.dart` 账号区块 | Log out 行 | `showDivider: false` |
| 10 | `aggregated_search_page.dart` 源选择弹窗 | `entry.sources.map` | `c != entry.sources.last` |

**刻意不动**的两类：

- **`comic_source_page.dart` 设置项流**（`for ... yield KcListTile`，4 个分支）。同一个 for 里按 `type` 分支 yield，静态判不出「最后一行是哪条」，要改造得先把整个列表物化再统一收尾，为一个 0.7px 的线不值得。
- **弹窗里只有一行的 `content: KcListTile(...)`**（`favorite_actions.dart` 选文件夹、`local_favorites_page.dart` 筛选）。那根线在内容和底部按钮区之间起分隔作用，不是列表尾线，保留。

⚠️ **格式化副作用**：这轮修的是 10 行参数，但动过手的 7 个文件顺手跑了 `dart format`，而这些文件此前从未被格式化过（全库只有新文件 `list_tile.dart`/`card.dart` 是 format 过的）。tall style 把原有的紧凑写法（`if (x) { a; return; }`）全部展开，产生 **约 265 行与本次修改无关的纯格式 diff**（`git diff -w` 只剩 269/195，含格式是 534/460）。语义零变化，`flutter analyze` 通过。要回退只能逐块重排回原风格，不建议。

**验证**：`flutter analyze` No issues；五门禁全绿（翻译 937/937/934、字号、settings 93 键、令牌、组件 ListTile 0 / Card 1 / addListener 27）；arm64 debug 构建 46s 成功并装机启动正常。

## 十一、无障碍行高 + 顶栏自声明（2026-10-22，已完成）

### 11.1 `KcListTile` 补到 48dp 点击区

第九节待办第 1 项的落地。新增令牌 `kcMinTapTarget = 48`（`design_tokens.dart`），`KcListTile` 用 `ConstrainedBox(minHeight: kcMinTapTarget)` 包住 `Material`：

```dart
ConstrainedBox(
  constraints: const BoxConstraints(minHeight: kcMinTapTarget),
  child: Material(... InkWell ... Padding ... Row),
)
```

**为什么这样能生效**：`ConstrainedBox` 把 `minHeight` 沿子链下传，`Material`（proxy box）→ `InkWell` → `Padding`（减掉 24）→ `Row` 依次收到 `minHeight: 24`，Row 被撑到 24 后按默认 `crossAxisAlignment.center` 让文字垂直居中。整行 48，点击区和文字都居中，不需要额外 `Center`/`Align`。

**实测**（`flutter_test`，Ahem 字体）：单行 42.9 → **48.7**；带副标题 62.7 不变（本来就 > 48）。
**代价**：全 App 列表每行 +5dp，49 处列表约 +245dp（半屏）。换来的是符合 M3/WCAG 的点击区，且因为只加 5dp，视觉上几乎只是「松了一点点」。

### 11.2 `topBarHiddenPages` 改页面自声明（P3-6）

原写法 `topBarHiddenPages: const [1, 4]` 硬编码页索引（1 收藏 / 4 历史），底栏顺序一调或插入新 tab 就会把无关页面的顶栏误伤掉。

改为：

| 件 | 内容 |
|---|---|
| `SelfTopBarPage` | `navigation_bar.dart` 新增的空标记接口，语义 = 「本页自绘整条顶栏」 |
| `FavoritesPage` / `HistoryPage` | `extends StatefulWidget implements SelfTopBarPage` |
| `main_page.dart` | `topBarHiddenPages: [for (var i = 0; i < _pages.length; i++) if (_pages[i] is SelfTopBarPage) i]` |

收益：新增自绘顶栏的页面只需 `implements`，`main_page` 零改动；调整底栏顺序不再需要同步魔法索引。

### 11.3 顺带发现（未修）

手动代理表单（`settings/network.dart`）四行是 `KcListTile(title: TextField(...))`。M3 下 `TextField` 自带 `InputBorder.underline`，与 `KcRowDivider` 叠成「一条深（underline）+ 一条极淡（发丝线）」的双线。两种解法：给这些 `TextField` 设 `border: InputBorder.none`，或该表单整体 `showDivider: false` 只留 underline。属独立视觉问题，本轮未动。

### 11.4 验证

`flutter analyze` No issues；五门禁全绿；`flutter test` 两条临时用例分别验证「单行 ≥48dp」「`showDivider: false` 时 KcRowDivider 数量为 0」后删除；arm64 debug 构建 42s 成功，模拟器走查：分类页共享顶栏正常、收藏页与历史页自绘顶栏正常让位、设置 → 网络 → 手动代理表单布局无溢出。

## 十二、error 钉色 + 表单双线（2026-10-22，已完成）

### 12.1 手动代理表单去掉 `TextField` 自带下划线

`settings/network.dart` 四个 `TextField`（Host / Port / Username / Password）加 `border: InputBorder.none`，只保留 `KcRowDivider`。

改前每行是「深（M3 `InputBorder.underline`）+ 极淡（发丝线）」双线；改后单线，且密码行因 `showDivider: false` 连发丝线也没有。截图对比确认。

### 12.2 error 钉色：先证伪原判断

**更正**：第九 / 十节写的「`error` 由品牌红种子派生、与 `kcBrandColor` 难区分」**只对了一半**。实测两条独立证据：

| 证据 | 结果 |
|---|---|
| `flutter_test` 直接打印 `SeedColorScheme.fromSeeds(...)` 的派生值 | 浅色 `#BA1A1A` / 深色 `#FFB4AB` / 灰度 `#FFB4AB` |
| 错误页截图（502 页）圆形感叹号图标**像素取色** | `#BA1A1A` |

也就是说 `error` 本来就是 M3 默认错误红，已经比品牌红 `#D4381B` 深一档、色相更冷；「两个红分不清」主要是**品牌红本身偏橙、亮度高**带来的错觉，不是 error 没钉。所以第一次按 M3 标准值钉成 `#B3261E` 属于无效改动（与 `#BA1A1A` 肉眼无差），已按用户要求改为真正更深的一档。

**最终值**（`main.dart` 三套外观都显式钉住）：

| 外观 | error | onError | 白/黑底对比度 |
|---|---|---|---|
| 浅色 | `#8C1D18` | `#FFFFFF` | 白底 **9.2:1** |
| 深色 | `#FFB4AB` | `#690005` | 暖黑底 ~8.9:1 |
| AMOLED 灰度 | `#FFB4AB` | `#690005` | 纯黑底 ~9.1:1 |

深色 / 灰度两支的 `#FFB4AB` 与派生值相同，钉住的意义是**不随种子或色调策略变化而漂移**；浅色那支才是真变化（`#BA1A1A` → `#8C1D18`，色相从 0° 移到 5°、亮度降 1 档）。

### 12.3 顺带发现（未修）

断网后进入源分类列表，页面会**一直停在骨架屏**（观察 15s 无变化），既没超时提示也没错误态。属网络层 / 列表状态机问题，不在本轮视觉范围。

**验证**：`flutter analyze` No issues；五门禁全绿；arm64 debug 构建 40s 成功，装机走查手动代理表单已无双线。

## 十三、错误提示英文化：根因与统一（2026-10-22，已完成）

### 13.1 根因不是「翻译缺失」，是「原文直出」

先做了两项证伪：

| 检查 | 结果 |
|---|---|
| `tools/check_translations.py` | 三语 937/937/934 条，**无缺口** |
| 把 `Error`/`Failed` 等字幕面量全库扫描（201 条） | 绝大多数是 `Log.*` 日志，非 UI |

真正的问题在 `lib/utils/translations.dart` 的 `friendlyError`：

```dart
String friendlyError(Object e) {
  if (e is String) {
    if (e.contains("Empty response body") || ...) return "Failed to load image".tl;
    if (e.contains("Comic source not found")) return "Comic source not found".tl;
    return e;              // ← 英文原文直接返回，界面照原样显示
  }
  return "Unknown error".tl;
}
```

`res.errorMessage` 的类型是 `String?`，所以**几乎所有错误都走 `return e`**，`.tl` 根本没机会介入。而这个函数被 SnackBar / 网络收藏 / 评论 / 章节评论 / 下载 / 聚合搜索等 20+ 处调用。

与此同时 `NetworkError` 组件内部另有一份 `_prettifyErrorMessage`（映射完整），两套逻辑各写各的——同一个错误在整页错误态里是中文、在 SnackBar 里就是英文。

### 13.2 统一成一份实现

| 动作 | 位置 |
|---|---|
| `isAuthError` / `friendlyErrorMessage` / `_friendlyHttpStatus` 上移 | `lib/components/loading.dart` → `lib/utils/translations.dart` |
| `loading.dart` 只留一句注释，`NetworkError.build` 改调 `friendlyErrorMessage` | `lib/components/loading.dart` |
| `friendlyError(String)` 的特例之后改调 `friendlyErrorMessage(e)` | `lib/utils/translations.dart` |
| 兜底策略改成「不再直出英文」 | 见下 |

新增映射（原来漏掉的真实错误）：

- `Failed host lookup`（Android 断网最常见）、`Unable to resolve host` → 无法连接服务器
- `Connection closed / terminated / aborted / broken pipe` → 网络错误（代理与源站常见）
- `FormatException / unexpected end of input / not valid JSON` → 服务器端错误
- 前缀剥离扩展到 `Exception:` / `SocketException:` / `ClientException with`
- 图片类：`Empty image URL` / `xxx not found.` / `Invalid onResponse result` → 图片加载失败

兜底语义变化：**已经是中文的原文照旧返回；仍是英文技术串的统一变成「未知错误」，原文写 `Log.info`**。这是本轮唯一的行为取舍——宁可少给细节，也不让中文界面出现 `SocketException: ...`。

### 13.3 还直出原文的调用点（12 处）

`friendlyError` 修好后，仍有地方绕过它直接 `showMessage(message: x.errorMessage!)` / `Text(e.toString())`：

| 文件 | 处数 | 修法 |
|---|---|---|
| `comic_details_page/actions.dart` | 4 | 包 `friendlyError(...)` |
| `comic_source_page.dart` | 2 + `updateFailureMessage` | 同上；DioException 的 `type.name`（英文枚举）换成中文说明 |
| `comic_details_page/comments_page.dart` | 2 | 同上 |
| `reader/chapter_comments.dart` | 6 | 同上 |
| `comic_details_page/comic_page.dart` | 1 | 同上 |
| `source_repositories_page.dart` | 3 + `_error = e.toString()` | 后者直接渲染成整页错误态 |
| `settings/local_favorites.dart` | 1 | 同上 |
| `settings/app.dart` | 1 | `showMessage(e.toString())` |
| `aggregated_search_page.dart` | 1 | `error = e.toString()` 后 `Text(error!)` |
| `comic_details_page/thumbnails.dart` | 1 | `error = res.errorMessage` 后 `Text(error!)` |
| `components/comic.dart` | 3 | `_error = e` / `_error = res.errorMessage` |

另有一条硬编码英文 `loadPage and loadNext can't be null at the same time`，改为 `.tl` 并补三语词条：
`This source is misconfigured: loadPage and loadNext cannot both be null` →
「源配置有误：loadPage 与 loadNext 不能同时为空」/「源設定有誤：loadPage 與 loadNext 不能同時為空」/「ソース設定に誤りがあります：loadPage と loadNext は同時に空にできません」。

### 13.4 验证

**单测**（`flutter_test`，注入最小中文表 + `language=zh-CN`，跑完删除）：

10 条真实英文异常全部输出中文且不含成段英文，含
`Exception: Invalid status code: 502`、`Failed host lookup (OS Error ...)`、
`Connection closed before full header was received`、`DioException [connection error]`、
`TimeoutException`、`CERTIFICATE_VERIFY_FAILED`、完全未知的英文串（→ 未知错误）；
中文原文原样返回；空串 → 未知错误。

**端到端**（模拟器断网）：搜索 `abc` → 错误页显示「错误 / 无法连接服务器，请检查网络或源站地址 / 重试 / 导出日志」，全中文。

`flutter analyze` No issues；五门禁全绿；arm64 debug 构建 44s 成功。

### 13.5 顺带发现（未修）

- **断网时「发现」页无限转圈**：断网 45s 后仍在 loading，既无错误态也无超时提示。Dio 的 `connectTimeout` 是 15s，说明该页在失败后继续重试或压根没 await 到失败分支。与本节无关，但同属「网络失败无反馈」。
- **断网时分类列表（`category_comics_page`）也停在骨架屏**，25s 无变化（第十二节已记）。

## 十四、网络失败无反馈：根因与修复（2026-10-22，已完成）

### 14.1 现象与实测

| 场景 | 改前 | 改后 |
|---|---|---|
| 断网进入分类列表 | 骨架屏，**104s 仍无变化** | ~16s 出现「错误 / 连接超时 / 重试」 |
| 断网进入发现页 | 转圈，45s 仍无变化 | ~16s 出现「错误 / 无法连接服务器 / 重试」 |
| 恢复网络点「重试」 | —— | 正常重新请求（分类页载入 1/90 页；含登录的源提示「需登录」） |

排查方式：`adb logcat -c` 后断网、进页面、按秒截图并抓 `flutter :` 日志。关键证据是
`02:45:21` 发出 `GET https://www.yamibo.com/manga/list?...`，到 `02:47:05`（104s）
既没有 response 日志也没有 error 日志 —— 请求**根本没结束**。

### 14.2 根因一：Dio 的超时字段在自定义 adapter 里是死配置

`MyLogInterceptor.onRequest` 一直在设 `connectTimeout / receiveTimeout / sendTimeout = 15s`，但全项目用的是自定义 `RHttpAdapter`。**Dio 本身不执行超时，只有内置 `IOHttpClientAdapter` 才会读取这三个字段**。原 adapter 仅设置了 `HttpClient.connectionTimeout`（那只管 TCP 建连，不管 DNS 与响应等待），于是：

- 断网 / DNS 卡住 → `openUrl` 无限挂起；
- 源站接受连接后不回包 → `request.close()` 无限挂起；
- 响应头回来但 body 不再推进（大图断流）→ `await` 无限挂起。

修法（`lib/network/app_dio.dart`）：

| 阶段 | 处理 |
|---|---|
| 建连（含 DNS） | `openUrl(...).timeout(connectTimeout)` → `DioException.connectionTimeout` |
| 发送 body | `addStream(...).timeout(sendTimeout)` → `DioException.sendTimeout`，并 `request.abort()` |
| 等响应头 | `request.close().timeout(receiveTimeout)` → `DioException.receiveTimeout`，并 abort |
| 读响应体 | `response.cast<Uint8List>().timeout(receiveTimeout, onTimeout: ...)` |

抛 `DioException` 而不是 `TimeoutException`，是为了让既有的 `MyLogInterceptor`
把类型翻译成中文（「连接超时」/「接收超时：服务器繁忙」）。

### 14.3 根因二：加载状态机没有 catch，异常静默吞掉

即使请求失败，界面也不一定报错 —— 因为多个状态机只处理「返回 `Res.error`」，对**抛异常**完全没有兜底：

| 位置 | 改前行为 |
|---|---|
| `LoadingState.loadDataWithRetry` | `loadData()` 抛异常 → Future 带错误结束，`isLoading` 永远 true |
| `LoadingState` 的 `onDataLoaded()` | 抛异常 → 同上（`initState`/`retry` 两份 `.then` 都没兜） |
| `MultiPageLoadingState.firstLoad / nextPage` | `.then` 无 onError，`_isFirstLoading` / `_isLoading` 永挂 |
| `ComicListState._loadPage` | 无 catch，`_data[page]` 仍为 null 且 `_error` 为 null → build 里再调一次又抛 → 永久骨架屏 |
| `_MultiPartExplorePageState.load()` | 无 catch，`loading` 永挂；且 **`load()` 写在 build 里、没有去重**，每次 rebuild 再发一遍请求 |
| `CategoryComicsPage.loadOptions()` | 无 catch，`options == null && optionsLoader != null` 分支永久转圈 |

统一改为 `try { ... } catch (e) { 归一到错误态 }`，并顺手：

- `friendlyError(Object)` 对非 String 对象不再一律返回「未知错误」，改为 `toString()` 后走同一份映射（`Exception: Invalid status code: 502` 现在能正确显示「服务器端错误」）；
- `LoadingState` 抽出 `_performLoad()`，两条入口共用，`onDataLoaded` 抛异常也落到错误态；
- `_MultiPartExplorePageState` 用 `Future? _inflight` 去重，重复 rebuild 不再重复请求。

### 14.4 顺带修掉两类真实未捕获异常

| 现象（logcat） | 根因 | 修法 |
|---|---|---|
| `Exception: Invalid status code: 502` + 堆栈指向 `Res.data` | `updateComic` 直接取 `(await loadComicInfo()).data`，`Res.data` 在出错时会 `throw` | 先判 `infoRes.error` 再取 data，失败原因走 `friendlyError`（追更页此前只显示「N 个失败」，拿不到原因） |
| `Bad state: Future already completed` + 堆栈指向 `Channel.close` | 生产者投递完 `close()` 一次，订阅方结束时 `onCancel` 又 `close()` 一次 | `close()` 幂等：`isCompleted` 才 `complete()` |

### 14.5 重试策略：不再把失败反馈推迟一分钟

`loadDataWithRetry` 原来对**任何**失败固定重试 3 次。断网时 4 次 × 15s ≈ 一分钟骨架屏，而 DNS 失败重试一百次也不会成功。新增 `isRetryableError(String?)`（`lib/utils/translations.dart`）：

| 类别 | 判定 | 例子 |
|---|---|---|
| 硬失败（不重试） | DNS 解析失败、无路由、证书/握手、连接被拒绝、源脚本 TypeError | `Failed host lookup`、`CERTIFICATE_VERIFY_FAILED` |
| 可自愈（重试） | 超时、连接被重置/中断、5xx、408、429、源站繁忙 | `Connection closed before full header`、`Invalid status code: 502` |
| 其余 | 不重试（默认保守） | 404、未知文案 |

另外加**总预算 16s**：失败来得快（5xx 几百毫秒）时仍可重试 3 次；但 15s 超时这种慢失败，超过一个完整超时周期就不再叠加 —— 最坏等待从一分钟降到 15–16s。

### 14.6 验证

- 临时单测（跑完删除）：DNS/证书/拒绝连接 → 不重试；超时/断流/502/503/429 → 重试；404/未知/null → 不重试；`friendlyError(Exception('Invalid status code: 502'))` → 「服务器端错误」。
- `flutter analyze` No issues；五门禁全绿；arm64 debug 构建 20s。
- 模拟器端到端（截图 + logcat）：断网分类列表 16s 出错误页；断网发现页两个 tab 各自 16s 出错误页；恢复网络点重试正常；在线分类列表正常载入（1/90，封面可见）；全程 `Bad state` / `Unhandled Exception` 计数 0。

### 14.7 遗留（未做）

- 慢网络时仍只有转圈，没有「网络较慢，仍在加载…」的提示（加提示要动 UI，另议）。
- `ComicList` 的 `loadNext` 流式分支仍是 `while (_data[page] == null) await _fetchNext();` 的写法，失败靠 `Res.data` 抛出后由外层 catch 接住，语义上不如显式判 `res.error` 清晰（本轮未重构，行为已正确）。

---

## 十五、慢网络提示与 v1.5.2 发版（当日收尾）

### 15.1 补上「网络较慢」提示（14.7 遗留项）

| 组件 | 位置 | 行为 |
|---|---|---|
| `SlowLoadingHint` | `components/loading.dart` | 7 秒后淡入「网络较慢，仍在加载…」；未到点高度为 0 不占位（`AnimatedSize` 长出），计时器随组件销毁自动取消 |
| `SlowLoadingOverlay` | 同上 | `Stack` + 底部 28px 浮一层胶囊提示，给骨架屏这类「铺满整块区域」的加载态用 |

挂载点三处，覆盖所有首屏加载：`LoadingState.buildLoading`、`MultiPageLoadingState.buildLoading`（默认实现改为 `Center(Column(min, [转圈, 提示]))`）、`_ComicGridSkeleton`（分类/搜索列表骨架屏）。

7 秒这个值是按 15s 总超时取的：正常网络下不会闪一下，慢网络下在超时前一半就给了解释。

### 15.2 重试预算再收紧

14.5 的「总预算 16s」在**一次 15s 连接超时**的场景下会误判（`elapsed≈15 < 16`），仍会再叠一轮 → 用户实际等 30s。新增判据：`attemptCost > 8s` 直接放弃重试。快速失败（5xx 几百毫秒）仍可重试 3 次。

### 15.3 顺带修掉分享文件名退化成 UUID

| 现象 | 根因 | 修法 |
|---|---|---|
| 分享出去的图片文件名是 `d82-11f1-95a8-....jpg` 这种乱码 | `cross_file` 的 **io 实现忽略 `XFile.fromData(name:)`**（源码注释写明 "name is ignored"），share_plus 12 于是退化成 `Uuid().v1().substring(10)` + 扩展名 | `shareImages` 收集 filename，随 `ShareParams(fileNameOverrides: names)` 一起传 |

同时修好 `test/share_test.dart`：share_plus 12 会把「只有字节没有 path」的 XFile 落到 `path_provider` 的临时目录，host 测试缺插件实现会抛 `MissingPluginException`（该测试在 v1.5.1 发版时是红的）。补 mock `plugins.flutter.io/path_provider`，断言改为「交给 share channel 的 paths 指向真实存在的文件 + 字节内容一致 + 原文件名 + mimeTypes」。

### 15.4 验证与发版

- `flutter analyze` No issues；四门禁（翻译/组件/设置键/令牌）全绿；`flutter test` 3/3；日文补齐 3 键后三语 939/939/939。
- 模拟器端到端（`iptables DROP` 制造半死网络）：8s 截图骨架屏 + 底部胶囊「网络较慢，仍在加载…」；17s 截图已到「连接超时」错误页；断网时秒报「无法连接服务器」；502 显示「服务器端错误」；logcat `Unhandled Exception` / `Bad state` 计数 0。
- 发版：`1.5.2+181`，`changelogs/v1.5.2.md`（英/简/繁/日），commit `7a54351`、tag `v1.5.2`，`main` 由 `a20dc30` fast-forward，CI run `39660037083`。
- ⚠️ `.github/workflows/lint.yml` 未随本次发布提交：`gh` token 缺 `workflow` scope，GitHub 拒绝任何含 workflow 文件的 push。需要 `gh auth refresh -s workflow` 后单独补推。
