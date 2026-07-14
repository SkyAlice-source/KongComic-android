# KongComic 图标使用规范（v1.2.21 起生效）

> 本规范由 UI Designer 在 v1.2.21 图标统一轮次确立，所有后续开发必须遵循。

## 一、核心决策

- **唯一图标库**：统一使用 **HugeIcons（strokeRounded 线性风）**。
- **禁止混用**：不得再使用 Material Icons 的 Material 风格常量（`Icons.search_outlined`、`Icons.star` 等）或 FluentIcons。
- **渲染方式**：一律通过 `HugeIcon` widget 渲染：
  ```dart
  HugeIcon(icon: HugeIcons.strokeRoundedXxx, size: 18, color: context.colorScheme.primary)
  ```

## 二、关键事实（避免常见错误）

- `HugeIcons` 类来自 `package:hugeicons/hugeicons.dart`，已通过 `lib/components/components.dart` 全局 re-export，业务文件无需单独 import。
- `HugeIcons.strokeRoundedXxx` 的类型是 **`List<List<dynamic>>`（SVG 路径数据）**，**不是** `IconData`。
- 渲染组件是 `HugeIcon`（非 Flutter 的 `Icon`）。
- ❌ **不要写** `Icon(HugeIcons.strokeRoundedXxx)` —— `Icon.icon` 要求是 `IconData` 类型，会编译报错。
- ✅ 需要图标的地方直接用 `HugeIcon(...)` widget。

## 三、Material / Fluent → HugeIcons 映射表

本次统一已将项目中全部 42 个 Material 异类图标 + 1 个 FluentIcons 替换为如下对应：

| 原图标（禁用） | 替换为（HugeIcons strokeRounded） |
| --- | --- |
| `Icons.search_outlined` | `strokeRoundedSearch02` |
| `Icons.settings_outlined` | `strokeRoundedSettings01` |
| `Icons.explore_outlined` | `strokeRoundedCompass01` |
| `Icons.arrow_back_ios_outlined` | `strokeRoundedArrowLeft01` |
| `Icons.arrow_forward_ios` | `strokeRoundedArrowRight01` |
| `Icons.arrow_upward` | `strokeRoundedArrowUp01` |
| `Icons.arrow_downward` | `strokeRoundedArrowDown01` |
| `Icons.star` / `Icons.star_outline` / `Icons.star_border` | `strokeRoundedStar` |
| `Icons.favorite` | `strokeRoundedHeartAdd` |
| `Icons.send` | `strokeRoundedSent02` |
| `Icons.swap_horiz` | `strokeRoundedArrowLeftRight` |
| `Icons.inbox_outlined` | `strokeRoundedInbox` |
| `Icons.error_outline` | `strokeRoundedAlertCircle` |
| `Icons.image_outlined` | `strokeRoundedImage01` |
| `Icons.history_outlined` | `strokeRoundedClock01` |
| `Icons.category_outlined` | `strokeRoundedGrid` |
| `Icons.lightbulb_outline` | `strokeRoundedBulb` |
| `Icons.save` | `strokeRoundedSave` |
| `Icons.screen_lock_portrait` | `strokeRoundedScreenLockRotation` |
| `Icons.screen_lock_landscape` | `strokeRoundedRotate01` |
| `Icons.download_done_rounded` | `strokeRoundedDownload04` |
| `Icons.close` | `strokeRoundedCancel01` |
| `Icons.check` / `Icons.check_circle` | `strokeRoundedCheckmarkCircle01` |
| `Icons.alarm_on` | `strokeRoundedAlarmClock` |
| `Icons.battery_full_sharp` / `battery_6_bar` / `battery_5_bar` | `strokeRoundedBatteryFull` |
| `Icons.battery_4_bar` / `battery_3_bar` / `battery_alert_sharp` | `strokeRoundedBatteryLow` |
| `Icons.battery_2_bar` / `battery_1_bar` / `battery_0_bar` | `strokeRoundedBatteryEmpty` |
| `Icons.battery_charging_full` | `strokeRoundedBatteryCharging01` |
| `FluentIcons.chevron_right_24_regular` | `strokeRoundedArrowRight01` |

## 四、开发注意事项

1. **三元表达式 / 条件图标**：直接返回 `HugeIcon` widget，不要包在 `Icon()` 里。
   ```dart
   // ✅ 正确
   icon: cond ? HugeIcon(icon: HugeIcons.strokeRoundedArrowUp01, size: 18)
              : HugeIcon(icon: HugeIcons.strokeRoundedArrowDown01, size: 18),
   // ❌ 错误：Icon(Widget) 类型不匹配
   icon: Icon(cond ? HugeIcon(...) : HugeIcon(...)),
   ```
2. **接收方类型**：若某组件字段/变量/方法返回类型声明为 `IconData`，需改为 `Widget` 才能接收 `HugeIcon`。
3. **电池图标**：HugeIcons 无分段电量档位，已用 `BatteryFull` / `BatteryLow` / `BatteryEmpty` / `BatteryCharging01` 近似，丢失原 `Icon.shadows` 描边效果（颜色已由 `color` 控制，可接受）。
4. **新增图标**：先在 HugeIcons 常量表中检索 `strokeRoundedXxx`（包内约 5000+ 常量），找不到近似时再评估，严禁回退到 Material/Fluent。

## 五、验证标准

- `flutter analyze` 零错误零警告（未使用 import 需清理）。
- 构建时 `MaterialIcons-Regular.otf` 应被 tree-shake 至接近 0 字节（>= 99% 缩减即证明 Material 图标已清除）。
