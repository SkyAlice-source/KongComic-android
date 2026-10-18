#!/usr/bin/env python3
"""字号门禁 —— 防止旧字号表继续扩散。

约定（见 lib/design_tokens.dart）：
  * 新增 / 修改样式只允许用 kc* 语义阶梯（kcTitleMain / kcAppbarTitle /
    kcTitleLarge / kcSectionTitle / kcSubtitle / kcBody / kcCaption）。
  * `ts.sNN`、`AppFontSizes.sNN`、裸数字 `fontSize: 14` 都是历史遗留，只减不增。

用法：
    python3 tools/check_font_sizes.py            # 检查是否超过基线
    python3 tools/check_font_sizes.py --list     # 列出全部违规点
    python3 tools/check_font_sizes.py --baseline # 打印当前计数，用于更新 BASELINE

退出码：0 通过；1 超过基线（说明有新增的旧表用法）。
"""

from __future__ import annotations

import os
import re
import sys
from collections import Counter

# 迁移过程中逐步下调：每清理完一批就把这里改成新的实际计数。
BASELINE = {
    "ts": 0,           # ts.sNN / AppFontSizes.sNN：已全部迁移，旧表定义也已删除
    "literal": 0,      # 裸数字 fontSize：已全部令牌化
    "kcFont": 39,      # kcFontNN 精确值：剩 kcFont13(徽章/等宽例外) + kcFont15/11/22/24
}

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")

TS_RE = re.compile(r"\b(?:ts|AppFontSizes)\.s\d+\b")
LITERAL_RE = re.compile(r"fontSize:\s*(\d+(?:\.\d+)?)\s*[,)]")
KCFONT_RE = re.compile(r"\bkcFont\d+\b")


def scan() -> tuple[Counter, list[tuple[str, int, str, str]]]:
    counts = Counter()
    hits: list[tuple[str, int, str, str]] = []
    for dirpath, _, files in os.walk(ROOT):
        for name in files:
            if not name.endswith(".dart"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, ROOT)
            for lineno, line in enumerate(open(path, encoding="utf-8"), 1):
                stripped = line.strip()
                if stripped.startswith("//"):
                    continue
                for m in TS_RE.finditer(line):
                    counts["ts"] += 1
                    hits.append((rel, lineno, "ts", m.group(0)))
                for m in LITERAL_RE.finditer(line):
                    counts["literal"] += 1
                    hits.append((rel, lineno, "literal", f"fontSize: {m.group(1)}"))
                for m in KCFONT_RE.finditer(line):
                    counts["kcFont"] += 1
                    hits.append((rel, lineno, "kcFont", m.group(0)))
    return counts, hits


def main() -> int:
    counts, hits = scan()
    if "--list" in sys.argv:
        for rel, lineno, kind, text in hits:
            print(f"{kind:8s} {rel}:{lineno}  {text}")
        print()
    if "--baseline" in sys.argv:
        print("BASELINE = " + str({k: counts[k] for k in BASELINE}))
        return 0

    print("字号使用计数：")
    failed = False
    for key, limit in BASELINE.items():
        actual = counts[key]
        mark = "OK " if actual <= limit else "FAIL"
        if actual > limit:
            failed = True
        print(f"  {mark} {key:8s} 当前 {actual:4d}  基线 {limit:4d}")
    if failed:
        print(
            "\n旧字号表用量增加了。请改用 kc* 阶梯；"
            "如果是迁移导致的下降，请更新 tools/check_font_sizes.py 的 BASELINE。"
        )
        return 1
    print("\n通过：旧字号表没有扩散。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
