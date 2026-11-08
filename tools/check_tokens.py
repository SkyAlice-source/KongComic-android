#!/usr/bin/env python3
"""设计令牌门禁 —— 防旧体系复活，并让裸数字 / 硬编码色只减不增。

背景（见 lib/design_tokens.dart 头部）：
  * `lib/foundation/design_tokens.dart` 的 `AppRadii` / `AppSpacing` 曾是与
    kc* 体系语义重叠的死代码，已于 v1.5.2 删除。
  * kcRadius11 / kcChipRadius 是 kc* 体系内部的死 token，同样已删除。

两层检查：
  A. 硬失败：上述死符号在全库（design_tokens.dart 的说明性注释除外）不得出现。
  B. 棘轮（ratchet）：历史遗留的裸圆角 / 裸间距 / 硬编码色 / 算式字号。
     存量计入 BASELINE，**新增一处即失败**；每清理一批就把 BASELINE 调低。
     这样门禁现在就能拦住退化，不必先完成全量迁移。
     · bare_radius   —— BorderRadius.circular(12) 这类应写 kcCardRadius
     · bare_spacing  —— EdgeInsets.all(8) 这类应写 kcSpaceSm / kcSpaceMd
     · color_literal —— 非 design_tokens.dart 里的 Color(0x..) / Colors.xxx
                        （Colors.white/black/transparent/grey 等中性色豁免）
     · fontsize_expr —— fontSize: kcTitleLarge - 7 这类算式字号

用法：
    python3 tools/check_tokens.py             # 检查
    python3 tools/check_tokens.py --list     # 列出全部棘轮命中点
    python3 tools/check_tokens.py --baseline # 打印当前计数，用于更新 BASELINE

退出码：0 通过；1 出现死符号或存量超过基线。
"""

from __future__ import annotations

import os
import re
import sys
from collections import Counter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")

# 死类（旧体系）—— 除 design_tokens.dart 头部注释外不得再出现。
DEAD_CLASSES = ["AppRadii", "AppSpacing"]
# 死 token（kc* 内部）—— 已删除定义，全库不得出现。
DEAD_TOKENS = ["kcRadius11", "kcChipRadius"]

# design_tokens.dart 头部允许出现上述名字（仅作说明性注释）。
ALLOWED_FILE = os.path.join(ROOT, "design_tokens.dart")

# 迁移过程中逐步下调：每清理完一批就把这里改成新的实际计数。
BASELINE = {
    # 第 ④ 批把封面 9 / 9.5 / 20 / 12 / 2 等裸圆角全部收口到 kcRadius*
    # 与 kcCardRadius，裸圆角清零。
    "bare_radius": 0,
    # 第 ④ 批批量替换 208 行 EdgeInsets 裸数字为 kcSpace*（559 → 180）。
    # 方案 E/F 把设置 / 分类 / 发现 / 速搜 / 追更 / 收藏夹选择弹窗的
    # 28 / 20 / 16 / 10 / 5 / 3 与分区标题内缩收口到 kcRowInsetH 等令牌，
    # 再降 180 → 165。余下 165 处是阶梯外精确值与浮点表达式，
    # 没有对应令牌，先留在棘轮里；新增一处仍会失败。
    "bare_spacing": 162,
    # 剩下 86 处里绝大多数在 main.dart 的 getTheme —— 那是主题本身的
    # 「唯一事实来源」，不是散落的组件层硬编码色，不迁移。
    # 2026-11-09 UI 一致性审计：评论点赞/点踩、追更「查看更多」、阅读器定时器
    # 与低电量图标从 Colors.red/blue/green 收口到 kcBrandAdaptive / kcInfoColor /
    # kcStatusColor / colorScheme.error，86 → 77。
    "color_literal": 77,
    # kcTitleLarge - 7 / kcCaption + 1 换成 kcFont15 / kcFont13，算式清零。
    "fontsize_expr": 0,
}

RADIUS_RE = re.compile(r"\bcircular\(\s*(\d+(?:\.\d+)?)\s*\)")
INSETS_RE = re.compile(
    r"\bEdgeInsets(?:Directional)?\.(?:all|only|symmetric|fromLTRB)\(([^)]*)\)"
)
PLAIN_NUM_RE = re.compile(r"(?<![\w.])\d+(?:\.\d+)?(?![\w.])")
COLOR_LITERAL_RE = re.compile(
    r"\bColor\(\s*0x[0-9A-Fa-f]{6,8}\b|\bColor\.from(?:ARGB|RGBO)\("
)
COLOR_NAMED_RE = re.compile(r"\bColors\.([A-Za-z][A-Za-z0-9]*)")
# 无色相的中性色不算「绕过 ColorScheme 契约」。
NEUTRAL_COLORS = {
    "white", "black", "transparent", "grey", "white10", "white12",
    "white24", "white30", "white38", "white54", "white60", "white70",
    "black12", "black26", "black38", "black45", "black54", "black87",
}
FONTSIZE_EXPR_RE = re.compile(
    r"fontSize:\s*(?:kc\w+|ts\.s\d+|AppFontSizes\.s\d+)\s*[+\-]\s*\d+"
)


