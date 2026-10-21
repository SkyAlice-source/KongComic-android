#!/usr/bin/env python3
"""设计令牌门禁 —— 防止「第二套令牌体系」复活。

背景（见 lib/design_tokens.dart 头部）：
  * `lib/foundation/design_tokens.dart` 的 `AppRadii` / `AppSpacing` 曾是与
    kc* 体系语义重叠的死代码，已于 v1.5.2 删除。
  * kcRadius11 / kcChipRadius 是 kc* 体系内部的死 token，同样已删除。

本脚本断言这两类「不应再出现」的符号确实不再出现：
  1. `AppRadii` / `AppSpacing` —— 全库除 design_tokens.dart 自身注释外不得出现。
  2. `kcRadius11` / `kcChipRadius` —— 全库不得出现（已无定义）。

退出码：0 通过；1 出现违禁符号。
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")

# 死类（旧体系）—— 除 design_tokens.dart 头部注释外不得再出现。
DEAD_CLASSES = ["AppRadii", "AppSpacing"]
# 死 token（kc* 内部）—— 已删除定义，全库不得出现。
DEAD_TOKENS = ["kcRadius11", "kcChipRadius"]

# design_tokens.dart 头部允许出现上述名字（仅作说明性注释）。
ALLOWED_FILE = os.path.join(ROOT, "design_tokens.dart")


def scan() -> tuple[list[tuple[str, int, str]], list[tuple[str, int, str]]]:
    class_hits: list[tuple[str, int, str]] = []
    token_hits: list[tuple[str, int, str]] = []
    for dirpath, _, files in os.walk(ROOT):
        for name in files:
            if not name.endswith(".dart"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, ROOT)
            allowed = path == ALLOWED_FILE
            for lineno, line in enumerate(open(path, encoding="utf-8"), 1):
                stripped = line.strip()
                # 注释行在允许文件里豁免（说明性文字）。
                if allowed and stripped.startswith("//"):
                    continue
                for cls in DEAD_CLASSES:
                    if re.search(r"\b" + re.escape(cls) + r"\b", line):
                        class_hits.append((rel, lineno, line.strip()))
                for tok in DEAD_TOKENS:
                    if re.search(r"\b" + re.escape(tok) + r"\b", line):
                        token_hits.append((rel, lineno, line.strip()))
    return class_hits, token_hits


def main() -> int:
    class_hits, token_hits = scan()
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
    if failed:
        return 1
    print("✅ 令牌体系干净：无 AppRadii/AppSpacing，无 kcRadius11/kcChipRadius。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
