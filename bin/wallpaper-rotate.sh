#!/bin/bash
#
# Wallpaper Engine 动态壁纸轮换脚本 —— Arch Linux + niri
#
# 用法:
#   wallpaper-rotate.sh            # 下一张(默认)
#   wallpaper-rotate.sh next       # 下一张
#   wallpaper-rotate.sh prev       # 上一张
#   wallpaper-rotate.sh stop       # 只停掉当前壁纸, 不启动新的
#   wallpaper-rotate.sh current    # 打印当前壁纸 ID
#   wallpaper-rotate.sh status     # 看电源判定/忽略标记/进程/当前壁纸
#   wallpaper-rotate.sh ensure     # 看门狗: 该在却没在跑就补一个
#   wallpaper-rotate.sh sync-power # 按当前电源启停(电源事件触发, 由守护进程调用)
#   wallpaper-rotate.sh ignore     # 手动忽略电源限制(电池上也显示)  ← Super+F10
#   wallpaper-rotate.sh respect    # 恢复「只充电时显示」            ← Super+Shift+F10
#
# 【2026-11-05 电源门控】默认「只有插着电源适配器时才显示壁纸」, 用电池时不启动、
#   已启动的会被停掉(桌面露出 niri 的 transparent 背景色 = 纯黑)。
#   判定只看 /sys/class/power_supply/*/type == Mains 的 online(见 on_ac_power):
#   不看 BAT0/status(充满后是 Full 而非 Charging, 会误判), 也不看 USB-C 的
#   ucsi-source-psy(插普通 USB 设备时语义不可靠)。ignore 标记可临时绕过。
#   即时响应由 wallpaper-power-daemon.sh + wallpaper-power.service 负责监听 upower;
#   即使用户没登录该守护, wallpaper-watchdog.timer 每 2 分钟也会兜底对齐。
#
# 依赖: kirie  (~/.local/bin/kirie, GitHub release UnhingedSoftware/kirie 的单文件二进制;
#         2026-10-12 从 linux-wallpaperengine 换过来 —— 同一张重壁纸显存 5449 MiB -> 804 MiB)
#         想退回旧引擎: 把下面配置区的 BIN= 改回 linux-wallpaperengine (仍在 /usr/bin)
# 配套:
#   ~/.config/systemd/user/wallpaper-rotate.timer   每 30 分钟自动轮换
#   ~/.config/niri/config.kdl                       layer-rule place-within-backdrop + Super+F11/F12
# 笔记: ~/note/my_computer/Niri桌面环境/Wallpaper Engine配置.md
#
# 【2026-10-05 从 Ubuntu 迁到 Arch 时的改动】
#   - 状态/日志从 /tmp/opencode/ 换到 ~/.local/state/wallpaper-rotate/
#     (旧路径是 opencode 的临时目录, 重启即失、还容易和别的工具的临时文件混在一起)
#   - 停止旧壁纸时先按记录的 PID 精确结束, 再用 pkill 兜底;
#     pkill 的模式带上 "--screen-root", 避免误伤 AUR 编译目录里的进程
#   - 加 flock 互斥: 定时器和快捷键同时触发时不会起出两个壁纸进程
#
# 【2026-10-06 改动】
#   - EXTRA_ARGS 加 --no-fullscreen-pause: 修复「系统里有全屏窗口时视频壁纸全黑」
#     (详见下面配置区那段注释)
#
# 【2026-10-12 二次改动: 先起新的, 起来了再杀旧的】
#   - 症状: 用户快速 next/prev 的那几分钟里, 多张壁纸(含 scene 和 video)连续 3 次启动都崩,
#     脚本 return 1 → 桌面**完全空白**(进程没了、Background 层也没了), 用户看到的就是「壁纸有 bug」。
#   - 真因: kirie v0.8.2 的 wgpu 格式 bug, 与壁纸本身无关。crates/kirie-platform/src/platform.rs:784-800
#     只在**第一帧**用当帧 surface 纹理的格式建 pipeline(SceneRenderer::new), 之后每帧重新
#     create_view 却从不重建 pipeline; 一旦 wgpu 因 surface 被重配而给出另一种格式的纹理
#     (niri 的 layer surface 给 Bgra8UnormSrgb, 而首帧拿到的是 Rgba8UnormSrgb), 下一帧就必然
#     报 "kirie-scene-blit-pipeline ... Incompatible color attachments" 并 abort。
#     实测同一张壁纸在故障窗口内/外表现相反, 崩溃点固定在首帧后 ~80ms。
#   - 因此轮换改成「新壁纸确认活着之后才杀旧壁纸」: 新旧会短暂并存 ~2 秒, 但新壁纸起不来时
#     旧壁纸继续显示, 桌面永远不会因为一次切换失败而变空。索引也只在成功后才写。
#   - start_wallpaper() 里识别新进程 PID 时排除启动前就存在的 PID(并发时不认错人)。
#
# 【2026-10-12 换渲染器: linux-wallpaperengine -> kirie】
#   - 原因: 两张 Time Variation 的重 scene 壁纸在引擎下吃 5449 MiB 显存(整卡才 8GB),
#     kirie 跑同一张只要 804 MiB(--render-scale 0.5 可到 548), 画质肉眼无差别。
#     kirie 的 CLI 与引擎逐字兼容, 上报的 layer namespace 也叫 linux-wallpaperengine,
#     所以 niri 的 layer-rule 完全不用动。video 类也照旧能跑。
#   - is_our_wallpaper() 从「只认 linux-wallpaperengine」改成认一组名字(OUR_BIN_NAMES),
#     并新增 wallpaper_pids() 统一候选集: 切换那一刻还跑着旧引擎, 名字必须一起认,
#     否则兜底清理和看门狗会漏掉旧进程 / 认不出新进程。
#   - EXTRA_ARGS 去掉 --scaling fill: 它会触发 kirie 的 wgpu 格式断言而崩溃,
#     详见下面配置区那段注释。
#   - start_wallpaper() 加了自动重试(最多 3 次): kirie 有约 1/4 概率「启动即崩」
#     (同一个 wgpu 格式断言, 主要砸在 video 类壁纸上), 崩了进程直接 abort、桌面全黑;
#     实测同一张重试一次就能起来, 所以起完等 2 秒确认存活, 死了立刻重试。

