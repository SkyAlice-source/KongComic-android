#!/usr/bin/env python3
"""翻译门禁 —— 发版前跑一遍，防止「中文界面冒出英文」。

检查两项：
  1. 缺口：代码里写了 `"xxx".tl` 但 translation.json 某语言没有这条 key
     （缺失会直接 fallback 成英文，正是用户反馈的「没跟语言走」）。
  2. 死词条：翻译表里有、但代码完全没用到的条目（只统计，不做删除判定 ——
     远程数据字典如 Popular / Latest 由服务端返回后走 .tl，无法静态验证）。

用法：
    python3 tools/check_translations.py           # 只报缺口，缺口为 0 时退出码 0
    python3 tools/check_translations.py --dead    # 附带列出死词条候选

退出码：0 无缺口；1 存在缺口。
"""

from __future__ import annotations

import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LIB = os.path.join(ROOT, "lib")
ASSETS = os.path.join(ROOT, "assets")
TRANS = os.path.join(ASSETS, "translation.json")

# 同时匹配单引号与双引号：'Photo View'.tl 这种写法早期统计被漏掉过。
QUOTED = r'(?:"((?:[^"\\]|\\.)*)"|\'((?:[^\'\\]|\\.)*)\')'
TL_RE = re.compile(QUOTED + r"\s*\.tl\b")
ANY_STR_RE = re.compile(QUOTED)


def _val(m: re.Match) -> str:
    a, b = m.group(1), m.group(2)
    return a if a is not None else (b if b is not None else "")


def collect() -> tuple[dict, set, set]:
    data = json.load(open(TRANS, encoding="utf-8"))
    used: dict[str, list[str]] = defaultdict(list)
    code_strings: set[str] = set()
    for dirpath, _, files in os.walk(LIB):
        for name in files:
            if not name.endswith(".dart"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, name), LIB)
            src = open(os.path.join(dirpath, name), encoding="utf-8").read()
            for m in TL_RE.finditer(src):
                used[_val(m)].append(rel)
            for m in ANY_STR_RE.finditer(src):
                code_strings.add(_val(m))
    # 注意：必须返回 dict（键 -> 出现位置列表），main 里要靠 used[k][0]
    # 取首个引用位置；早年误写成 set(used)，把 dict 压成 key 集合，
    # 第 69 行 used[k][0] 下标访问 set 直接 TypeError，门禁形同虚设。
    return data, used, code_strings


def main() -> int:
    data, used, code_strings = collect()
    langs = list(data)
    print(f"语言：{langs}  条目数：{{ {', '.join(f'{l}: {len(data[l])}' for l in langs)} }}")

    missing = {l: sorted(k for k in used if k and k not in data[l]) for l in langs}
    total_missing = sum(len(v) for v in missing.values())
    if total_missing:
        print(f"\n❌ 存在 {total_missing} 处缺口：")
        for l in langs:
            for k in missing[l]:
                print(f"   [{l}] {k[:80]!r}  ← {used[k][0] if used[k] else '?'}")
        return 1
    print("\n✅ 无缺口：所有 .tl 文案在三语中都有译文。")

    if "--dead" in sys.argv:
        dead = [k for k in data[langs[0]] if k not in used]
        no_literal = [k for k in dead if k not in code_strings]
        print(f"\n死词条：{len(dead)} 条（其中代码里无任何字面量的 {len(no_literal)} 条）")
        print("⚠️ 删除前注意：Popular / Latest / Top 等远程数据字典由服务端返回后走 .tl，")
        print("   静态扫不到，误删会让对应界面变英文。")
        for k in no_literal:
            print(f"   {k[:88]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
