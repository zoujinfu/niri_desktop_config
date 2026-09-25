#!/usr/bin/env python3
"""waybar 工作区模块：每次被调用时直接查询 niri IPC，实时渲染。

waybar 以 interval:1 调用本脚本，因此任何工作区切换都只会滞后约 1 秒，
不依赖后台事件守护进程，也不会出现缓存过期导致的“切区不更新”问题。
"""

import json
import subprocess

# Catppuccin Mocha 配色（与旧版保持一致）
ACCENT = "#89b4fa"
ACCENT_BG = "#313244"
IDLE = "#585b70"
IDLE_BG = "#1e1e2e"


def fetch_workspaces():
    """通过 `niri msg -j workspaces` 拉取实时工作区列表。"""
    try:
        out = subprocess.run(
            ["niri", "msg", "-j", "workspaces"],
            capture_output=True,
            text=True,
            timeout=3,
        ).stdout.strip()
        if not out:
            return []
        return json.loads(out)
    except Exception:
        return []


def render(ws_list):
    spans = []
    tips = []
    for w in sorted(ws_list, key=lambda x: x.get("idx", 0)):
        idx = w.get("idx", 0)
        # is_focused 表示当前所在工作区；单输出下与 is_active 一致，
        # 用 "or" 兜底，避免短暂无焦点时高亮消失。
        active = bool(w.get("is_focused") or w.get("is_active"))
        if active:
            spans.append(
                f'<span foreground="{ACCENT}" background="{ACCENT_BG}" '
                f'weight="bold">  {idx}  </span>'
            )
        else:
            spans.append(
                f'<span foreground="{IDLE}" background="{IDLE_BG}">  {idx}  </span>'
            )
        marker = "●" if active else "○"
        tips.append(f"{marker} 工作区 {idx}")

    return {
        "text": " ".join(spans),
        "class": "workspaces",
        "tooltip": True,
        "tooltip_text": "\n".join(tips),
    }


def main():
    print(json.dumps(render(fetch_workspaces())))


if __name__ == "__main__":
    main()
