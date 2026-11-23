# niri 桌面配置

一套基于 **niri** 平铺式 Wayland 合成器的 Arch Linux 桌面配置：全中文注释，noctalia 承担状态栏 / 通知 / 锁屏 / 剪贴板 / OSD，Vicinae 做启动器，配合 Wallpaper Engine 动态壁纸、截图标注、键盘控鼠标、选中文本翻译与番茄钟。

> 环境：Arch Linux / niri 26.04 / Wayland
> 硬件：Intel i7-13650HX + NVIDIA RTX 4060（nvidia 驱动）
> 更新时间：2026-11-23

## 目录结构

```
niri_desktop_config/
├── niri/
│   └── config.kdl                    # niri 主配置（中文注释，完整快捷键绑定）
├── noctalia/
│   └── config.toml                   # 桌面外壳：状态栏 / 通知 / 锁屏 / 剪贴板 / OSD / 番茄钟
├── vicinae/
│   └── settings.json                 # 启动器配置（Catppuccin Mocha 主题 + snippets provider）
├── bin/
│   ├── wallpaper-rotate.sh           # Wallpaper Engine 壁纸切换 + 电源门控 + 守护
│   ├── wallpaper-power-daemon.sh     # 监听 upower 事件，插拔电源时启停壁纸
│   ├── we-scene-guard.sh             # 巡检 Wallpaper Engine 资产，被 Steam 覆盖回 4K 时降码率
│   └── translate.py                  # 翻译选中文本（Super+D），带 GTK 窗口
└── systemd/
    └── user/
        ├── wallpaper-rotate.service  # 轮换壁纸（配合 .timer，30 分钟一次）
        ├── wallpaper-rotate.timer
        ├── wallpaper-power.service   # 电源门控守护（常驻）
        ├── wallpaper-watchdog.service # 壁纸进程存活检查（配合 .timer，2 分钟一次）
        ├── wallpaper-watchdog.timer
        ├── we-scene-guard.service    # 壁纸资产巡检（配合 .timer，30 分钟一次）
        └── we-scene-guard.timer
```

> 脚本装到 `~/.local/bin/`，systemd unit 装到 `~/.config/systemd/user/`。

## 依赖

```bash
# 基础（Arch 官方源 + AUR）
sudo pacman -S niri kitty nautilus wl-clipboard brightnessctl \
  pipewire wireplumber upower python-gobject gtk3

# 桌面外壳 / 启动器（AUR）
yay -S noctalia-shell vicinae-bin

# 截图 / 键盘控鼠标
#   mark-shot        截图标注（选区后画箭头/方框/马赛克，Ctrl+P 钉图）
#   wl-kbptr         用键盘点击屏幕元素

# 动态壁纸
#   linux-wallpaperengine   Wallpaper Engine 壁纸渲染（AUR）
#   （壁纸资产需通过 Steam 订阅 Workshop 项目）
```

字体需要 **Nerd Font**（如 JetBrainsMono Nerd Font），否则 noctalia 图标显示为空。

## 安装

```bash
# niri 主配置
cp niri/config.kdl ~/.config/niri/config.kdl

# 桌面外壳
mkdir -p ~/.config/noctalia && cp noctalia/config.toml ~/.config/noctalia/

# 启动器
mkdir -p ~/.config/vicinae && cp vicinae/settings.json ~/.config/vicinae/

# 脚本
mkdir -p ~/.local/bin
cp bin/*.sh bin/translate.py ~/.local/bin/
chmod +x ~/.local/bin/wallpaper-rotate.sh ~/.local/bin/wallpaper-power-daemon.sh \
         ~/.local/bin/we-scene-guard.sh ~/.local/bin/translate.py

# systemd user units
mkdir -p ~/.config/systemd/user
cp systemd/user/* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now wallpaper-rotate.timer wallpaper-watchdog.timer \
                               we-scene-guard.timer wallpaper-power.service
```

装完执行 `niri validate` 检查语法（应输出 `config is valid`），重新登录 niri 生效。

## 开机自启

`config.kdl` 里通过 `spawn-at-startup` 拉起三项。**注意：状态栏、通知、锁屏、剪贴板、polkit 认证代理、OSD 全部由 noctalia 一个进程管**，不再需要单独启动 mako / hyprlock / polkit-gnome：

| 启动项 | 作用 |
|---|---|
| `noctalia --daemon` | 桌面外壳：状态栏 / 通知 / 锁屏 / 剪贴板历史 / OSD / polkit |
| `wallpaper-rotate.sh` | 动态壁纸（之后由 systemd timer 每 30 分钟轮换） |
| `vicinae server` | 启动器后台服务（Alt+Space 唤起） |

## 快捷键

### 应用与帮助

| 快捷键 | 功能 |
|---|---|
| `Super+Shift+/` | 显示快捷键帮助浮层 |
| `Super+T` | 打开终端（kitty） |
| `Super+E` | 文件管理器（nautilus） |
| `Super+Delete` | 打开回收站 |
| `Alt+Space` | Vicinae 启动器 |
| `Super+P` / `Super+Ctrl+P` / `Super+Alt+P` | 番茄钟 开始暂停 / 面板 / 重置全部 |

