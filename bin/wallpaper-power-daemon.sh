#!/bin/bash
#
# 壁纸电源门控守护进程 —— 配合 wallpaper-rotate.sh 实现「只有充电时才显示壁纸」
#
# 为什么需要它: wallpaper-watchdog.timer 每 2 分钟才检查一次电源, 插拔适配器后
# 最长要等 2 分钟壁纸才启停。这个守护用 `upower --monitor` 监听电源事件, 变化即响应。
#
# 行为(全部转交 wallpaper-rotate.sh sync-power, 保持单一事实来源):
#   插上适配器 -> 壁纸没在跑就拉起
#   拔掉适配器 -> 立刻停掉壁纸
#   手动 ignore 标记存在时 -> 一律当插着电处理, 不拦
#
# 本脚本只负责「什么时候叫它」; 电源状态的真实判定在 wallpaper-rotate.sh 的 on_ac_power。
#
set -u

ROTATE=/home/sky/.local/bin/wallpaper-rotate.sh
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-rotate"
LOG_FILE="$STATE_DIR/power-daemon.log"
mkdir -p "$STATE_DIR"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"; }

# 日志轮转: 超过 256KB 滚一次, 免得长跑后无限增长
if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)" -gt 262144 ]; then
    mv -f "$LOG_FILE" "$LOG_FILE.1"
fi

run_sync() {
    "$ROTATE" sync-power >/dev/null 2>&1
}

log "电源守护启动 (监听 upower 事件, 动作转交 wallpaper-rotate.sh sync-power)"

# 启动时先对齐一次: 开机若在用电池, 别让壁纸在 niri 自启那一下跑出来
run_sync
log "启动时已对齐一次电源状态"

# upower 把事件按行刷出; 第一行是固定的标题 "Monitoring activity from the power daemon. ..."
# 跳过标题行, 其余每行都当作「电源可能变了」的信号。
# 不解析 upower 的文本 —— 电源判据统一由 sysfs 决定, 这里只把它当闹钟。
# stdout 断开(upower 挂了)就退出, 由 systemd Restart=always 拉回来。
last=$(cat /sys/class/power_supply/ADP0/online 2>/dev/null || echo "?")
stdbuf -oL upower --monitor 2>/dev/null | while IFS= read -r line; do
    case "$line" in
        "Monitoring activity"*) continue ;;
        "") continue ;;
    esac
    # 去抖动用「状态去重」而不是 sleep: 一次插拔 upower 会连吐多行
    # (在线状态 / 图标 / 警告级别各一条), 前面试过 sleep 1.5 再同步, 但 while 循环里
    # sleep 是串行叠加的, 积压事件反而被放大成 6 次同步(实测 2026-11-05 09:02)。
    # 现在只比较「适配器是否在线」这个真实判据: 没变就什么都不做。
    now=$(cat /sys/class/power_supply/ADP0/online 2>/dev/null || echo "?")
    [ "$now" = "$last" ] && continue
    last=$now
    run_sync
    case "$now" in
        1) log "适配器已接上 (ADP0/online=1), 已同步: 壁纸应启动" ;;
        0) log "已切到电池 (ADP0/online=0), 已同步: 壁纸应停止" ;;
        *) log "ADP0/online 不可读 ($now), 已按当前状态同步" ;;
    esac
done

# 管道结束 = upower 退出, 让 systemd 重启整个单元
log "upower --monitor 已退出, 守护结束(等待 systemd 重启)"
exit 0