set -u

# ---- 图形环境变量 (systemd timer / 非登录 shell 启动时可能缺失) ----
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DISPLAY=${DISPLAY:-:0}

# ---- 配置 ----
# 【2026-10-12】订阅的 scene 壁纸（Time Variation 系列）：
#   3326873240 窗旁的伊蕾娜 / 3470764447 伊蕾娜：闲憩微息 —— 两张 scene.pkg 分别
#   246MB / 336MB，比原来几张重，首次加载会慢一点。
# 【2026-10-12 全量验收后】workshop 里全部 11 张都进轮换（追加在末尾的 6 张）：
#   3272717573 山晚-三叶(video, 227MiB) / 3291326967 蒙眼少女4K(scene, 1338MiB)
#   3409595232 Miku-长安雪(scene, 1060MiB) / 3492627662 Miku醉花间(scene, 1572MiB)
#   3500648585 鸣潮-卡提希娅(scene, 1316MiB) / 3518966788 Shorekeeper(scene, 1062MiB)
#   11 张全部实测可渲染（离屏 1920x1080 + 实机播放），显存最大 1572 MiB（8GB 够用）。
#   一圈 30 分钟 x 11 = 5.5 小时才轮完；想快就改 wallpaper-rotate.timer 的 OnUnitActiveSec。
#   新条目一律**追加在末尾**，这样已有的 index 语义不变（换位置会让当前显示的那张变掉）。
WALLPAPERS=(3235984631 3284636810 3314492008 3326873240 3470764447 \
            3272717573 3291326967 3409595232 3492627662 3500648585 3518966788)
