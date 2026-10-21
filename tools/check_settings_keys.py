#!/usr/bin/env python3
"""settings 键门禁 —— 防止「新增开关漏写默认值」再次引发崩溃。

历史坑：v1.5.0 引入 `autoUpdateSourcesEnabled` 漏写进 `Settings._create()` 默认值表，
老用户升级后设置页读 `bool v = settings[k]` 因取到 null 直接崩溃
（`type 'Null' is not a subtype of type 'bool'`）。当时全靠纪律兜底，没有机制。

本脚本把「代码里读到的字面量 settings 键」与「默认值表里声明的键」做 diff：
  * 代码用到、但默认值表没有的键 → 失败（就是当年那个坑）。
  * 默认值表有、但代码完全没用到的键 → 仅提示（可能是死配置，不阻断）。

用法：python3 tools/check_settings_keys.py
退出码：0 通过；1 存在「用到却无默认值」的键。
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
APPDATA = os.path.join(ROOT, "lib", "foundation", "appdata.dart")
LIB = os.path.join(ROOT, "lib")

# 默认值表：`final _data = <String, dynamic>{ ... };`
_DATA_START = "final _data = <String, dynamic>{"
# 字面量读取：`appdata.settings['key']` 或 `appdata.settings["key"]`
USED_RE = re.compile(r"appdata\.settings\[(['\"])([^'\"]+)\1\]")
# 默认值表内的键：`'key':` 或 `"key":`
KEY_RE = re.compile(r"""['"]([^'"]+)['"]\s*:""")

# 这些键是「运行时动态写入 / 迁移遗留」键，按设计不进 _data 默认值表，
# 且读取处都已做 null 安全处理（as X? ?? 默认 / == true），不会触发
# 当年 `bool v = settings[k]` 的 Null 崩溃坑，故从门禁中豁免。
ALLOWLIST = {
    "followUpdatesFolder",        # 旧版单文件夹设置，启动迁移后写 null 淘汰，非持久设置
    "debug",                     # 调试开关，读取处用 `== true` 做了 null 安全
    "comicCategories",           # 漫画分类映射，运行时动态读写（as Map? ?? {}）
    "comicSourceSeededDefaults",  # 已播种源默认列表，运行时动态写入（as List? ?? []）
    "sourceCatalogOrder",         # 源目录排序，运行时动态读写
}


def read_defaults() -> set[str]:
    src = open(APPDATA, encoding="utf-8").read()
    start = src.index(_DATA_START)
    # 从起始位置找到第一个闭合 `};`（默认值表内无嵌套 `};`）。
    end = src.index("};", start)
    block = src[start:end]
    return {m.group(1) for m in KEY_RE.finditer(block)}


def read_used() -> set[str]:
    used: set[str] = set()
    for dirpath, _, files in os.walk(LIB):
        for name in files:
            if not name.endswith(".dart"):
                continue
            src = open(os.path.join(dirpath, name), encoding="utf-8").read()
            for m in USED_RE.finditer(src):
                used.add(m.group(2))
    return used


def main() -> int:
    defaults = read_defaults()
    used = read_used()

    missing = sorted(k for k in used if k not in defaults and k not in ALLOWLIST)
    dead = sorted(k for k in defaults if k not in used)

    print(f"默认值表键数：{len(defaults)}   代码用到的字面量键数：{len(used)}")

    if missing:
        print(f"\n❌ {len(missing)} 个键被代码读取，但默认值表没有声明（升级用户会崩溃）：")
        for k in missing:
            print(f"   {k!r}")
        print("\n请在 lib/foundation/appdata.dart 的 _data 表里补上这些键的默认值。")
        return 1

    print("\n✅ 所有被读取的 settings 键都有默认值，无「用到却无默认」的坑。")
    if dead and "--dead" in sys.argv:
        print(f"\nℹ️ {len(dead)} 个默认值表键未被代码字面量读取（可能是死配置，仅供参考）：")
        for k in dead:
            print(f"   {k!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