### 窗口管理

| 快捷键 | 功能 |
|---|---|
| `Super+W` | 关闭窗口 |
| `Super+M` / `Super+Shift+M` | 最大化列 / 全屏窗口 |
| `Super+Ctrl+M` | 最大化到边缘 |
| `Super+Ctrl+F` | 扩展列到可用宽度 |
| `Super+C` / `Super+Ctrl+C` | 居中当前列 / 所有可见列 |
| `Super+Shift+F` | 切换浮动 / 平铺 |
| `Super+BracketLeft` / `Super+BracketRight` | 吸收 / 弹出左侧（右侧）窗口 |
| `Super+,` / `Super+.` | 吸收到列 / 从列弹出 |
| `Super+Ctrl+,` / `Super+Ctrl+.` | 与左 / 右窗口交换 |

### 焦点与移动

| 快捷键 | 功能 |
|---|---|
| `Super+←/→/↑/↓`、`Super+H/L` | 焦点移动（上下见下条） |
| `Super+Alt+←→↑↓`、`Super+Alt+HJKL` | 循环导航（到边界后跳上/下个工作区） |
| `Super+Ctrl+←→↑↓`、`Super+Ctrl+HJKL` | 移动列 / 窗口 |
| `Super+Home` / `Super+End` | 聚焦首列 / 末列 |
| `Super+Shift+←→↑↓`、`Super+Shift+HJKL` | 跨显示器焦点移动 |
| `Super+Ctrl+Shift+←→↑↓` | 列移到其它显示器 |
| `Super+Alt+Shift+←→↑↓` | 工作区移到其它显示器 |

### 工作区

| 快捷键 | 功能 |
|---|---|
| `Super+1` ~ `Super+9` | 切换到工作区 N |
| `Super+Ctrl+1` ~ `Super+Ctrl+9` | 把列移到工作区 N |
| `Super+J` / `Super+K` | 下一个 / 上一个工作区（Vim 风格） |
| `Super+Page_Down` / `Super+Page_Up` | 同上（别名） |
| `Super+Ctrl+J/K`、`Super+Ctrl+U/I` | 列移到下 / 上个工作区 |
| `Super+Tab` | 总览（Overview） |
| `Super+Backspace` / `Super+Ctrl+Backspace` | 回到上个工作区 / 上个窗口 |
| `Super+Shift+Page_Down` / `Page_Up` | 工作区下移 / 上移 |
| `Super+滚轮上下` | 切换工作区 |
| `Super+滚轮左右` | 切换列 |
| `Super+Ctrl+滚轮上下` | 列移到上 / 下个工作区 |
| `Super+Ctrl+滚轮左右` | 列左移 / 右移 |

### 尺寸

| 快捷键 | 功能 |
|---|---|
| `Super+R` / `Super+Shift+R` | 正向 / 反向切换列宽 |
| `Super+Ctrl+E` / `Super+Ctrl+Shift+E` | 正向 / 反向切换窗口高度 |
| `Super+Ctrl+R` | 重置窗口高度 |
| `Super+Minus` / `Super+Equal` | 列宽 -10% / +10% |
| `Super+Shift+Minus` / `Super+Shift+Equal` | 窗口高度 -10% / +10% |

### 截图 / 翻译 / 键盘鼠标

| 快捷键 | 功能 |
|---|---|
| `Print` | 截图标注（mark-shot，选区后可画箭头/方框/马赛克，`Ctrl+P` 钉图） |
| `Super+D` | 翻译选中文本（`translate.py`，GTK 窗口） |
| `Super+G` | 键盘点击屏幕元素（wl-kbptr，截屏识别可点区域） |
| `Super+Shift+G` | 键盘移动鼠标指针（全屏网格 + 二分逼近，只挪不点） |
| `Super+Alt+G` | 同上识别流程，但改为右键点击 |

> wl-kbptr 用法：分区标签是字母，`Backspace` 退回上一步，`Esc` 取消。`bisect`/`split` 模式下 `g`/`h`/`b` 分别触发左/右/中键，属内置行为。
> niri 开了 `cursor hide-when-typing`，wl-kbptr 结束后指针可能短暂隐藏，动一下鼠标即恢复。

### 声音 / 亮度 / 媒体

| 快捷键 | 功能 |
|---|---|
| `Fn` 音量键（`XF86Audio*`） | 音量 ±5% / 静音（锁屏时仍可用） |
| `Super+F3` / `Super+F2` | 音量加 / 减（备用，带通知） |
| `Fn` 亮度键（`XF86MonBrightness*`） | 亮度 ±5%（锁屏时仍可用） |
| `Super+F6` / `Super+F5` | 亮度加 / 减（备用，带通知） |
| `XF86AudioPlay/Next/Prev` | 播放暂停 / 下一曲 / 上一曲（走 noctalia，锁屏时仍可用） |
| `Super+Z` / `Super+X` | 上一曲 / 下一曲（媒体键的键盘替代） |
| `Super+Shift+X` | 播放暂停（同上） |