SCREEN="eDP-1"
BIN="kirie"
# 说明: kirie 是 UnhingedSoftware/kirie 的官方 release 单文件二进制, 装在 ~/.local/bin/kirie。
# 换回旧引擎只需把上面这行改成 linux-wallpaperengine(其余逻辑会自动跟随, 见 OUR_BIN_NAMES)。
# niri 专用: 挂到 background 层, 配合 config.kdl 里的 layer-rule place-within-backdrop,
# 否则概览(Overview)里壁纸会被复制到每个工作区。
#
# 【2026-10-06 加 --no-fullscreen-pause】否则只要系统里存在任意一个全屏窗口
# (哪怕在别的工作区、没聚焦, 例如全屏看直播的 Chrome), linux-wallpaperengine 就会
# setPause(true) 并直接 return 不再绘制。scene 壁纸在暂停前已画出首帧所以看不出来,
# video 壁纸会在 mpv 解出第 0 帧之前就被 pause=yes, 纹理永远是空的 -> 桌面全黑。
# 表面症状极具迷惑性: 进程在跑、GPU 占 1GB、`niri msg layers` 有表面、日志无报错。
# 复现/验证: 去掉这个参数, 视频壁纸截屏只有 ~3000 色; 加上后 4 万~20 万色。
# 代价: 全屏看视频/打游戏时壁纸照常渲染(本机 nvdec 硬解, 开销可控)。
# 【2026-10-12 去掉 --scaling fill】kirie 只要走进"渲染到离屏纹理再 blit"的路径就撞 wgpu 格式 bug:
#   RenderPass 用的是 Bgra8UnormSrgb(niri 给的 layer surface 格式, NVIDIA 驱动下排第一),
#   而 kirie 的 'kirie-scene-blit-pipeline' / 'kirie-video-pipeline' 硬编码 Rgba8UnormSrgb ->
#   "Render pipeline targets are incompatible with render pass" 直接 abort(核心转储)。
#   实测: 带 --scaling fill/fit 时 3326873240 与 3284636810 必崩, 不带 scaling / 用 default 稳定;
#   画面没变化 —— 离屏同尺寸 A/B 的差异全部来自动画时序(樱落那张 RMSE=0, 其余无黑边、满屏一致)。
#   注: 这是 kirie 自身的 bug(与管道缓存无关, 清空 ~/.cache/kirie/pipelines 后照样崩), 等上游修。
EXTRA_ARGS=(--layer background --no-fullscreen-pause)

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-rotate"
STATE_FILE="$STATE_DIR/index"
PID_FILE="$STATE_DIR/pid"
LOG_FILE="$STATE_DIR/wallpaper.log"
LOCK_FILE="$STATE_DIR/lock"
# 手动 stop 的标记: 存在时看门狗不再自动拉起(否则你刚 stop, 2 分钟后它又回来了)
DISABLE_FLAG="$STATE_DIR/disabled"
# 「仅充电时才显示壁纸」的忽略开关(Super+F10 = 在电池上也强行显示; Super+Shift+F10 = 恢复跟随电源)。
# 存在 = 忽略电源限制, 就当一直插着电。
IGNORE_POWER_FLAG="$STATE_DIR/ignore-power"

