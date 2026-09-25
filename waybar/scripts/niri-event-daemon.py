#!/usr/bin/env python3
"""Background daemon: listen to niri IPC events, write cache files for waybar."""

import json
import os
import subprocess
import sys
import time

CACHE_DIR = "/tmp/opencode"
WS_CACHE = os.path.join(CACHE_DIR, "waybar-workspaces.json")
WIN_CACHE = os.path.join(CACHE_DIR, "waybar-window.txt")

# Catppuccin Mocha palette
ACCENT = "#89b4fa"
ACCENT_BG = "#313244"
IDLE = "#585b70"
IDLE_BG = "#1e1e2e"

# Global state
workspaces = []
focused_title = ""


def parse_workspaces(event):
    global workspaces
    ws_list = event.get("workspaces", [])
    workspaces = []
    for w in ws_list:
        workspaces.append({
            "idx": w.get("idx", 0),
            "is_active": w.get("is_active", False),
            "is_focused": w.get("is_focused", False),
        })
    workspaces.sort(key=lambda x: x["idx"])


def parse_windows(event):
    global focused_title
    focused_title = ""
    for w in event.get("windows", []):
        if w.get("is_focused"):
            focused_title = w.get("title", "")
            break


def write_ws_cache():
    spans = []
    tips = []
    for ws in workspaces:
        idx = ws["idx"]
        if ws["is_active"]:
            spans.append(
                f'<span foreground="{ACCENT}" background="{ACCENT_BG}" '
                f'weight="bold">  {idx}  </span>'
            )
        else:
            spans.append(
                f'<span foreground="{IDLE}" background="{IDLE_BG}">  {idx}  </span>'
            )
        marker = "●" if ws["is_active"] else "○"
        tips.append(f"{marker} 工作区 {idx}")

    payload = {
        "text": " ".join(spans),
        "class": "workspaces",
        "tooltip": True,
        "tooltip_text": "\n".join(tips),
    }
    tmp = WS_CACHE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(payload, f)
    os.replace(tmp, WS_CACHE)


def write_win_cache():
    tmp = WIN_CACHE + ".tmp"
    with open(tmp, "w") as f:
        f.write(focused_title)
    os.replace(tmp, WIN_CACHE)


def get_initial_state():
    """Fetch current state via one-shot commands."""
    global workspaces, focused_title
    # Workspaces
    try:
        out = subprocess.run(
            ["niri", "msg", "-j", "workspaces"],
            capture_output=True, text=True, timeout=3,
        ).stdout.strip()
        if out:
            ws_list = json.loads(out)
            workspaces = []
            for w in ws_list:
                workspaces.append({
                    "idx": w.get("idx", 0),
                    "is_active": w.get("is_active", False),
                    "is_focused": w.get("is_focused", False),
                })
            workspaces.sort(key=lambda x: x["idx"])
    except Exception:
        pass

    # Focused window
    try:
        out = subprocess.run(
            ["niri", "msg", "-j", "focused-window"],
            capture_output=True, text=True, timeout=3,
        ).stdout.strip()
        if out:
            win = json.loads(out)
            focused_title = win.get("title", "")
    except Exception:
        pass


def run_daemon():
    """Listen to niri event stream, update caches on changes."""
    while True:
        try:
            proc = subprocess.Popen(
                ["niri", "msg", "-j", "event-stream"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            for line in proc.stdout:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue

                if "WorkspacesChanged" in event:
                    parse_workspaces(event["WorkspacesChanged"])
                    write_ws_cache()
                elif "WindowsChanged" in event:
                    parse_windows(event["WindowsChanged"])
                    write_win_cache()
        except Exception:
            pass
        time.sleep(2)


if __name__ == "__main__":
    os.makedirs(CACHE_DIR, exist_ok=True)
    get_initial_state()
    write_ws_cache()
    write_win_cache()
    run_daemon()