> 为什么要有 `Super+Z/X` 这组：不少外接键盘**没有媒体键**，而笔记本的 `Fn+←/→` 又常被键盘固件直接翻译成**普通方向键**（实测发出 `LEFT`/`RIGHT`，与方向键无法区分）—— 这种情况软件层无解（绑裸方向键会废掉方向键本身）。所以补一组顺手的组合键兜底。媒体控制走 `noctalia msg media`，只对支持 MPRIS 的播放器生效。

### 壁纸 / 剪贴板 / 电源

| 快捷键 | 功能 |
|---|---|
| `Super+F12` / `Super+F11` | 下一张 / 上一张壁纸 |
| `Super+F10` / `Super+Shift+F10` | 壁纸在电池上也显示 / 只充电时显示 |
| `Super+V` | 剪贴板历史（noctalia 面板） |
| `Super+Shift+O` | 立刻熄屏（按键亮回） |
| `Super+Escape` | 暂停 / 恢复所有快捷键（玩游戏、远程桌面） |
| `Ctrl+Alt+Delete` | 退出 niri |
| `Super+Shift+P` / `Q` / `S` | 关机 / 重启 / 挂起（走 noctalia session） |

> `Ctrl+Alt+L`（锁屏并熄屏）当前**注释停用**。noctalia 自带空闲锁屏，如需手动锁屏可取消该行注释，或直接用 `noctalia msg session lock`。

## 组件说明

### 桌面外壳（noctalia）

一个守护进程顶掉原来的 waybar + mako + hyprlock + 剪贴板管理器 + polkit 代理：

- 状态栏、通知、锁屏、剪贴板历史、OSD、音量/亮度浮层
- 快捷键全部走 `noctalia msg ...` 子命令转发，niri 侧只负责按键
- 番茄钟是第三方插件（`thepunkoff/pomodoro`），通过 `noctalia msg plugin` 控制
- 配置在 `noctalia/config.toml`，改完 `noctalia msg reload` 或重启进程

### 动态壁纸

`bin/wallpaper-rotate.sh` 是唯一入口，按参数分模式：

| 调用 | 行为 |
|---|---|
| 无参数 | 轮换到下一张（timer 每 30 分钟调一次） |
| `next` / `prev` | 手动切下 / 上一张 |
| `ensure` | 检查壁纸进程是否还活着，死了就拉起来（watchdog 用） |
| `ignore` / `respect` | 电池供电时也显示 / 只在充电时显示 |

- 电源门控由 `wallpaper-power-daemon.sh` 常驻监听 upower 事件完成，插拔电源自动启停壁纸
- 壁纸进程用 `setsid` 脱离 unit 的 cgroup，所以所有 service 都必须 `KillMode=process`，否则 oneshot 结束会把壁纸一起杀掉
- `wallpaper-power.service` 反而是 `KillMode=control-group`：它要连带清掉 `upower --monitor` 和管道里的 while 子 shell，否则 restart 后新旧两份一起监听、动作翻倍（2026-11-05 实测）

### 壁纸渲染层

`config.kdl` 里用 `layer-rule` 把 `linux-wallpaperengine` 放进 **backdrop 层**：

```kdl
layer-rule {
    match namespace="^linux-wallpaperengine$"
    place-within-backdrop true
}
```

配套要求：`layout` 里的 `background-color` 必须是 `"transparent"`，否则纯色背景会把壁纸整个盖住。放进 backdrop 层还顺带解决了总览（Overview）里壁纸被复制到每个工作区的问题。

### 截图与翻译

- `Print` → `mark-shot`，窗口规则里设了 `open-floating true`，出来是浮窗而不是塞进列里
- `Super+D` → `translate.py`，读取主选区文本，弹 GTK 窗口显示译文（同样 `open-floating`，app-id 是 `Translate.py`，大小写敏感）

### 窗口圆角与毛玻璃

- 全局 `geometry-corner-radius 12` + `clip-to-geometry true`
- VSCode 单独给了半透明 + 背景模糊（`opacity` + `background-effect { blur true }`），**前提是 VSCode 内部背景也设为半透明**，见它的 `workbench.colorCustomizations`
- app-id 两种写法（`^code$` / `^com\.microsoft\.VSCode$`）必须各建一条规则——同一条规则里的多个 `match` 是「且」关系，并列写永远匹配不上
- blur 默认走 xray 模式，模糊的是壁纸而不是下层窗口，这是 niri 的优化行为，不是配置错了

## 说明

- 配置里多处写了**绝对路径** `/home/sky/...`（kitty、vicinae、各脚本、systemd unit）。换用户请全局替换成自己的家目录。
- `niri/config.kdl` 末尾的 `output "eDP-1"` 段固定了 `1920x1080@144.003`。**刷新率必须与 EDID 完全一致**，写 `144` 会回退到 60Hz。
- 配置保存后 niri 自动热加载；强制重载用 `niri msg action load-config-file`。
- 备份文件（`config.kdl.bak-*`、`config.toml.bak-*`）已在 `.gitignore` 中排除。
- 仓库为公开仓库，提交前确认配置里没有密钥/账号信息。