# ---- 电源判定 (2026-11-05 新增: 非充电时不启动壁纸) ----
# 只认电源适配器 Mains 的 online 标志(/sys/class/power_supply/ADP0/online):
#   1 = 插着适配器, 0 = 用电池。刻意**不**看 BAT0/status: 电池充满后状态是 Full / Not charging
#   而不是 Charging, 拿它当判据会出现「插着电却判定成没充」的反常结果;
#   也刻意**不**看 USB-C 的 ucsi-source-psy: 本机插着普通 USB-C 设备时它的 online 也报 0,
#   语义不可靠(实测 2026-11-05)。读不到任何 Mains 时按「在充电」处理 —— 宁可显示壁纸,
#   也不要因为 sysfs 改动让桌面在插着电时莫名变黑。
on_ac_power() {
    local d seen=0
    for d in /sys/class/power_supply/*; do
        [ -r "$d/type" ] || continue
        [ "$(cat "$d/type" 2>/dev/null)" = "Mains" ] || continue
        seen=1
        [ "$(cat "$d/online" 2>/dev/null)" = "1" ] && return 0
    done
    [ "$seen" -eq 1 ] && return 1   # 找到了 Mains 但都 offline = 在用电池
    return 0                         # 没有 Mains(桌面机/异常) = 不拦
}

# 是否允许显示壁纸: 插着电, 或用户用 Super+F10 显式忽略了电源限制
power_allows_wallpaper() {
    [ -e "$IGNORE_POWER_FLAG" ] && return 0
    on_ac_power
}

mkdir -p "$STATE_DIR"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"; }

# 日志超过 1MB 就轮转一次, 免得无限长大
if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv -f "$LOG_FILE" "$LOG_FILE.1"
fi

# ---- 互斥: 同一时刻只允许一个实例在切壁纸 ----
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log "另一个轮换实例正在运行, 本次跳过"
    exit 0
fi

if ! command -v "$BIN" >/dev/null 2>&1; then
    log "找不到 $BIN"
    echo "找不到 $BIN" >&2
    if [ "$BIN" = "kirie" ]; then
        echo "  kirie 不在 pacman/AUR 里, 是从 GitHub release 下的单文件二进制:" >&2
        echo "    gh release download v0.8.2 -R UnhingedSoftware/kirie -p kirie-linux-x86_64 -D /tmp" >&2
        echo "    install -Dm755 /tmp/kirie-linux-x86_64 ~/.local/bin/kirie" >&2
        echo "  或者退回旧引擎: 把本脚本的 BIN= 改回 linux-wallpaperengine" >&2
    else
        echo "  安装: paru -S linux-wallpaperengine-git" >&2
    fi
    exit 1
fi

# ---- 读取当前索引 (语义: 当前显示的壁纸在列表中的下标; 无状态则 -1) ----
CUR=-1
if [ -f "$STATE_FILE" ]; then
    RAW=$(cat "$STATE_FILE" 2>/dev/null)
    # 仅接受纯数字, 避免损坏的文件让脚本出错
    if [[ "$RAW" =~ ^[0-9]+$ ]]; then
        CUR=$RAW
    fi
fi

# ---- 停止当前壁纸 ----

# 认哪些二进制算「我们的壁纸」: 当前 $BIN 的 basename + 换渲染器前的旧名字。
# 两个都认是必须的 —— 切换那一刻旧引擎还跑着, 得能被清理掉; 将来再换也只改这一处。
OUR_BIN_NAMES=("${BIN##*/}" "linux-wallpaperengine")

# 判断某个 PID 是不是我们的壁纸进程。
# 只看 /proc/<pid>/exe 或 argv[0] 的 basename —— 刻意不用「整条命令行」匹配:
# 命令行里恰好含有 "kirie"/"linux-wallpaperengine" 字样的无关进程(例如你正在手敲的一条
# 调试命令、pgrep/pkill 自己、AUR 编译目录里的构建进程)会被整条匹配误杀。
is_our_wallpaper() {
    local p="$1" exe arg0 n
    [ "$p" = "$$" ] && return 1
    exe=$(readlink -f "/proc/$p/exe" 2>/dev/null)
    # 包装脚本(或 kirie 刚被 exec 前)exe 可能还是 bash, 所以再看一眼 argv[0]
    arg0=$(tr '\0' '\n' <"/proc/$p/cmdline" 2>/dev/null | head -1)
    for n in "${OUR_BIN_NAMES[@]}"; do
        [ "${exe##*/}" = "$n" ] && return 0
        [ "${arg0##*/}" = "$n" ] && return 0
    done
    return 1
}

# 候选 PID 集: 用正则同时覆盖新旧两个名字。命中只是候选, 到底算不算壁纸由 is_our_wallpaper 定,
# 所以这里放宽不会误杀(例如停在 /tmp/kirie-test 里的 shell 会被选中、再被函数排除)。
wallpaper_pids() {
    pgrep -f 'kirie|linux-wallpaperengine' 2>/dev/null
}

stop_wallpaper() {
    local pid="" p
    if [ -s "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE" 2>/dev/null)
    fi
    if [ -n "$pid" ] && [ "$pid" != "$$" ] && kill -0 "$pid" 2>/dev/null; then
        # setsid 起的进程是进程组组长, 整组一起结束更干净
        kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
        for _ in $(seq 1 25); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
        fi
    fi
    # 兜底: 清掉没记上 PID 的残留进程, 逐个核对 exe/argv[0] 之后再动手
    for p in $(wallpaper_pids); do
        if is_our_wallpaper "$p"; then
            kill -TERM "$p" 2>/dev/null
        fi
    done
    rm -f "$PID_FILE"
}

