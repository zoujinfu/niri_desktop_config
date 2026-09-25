# niri 桌面配置

一套基于 **niri** 平铺式 Wayland 合成器的 Ubuntu 桌面配置：全中文注释，含 Waybar 状态栏、mako 通知、hyprlock 锁屏、截图翻译（OCR）、剪贴板历史、音量/亮度/壁纸快捷键与电源管理。

> 环境：Ubuntu 24.04 / niri 26.04（源码编译）/ Wayland
> 硬件：Intel i7-13650HX + NVIDIA RTX 4060（nvidia 驱动）
> 更新时间：2026-09-25

## 目录结构

```
niri_desktop_config/
├── niri/
│   └── config.kdl                    # niri 主配置（中文注释，完整快捷键绑定）
├── waybar/
│   ├── config.jsonc                  # 状态栏模块布局（niri IPC + custom 模块）
│   ├── style.css                     # 状态栏样式（Catppuccin Mocha）
│   └── scripts/
│       ├── niri-workspaces.py        # 工作区胶囊
│       ├── niri-window.py            # 当前窗口标题
│       └── niri-event-daemon.py      # 事件流守护（已停用，改用 IPC 轮询，保留备用）
├── mako/
│   └── config                         # 通知守护配置（历史 + 按应用分组）
├── hypr/
│   └── hyprlock.conf                  # 锁屏界面（Catppuccin Mocha，走 session-lock 协议）
└── bin/
    ├── niri-power                    # 电源管理（弹确认框关机/重启/挂起）
    ├── nirimod                       # 图形化 niri 配置面板启动脚本
    ├── lock-and-off                  # 锁屏 + 立即熄屏（等 hyprlock 接管后再熄）
    ├── markshot-translate-region     # 框选截图 → OCR → 翻译 → 译文原地覆盖
    ├── wallpaper-rotate.sh           # Wallpaper Engine 动态壁纸切换
    └── home-bin/
        └── toggle-copyclip.sh        # 唤起 CopyClip 剪贴板管理器（本文件放 ~/bin/）
```

> `bin/` 下的脚本装到 `~/.local/bin/`，`bin/home-bin/` 下的装到 `~/bin/`。

## 依赖

```bash
# 基础
sudo apt install niri waybar mako slurp grim wl-clipboard \
  brightnessctl playerctl zenity python3

# 锁屏（hyprlock，见下方说明）
sudo apt install hyprlock

# 可选：截图标注 / OCR / 动态壁纸 / 剪贴板管理器
#   mark-shot             截图标注工具（选区后画箭头/方框/马赛克，配 mark-shot-ocr 做 OCR）
#   tesseract-ocr         截图翻译的 OCR 后端（需含 chi_sim 简体中文语言包）
#   linux-wallpaperengine Wallpaper Engine 动态壁纸
#   CopyClip              D-Bus 名 dev.walkercito.CopyClip，剪贴板历史
#   Vicinae               Raycast 风格启动器（Alt+Space）
```

图标字体需要 **Nerd Font**（如 JetBrainsMono Nerd Font），否则状态栏图标显示为空。

## 安装

```bash
# niri
cp niri/config.kdl ~/.config/niri/config.kdl

# waybar
mkdir -p ~/.config/waybar/scripts
cp waybar/config.jsonc waybar/style.css ~/.config/waybar/
cp waybar/scripts/*.py ~/.config/waybar/scripts/
chmod +x ~/.config/waybar/scripts/*.py

# mako
mkdir -p ~/.config/mako && cp mako/config ~/.config/mako/config

# hyprlock（锁屏界面；PAM 需要 /etc/pam.d/hyprlock，多数发行版的 hyprlock 包会自带）
mkdir -p ~/.config/hypr && cp hypr/hyprlock.conf ~/.config/hypr/hyprlock.conf

# 脚本（bin/ 下的装到 ~/.local/bin/，home-bin/ 下的装到 ~/bin/）
mkdir -p ~/.local/bin ~/bin
cp bin/niri-power bin/nirimod bin/lock-and-off bin/markshot-translate-region ~/.local/bin/
cp bin/wallpaper-rotate.sh ~/.local/bin/
cp bin/home-bin/toggle-copyclip.sh ~/bin/
chmod +x ~/.local/bin/{niri-power,nirimod,lock-and-off,markshot-translate-region,wallpaper-rotate.sh} ~/bin/toggle-copyclip.sh
```

