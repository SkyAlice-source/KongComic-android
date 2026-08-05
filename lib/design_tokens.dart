import 'package:flutter/material.dart';

/// KongComic 设计令牌 —— 统一卡片圆角 / 描边 / 阴影 / 字号阶梯，消灭魔法数字。
///
/// 配套文档：design/kongcomic-design/kongcomic-ui-improvement-proposal.md
/// 约束：主页英雄卡片外观保持不变，这里只把散落的硬编码值收口到令牌。

// ── 圆角 ───────────────────────────────────────────────
const double kcCardRadius = 12; // 漫画卡 / 英雄卡 外圆角
const double kcCardInnerRadius = 10; // 卡内裁剪圆角
const double kcPillRadius = 999; // 胶囊 / 底栏激活态
const double kcChipRadius = 10; // 文件夹 chip / 标签

// ── 字号阶梯（对齐用户习惯，杜绝 18/20 混用）─────────────
const double kcTitleMain = 18; // 全局根页主标题（粗体）
const double kcTitleLarge = 20; // 页面级标题（如内部栏）
const double kcSubtitle = 16;
const double kcBody = 14;
const double kcCaption = 12;

// ── 层级阴影（取代各处长硬编码 black α）─────────────────
/// 统一卡片阴影：亮色用浅黑、暗色用浅白，保证暗色下投影逻辑一致。
BoxShadow kcCardShadow(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxShadow(
    color: (isDark ? Colors.white : Colors.black)
        .withValues(alpha: isDark ? 0.16 : 0.10),
    blurRadius: 8,
    offset: const Offset(0, 2),
  );
}

// ── 减弱动效 ───────────────────────────────────────────
/// 系统“减弱动效”开启时返回 true，调用方应将 >150ms 的转场降级为瞬切。
bool kcReduceMotion(BuildContext context) =>
    MediaQuery.of(context).disableAnimations;

// ── 间距（精确值令牌，覆盖散落字面量，零视觉改动）──────
const double kcSpaceXs = 4;
const double kcSpaceXxs = 6;
const double kcSpaceSm = 8;
const double kcSpaceMd = 12;
const double kcSpaceLg = 16;

// ── 圆角（精确值令牌，覆盖散落字面量，零视觉改动）──────
const double kcRadius3 = 3;
const double kcRadius4 = 4;
const double kcRadius6 = 6;
const double kcRadius8 = 8;
const double kcRadius10 = 10;
const double kcRadius11 = 11;
const double kcRadius16 = 16;
const double kcRadius18 = 18;
const double kcRadius20 = 20;
const double kcRadius22 = 22;
const double kcRadius24 = 24;
const double kcRadius32 = 32;

// ── 字号（精确值令牌，覆盖散落字面量，零视觉改动）──────
const double kcFont10 = 10;
const double kcFont11 = 11;
const double kcFont13 = 13;
const double kcFont15 = 15;
const double kcFont22 = 22;
const double kcFont24 = 24;