# 结束指定的 PID 列表(先 TERM 整组, 再等, 还活着才 KILL)。
# 只对「确实是我们的壁纸进程」的 PID 动手 —— 这个函数拿到的列表来自 wallpaper_pids(),
# 里面可能混着命令行恰好含关键字的无关进程。
kill_pids() {
    local list="$1" p i
    for p in $list; do
        is_our_wallpaper "$p" || continue
        kill -TERM -- "-$p" 2>/dev/null || kill -TERM "$p" 2>/dev/null
    done
    for p in $list; do
        [ -n "$p" ] || continue
        for i in $(seq 1 20); do
            kill -0 "$p" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$p" 2>/dev/null && is_our_wallpaper "$p"; then
            kill -KILL -- "-$p" 2>/dev/null || kill -KILL "$p" 2>/dev/null
        fi
    done
}

# ---- 小工具: 桌面通知 + 当前壁纸 ID ----
# 没有通知守护(notify-send 失败)时不报错, 通知只是锦上添花。
notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a "壁纸" "壁纸" "$1" 2>/dev/null || return 0
}

# 打印当前壁纸的 workshop ID(兼容旧的 current 子命令与新的 status)
current_id() {
    if [ "$CUR" -ge 0 ] && [ "$CUR" -lt "${#WALLPAPERS[@]}" ]; then
        echo "${WALLPAPERS[$CUR]}"
    else
        echo "(未知)"
    fi
}

# ---- 有没有壁纸进程在跑(按 exe 精确判断, 不做整条命令行匹配) ----
any_wallpaper_running() {
    local _p
    for _p in $(wallpaper_pids); do
        is_our_wallpaper "$_p" && return 0
    done
    return 1
}

# ---- 启动指定索引的壁纸(不改索引、不轮换) ----
# 起来之后要确认它真的活下来了: kirie 有「启动即崩」的毛病(实测约 1/4 概率, 日志里是 wgpu 的
# Bgra8UnormSrgb / Rgba8UnormSrgb 校验失败, 主要砸在 video 类壁纸上), 崩了进程直接 abort、
# 桌面全黑。实测同一张重试一次就能起来, 所以这里自动重试 —— 失败窗口在启动后 2 秒内。
MAX_START_ATTEMPTS=3

start_wallpaper() {
    local new="$1" wallpaper="${WALLPAPERS[$1]}" attempt launched real_pid _p before

    # 启动前就已经存在的候选 PID: 接下来要杀但不该现在杀的旧壁纸(以及任何别的同类进程)。
    # 认新进程时要排除它们, 否则并发时会认错人、把旧进程的存活当成新进程成功。
    before=" $(wallpaper_pids | tr '\n' ' ') "

    for attempt in $(seq 1 "$MAX_START_ATTEMPTS"); do
        # setsid 让进程脱离本脚本的会话, 避免被 systemd oneshot 收尾时带走。
        # 末尾的 9>&- 很关键: 关掉 flock 用的 fd 9, 否则壁纸进程会一直继承并占着这把锁,
        # 导致此后每次轮换都被 flock 判成「另一个实例在跑」而静默跳过。
        setsid "$BIN" --screen-root "$SCREEN" "${EXTRA_ARGS[@]}" "$wallpaper" >>"$LOG_FILE" 2>&1 </dev/null 9>&- &
        launched=$!
        echo "$launched" >"$PID_FILE"
        disown 2>/dev/null || true

        # setsid 在部分情况下会 fork, $! 不一定是最终进程, 稍后用真实 PID 覆盖
        sleep 0.5
        real_pid=""
        for _p in $(wallpaper_pids); do
            case "$before" in *" $_p "*) continue ;; esac   # 启动前就在跑的, 不是这次起的
            is_our_wallpaper "$_p" && real_pid="$_p"
        done

        # 再等 1.5 秒确认它还活着 —— 崩溃都发生在启动后 2 秒内(实测同一秒)
        sleep 1.5
        if [ -n "$real_pid" ] && kill -0 "$real_pid" 2>/dev/null; then
            echo "$real_pid" >"$PID_FILE"
            echo "$real_pid"
            [ "$attempt" -gt 1 ] && log "重试第 $attempt 次成功启动 $wallpaper"
            return 0
        fi

        rm -f "$PID_FILE"
        if [ "$attempt" -lt "$MAX_START_ATTEMPTS" ]; then
            log "第 $attempt 次启动 $wallpaper 失败(进程已退出), 立刻重试"
        fi
    done
    log "警告: $wallpaper 连续 $MAX_START_ATTEMPTS 次启动失败, 详见 $LOG_FILE"
    echo "警告: 壁纸可能没起来, 详见 $LOG_FILE" >&2
    return 1
}

