# KongComic-android 问题清单（v1.3.11 / commit 650b055）

排查日期：2026-10-13  
修复进度（2026-10-13 第二轮）：

- P1：P1-1 ✅ / P1-2 ✅ / P1-4 ✅ / P1-3 ⏸ 前置条件未满足（见下）
- P2：P2-4 ✅ / P2-5 ✅ / P2-6 ✅ / P2-8 ✅；P2-1、P2-2、P2-3、P2-7 未动（改动面大/风险高，需单独排期）
- Issue #3 ✅ 已修（横屏导航占空间，见第 4 节）

> 第二轮改动涉及 Gradle / ProGuard / Manifest，必须以 **release 真编译**验收（debug 不跑 R8，验证不到 ProGuard 收窄）。  
> 排查方式：工具链探测 → `flutter analyze` → release 真编译 → 静态审计（i18n / 资源 / 泄漏 / 权限 / 密钥 / 返回键适配）→ 与线上 Release 交叉验证

## 0. 环境（本机命令基线）

```bash
export PATH="<flutter-sdk>/bin:$PATH"
export JAVA_HOME=<jdk-17-home>
cd <project-root>

flutter analyze                      # 静态分析
flutter build apk --release --split-per-abi   # release 真编译（本机约 23 分钟）
```

- Flutter 3.44 / Dart 3.8；JDK 17（另有 21/26）
- Android SDK：`/opt/homebrew/share/android-commandlinetools`（已有 android-36 + build-tools 36.0.0）
- `android/local.properties` 已存在（sdk.dir 已配），无需重建
- 签名：`android/key.jks` + `android/key.properties`（均已在 `.gitignore:52-53`，未被 git 跟踪 ✅）

## 1. 结论：整体健康

