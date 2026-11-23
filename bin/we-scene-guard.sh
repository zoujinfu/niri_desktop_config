#!/usr/bin/env bash
# 守住已降码率的壁纸资产：Steam 校验/更新 workshop 项会把 scene.pkg 或视频覆盖回 4K 原版，
# 本脚本比对指纹，发现被覆盖就自动重新降成 1080p30。
# 用法: we-scene-guard.sh [--init]   （--init 只记录当前指纹，不重建）
set -uo pipefail

W=/home/sky/.local/share/Steam/steamapps/workshop/content/431960
TOOL=/home/sky/builds/we-scene
STATE=$HOME/.local/state/we-scene-guard
LOG=$HOME/.cache/we-scene-guard.log
mkdir -p "$STATE" "$(dirname "$LOG")"

# 场景包：id -> scene.pkg
SCENES=(3470764447 3326873240)
# 整段视频壁纸：id -> 文件名（相对 workshop 目录）
declare -A VIDEOS=([3314492008]="世界很温柔—《龙族》上杉绘梨衣.mp4")

say() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }

# 指纹文件放在 state 下，键名带类型前缀避免冲突
hash_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

check_scene() {
  local id=$1 pkg="$W/$1/scene.pkg" key="scene-$1" rec
  [ -f "$pkg" ] || { say "[$id] scene.pkg 不存在，跳过"; return; }
  rec=$(cat "$STATE/$key" 2>/dev/null || true)
  local cur; cur=$(hash_of "$pkg")
  if [ "${INIT:-0}" = 1 ] || [ -z "$rec" ]; then
    echo "$cur" > "$STATE/$key"; say "[$id] 记录指纹 ${cur:0:12}"; return
  fi
  if [ "$cur" = "$rec" ]; then return; fi
  say "[$id] scene.pkg 被改动（现 ${cur:0:12}，记录 ${rec:0:12}），重新降码率"
  if nice -n 15 ionice -c3 python3 "$TOOL/downscale-scene.py" --id "$id" --install >>"$LOG" 2>&1; then
    echo "$(hash_of "$pkg")" > "$STATE/$key"
    say "[$id] 重建完成 $(du -h "$pkg" | cut -f1)"
  else
    say "[$id] 重建失败，见 $LOG"
  fi
}

check_video() {
  local id=$1 name=$2 f="$W/$1/$2" key="video-$1" rec cur
  [ -f "$f" ] || { say "[$id] $name 不存在，跳过"; return; }
  rec=$(cat "$STATE/$key" 2>/dev/null || true)
  cur=$(hash_of "$f")
  if [ "${INIT:-0}" = 1 ] || [ -z "$rec" ]; then
    echo "$cur" > "$STATE/$key"; say "[$id] 记录指纹 ${cur:0:12}"; return
  fi
  [ "$cur" = "$rec" ] && return
  say "[$id] 视频被改动（现 ${cur:0:12}，记录 ${rec:0:12}），重新编码为 1080p30"
  if nice -n 15 ionice -c3 ffmpeg -y -v error -i "$f" \
       -vf "scale=1920:1080:flags=lanczos,fps=30" -c:v libx264 -preset medium -crf 20 \
       -pix_fmt yuv420p -an -movflags +faststart "/tmp/guard-$$.mp4" >>"$LOG" 2>&1; then
    mv -f "/tmp/guard-$$.mp4" "$f"
    echo "$(hash_of "$f")" > "$STATE/$key"
    say "[$id] 重建完成 $(du -h "$f" | cut -f1)"
  else
    say "[$id] 编码失败，见 $LOG"
    rm -f "/tmp/guard-$$.mp4"
  fi
}

[ "${1:-}" = "--init" ] && INIT=1
INIT=${INIT:-0}
for id in "${SCENES[@]}"; do check_scene "$id"; done
for id in "${!VIDEOS[@]}"; do check_video "$id" "${VIDEOS[$id]}"; done
exit 0
