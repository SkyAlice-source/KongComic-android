#!/usr/bin/env python3
"""组件门禁：原生 ListTile / M3 Card / 手写 addListener 只减不增。

设计审计（2026-10-22）指出三类「体系裂缝」：
  - P2-4  64 处原生 Material ListTile vs 已建立的 KcListTile（实际 49 处，已全部迁移）
  - P2-5  23 处 M3 Card vs token 卡片语言（实际已迁移，仅剩 KcCard 自身封装）
  - P3-3  43 处手写 addListener(initState/dispose 配对)（实际 68 处），是收藏
          角标刷新 bug 的根因模式（漏 dispose / 忘调用）；已收敛到 27 处

策略（与字号门禁一致）：把「当前数量」固化为基线，CI 里只减不增——
任何一次提交让原生 ListTile / M3 Card / 手写 addListener 数量超过基线即失败，
逼着每一次新增/迁移都朝 KcListTile / KcCard / AutoListenMixin 收敛。

计数用零宽后顾排除 KcListTile / KcCard 等自定义件，避免把 _XCard、buildCard、
KcListTile 这类误算进来。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"

# 基线（2026-10-22 迁移完成后实测）。只允许下降，回升即失败。
BASELINE_LISTTILE = 0   # 原生 ListTile 已全部迁到 KcListTile
BASELINE_CARD = 1       # 仅 KcCard 自身封装里的 1 处 Card(，新增原生 M3 Card 即违例
BASELINE_ADDLISTENER = 31  # 余下均为「动态换绑 / ImageStream / WindowListener / 单例 service」自管理，不再收敛
# 27 → 29（2026-10-23）：发现页把 TabController 的换绑收敛成 _bindController，
# 但「重建 controller 后重新挂 _onTabChanged」仍是两处必须手写的 addListener
# （controller 换了实例，AutoListenMixin 的 listen() 只在 initState 绑一次，撑不住）。
# 29 → 31（2026-10-30）：历史页 / 收藏页在 didChangeDependencies 里跟随 NaviPane
# 换实例重绑 _onPaneIndexChanged（切回本 tab 时补注入顶栏），同样属于「listenable
# 实例会变」的场景：NaviPane.of(context) 拿到的是依赖树上的状态，重建后 notifier
# 是另一个对象，initState 里绑一次会绑在废弃实例上。


def count_lib(pattern: str) -> int:
    total = 0
    for f in LIB.rglob("*.dart"):
        text = f.read_text(encoding="utf-8", errors="ignore")
        total += len(re.findall(pattern, text))
    return total


def main() -> int:
    # 零宽后顾 `(?<![\w])` 已把 KcListTile( / KcCard( 排除在外（前一个字符是
    # 标识符字符），**不要再做减法**，否则会重复扣成负数。
    listtile = count_lib(r"(?<![\w])ListTile\(")
    card = count_lib(r"(?<![\w])Card\(")
    addlistener = count_lib(r"addListener")

    rows = [
        ("原生 ListTile", listtile, BASELINE_LISTTILE),
        ("原生 M3 Card", card, BASELINE_CARD),
        ("手写 addListener", addlistener, BASELINE_ADDLISTENER),
    ]

    ok = True
    print("组件门禁（只减不增）")
    print("─" * 44)
    for name, cur, base in rows:
        delta = cur - base
        if delta > 0:
            ok = False
            flag = f"❌ +{delta} 超过基线！"
        elif delta < 0:
            flag = f"✅ -{abs(delta)}（收敛中）"
        else:
            flag = "✅ 持平"
        print(f"  {name:<16} 当前 {cur:<4} 基线 {base:<4} {flag}")

    if not ok:
        print(
            "\n❌ 有组件数量回升到基线之上。新增列表行请用 KcListTile、"
            "卡片请用 KcCard、监听请走 AutoListenMixin（listen()），不要回退。"
        )
        return 1
    print("\n✅ 组件数量未回升，规范持续收敛。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