# ---- 参数 ----
DIR="${1:-next}"
case "$DIR" in
    ensure)
        # 看门狗模式: 壁纸没在跑才补一个当前索引的, 不做轮换。
        # 由 wallpaper-watchdog.timer 每 2 分钟调一次 —— 壁纸进程要是崩了/被误杀,
        # 最多 2 分钟就会自己回来, 不用干等 30 分钟的下一次轮换。
        if [ -f "$DISABLE_FLAG" ]; then
            exit 0
        fi
        # 【2026-11-05】非充电状态: 不但不补, 已经跑着的也要停掉(用户要求「不是充电就不启动」)。
        # 放在 DISABLE_FLAG 之后、catch-up 之前, 这样拔掉电源后最多 2 分钟壁纸就没了。
        if ! power_allows_wallpaper; then
            if any_wallpaper_running; then
                stop_wallpaper
                log "看门狗: 已改用电池供电, 停止壁纸"
            fi
            exit 0
        fi
        if any_wallpaper_running; then
            exit 0
        fi
        if [ "$CUR" -ge 0 ] && [ "$CUR" -lt "${#WALLPAPERS[@]}" ]; then
            NEW=$CUR
        else
            NEW=0
        fi
        log "看门狗: 壁纸没在跑, 重新启动 ${WALLPAPERS[$NEW]} (索引 $NEW)"
        start_wallpaper "$NEW"
        exit $?
        ;;
    sync-power)
        # 电源状态刚变过(由 wallpaper-power-daemon.sh 或看门狗调用): 按当前电源决定启停。
        # 与 ensure 的区别: ensure 是「没在跑就补」, 这里是「该停就停、该起就起」。
        if ! power_allows_wallpaper; then
            if any_wallpaper_running; then
                stop_wallpaper
                log "电源已改为电池供电, 停止壁纸"
            fi
            exit 0
        fi
        # 允许显示: 没跑就拉起来(用当前索引)
        if any_wallpaper_running; then
            exit 0
        fi
        if [ -f "$DISABLE_FLAG" ]; then
            exit 0
        fi
        if [ "$CUR" -ge 0 ] && [ "$CUR" -lt "${#WALLPAPERS[@]}" ]; then
            NEW=$CUR
        else
            NEW=0
        fi
        log "电源已接上适配器, 启动壁纸 ${WALLPAPERS[$NEW]} (索引 $NEW)"
        start_wallpaper "$NEW"
        exit $?
        ;;
    status)
        # 一条命令看全: 电源判定 + 手动忽略标记 + 进程 + 当前壁纸。
        if on_ac_power; then
            AC="插着适配器 (允许显示)"
        else
            AC="用电池 (不允许显示)"
        fi
        if [ -e "$IGNORE_POWER_FLAG" ]; then
            IGN="已开启 (Super+F10 会忽略电源限制)"
        else
            IGN="未开启"
        fi
        if any_wallpaper_running; then
            RUN="运行中 (pid $(wallpaper_pids | tr '\n' ' '))"
        else
            RUN="没在跑"
        fi
        echo "电源:       $AC"
        echo "忽略限制:   $IGN"
        echo "壁纸进程:   $RUN"
        echo "当前壁纸:   $(current_id)"
        exit 0
        ;;
    ignore)
        # 手动忽略电源限制(电池上也显示壁纸)。与 stop 的 DISABLE_FLAG 相互独立。
        touch "$IGNORE_POWER_FLAG"
        rm -f "$DISABLE_FLAG"
        log "手动开启「忽略电源限制」(电池上也显示壁纸)"
        notify "已开启: 电池上也显示壁纸" || true
        # 立刻把壁纸拉起来, 不用等看门狗
        if ! any_wallpaper_running; then
            if [ "$CUR" -ge 0 ] && [ "$CUR" -lt "${#WALLPAPERS[@]}" ]; then NEW=$CUR; else NEW=0; fi
            start_wallpaper "$NEW"
        fi
        exit 0
        ;;
    respect)
        # 恢复跟随电源(撤销 ignore)。
        rm -f "$IGNORE_POWER_FLAG"
        log "手动恢复「跟随电源」"
        notify "已恢复: 只有充电时显示壁纸" || true
        if ! on_ac_power && any_wallpaper_running; then
            stop_wallpaper
            log "恢复跟随电源后正在用电池, 已停止壁纸"
        fi
        exit 0
        ;;
    stop)
        stop_wallpaper
        touch "$DISABLE_FLAG"
        log "已手动停止壁纸 (看门狗暂停; 用 next/prev 恢复)"
        echo "已停止当前壁纸 (看门狗暂停; 用 $0 next 恢复)"
        exit 0
        ;;
    current)
        current_id
        exit 0
        ;;
    prev) ;;
    next | "") DIR=next ;;
    *)
        echo "用法: $0 [next|prev|stop|current|ensure|status|ignore|respect|sync-power]" >&2
        exit 2
        ;;
