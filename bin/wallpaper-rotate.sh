#!/bin/bash

# 加载图形环境变量
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DISPLAY=${DISPLAY:-:0}

WALLPAPERS=(3235984631 3284636810 3314492008)
STATE_DIR="/tmp/opencode"
STATE_FILE="$STATE_DIR/wallpaper_index"
LOG_FILE="$STATE_DIR/wallpaper.log"

# 确保状态/日志目录存在
mkdir -p "$STATE_DIR"

# 读取当前壁纸索引 (语义: 当前正在显示的壁纸在列表中的下标; 无状态则 -1)
CUR=-1
if [ -f "$STATE_FILE" ]; then
    RAW=$(cat "$STATE_FILE" 2>/dev/null)
    if [[ "$RAW" =~ ^[0-9]+$ ]]; then
        CUR=$RAW
    fi
fi

# 方向: 默认下一张; 传 prev 则上一张
DIR="${1:-next}"
LEN=${#WALLPAPERS[@]}
case "$DIR" in
    prev) NEW=$(( (CUR - 1 + LEN) % LEN ));;
    *)    NEW=$(( (CUR + 1) % LEN ));;
esac

WALLPAPER=${WALLPAPERS[$NEW]}

# 保存当前显示的索引
echo "$NEW" > "$STATE_FILE"

# 停止当前壁纸
pkill -f linux-wallpaperengine 2>/dev/null
sleep 2

# 启动新壁纸 (使用 setsid 确保进程独立)
setsid linux-wallpaperengine --screen-root eDP-1 --layer background --scaling fill "$WALLPAPER" > "$LOG_FILE" 2>&1 < /dev/null &
disown
