#!/usr/bin/env python3
"""waybar custom module: focused niri window title."""

import subprocess


def focused_title():
    try:
        out = subprocess.run(["niri", "msg", "windows"],
                             capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return ""

    title = None
    in_focused = False
    for line in out.splitlines():
        if line.startswith("Window ID"):
            in_focused = "(focused)" in line
        elif in_focused and line.lstrip().startswith("Title:"):
            title = line.split("Title:", 1)[1].strip()
            break
    return title or ""


if __name__ == "__main__":
    print(focused_title())
