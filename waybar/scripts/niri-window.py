#!/usr/bin/env python3
"""waybar 窗口标题模块：每次被调用时直接查询 niri IPC，实时渲染。"""

import json
import subprocess


def get_focused_title():
    try:
        out = subprocess.run(
            ["niri", "msg", "-j", "focused-window"],
            capture_output=True,
            text=True,
            timeout=3,
        ).stdout.strip()
        if not out:
            return ""
        win = json.loads(out)
        if win is None:
            return ""
        title = win.get("title")
        return title if isinstance(title, str) else ""
    except Exception:
        return ""


def main():
    print(get_focused_title())


if __name__ == "__main__":
    main()
