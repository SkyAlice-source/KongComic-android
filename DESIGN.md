# KongComic DESIGN.md

> **给谁读**：AI 编码助手 / 设计助手在改动任何 UI 之前先读本文件。
> **事实来源优先级**：`lib/design_tokens.dart`（代码）> `tools/*.py`（CI 门禁）> 本文件（叙述）。
> 三者冲突时**以代码为准**，并同步修订本文件。
> **当前基线**：v1.5.23（2026-11-12，含 a11y 语义树门禁补强）。

## 0. 平台边界（读了再动手）

| | KongComic | 网页 DESIGN.md 里的东西 |
|---|---|---|
| 平台 | Flutter / Dart，Android + iOS，移动优先 | 浏览器、Google Stitch、CSS |
| 单位 | dp、逻辑像素、`Color(0xAARRGGBB)` | px、hex、rem、CSS 变量 |
| 结构 | Widget 树、`ThemeData`、`ColorScheme` | 三栏 sidebar/prose/TOC、hero、footer |
| 交互 | 触摸、长按、边缘返回手势 | hover、focus、desktop breakpoints |
| 标题 | 最大 22–24（`kcTitleLarge` / `kcFont24`） | 72–112px display type |

本文件借用了 `VoltAgent/awesome-design-md` 的 **DESIGN.md 结构**（Google Stitch 的 9 段式）和它最有价值的一点：**把风格写成 AI 可执行的约束**，以及 Notion / Mintlify 这类内容型站点里「Do's and Don'ts 必须写具体值、写明确禁令」的写法。

