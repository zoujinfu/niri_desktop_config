# niri 桌面配置

一套基于 **niri** 平铺式 Wayland 合成器的桌面配置，包含中文注释、Waybar 状态栏美化、剪贴板历史、通知、音量/亮度快捷键和电源管理。

> 环境：Ubuntu 24.04 / niri 26.04 / Wayland
> 相关：NVIDIA RTX 4060 + nvidia 驱动

## 目录结构

```
niri_desktop_config/
├── niri/
│   └── config.kdl          # niri 主配置（含中文注释，快捷键绑定）
├── waybar/
│   ├── config.jsonc        # 状态栏模块布局（custom 模块 + niri IPC）
│   ├── style.css           # 状态栏样式（深色半透明/圆角胶囊）
│   └── scripts/
│       ├── niri-workspaces.py   # 工作区胶囊（GTK markup 内联样式）
│       └── niri-window.py       # 当前窗口标题
├── mako/
│   └── config              # 通知守护配置（5 秒自动消失）
└── bin/
    ├── niri-power          # 电源管理脚本（弹确认框关机/重启/挂起）
    └── nirimod             # 图形化 niri 配置面板启动脚本
```

## 依赖

```bash
sudo apt install niri waybar mako swaybg fuzzel alacritty \
  cliphist wl-clipboard brightnessctl wpctl playerctl swaylock \
  python3-pip zenity
```

图标字体需要 Nerd Font（如 JetBrainsMono Nerd Font）才能正常显示方式栏图标。

## 安装

将各文件软链/复制到对应位置：

```bash
# niri
cp niri/config.kdl ~/.config/niri/config.kdl

# waybar
cp -r waybar/* ~/.config/waybar/

# mako
cp mako/config ~/.config/mako/config

# 电源脚本 & nirimod 启动器
cp -r bin/* ~/.local/bin/
chmod +x ~/.local/bin/niri-power ~/.local/bin/nirimod
```

然后重新登录 niri 生效。

## 功能亮点

### Waybar 状态栏
- 左侧：工作区胶囊（active 高亮主题绿）+ 当前窗口标题
- 中央：日期时间
- 右侧：网络 / CPU / 内存 / 电池 / 托盘
- 用 `custom` 模块 + `niri msg` IPC 实现（waybar 0.9.24 无 niri 模块时也可用）

### 剪贴板历史
- 启动项自动记录复制内容：`wl-paste --watch cliphist store`
- 按 `Super+V`（Win+V）弹出 fuzzel 剪贴板历史选择器

### 通知（mako）
- `default-timeout=5000` + `ignore-timeout=1`：通知 5 秒自动消失

### 音量 / 亮度
- Fn 媒体键 + 备用 `Super+F2/F3`（音量）、`Super+F5/F6`（亮度），带百分比通知

### 电源管理
- `Super+Shift+P` 关机 / `Super+Shift+Q` 重启 / `Super+Shift+S` 挂起（均弹确认框）
- 用 zenity 确认，防止误触

### 图形化设置
- `nirimod`（NiriMod，GTK4/libadwaita），在 fuzzel 搜 "NiriMod" 打开

## 常用快捷键

| 快捷键 | 功能 |
|--------|------|
| `Super+T` | 打开终端 |
| `Alt+Space` | 打开应用启动器（fuzzel） |
| `Super+V` | 剪贴板历史 |
| `Super+left/right/up/down` | 聚焦左右列/上下窗口 |
| `Super+Ctrl+left/right/up/down` | 移动列/窗口 |
| `Super+F3/F2` | 音量加/减（备用） |
| `Super+F6/F5` | 亮度加/减（备用） |
| `Super+L` | 锁屏 |
| `Super+Shift+P/Q/S` | 关机/重启/挂起 |

更多完整快捷键见 `niri/config.kdl` 内中文注释。

## 说明

- `niri/config.kdl` 中壁纸路径已用 `~/Pictures/Wallpapers/` 通用写法，请按需替换。
- 配置保存后 niri 自动热加载，可用 `niri validate` 检查语法。