| 检查项                | 结果                                                                                         |
| ------------------ | ------------------------------------------------------------------------------------------ |
| `flutter analyze`  | **No issues found**（0 error / 0 warning）                                                   |
| release 真编译（3 ABI） | **成功**（arm64 18.4MB / armv7 18.0MB / x86_64 18.8MB）                                        |
| CI（最近 5 次）         | **全部 success**（v1.3.7 ~ v1.3.11）                                                           |
| 线上 Release v1.3.11 | 4 个 APK + sha256 校验块完整                                                                     |
| i18n 三语对齐          | zh_CN / zh_TW / **ja_JP** 各 995 条，**0 缺失、0 非对称**                                           |
| 未翻译的 `.tl` key     | 0                                                                                          |
| 签名密钥泄漏             | 无（`.jks`/`key.properties` 已忽略且未跟踪）                                                         |
| 硬编码 token/密钥       | 无                                                                                          |
| Android 16 返回键适配   | **正确**：`WillPopScope` 0 处、`PopScope` 8 处、Manifest 已声明 `enableOnBackInvokedCallback="true"` |
| App Link 配置        | 合规（`https` scheme + 合法 host）                                                               |
| 异常兜底               | 4 层：`FlutterError.onError` + `runZonedGuarded` + Sentry + `ErrorWidget.builder`            |
| 仓库同步               | 工作区干净，与 `origin/main` 一致，tag `v1.3.11` = pubspec `1.3.11+172`                              |
| README 截图          | 仍为隐藏状态（\`\` 注释包裹）                                                                          |

> v1.3.11 本身已做过一轮「全量审查修复」（见 `changelogs/v1.3.11.md`），修掉了灰屏、批量更新、源仓库更新错位、十余处崩溃。以下为**残留/新增**问题。

## 2. P1 — 建议尽快修

### [x] P1-1 `PageController` 未 dispose（内存泄漏）— ✅ 已修

- 文件：`lib/pages/image_favorites_page/image_favorites_photo_view.dart:19`（`late PageController controller`）、`:40`（初始化）
- 问题：整个文件没有任何 `dispose()` 调用，页面关闭后 controller 及其动画监听不释放
- 修复：在对应 State 增加
  ```dart
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
  ```
- 验收：`grep -n 'dispose' lib/pages/image_favorites_page/image_favorites_photo_view.dart` 应有输出

### [x] P1-2 `TextEditingController` 未释放（×2）— ✅ 已修

- 文件：`lib/pages/settings/explore_settings.dart:146`、`:291`
- 问题：在 `StatefulBuilder` 外创建，对话框关闭后从不 `dispose()`，每次打开泄漏一个
- 修复：改为在 `StatefulBuilder` 的 `dispose` 回调中释放，或在 dialog 关闭的 `pop` 前调用 `controller.dispose()`

### [ ] P1-3 Kotlin Gradle Plugin (KGP) 弃用 — ⏸ **当前不可修，前置条件未满足**

- 现象：release 构建告警
  > Future versions of Flutter will fail to build if your app uses plugins that apply KGP
- 涉及插件（10 个）：`device_info_plus`、`flutter_file_dialog`、`flutter_memory_info`、`flutter_qjs`、`flutter_saf`、`package_info_plus`、`sentry_flutter`、`share_plus`、`wakelock_plus`、`workmanager_android`
- 另有主工程 KGP 告警：`android/app/build.gradle` 应用了 Kotlin Gradle Plugin

**为什么现在不能改**（已查官方迁移指南确认）：

- built-in Kotlin **要求 AGP 9+**，本项目 AGP = **8.11.1**
- 启用 `android.builtInKotlin=true` **要求 Flutter 3.47+**，当前 Flutter = **3.44.0**
- 迁移动作是「移除 `kotlin-android` 插件 + `kotlinOptions` 块」，但 app 有 `MainActivity.kt`（550 行原生代码），在 AGP 8 下移除后 **Kotlin 源码无法编译 → 构建直接失败**
- 当前 `android/gradle.properties` 已有 `android.builtInKotlin=false` 与 `android.newDsl=false`（Flutter 3.44 自动写入），处于 legacy KGP 兼容模式，**现在不会构建失败**

**到什么时机再修**（前置条件全部满足后）：

1. 升级到 Flutter 3.47+（`flutter upgrade`）
2. AGP 升到 9+：`android/settings.gradle` 的 `com.android.application` 版本
3. 按 [官方指南](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers) 改 `android/app/build.gradle`：移除 `id "kotlin-android"` 与 `kotlinOptions { jvmTarget }`，改为
   ```groovy
   kotlin {
       compilerOptions {
           jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
       }
   }
   ```
4. `android/gradle.properties` 置 `android.builtInKotlin=true`
5. 10 个插件中 `flutter_qjs`、`flutter_saf` 是**本地路径包**（`packages/`），届时可自行按 [plugin author 指南](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors) 迁移；其余 8 个需等上游发版（可用官方 issue 模板催作者）
6. 验收：`flutter build apk --release` 不再出现 KGP WARNING

### [x] P1-4 阅读进度角标硬编码中文 — ✅ 已修

- 文件：`lib/components/comic.dart:209-210`
  ```dart
  "第${history.ep}话 · ${(progress * 100).toInt()}%"   // 英/日设备也显示中文
  "第${history.ep}话"
  ```
- 实际修法（**复用已有 key，不新建**）：翻译表里本来就存在 `Ep @ep` 与 `Ep @ep·@progress%`，只是代码没用
  ```dart
  final text = hasProgress
      ? "Ep @ep·@progress%".tlParams({
          'ep': history.ep,
          'progress': (progress * 100).toInt(),
        })
      : "Ep @ep".tlParams({'ep': history.ep});
  ```
- **顺带发现并修复的隐患**：`ja_JP` 里这两个 key 的值是**英文原文**（`"Ep @ep": "Ep @ep"`）——key 存在但未本地化，日语设备会显示 "Ep 12"。已补为「第@ep話」/「第@ep話·@progress%」
- 教训：i18n 检查**不能只查 key 是否缺失**，还要查 value 是否等于英文原文（存在但未翻译）。这类问题 key 对称性检查发现不了
- 验收：切换系统语言为 English/Japanese 后角标跟随语言

## 3. P2 — 技术债 / 合规

### [ ] P2-1 `MANAGE_EXTERNAL_STORAGE` 权限（Google Play 上架风险）

- `android/app/src/main/AndroidManifest.xml:3`
- 该权限受 Play 政策严格限制（一般仅限文件管理器/备份类应用），漫画类应用申请可能被拒
- 建议：改用 SAF / MediaStore；确需保留则准备 Play 声明

### [ ] P2-2 依赖过时（83 个包有新版本但不兼容当前约束）

- `flutter pub outdated` 可查看明细；建议分批升级，重点关注 `sentry_flutter`、`dio`、`flutter_inappwebview`

### [ ] P2-3 测试覆盖极低

- `test/` 下仅 `share_test.dart` 1 个文件
- 建议：为核心链路补测试（翻译表加载容错、源更新、版本比较）

### [x] P2-4 ProGuard 规则过宽 — ✅ 已修

- `android/app/proguard-rules.pro`：`-keep class com.KongComic.reader.** { *; }` 等于自身代码完全不混淆，削弱 release 瘦身效果
- 已收窄为：
  ```proguard
  -keep class com.KongComic.reader.MainActivity { *; }
  -keepclassmembers class com.KongComic.reader.** { native <methods>; }
  -keep class com.dexterous.flutterlocalnotifications.** { *; }
  ```
- 依据：全仓库自定义原生类只有 `MainActivity.kt` 一个（550 行），无 `external fun`/JNI；`MethodChannel`/`EventChannel` 走字符串 channel name，不依赖类名反射，可被安全混淆
- **收益有限**（只有一个自有类），主要价值是防止以后新增的类被无条件全保留；顺带显式保留 `flutter_local_notifications` 的广播回调类（不在 `io.flutter.plugins` 包下，收窄后不再被原规则覆盖）
- Manifest 里声明的 Activity/Receiver/Provider 由 AGP 自动保留，无需手写
- 验收：release 构建通过 + 冷启动/通知点击无 `ClassNotFoundException`

### [x] P2-5 `allowBackup` 未显式关闭 — ✅ 已修

- Manifest 未声明 `android:allowBackup`，默认为 `true`，数据可被 `adb backup` 导出
- 已加 `<application android:allowBackup="false">`。只关这一项、不加 `dataExtractionRules`：Android 12+ 在 `allowBackup=false` 时本就忽略备份规则，多写一个 `@xml/data_extraction_rules` 反而要新增资源文件（无收益）。
- ⚠️ 副作用：换机时无法靠系统备份恢复本地收藏/历史（App 自身若有导出/同步功能不受影响）

### [x] P2-6 Groovy 空格赋值语法弃用（×11）— ✅ 已修

- `android/app/build.gradle`：`ndkVersion "..."`、`useLegacyPackaging true`、`enable true`、`universalApk true`、`shrinkResources true`、`signingConfig ...`、`storeFile file(...)` 等
- Gradle 10.0 将移除；已全部改为 `xxx = value` 形式
- 未改（它们是**方法调用**不是赋值，AGP 官方写法）：`proguardFiles ...`、`abiFilters "..."`、`include '...'`、`reset()`

### [ ] P2-7 超大源文件（维护风险）

- `lib/pages/comic_source_page.dart` 2631 行、`lib/components/comic.dart` 2468 行、`lib/pages/reader/images.dart` 1986 行、`lib/pages/reader/scaffold.dart` 1952 行
- 建议逐步拆分

### [x] P2-8 更新说明兜底文案硬编码 — ✅ 已修

- `lib/utils/app_update.dart`：原 `_defaultReleaseNotes` 是「中文 + 英文」双段硬编码，英/日设备也会看到中文
- 改为走翻译表：`"This update includes bug fixes and UX improvements.".tl`
- 三语已补齐（现各 **996** 条，0 缺失 / 0 非对称）：
  - zh_CN 本次更新包含若干问题修复与使用体验优化。
  - zh_TW 本次更新包含若干問題修正與使用體驗優化。
  - ja_JP 今回のアップデートでは、不具合の修正と使い勝手の改善を行いました。
- 仅在 GitHub Release 无描述时触发（当前 `changelogs/` 齐全，几乎不会用到），优先级低

## 4. 待办 / 外部反馈

### [x] 开放 Issue #3（Enhancement）— ✅ 已修

- 「全屏阅读时，左侧这个边栏是否能自动隐藏？」（2026-10-08）

**定位到的真正原因**（不是阅读器自己的工具栏）：

- 外层导航框架 `NaviPane`（`lib/components/navigation_bar.dart`）按**宽度**分档（`changePoint = 600`）：宽度 > 600 显示左侧栏（折叠 72dp / 展开 224dp），否则显示悬浮底栏
- **横屏手机宽度普遍 > 600**，于是阅读时左侧那条侧栏一直常驻，挤占漫画画面 —— issue 里说的「左侧边栏」就是它
- 阅读器自己的底栏（`_ReaderScaffold.buildBottom`）在横屏下也是两行 100dp，横屏竖向空间本就紧张，同样吃掉一大截

**修复（两处）**：

1. `NaviPaneState` 新增「收起导航框架」能力：新增 `_chromeController`（200ms），`hideProgress` 0→1 时左侧栏整条滑出屏幕、主视图 `left` 补满全宽；用 **请求计数** `_chromeHideRequests` 而不是 bool —— 路由 replace（新页面 init 早于旧页面 dispose）时 bool 会被旧页面误刷回「显示」
   - Reader 侧：`_ReaderState.initState` 里 `addPostFrameCallback` 后 `findAncestorStateOfType<NaviPaneState>()?.setChromeHidden(true)`，`dispose` 里恢复；找不到 NaviPane（独立路由打开）时静默跳过
   - 嵌套两层 `AnimatedBuilder`（外层监听收起动画、内层监听宽度分档动画），不用 `Listenable.merge` 以免每次 build 新建 Listenable
2. 阅读器底栏横屏改单行：新增 `kLandscapeBottomBarHeight = 56.0`（竖屏仍 100）；`bottomBarHeight` getter 按 orientation 取值，`build` 的收起位移与 `gesture.dart` 的点击区域判定**都改成用它**（用常量会导致横屏下底栏上方空白被误判为工具栏、吞掉翻页点击）
   - 顺手把两处翻章按钮抽成 `_chapterJumpButton(bool forward)`、页码胶囊抽成 `_buildPageChip`，竖屏横屏共用

**未实测**：本机无横屏设备/模拟器（adb 设备列表为空），仅静态验证（analyze + 构建）。需要真机或模拟器横屏确认：①进阅读器左侧栏滑出、退出滑回；②横屏底栏单行不溢出、点击翻页正常。

### 真机横屏实测后的追加修复（2026-10-13）

用户实测截图（详情页横屏 2731×1126 / 阅读器横屏 2800×1272）用 PIL 逐列三态分类（白 255 / App 底色 249,248,254 / 内容）分析：

- 阅读器横屏里 `246..2694` 整块是阅读器底色、**零图标 → 左侧栏确实收起了**；漫画页 `1025..1915` **正好居中在 `246..2694` 里（中心 1470 完全吻合）**。
- 但左边仍有一条 `0..245` 纯白：**宽 ≈70dp，与折叠侧栏 72dp 几乎等宽**，看起来就像"没收干净"。真因是 `NaviPane.build` 横屏时的 `sideInsets = max(viewPadding, systemGestureInsets)`：实测左 ≈70dp（刘海/挖孔）、右 ≈30dp（手势区），整块 shell（含阅读器）被挤在安全区里，阅读器相对整屏偏右 70px。
- 反推 dpr 的办法（可复用）：详情页「首页」高亮块 = `_SideNaviWidget` 的 `AnimatedContainer` = 48×38dp，实测 163×132px → **dpr ≈ 3.45**；再由"图标中心 370px = O+W/2、右边框 497px = O+W"解出栏宽 72dp、偏移 70dp。

**追加修复（3 处）**：

1. `navigation_bar.dart`：`sideInsets` 计算挪进 `AnimatedBuilder` 内，用 `EdgeInsets.lerp(fullInsets, EdgeInsets.zero, hideProgress)` —— 收起导航时安全区留白同步收缩到 0，阅读器接管整屏（`hideProgress` 只在动画里变化，放在 `build` 顶部读值不会触发重建）。
2. **`NaviPaneState` 的 mixin 从 `SingleTickerProviderStateMixin` 改成 `TickerProviderStateMixin`** —— 上一轮加第二个 `AnimationController(vsync: this)` 时漏了这点：debug 构建首帧直接抛 `SingleTickerProviderStateMixin is already used as a TickerProvider`，release 因 assert 关闭才没炸（两个 Ticker 互踩、旧 Ticker 不会被 dispose）。
3. 阅读器沉浸模式：`SystemUiMode.immersive` → `immersiveSticky`，并把系统栏设置抽成 `_ReaderState._applySystemUiMode()`，在 `initState` 与 **`didChangeDependencies`（旋转）** 各下发一次 —— 普通 `immersive` 不是粘性的，旋转后会被系统重置、状态栏冒出来压在漫画上（默认设置是隐藏，属回退）。


## 5. 复现本次排查的验证命令

```bash
# 1) 静态分析（应为 No issues found）
flutter analyze