**不引入任何外部品牌的色板、字体、字号、间距数值。** 只采用 5 条抽象原则：阅读密度、留白节奏、层级对比、深色下的表面层级表达、最小点击区。详见 [§11 抽用原则核查表](#11-外部原则抽用与现状核查)。

---

## 0.1 Token Snapshot（机器可读摘要）

借移动端 DESIGN.md 扩展的 YAML tokens 写法，但**只写令牌名与语义，不抄色值/数值**——避免文档变成第二份色板（§2 记录过这种漂移）。改令牌时以 `design_tokens.dart` 为准并同步本段，可用 §10 的引用名校验脚本核对。

```yaml
source_of_truth: lib/design_tokens.dart
gate: tools/check_tokens.py
theme_modes: [light, dark, amoled]      # amoled = 零彩色，判定走 kcIsAmoled()
accent_surface: kcAccentColor(context)
accent_icon: kcBrandAdaptive(context)
on_accent: kcOnAccentColor
status: kcStatusColor(context, ok:)
hairline: kcHairlineColor(context)      # 线宽 kcHairline
type_scale: [kcTitleMain, kcAppbarTitle, kcTitleLarge, kcSectionTitle,
             kcSubtitle, kcBody, kcCaption]
line_height: kcLineHeightFactor
spacing: [kcSpaceXs, kcSpace6, kcSpaceSm, kcSpaceMd, kcSpaceLg, kcSpace18]
section_gap: kcSectionGap(context)
radii: [kcCardRadius, kcCardInnerRadius, kcPillRadius, kcFieldRadius,
        kcSurfaceRadius]
min_tap_target: kcMinTapTarget           # 48dp
grid_breakpoint: kcGridCompactBreakpoint
grid_extent: [kcGridExtentPhone, kcGridExtentTablet]
content_max_width: kcContentMaxWidth
card_shadow: kcCardShadow(context)
spring: [kcSpring, KcSpring]
reduce_motion: kcReduceMotion(context)
component_prefix: "Kc* (lib/components/)"
i18n: assets/translation.json           # zh_CN / zh_TW / ja_JP，统一 ".tl"
a11y_test: test/a11y_guidelines_test.dart
```

## 1. Visual Theme & Atmosphere

漫画阅读器，**内容是主角，UI 要退后**。

- 三套外观（唯一事实来源 `main.dart` 的 `getTheme` + `kcThemePalettes`）：
  - **浅色**：Material 亮色，白底。
  - **深色**：暖近黑 `kcDarkBackground = #100D0F`，前景 `kcDarkForeground = #EDEAEB`。
  - **AMOLED 纯黑**：`kcAmoledBackground = #0A0A0A`，**零彩色**——所有强调色、状态色、标签色都退化为中性灰，靠表面明度和 hairline 区分层级，不靠阴影和颜色。判定统一走 `kcIsAmoled()`，不要在组件里自己判断 `theme_mode`。
- 品牌色 **Kong Coral `#D4381B`** 是全站唯一强调色，只用于收藏红心、角标、主 CTA、当前项、开关 ON。不要拿它铺大面积背景或写正文。
- 密度分两端：
  - **浏览态**（主页 / 收藏 / 历史 / 发现）：封面网格、信息密度高，卡片之间留等宽缝（`kcStackSeamWidth = 2.0`），下沿渐隐（`kcStackEdgeFade = 0.015`）。
  - **阅读态**：极低密度，画面铺满，HUD 只在需要时出现并自动隐藏；HUD 隐藏期间用 `IgnorePointer` 保证点击穿透到翻页手势。

## 2. Color Palette & Roles

| 角色 | 令牌 | AMOLED 下的行为 |
|---|---|---|
| 品牌强调（面与线） | `kcAccentColor(context)` | 退化为 `surfaceContainerHigh` 中性灰 |
| 品牌标记（图标/小色块） | `kcBrandAdaptive(context)` | 退化为 `cs.primary` 亮灰 |
| 品牌色上的前景 | `kcOnAccentColor`（白，红底 4.8:1） | — |
| 暗底上的品牌小字 | `kcBrandColorOnDark = #E4553A`（5.3:1 过 AA） | — |
| 弱强调面 | `kcAccentSurface(context, alpha: 0.10)` | 跟随主题 |
| 状态色（可达/超时） | `kcStatusColor(context, ok:)` | 退化为 `onSurfaceVariant` |
| 信息色（点踩/中性提示） | `kcInfoColor(context)` | 退化为 `onSurfaceVariant` |
| 分割线 | `kcHairlineColor(context)`，线宽 `kcHairline = 0.8` | 跟随主题 |
| 标签色板 | `kcTagColor(index, brightness, amoled:)` / `kcTagPaletteLight` / `kcTagPaletteDark` / `kcTagAmoledGray` | 统一灰 |
| 可选主题色板 | `kcThemePalettes`（8 组 primary/secondary） | 不参与 AMOLED |

**规则**：颜色一律经令牌或 `ColorScheme` 取，不要写 `Color(0xFF...)`；注释、预览卡、文档里也不要抄一份色值（历史上 `main.dart` 和设置页预览卡各抄一份，导致「点的是紫、界面是蓝」）。

**合法的第二色表**：`lib/foundation/colors.dart` 是「翻译类型」标签色板（female / male / parody / character / artist / group …），是该文件自己的事实来源；`main.dart` 的 `getTheme` 是主题色值的事实来源。`pages/settings/appearance.dart` 预览卡里的 `#1A1A1A` / `#E0E0E0` 只是预览自身的文字灰阶，主题色仍引用 `kcThemePalettes` / `kcBrandColorOnDark`。**组件层不要复制这些色值**，也不要把它们当成「可以随便写硬编码色」的先例。

## 3. Typography Rules

七级语义阶梯（`lib/design_tokens.dart`），新增/修改样式**只允许用这些**：

| 令牌 | 值 | 用途 |
|---|---|---|
| `kcTitleMain` | 20 | 根页主标题（粗体） |
| `kcAppbarTitle` | 20 | 顶栏标题 |
| `kcTitleLarge` | 22 | 内容区大标题、详情页漫画名、分区标题 |
| `kcSectionTitle` | 17 | 小节标题 |
| `kcSubtitle` | 16 | 副标题 |
| `kcBody` | 14 | 正文 |
| `kcCaption` | 12 | 辅助文字 |

- 行高系数 `kcLineHeightFactor = 1.55`。
- 徽标等非常规尺寸用 `kcFont10/11/13/15/22/24`，不要裸写 `fontSize: 14`。
- 禁止 `ts.sNN`、`AppFontSizes.sNN`、裸数字字号——`tools/check_font_sizes.py` 只减不增。
- 字号缩放：网格用 `kcGridBaseExtent(widthDp, textScale)`，不要写死列宽。
- **所有 UI 字符串必须 `"key".tl`**，`assets/translation.json` 现有 `zh_CN / zh_TW / ja_JP` 各 1072 键；英文以纯英文 key 本身兜底。新增字符串三语同时补齐，跑 `check_translations.py`。

## 4. Component Stylings

统一用 `Kc*` 组件族（`lib/components/`、`lib/design_tokens.dart`），**不要回退到原生 Material 件**。

| 需求 | 用 |
|---|---|
| 卡片 | `KcCard`（唯一允许出现原生 `Card(` 的地方） |
| 列表行 | `KcListTile`（`showDivider` 控制分隔线；**末行不画线**，否则像多一条边框） |
| 行内分隔 / 值标签 | `KcRowDivider` / `KcValueChip` |
| 胶囊、筛选、标签 | `KcPillChip` / `KcFilterChipRow` / `KcChoiceTabBar` |
| 页面骨架 | `KcPageScaffold` / `KcPageContent` / `KcSectionHeader` / `KcGroupHeaderDelegate` |
| 顶栏与工具条 | `KcDockedToolbar` / `KcToolbarAction` / `KcActionOverflowBar` |
| 选择类弹窗 | `KcChoiceDialog` / `KcActionDialogSection` / `KcRadioOption`（不要自造 `Completer` 弹窗） |
| 表单 | `KcSwitch` / `KcEntryBox` / `CustomSlider` |
| 进度与动效 | `KcTrackProgress` / `KcInlineSpinner` / `KcPageProgressBar` / `KcGlassActivity` |

输入框、确认框、JS 自定义 UI 等**非选择类弹窗**仍用 Flutter 标准 `showDialog`（仓库 34 处），这是合规的；要求是：不要自造 `Completer` 弹窗、不要漏 `StatefulBuilder` 让勾选状态失效、错误页要有标题。
| 加载/空态/错误 | `KcPageLoading`、`KcChibiIdle`、`KcChibiCrawlLoading`；`EmptyState` 空态（与 `NetworkError` 错误态区分：**「还没有内容」≠「出事了」**） |
| 轻提示 | `message.dart` 的 `context.showMessage`，不要自己插 `OverlayEntry.remove()` |
| 弹性曲线 | `kcSpring` / `KcSpring`；`kcReduceMotion(context)` 为真时降级动效 |

**状态约定**（都是踩过的坑）：
- 错误页**必须有标题**（`loading.dart` 的 `title` 参数），只有返回箭头不行。
- `NetworkError` 给三层信息：**分类标题**（发生了什么）+ **归一化原因** + **下一步建议**（能做什么），由 `classifyErrorMessage()` / `_errorStyle()` 决定；技术原文和导出日志默认收进「查看详情」，不要摆进主视觉区。错误文案一律走 `friendlyErrorMessage()`，禁止把英文异常串直出界面。
- 错误页视觉用 `kcAccentSurface` 柔光圆徽章 + `kcBrandAdaptive` / `kcBrandColorOnDark`，AMOLED 保持零彩色；内容列限宽 `kcChoiceDialogMaxWidth`，平板/横屏不铺满整块内容区。
- **`ComicList` 子树里的每个滚动容器都必须有自己的 `PageStorageKey`**（骨架屏 `GridView`、混合探索页滚动、多段页滚动都算）。原因不是洁癖：`PageStorage` 的槽位标识只是「到 bucket 为止路径上有哪些 `PageStorageKey`」，**不区分 widget 类型**，而 `ComicList` 会把自己整份分页状态（一个 `Map`）写进同一个槽。无 key 的滚动视图就会在 `ScrollPosition.restoreScrollOffset` 里执行 `readState(...) as double?` 拿到 `_Map<String, dynamic>`，抛 `type '_Map<String, dynamic>' is not a subtype of type 'double?'`，整块列表变成 ErrorWidget（表现：整页空白 + 一行报错文字，刷新或跳未加载页时触发）。
  - 已加固：骨架屏 `kc_grid_skeleton`、`_MixedExplorePage` 的 `mixed_scroll`、网络收藏两处 `ComicList` 用 `KeyedSubtree(PageStorageKey(...))` 单独分槽（`GlobalKey` 不是 `PageStorageKey`，会让它写进「空标识」污染整个 bucket）。
  - 回归测试：`test/comic_list_page_storage_test.dart`。
- 任何 `await` 网络动作都要 try/catch 复位 loading 标志，否则按钮永久转圈（评论发送/点赞/投票曾 8 处中招）。
- 开关类设置**先落盘再刷新 UI**；滑块加防抖，不要每次 `onChanged` 都写盘。
- 收藏角标刷新用 `AutoListenMixin.listen()`，不要手写 `addListener`（漏 dispose 就是角标不刷新的根因）。
- 阅读设置按 `(cid, sourceKey, key)` 取 `getReaderSetting()`，**不要监听整张 `appdata.settings`**。
- **封面一律走 `CoverBox`**（不要裸 `AnimatedImage`）：占位 = 书名首字 + **延迟 320ms** 才出现的加载环；失败给重试入口（大卡 pill / 小卡紧凑圆点）+ 一次带抖动的自动重试。裸 `AnimatedImage` 加载中只有一片空底色、失败什么都没有，用户分不清「慢」和「坏」。
  - **百分比环只给大卡**（`showProgressPercent`：主页英雄卡、详情页封面）。环内写真实 `N%`，数据来自 `AnimatedImage.onProgress` 转发的 `ImageChunkEvent`；数字套 `FittedBox`，`100%` 和大字号都不会顶到环上。
  - 服务器不报 `content-length`（chunked）时 `expectedTotalBytes` 为 null，必须退回不确定环，**不要画一个停在 0% 的假进度**。
  - 列表小卡一律不确定环：几十张同时跳数字比安静转圈噪得多，小环也塞不下两位数。
  - 下拉刷新只清列表数据、不重建卡片 State，**失败封面不会自己重试**。`ComicList._handleRefresh` 末尾调 `CoverBox.refreshAll()`（全局代次 +1，只重置失败项）让存量缺图重来 —— 因此不需要额外的「重载封面」按钮。回归测试：`test/cover_loading_test.dart`。

**悬浮小控件（回顶 FAB / 分页胶囊）**：
- 配色统一走 `kcFloatingGlassColors(context)` / `kcFloatingGlassDecoration()`，**不要再各写一套**：浅色是半透明 surface@0.82 + 描边@0.16，深色是 `surfaceContainerHighest` 实心。两者同屏并排时要像同一块玻璃上的两个孔位。
- 不套 `BoxShadow`（`elevation: 0` 的平片）；分离感交给底色 + 发丝描边。
- 半透明底压在封面 / 文字上时**必须配一层 `BackdropFilter`**：只降不透明度会让底下的书名透进控件里（"深渊融接 1 / 52" 看着像控件里的字）。滚动时这类控件本来就会隐藏，模糊只在静止时开销。
- 分页胶囊与右下角回顶 FAB 同处一条尾排：胶囊用 `kcScrollTopFabSize + kcSpaceLg + kcSpaceSm` 算左右让位、用两者半高差算抬高，保证同心且窄屏 / 大字号下只会等比缩小，不会压到按钮。
- 分页胶囊只显示数字 `1 / 52`（读屏走 `semanticsLabel` 念完整句），箭头用 `kcPagerArrowSize`（34dp）——小于 48dp 是**已知例外**：胶囊总高只有 38dp，箭头按 48dp 撑宽会把整条拉长到内容区一半（`test/a11y_guidelines_test.dart` 里钉死，别偷偷改回去）。
- **Toast 必须让开浮岛底栏**（`showToast` / `showUndoMessage` → `_toastBottomInset`）：根 tab 页抬到 `NaviPaneState.bottomBarHeight + kcSpaceSm`，子页面（无底栏）才用 24dp。写死 24dp 会把提示正好压在 5 个 tab 上 —— 用户刚点完「已收藏」，反馈条却盖住了自己点的那一格。`NaviPaneState.active` 是给 `App.rootContext` / 已 pop 的弹窗 context 兜底用的（它们向上查不到 State）。

## 5. Layout Principles

| 令牌 | 值 | 用途 |
|---|---|---|
| `kcSpaceXs / kcSpace6 / kcSpaceSm / kcSpaceMd / kcSpaceLg / kcSpace18` | 4 / 6 / 8 / 12 / 16 / 18 | 间距阶梯，基线 4dp |
| `kcSectionGap(context)` | 宽 28 / 紧凑 20 | 分区之间 |
| `kcRootTopBarHeight` | 56 | 根页顶栏 |
| `kcPageBottomGap` | 16 | 页面底部留白 |
| `kcContentMaxWidth` | 900 | 大屏内容最大宽，配 `kcPageContentWidth()` |
| `kcCardRadius / kcCardInnerRadius` | 12 / 10 | 卡片外/内 |
| `kcPillRadius` | 999 | 胶囊、底栏激活态 |
| `kcFieldRadius` | 16 | 输入框 |
| `kcSurfaceRadius` | 24 | 弹层、底部面板 |
| `kcRadius3 … kcRadius32` | 3/4/6/8/10/16/18/20/22/24/32 | 其余圆角 |
| 对话框 | `kcDialogInset 22` / `kcDialogRadius` / `kcDialogOptionHeight 48` / `kcDialogTabHeight 40` / `kcDialogConfirmHeight 44` / `kcChoiceDialogMaxWidth 420` | 统一对话框几何 |
| `kcMinTapTarget` | **48** | 所有可点区域下限 |
| `kcPagerPillHeight / kcPagerArrowSize` | 38 / 34 | 悬浮分页胶囊：高度、箭头命中区（见 §4 说明） |
| `kcScrollTopFabSize` | 56 | 回顶 FAB 直径；分页胶囊按它算让位与同心 |

留白哲学（抽自内容型站点，落到移动端）：**浏览页靠等宽缝和分区间距建立节奏；阅读页靠「隐藏 UI」制造留白**，不要靠加大 padding 把画面挤小。

## 6. Depth & Elevation

- 常规卡片阴影只用 `kcCardShadow(context)`；分割用 `kcHairline = 0.8` + `kcHairlineColor(context)`。
  `glass_container.dart` 的毛玻璃层与 `button.dart` 的按钮阴影是**组件内聚的合法例外**（毛玻璃需要自定义内外阴影），但新增普通卡片不得再自己写 `BoxShadow`。
- **AMOLED 下不要靠阴影和彩色表达层级**，用 `ColorScheme` 的 surface 层级 + hairline。深色下小字对比度要过 AA，语义色会向白提亮一档（`kcStatusColor`）。
- 禁止重阴影、禁止给平面列表卡片加投影。
- 层级顺序：页面底 → 卡片 → 浮起工具条 / 底部面板 → 对话框 → toast。

## 7. Do's and Don'ts

### Do

- 所有颜色、圆角、间距、字号走 `kc*` 令牌；所有列表/卡片/对话框走 `Kc*` 组件。
- 小图标按钮用 `kcMinTapTarget` 包一层；三套外观都过一遍（尤其 AMOLED）。
- `KcSwitch` 必须传 `semanticLabel`（行标题）：开关语义节点独立于列表行，不传时 TalkBack 只会读「已开启」，读不出开关是什么。
- 点击区、语义标签、文字对比度由 `test/a11y_guidelines_test.dart` 的官方 guideline 实测，不要只看有没有写令牌。`KcSwitch` 的孤立语义节点是 52×34，但真实可点区由整行 `InkWell`（≥48dp）覆盖；**不要为凑 guideline 把开关放大到 48dp**——`_KcSettingTile` 的 12dp padding 会把设置行从 58dp 顶到 72dp。
- 新增 UI 字符串三语补齐；改完 UI 跑 [§10 门禁](#10-门禁与验证流程)。
- 错误页给标题、空态给文案、加载态给骨架；网络动作失败要 toast + 复位标志。
- 详情页/收藏面板在源被停用或卸载时降级为纯本地，不要崩。
- 列表页分页与刷新用世代号防乱序（`_refreshToken` 模式），不要靠裸 `bool _loading`。

### Don't

- 不要 `Color(0xFF...)`、`fontSize: 14`、`ts.sNN`、`AppFontSizes.*`。
- 不要裸 `ListTile` / 裸 `Card` / 手写 `addListener(initState/dispose)`——CI 会拦。
- 不要 `comicSource!`、`ComicSource.find(key)!`：源停用后 `find` 返回 null，用 `?.` + 门控。
- 不要整表监听 `appdata.settings`，不要整页 `setState` 刷新一个角标。
- 不要让 `PageStorage.restoreState` 恢复 `_loading = true`（页面会永久停在骨架）。
- 不要在 AMOLED 下露红/蓝/绿：`kcBrandColor`、`Colors.blue[800]` 一类现写色都禁止。
- 不要把对话框错误字符串当路径写入 `local_path`（`io.dart` 曾因此污染数据）。
- 不要在屏幕左缘 `x < 120` 放可点元素：会和系统边缘返回手势抢事件；`adb input swipe` 起点也要避开。
- 不要跑 `dart format`：仓库 41/169 文件是旧 dart_style，全量格式化会产生巨量无关 diff。
- **不要在未获明确指令时 commit / push / 发版。**

## 8. Responsive Behavior（移动端版，不是网页断点）

网页 DESIGN.md 的 `480 / 768 / 1024 / 1280px` 断点、hamburger 折叠、hero 字号阶梯在这里**全部不适用**，替换为：

| 维度 | 规则 |
|---|---|
| 网格列宽 | `< 600dp` 用 `kcGridExtentPhone = 216`；`≥ 600dp` 用 `kcGridExtentTablet = 180`；断点 `kcGridCompactBreakpoint = 600`。仅适用于**封面网格**；固定尺寸的章节按钮网格（`SliverGridDelegateWithFixedHeight`）与缩略图网格（160 / 200 / 250 / 450）不随字倍率变化，不受此约束 |
| 字号缩放 | `kcGridBaseExtent(widthDp, textScale)` 跟随系统字倍率 |
| 大屏/平板 | 内容最大宽 `kcContentMaxWidth = 900`，`kcPageContentWidth()`；侧栏 `NaviPane` 换实例要重新绑定监听 |
| 分区节奏 | `kcSectionGap(context)` 在宽/紧凑布局下取 28 / 20 |
| 点击区 | ≥ `48dp`（`kcMinTapTarget`），高于网页常见的 40–44px |
| 外观 | 浅色 / 深色 / AMOLED 三套，且跟随系统 |
| 系统栏 | Android 15 边到边；阅读器沉浸时隐藏 HUD |
| 手势 | 左缘避开系统返回手势；侧滑返回用位移 + 速度双判定，不要只判位移 |

### Safe area 与系统手势区（移动端专属，网页 DESIGN.md 没有对应物）

这一节是从移动端平台规范补进来的，全部对照了现有实现，不是引入新约定：

- **不要整页套 `SafeArea`**：全站用 `context.padding.top / bottom` 显式内缩。`components/appbar.dart` 的栏高是 `56 + context.padding.top`；悬浮卡片若再借一层 `Appbar` 会重复加一段状态栏高度（`comic_page.dart` 的标题栏注释记录过这个坑）。
- **顶栏 / 弹层定位**：菜单锚点用 `kToolbarHeight + context.padding.top`；分类页、排行页、探索页的自定义头部同理用 `context.padding.top + 56`。
- **底部与键盘**：`comments_page.dart` 用 `MediaQuery.of(context).viewPadding.bottom` 而不是 `padding.bottom`——`viewPadding` 不随 IME 变化，和 `viewInsets` 各管各的，两者相加会重复避让。`glass_container.dart` 的 `edgeToEdge` 分支补底部手势区；底栏、列表尾部用 `context.padding.bottom`。
- **横屏 / 刘海 / 打孔**：左右安全区取 `MediaQuery.padding.left / right`，不要硬编码 24dp / 48dp（不同厂商挖孔尺寸不同）。
- **阅读器沉浸**：`showSystemStatusBar` 设置控制系统栏；HUD 隐藏期间用 `IgnorePointer` 保证点击穿透到翻页手势。
- **系统返回手势**：屏幕左缘 `x < 120` 不放可点元素（§7）；侧滑返回按位移 + 速度双判定。

## 9. Agent Prompt Guide

**改 UI 的标准流程**

1. 读本文件 → 读 `lib/design_tokens.dart` → 看同类页面现有实现。
2. 改动尽量只碰目标组件；用 `Kc*` / `kc*`，不要引入第二套命名体系。
3. 新增字符串 → `assets/translation.json` 三语补齐。
4. 跑完 [§10](#10-门禁与验证流程) 全部检查（含 `flutter test --no-pub` 里的 a11y guideline）；`--no-pub`，且清掉代理环境变量：
   `env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy -u ALL_PROXY -u all_proxy ...`
5. 需要实机验证时构建 arm64 debug APK 装 `emulator-5554`；`emulator` 必须后台启动。
6. **不 commit、不 push**，等明确指令。

**速查**：强调色 `kcAccentColor(context)` / 图标 `kcBrandAdaptive(context)`；标题 `kcTitleLarge` 正文 `kcBody` 辅助 `kcCaption`；卡片 `KcCard` 行 `KcListTile` 弹窗 `KcChoiceDialog`；卡片圆角 `kcCardRadius`；点击区 `kcMinTapTarget`。

**可直接用的提示词**：「按 `DESIGN.md` 改 X 页：保持三套外观（含 AMOLED 零彩色），只用 `kc*` 令牌和 `Kc*` 组件，补三语文案，改完跑 6 个门禁 + analyze。」

## 10. 门禁与验证流程

| 脚本 | 守护什么 |
|---|---|
| `tools/check_translations.py` | `.tl` 缺词条（三语 1072 键） |
| `tools/check_font_sizes.py` | 旧字号表 / 裸数字字号只减不增 |
| `tools/check_tokens.py` | 令牌体系唯一、无硬编码色扩散 |
| `tools/check_components.py` | 原生 `ListTile` / `Card` / 手写 `addListener` 只减不增 |
| `tools/check_settings_keys.py` | 被读取的 settings 键都有默认值 |
| `tools/check_webdav_merge.py` | WebDAV 合并路径 + INSERT SELECT 离线回归 |
| `test/a11y_guidelines_test.dart` | **官方 `AccessibilityGuideline` 语义树实测**：`androidTapTargetGuideline` / `labeledTapTargetGuideline` / `textContrastGuideline`，覆盖亮色、深色、AMOLED 零彩色 |

```bash
for s in tools/check_*.py; do python3 "$s" || exit 1; done
flutter analyze --no-pub lib test
flutter test --no-pub
```

`textContrastGuideline` 通过采样语义节点四角像素算对比度，对「半透明胶囊 + 相邻异色控件」会误报（把选中态红底和邻行灰字配成一对）。测试里只在**不透明纯文本**场景启用它，其余场景仍测点击区与语义标签，不要为了凑绿而放宽 guideline。

发版另需：`pubspec.yaml` version 与 `lib/foundation/app.dart` 的 `appVersion` 同步 bump（**auth 版本 `1.6.4` 永不动**）、`changelogs/v<ver>.md` 四语更新日志、commit → tag `v*` → push（push 走 gh token + 代理）。

## 11. 外部原则抽用与现状核查

只抽了 5 条抽象原则，且逐条对照了代码；核查于 2026-11-12（v1.5.23 基线）执行。

| 外部原则（Notion / Mintlify DESIGN.md） | 本项目对应实现 | 核查结果 |
|---|---|---|
| 阅读密度 / 留白节奏 | 阅读器 HUD 自动隐藏 + `IgnorePointer`；`kcSectionGap`、`kcStackSeamWidth`、`kcStackEdgeFade` | 已内建，摘要写入 §1 / §5 |
| 层级对比（完整字号阶梯 + 行高） | 7 级 `kc*` 字号 + `kcLineHeightFactor` | `check_font_sizes.py` **PASS** |
| 深色下靠表面层级而非彩色/重阴影 | `kcIsAmoled()` + 语义色退化灰 + `kcHairlineColor` | 已内建，写入 §2 / §6 |
| 最小点击区 ≥ 40–44px | `kcMinTapTarget = 48`（41 处使用），`IconButton` 依赖 Flutter 默认 48dp | **高于网页标准**；2026-11-12 起用官方 guideline 在语义树上实测，抓出并修复 `KcSwitch` 语义标签缺失，另把「孤立节点 52×34」确认为由整行点击区覆盖的有意例外（见 §12） |
| Do's / Don'ts 写具体值、写明确禁令 | 本文件 §7（全部反例来自本项目真实修过的 bug） | 本次新增 |

**明确不引入**：三栏文档布局、72–112px hero 字、marketing hero 区、CTA pill、hover 态、desktop breakpoints、任何外部品牌色板与字体。

## 12. 已知差距 / 后续可做（如实记录，未夸大）

1. **点击区门禁只覆盖核心组件**：2026-11-12 新增 `test/a11y_guidelines_test.dart`，用官方 `AccessibilityGuideline` 覆盖 `KcPillChip` / `KcListTile` / `KcCard` / `IconButton` 的亮色、深色、AMOLED 组合。实测抓出并修复一处真实缺陷：`KcSwitch` 语义节点缺标签（TalkBack 只读得到「已开启」），新增 `semanticLabel` 并给 6 个使用点补齐行标题。但 `lib/` 里 44 处自定义 `GestureDetector`、102 处 `IconButton` 仍未被 widget test 覆盖，靠抽查。
2. **两个「孤立节点 < 48dp」的有意例外**：
   - `Button.icon`：14 处调用，实测 30–36dp，集中在投票胶囊 / toast 关闭 / Appbar actions 等紧凑行；放大到 48dp 会改变既有间距节奏，需要产品决策。
   - `KcSwitch`：视觉轨道 44×26，命中区 52×34；官方 guideline 逐节点判定会报不达标，但它在真实页面里始终嵌于 48dp+ 的列表行 `InkWell`，实际可点区达标。放大组件会把 `_KcSettingTile` 的行高从 58dp 顶到 72dp。
   
   两者都在测试里**钉死当前尺寸**：谁修到 48dp，用例会红，提醒并入合规组并同步本文。
3. **间距 / 圆角不受门禁保护**：`check_tokens.py` 主要盯硬编码色和旧体系，`kcSpace*` / `kcRadius*` 仍靠自觉。
4. **空态文案未集中**：已有统一的空态组件（且与错误态区分），但「No results / No comments yet」这类文案散在各页面，未收敛成词条表。
5. **本文件自身无 CI 校验**：§0.1 YAML 与 `design_tokens.dart` 的一致性靠人工维护（`kc*` / `Kc*` 引用名可用脚本逐个核对），改令牌时记得同步本文件。
6. **`ComicSource.find(...)!` 空断言无静态门禁**：2026-11-12 审计扫到 10 处；2 处 P1 已修复 —— `models.dart` 的 `PageJumpTarget.jump()` 分类分支改为 nullable + 「未找到漫画源」提示后返回，`actions.dart` 的详情页 `comicSource` getter 改为 nullable + `_requireSource()` 操作前门控，并同步收敛 `comic_page.dart` / `thumbnails.dart` 的衍生用法（`download` / `onTapTag` / `showComments` / `starRating` / `likeOrUnlike` / 缩略图加载）。剩余 `favorite.dart` 3 处有 `hasNetwork` 门控、`parser.dart` 5 处是 JS 建源后的内部不变量。仍建议加一条只减不增的棘轮，防止新空断言回流。
7. 历史遗留（低收益，已记录）：`settings_page` 整表监听；仓库统计 TTL。

> 现状核查证据（2026-11-12）：6 个门禁全部 PASS、`flutter analyze --no-pub lib test` No issues、`flutter test --no-pub` 33/33（含 8 个 a11y guideline 用例）、翻译 `zh_CN / zh_TW / ja_JP` 各 1072 键。