esac

# 【2026-11-05】轮换方向键(Super+F11/F12)也遵守电源限制: 用电池时按了不启动壁纸,
# 免得「自动关了但一按快捷键又回来」。想强行看就先用 Super+F10 (ignore)。
if ! power_allows_wallpaper; then
    if any_wallpaper_running; then
        stop_wallpaper
        log "用电池供电, 停止壁纸 (快捷键 $DIR 被电源限制拦截)"
    fi
    notify "正在用电池, 壁纸不启动 (Super+F10 可临时忽略)"
    echo "正在用电池供电, 壁纸不启动。想临时显示请用 $0 ignore" >&2
    exit 0
fi

LEN=${#WALLPAPERS[@]}
case "$DIR" in
    prev) NEW=$(((CUR - 1 + LEN) % LEN)) ;;
    *) NEW=$(((CUR + 1) % LEN)) ;;
esac

WALLPAPER=${WALLPAPERS[$NEW]}

# 解除「手动停止」标记(能走到这里说明是要显示壁纸的)
rm -f "$DISABLE_FLAG"

# 先记下正在跑的旧壁纸, 但**先不杀它** —— 等新壁纸确认活下来再杀。
# 这样新壁纸连续崩 3 次时旧壁纸继续显示, 桌面不会变成一片空白(kirie 的格式 bug 会让同一张
# 壁纸在某个时间窗内连崩, 实测 2026-10-12 16:53-16:56 一个窗口内 8 次启动全崩)。
OLD_PIDS=$(wallpaper_pids | tr '\n' ' ')
OLD_PID=""
if [ -s "$PID_FILE" ]; then OLD_PID=$(cat "$PID_FILE" 2>/dev/null); fi

# 启动新壁纸(具体启动逻辑在 start_wallpaper 里)
log "启动壁纸 $WALLPAPER (索引 $NEW, 方向 $DIR, 显示器 $SCREEN; 现有进程: ${OLD_PIDS:-无})"
if start_wallpaper "$NEW"; then
    echo "$NEW" >"$STATE_FILE"
    # 新壁纸已经出画并在跑, 这时才清掉旧壁纸
    if [ -n "${OLD_PIDS// /}" ]; then
        log "新壁纸已就位, 结束旧进程: $OLD_PIDS"
        kill_pids "$OLD_PIDS"
    fi
    exit 0
fi

# 到这里说明 3 次都没起来: 什么都不动, 旧壁纸继续显示, 索引仍指向它。
# 恢复 PID 文件(start_wallpaper 失败时会删掉它, 但旧壁纸还在跑)
if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "$OLD_PID" >"$PID_FILE"
fi
if [ -n "${OLD_PIDS// /}" ]; then
    log "切换失败: $WALLPAPER 起不来, 保留原壁纸继续显示(原因见日志末尾)"
    echo "警告: $WALLPAPER 起不来, 继续显示原来的壁纸(桌面没变空)" >&2
else
    log "切换失败: $WALLPAPER 起不来, 且当前没有别的壁纸在跑"
    echo "警告: $WALLPAPER 起不来, 当前桌面没有壁纸" >&2
fi
exit 1
