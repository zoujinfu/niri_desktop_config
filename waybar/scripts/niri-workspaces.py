#!/usr/bin/env python3
"""waybar custom module: niri workspaces as inline-markup capsules.

Outputs a single JSON object whose `text` is a GTK-markup string. Every
workspace is a colored capsule; the focused one uses the accent color.
"""

import json
import subprocess

ACCENT = "#3fbf8f"      # active workspace
IDLE = "#8b95a3"        # inactive workspace
BG_ACTIVE = "#1e2b26"
BG_IDLE = "#262b33"


def get_workspaces():
    """Return list of (num, is_active)."""
    try:
        out = subprocess.run(["niri", "msg", "workspaces"],
                             capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return []

    ws = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        active = line.startswith("*")
        line = line.lstrip("*").strip()
        parts = line.split()
        if not parts or not parts[0].isdigit():
            continue
        ws.append((int(parts[0]), active))
    return ws


def build_text(ws):
    spans = []
    for num, active in ws:
        if active:
            spans.append(
                f'<span foreground="{ACCENT}" background="{BG_ACTIVE}" '
                f'weight="bold"> {num} </span>'
            )
        else:
            spans.append(
                f'<span foreground="{IDLE}" background="{BG_IDLE}"> {num} </span>'
            )
    return " ".join(spans)


if __name__ == "__main__":
    ws = get_workspaces()
    payload = {"text": build_text(ws), "class": "workspaces", "tooltip": "工作区"}
    print(json.dumps(payload))