装完执行 `niri validate` 检查语法（应输出 `config is valid`），重新登录 niri 生效。

## 开机自启

`config.kdl` 里通过 `spawn-at-startup` 拉起：

| 启动项 | 作用 |
|---|---|
| `env GDK_BACKEND=wayland waybar` | 状态栏 |
| `mako` | 通知守护 |
| `vicinae server` | 启动器后台服务 |
| `wallpaper-rotate.sh` | 动态壁纸 |
| `polkit-gnome-authentication-agent-1` | Polkit 认证代理（pkexec 弹密码框必需） |
| `xhost +si:localuser:root` | 授权 root 访问显示服务器（timeshift / gparted 等 GUI 需要） |

## 快捷键

### 应用与帮助

| 快捷键 | 功能 |
|---|---|
| `Super+Shift+/` | 显示快捷键帮助浮层 |
| `Super+\`` | 快捷键速查表（niri-cheatsheet） |
| `Super+T` | 打开终端（kitty） |
| `Super+E` | 文件管理器 |
| `Super+Delete` | 打开回收站 |
| `Alt+Space` | Vicinae 启动器 |

### 窗口管理

| 快捷键 | 功能 |
|---|---|
| `Super+W` | 关闭窗口 |
| `Super+M` / `Super+Shift+M` | 最大化列 / 全屏窗口 |
| `Super+Ctrl+M` | 最大化到边缘 |
| `Super+Ctrl+F` | 扩展列到可用宽度 |
| `Super+C` / `Super+Ctrl+C` | 居中当前列 / 所有可见列 |
| `Super+Shift+F` | 切换浮动 / 平铺 |
| `Super+Shift+T` | 切换列标签页显示 |
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
| `Super+Ctrl+J/K`、`Super+Ctrl+Page_Down/Up` | 列移到下 / 上个工作区 |
| `Super+Tab` | 总览（Overview） |
| `Super+Backspace` / `Super+Ctrl+Backspace` | 回到上个工作区 / 上个窗口 |
| `Super+Shift+Page_Down` / `Page_Up` | 工作区下移 / 上移 |
| `Super+滚轮上下` | 切换工作区 |
| `Super+Ctrl+滚轮左右` | 列左移 / 右移 |

### 尺寸

| 快捷键 | 功能 |
|---|---|
| `Super+R` / `Super+Shift+R` | 正向 / 反向切换列宽 |
| `Super+Ctrl+E` / `Super+Ctrl+Shift+E` | 正向 / 反向切换窗口高度 |
| `Super+Ctrl+R` | 重置窗口高度 |
| `Super+-` / `Super+=` | 列宽 -10% / +10% |
| `Super+Shift+-` / `Super+Shift+=` | 窗口高度 -10% / +10% |

### 截图与翻译

| 快捷键 | 功能 |
|---|---|
| `Print` | 截图标注（mark-shot，选区后可画箭头/方框/马赛克，`Ctrl+P` 钉图） |
| `Super+A` | **截图翻译**：框选区域 → OCR → 翻译成中文 → 译文原地盖在原文上 |

> 2026-09-19 起截图收敛为裸 `Print` 一个键；2026-09-24 新增 `Super+A` 截图翻译。
> `Super+Shift+E`（剪贴板文本翻译）已注释停用。

### 声音 / 亮度 / 媒体

| 快捷键 | 功能 |
|---|---|
| `Fn` 音量键（`XF86Audio*`） | 音量 ±5% / 静音（锁屏时仍可用） |
| `Super+F3` / `Super+F2` | 音量加 / 减（备用，带通知） |
| `Fn` 亮度键（`XF86MonBrightness*`） | 亮度 ±5%（锁屏时仍可用） |
| `Super+F6` / `Super+F5` | 亮度加 / 减（备用，带通知） |
| `XF86AudioPlay/Next/Prev` | 播放暂停 / 下一曲 / 上一曲 |