# 2) i18n 三语对称性（应为 0 缺失 / 0 非对称）
python3 - << 'PY'
import json
d = json.load(open("assets/translation.json"))
cn, tw, ja = d["zh_CN"], d["zh_TW"], d["ja_JP"]
print("counts:", len(cn), len(tw), len(ja))
print("zh_CN/zh_TW 差异:", len(set(cn) ^ set(tw)))
print("ja_JP 相对 zh_CN 缺失:", len(set(cn) - set(ja)))
PY

# 3) 返回键适配（WillPopScope 应为 0）
grep -rc 'WillPopScope' lib/ | grep -v ':0' || echo "WillPopScope: 0 ✅"

# 4) Controller 泄漏（修完 P1-1/P1-2 后应不再列出这两个文件）
grep -n 'dispose' lib/pages/image_favorites_page/image_favorites_photo_view.dart
grep -n 'dispose' lib/pages/settings/explore_settings.dart

# 5) release 真编译（同时观察 KGP 告警是否消失）
flutter build apk --release --split-per-abi 2>&1 | grep -E 'KGP|Built|FAIL'
```

### 第二轮改动后的实跑结果（2026-10-13）

| 检查项                | 结果                                                                                                              |
| ------------------ | --------------------------------------------------------------------------------------------------------------- |
| `flutter analyze`  | **No issues found**                                                                                             |
| release 真编译（3 ABI） | **成功**：arm64 18.4MB / armv7 18.0MB / x86_64 18.7MB                                                              |
| KGP 弃用告警           | 仍在（P1-3，预期）                                                                                                     |
| ProGuard 收窄生效      | ✅ `mapping.txt` 中 `com.KongComic.reader.MainActivity` 类名保留，其内部类/lambda/`VolumeListen` 已混淆为 `c1.*`（旧规则下这些全部无脑保留） |
| `allowBackup` 落盘   | ✅ `aapt2 dump xmltree AndroidManifest.xml` → `allowBackup(0x01010280)=false`                                    |
| 翻译打包               | ✅ APK 内 `translation.json` 三语各 **996** 条，兜底更新说明三语齐全，ja_JP 角标为「第@ep話」                                            |
| 运行时（横屏）            | ❌ 未实测 —— 无 adb 设备/模拟器                                                                                           |

验收横屏改动需要的最小操作：起一个横屏模拟器（或平板/折叠屏设备），  
① 打开任意漫画 → 左侧导航应滑出、漫画占满全宽，返回后滑回；  
② 阅读中点一下画面 → 底部工具条应为单行（56dp）而非两行；  
③ 在底栏上方空白处点击应仍能正常翻页（验证 `bottomBarHeight` 同步生效）。


## 6. 排查中已排除的「假阳性」（勿重复修）

- `loading.dart` 中的 `未登录/请登录/需要登录` 等中文：是**匹配源站返回的中文错误信息**的判定字符串，不是 UI 文案；UI 输出走 `"Login required".tl` ✅
- `tags_translation.dart` / `models.dart` 的中文：标签与字段默认名，非 UI 文案 ✅
- README 的 `<img src="doc/Screenshot_*">`：已被 \`\` 注释包裹，**仍是隐藏状态** ✅
- async 后 `context` 缺 `mounted` 检查的 31 处扫描候选：抽样验证多为误报（`_remove` await 后仅用返回值、`loginWithWebview` await 后不再用 context）；确有风险需逐个人工确认，不建议批量改
- 本地 release APK 与线上 sha256 不一致：因本地用 `key.jks` 签名且未传 `SENTRY_DSN`、CI 用 secret keystore 并注入 DSN，属**预期差异**；App 更新校验使用 CI 写入的 sha256，与 CI 产物自洽 ✅
- `yaml` 依赖看似未被引用于 `lib/`：实际由 `packages/flutter_to_debian`（Linux 打包）使用 ✅