def scan():
    class_hits: list[tuple[str, int, str]] = []
    token_hits: list[tuple[str, int, str]] = []
    counts: Counter = Counter()
    ratchet_hits: list[tuple[str, int, str, str]] = []
    for dirpath, _, files in os.walk(ROOT):
        for name in files:
            if not name.endswith(".dart"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, ROOT)
            allowed = path == ALLOWED_FILE
            for lineno, line in enumerate(open(path, encoding="utf-8"), 1):
                stripped = line.strip()
                is_comment = stripped.startswith(("//", "/*", "*"))

                # ── A. 死符号（原语义：仅豁免 design_tokens.dart 的注释行）──
                if not (allowed and is_comment):
                    for cls in DEAD_CLASSES:
                        if re.search(r"\b" + re.escape(cls) + r"\b", line):
                            class_hits.append((rel, lineno, line.strip()))
                    for tok in DEAD_TOKENS:
                        if re.search(r"\b" + re.escape(tok) + r"\b", line):
                            token_hits.append((rel, lineno, line.strip()))

                # ── B. 棘轮：跳过唯一事实来源文件与注释 ──
                if allowed or is_comment:
                    continue
                for m in RADIUS_RE.finditer(line):
                    if float(m.group(1)) == 0:
                        continue
                    counts["bare_radius"] += 1
                    ratchet_hits.append((rel, lineno, "bare_radius", m.group(0)))
                for m in INSETS_RE.finditer(line):
                    for n in PLAIN_NUM_RE.finditer(m.group(1)):
                        if float(n.group(0)) == 0:
                            continue
                        counts["bare_spacing"] += 1
                        ratchet_hits.append(
                            (rel, lineno, "bare_spacing", m.group(0)[:70])
                        )
                for m in COLOR_LITERAL_RE.finditer(line):
                    counts["color_literal"] += 1
                    ratchet_hits.append((rel, lineno, "color_literal", m.group(0)))
                for m in COLOR_NAMED_RE.finditer(line):
                    if m.group(1) in NEUTRAL_COLORS:
                        continue
                    counts["color_literal"] += 1
                    ratchet_hits.append((rel, lineno, "color_literal", m.group(0)))
                for m in FONTSIZE_EXPR_RE.finditer(line):
                    counts["fontsize_expr"] += 1
                    ratchet_hits.append((rel, lineno, "fontsize_expr", m.group(0)))
    return class_hits, token_hits, counts, ratchet_hits


def main() -> int:
    class_hits, token_hits, counts, ratchet_hits = scan()
    if "--list" in sys.argv:
        for rel, lineno, kind, text in ratchet_hits:
            print(f"{kind:15s} {rel}:{lineno}  {text}")
        return 0
    if "--baseline" in sys.argv:
        print("BASELINE = " + str({k: counts[k] for k in BASELINE}))
        return 0

    failed = False
    if class_hits:
        failed = True
        print("❌ 发现已删除的旧令牌类（AppRadii / AppSpacing）残留：")
        for rel, lineno, text in class_hits:
            print(f"   {rel}:{lineno}  {text}")
        print("   设计令牌唯一来源是 lib/design_tokens.dart 的 kc* 体系，请勿复活旧体系。")
    if token_hits:
        failed = True
        print("❌ 发现已删除的死 token（kcRadius11 / kcChipRadius）残留：")
        for rel, lineno, text in token_hits:
            print(f"   {rel}:{lineno}  {text}")

    print("历史遗留用量（棘轮，只减不增）：")
    for key, limit in BASELINE.items():
        actual = counts[key]
        mark = "OK " if actual <= limit else "FAIL"
        if actual > limit:
            failed = True
        print(f"  {mark} {key:15s} 当前 {actual:4d}  基线 {limit:4d}")
    if failed:
        print(
            "\n有死符号残留，或历史遗留用量增加了。\n"
            "  · 新代码请用 kc* 令牌 / Theme.of(context).colorScheme；\n"
            "  · 清理一批存量后，用 `python3 tools/check_tokens.py --baseline` 下调 BASELINE；\n"
            "  · `--list` 可列出全部命中点。"
        )
        return 1
    print("\n✅ 令牌体系干净：无旧体系残留，裸数字 / 硬编码色没有扩散。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