### 壁纸 / 剪贴板 / 电源

| 快捷键 | 功能 |
|---|---|
| `Super+F12` / `Super+F11` | 下一张 / 上一张壁纸 |
| `Super+V` | 剪贴板历史（CopyClip） |
| `Super+Shift+O` | 立刻熄屏（DPMS off，按键亮回） |
| `Super+Escape` | 暂停 / 恢复所有快捷键（玩游戏、远程桌面） |
| `Ctrl+Alt+L` | **锁屏并熄屏**（hyprlock + 立即黑屏） |
| `Ctrl+Alt+Delete` | 退出 niri |
| `Super+Shift+P` / `Q` / `S` | 关机 / 重启 / 挂起（zenity 确认框防误触） |

## 组件说明

### 状态栏（waybar）

- 左：工作区胶囊 + 当前窗口标题（走 `niri msg -j` IPC，直接查询、无需守护进程）
- 中：日期时间
- 右：音量 / 亮度 / 网络 / CPU / **CPU 温度** / 内存 / 电池 / 待机抑制 / 托盘 / 电源按钮
- 温度模块用 `hwmon-name: "coretemp"` 匹配，**不写死 hwmon 编号**（插拔设备后编号会漂移）
- ⚠️ Nerd Font 图标是私有区（PUA）字符，用编辑器批量处理时容易被吞掉。本仓库的配置文件图标完整，请勿手工重排。

### 锁屏（hyprlock）

`Ctrl+Alt+L` 调用 `bin/lock-and-off`：启动 hyprlock → 等 0.8s 确认它接管 session lock → 熄屏。

- 之所以不用 niri 里直接写两行 action：`spawn` 是异步的，熄屏会抢在锁屏接管之前，**按键唤醒的瞬间可能瞥见未锁的桌面**。
- ⚠️ 锁屏界面配置为仓库内的 `hypr/hyprlock.conf`（Catppuccin Mocha，含深色遮罩 + 三态输入反馈），装到 `~/.config/hypr/hyprlock.conf`。
- ⚠️ 该配置里 **`general.immediate_render = true` 不能删**：不开的话 hyprlock 会等背景截图就绪才开始绘制，那段时间屏幕全黑、要按一下键才出现界面。
- ⚠️ 深色 `shape` 遮罩也不能删：不加时截到浅色窗口 → 背景发白发灰、浅色文字全糊掉。加了遮罩后，`label` / `input-field` 必须显式 `zindex = 2`，否则会被遮住。
- 解锁卡住时：`pkill -USR1 hyprlock`。**切勿 SIGTERM / SIGKILL**——niri 走 ext-session-lock 协议，强杀会黑屏死锁。

### 截图翻译（`Super+A`）

`bin/markshot-translate-region`：`slurp` 选区 → `grim` 截图 → `mark-shot --pin-image`，并钉死四个环境变量让贴图窗口自动 OCR + 自动翻译，译文用 OCR 原始 box 原地覆盖原文（不落盘，Esc 关闭）。

mark-shot 本身不给 OCR / 翻译提供快捷键，所以只能挂 niri 侧。译文依赖本地 OpenAI 兼容 shim（把 `/chat/completions` 转到 Google 翻译端点），**该 shim 未包含在本仓库**；缺少时只出 OCR 原文、没有译文。

### 通知（mako）

`default-timeout=5000`（5 秒自动消失）+ 保留历史 200 条 + 按应用名分组 + 最多同时显示 5 条。

### 剪贴板

`Super+V` 唤起 CopyClip。X11 侧的剪贴板桥由 niri 托管的 `xwayland-satellite` 提供，无需额外脚本。

## 说明

- 配置里多处写了 **绝对路径** `/home/sky/...`（kitty、vicinae、各脚本）。换用户请全局替换成自己的家目录。
- `niri/config.kdl` 末尾的 `output "eDP-1"` 段固定了 1920x1080@144Hz，请按自己的显示器改。
- 配置保存后 niri 自动热加载；强制重载用 `niri msg action load-config-file`。
- 备份文件（`*.bak-*`）已在 `.gitignore` 中排除，不会误提交。
