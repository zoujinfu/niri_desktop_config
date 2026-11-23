#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""translate.py — niri 翻译窗口（左原文 / 右译文，可手输，停顿自动翻译）

用法
    Super+D          取「选中文本 → 剪贴板」填进左侧原文，右侧自动出译文
                     窗口已开着时再按 Super+D 会重新取词并刷新（不会开第二个窗口）
    左侧直接输入/粘贴 停顿 0.6 秒自动翻译；Ctrl+Enter 立刻翻
    右侧选中即可 Ctrl+C 复制；Ctrl+Shift+C 复制整段译文
    Esc 关闭 · Ctrl+R 重新取词 · Ctrl+L 回到原文
    Ctrl+E 切换译文语言（自动 → 英 → 中 → 日 → 自动）

翻译方向（自动判断，不用你选）
    选中的是中文      -> 翻成英文
    选中的是日文      -> 翻成中文
    其它（英/法/德…） -> 翻成中文
    想固定方向就设 HUACI_DST，或在窗口里用 Ctrl+E 切换

为什么这么写（和 ~/.config/niri/config.kdl 的约定对齐）
    * 路径固定 ~/bin/translate.py —— 配置里「剪贴板/翻译」段的 Super+D 就是它
    * 窗口 app-id 必须是 "Translate.py"：配置里已有
      window-rule { match app-id="Translate.py"; open-floating true }
      所以脚本开头显式 GLib.set_prgname()，不吃 GTK 推导的亏
    * 单实例：用 $XDG_RUNTIME_DIR/translate-py.sock 做 IPC。第二次 Super+D
      把「刚取到的选区」发给已开着的窗口再退出，避免开出一堆重复窗口。
    * 翻译后端走 Mozhi 的 HTTP API（POST /api/translate），不再经过 crow CLI
      原因（2026-10-24）：crow 默认引擎 google 所在的 Mozhi 实例被限流，
      返回 HTTP 500 "instance has been rate limited"；换别的实例也是 500 / 连不上。
      而同一实例上 duckduckgo / yandex 引擎是好的。
      另外 crow 的 -s 只能吃显式语言码，传 auto 会在本地崩
      (Parsing error: 无法解析自动检测到的语言)，而服务端 from=auto 的识别是准的。
      text 放进 POST body，还能绕开 GET 的 URL 长度上限（414 / 431）。
    * 选区仍用 wl-paste 取：Qt 的 Wayland 后端不支持 QClipboard::Selection，
      任何依赖 crow/Qt 自己读 PRIMARY 的做法都取不到东西。
    * 译文用 Gtk.TextView(editable=False) 而不是 Label：可整段选中复制，
      并且样式上和左侧输入框对齐；Label 一拿焦点就全选自己，很丑。

环境变量
    HUACI_INSTANCE           Mozhi 实例地址，默认 https://mozhi.ducks.party
    HUACI_INSTANCE_FALLBACK  备用实例，逗号分隔
    HUACI_ENGINES            引擎回退顺序，默认 duckduckgo,yandex
    HUACI_DST                强制译文语言（zh / en / ja 等），默认按原文自动判断
    HUACI_KEEP_OPEN          设为 1 则失焦/超时不自动关
    HUACI_SOURCE             调试用：直接把它当成原文，不读选区
    HUACI_DEBUG              设为 1 时把过程打到 stderr
"""

import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import threading
import urllib.error
import urllib.parse
import urllib.request

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")

from gi.repository import Gdk, GLib, Gtk  # noqa: E402

INSTANCE = os.environ.get("HUACI_INSTANCE", "https://mozhi.ducks.party")
# 实例也做回退：一个 Mozhi 站挂了不影响用（2026-10 实测这两个都活着）
INSTANCES = [INSTANCE] + [
    u.strip()
    for u in os.environ.get("HUACI_INSTANCE_FALLBACK", "https://mozhi.pussthecat.org").split(",")
    if u.strip() and u.strip() != INSTANCE
]
# 引擎按顺序回退：前一个失败就试下一个。
# duckduckgo 译得最自然，但正文超过约 1100 字符会 500；yandex 能吃长文，译文略生硬。
ENGINES = [e.strip() for e in os.environ.get("HUACI_ENGINES", "duckduckgo,yandex").split(",") if e.strip()]
KEEP_OPEN = os.environ.get("HUACI_KEEP_OPEN") == "1"
DEBUG = os.environ.get("HUACI_DEBUG") == "1"
DEBOUNCE_MS = 600          # 手输停顿多久后自动翻译
AUTO_CLOSE_MS = 45_000     # 无操作多久自动关（用户改过原文后不再自动关）
TIMEOUT = 20
SOCK_NAME = "translate-py.sock"

HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")  # 汉字
KANA = re.compile(r"[\u3040-\u30ff\u31f0-\u31ff]")  # 日文假名
LANG_NAME = {
    "zh": "中文", "en": "英文", "ja": "日文", "ko": "韩文",
    "fr": "法文", "de": "德文", "ru": "俄文", "es": "西班牙文",
}
# Ctrl+E 的循环顺序
LANG_CYCLE = [None, "en", "zh", "ja"]

CSS = b"""
.translate-window { background-color: #1e1e2e; }
.pane-frame {
    background-color: #181825;
    border: 1px solid #313244;
    border-radius: 10px;
}
textview.src-view, textview.dst-view {
    background-color: transparent;
    color: #cdd6f4;
    font-size: 13pt;
}
textview.dst-view { color: #cdd6f4; }
.toolbar { margin-bottom: 2px; }
.toolbar button {
    font-size: 10pt;
    padding: 2px 10px;
    border-radius: 6px;
    background-color: #313244;
    color: #cdd6f4;
}
.toolbar button:hover { background-color: #45475a; }
.dir-chip {
    color: #89b4fa;
    font-size: 10.5pt;
    padding: 0 6px;
}
.hint { color: #6c7086; font-size: 9pt; }
.placeholder { color: #6c7086; font-size: 12pt; }
"""


def log(*a):
    if DEBUG:
        print("[translate.py]", *a, file=sys.stderr, flush=True)


# ---------------------------------------------------------------- 翻译方向

def target_lang(text):
    """决定译文语言。

    中英互译是有意的：划词选中的若是中文，用户多半是想看英文怎么说，
    翻成中文等于什么都没做。HUACI_DST 可以强制指定。
    """
    forced = os.environ.get("HUACI_DST")
    if forced:
        return forced
    if KANA.search(text):
        return "zh"  # 日文 -> 中文
    if HAN.search(text):
        return "en"  # 中文 -> 英文
    return "zh"  # 英/法/德… -> 中文


def lang_name(code):
    return LANG_NAME.get(code, code or "")


# ---------------------------------------------------------------- 取词

def read_selection():
    """优先取 PRIMARY 选区，取不到再退到普通剪贴板。"""
    forced = os.environ.get("HUACI_SOURCE")
    if forced is not None:
        return forced.strip()
    for flags in (["--primary"], []):
        try:
            r = subprocess.run(
                ["wl-paste", *flags, "--no-newline"],
                capture_output=True, text=True, timeout=5,
            )
            text = r.stdout
        except Exception as e:  # noqa: BLE001
            log("wl-paste 失败:", e)
            continue
        if text.strip():
            log("取到文本", len(text), "字符，来源:", flags or ["clipboard"])
            return text.strip()
    return ""


# ---------------------------------------------------------------- 翻译后端

def _ask(instance, engine, text, dst):
    """向某个 Mozhi 实例的 HTTP API 要一次翻译。返回译文，失败抛异常。

    直接用 HTTP 而不用 crow CLI：crow 只认「显式 -s 源语言」，
    传 auto 会在本地解析阶段就崩（Parsing error: 无法解析自动检测到的语言），
    而服务端 from=auto 的自动识别是好的。用 text 走 POST body 还能绕开
    GET 的 URL 长度限制。
    """
    body = urllib.parse.urlencode({"text": text, "from": "auto", "to": dst}).encode()
    url = f"{instance}/api/translate?engine={urllib.parse.quote(engine)}"
    req = urllib.request.Request(
        url, data=body, method="POST",
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": "translate.py/3.0 (+niri)",
        },
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        data = json.load(r)
    out = (data.get("translated-text") or "").strip()
    if not out:
        raise ValueError("服务端返回了空译文")
    log("引擎", engine, "检测到语言", data.get("detected"))
    return out


def engine_order(text):
    """长文先走 yandex：duckduckgo 引擎正文超过约 1100 字符会 500，先试它纯属浪费一次往返。"""
    if len(text) > 1000 and ENGINES and ENGINES[0] == "duckduckgo":
        return ENGINES[1:] + ENGINES[:1]
    return ENGINES


def translate(text, dst):
    """先按「实例 × 引擎」顺序回退，第一个成功的就返回。"""
    last = None
    for instance in INSTANCES:
        for engine in engine_order(text):
            log("执行: POST", instance, "engine=" + engine, "| dst=" + dst, "| 长度", len(text))
            try:
                return _ask(instance, engine, text, dst), None
            except urllib.error.HTTPError as e:
                detail = ""
                try:
                    detail = e.read().decode("utf-8", "replace").strip()
                except Exception:  # noqa: BLE001
                    pass
                last = f"{engine}@{instance.split('//')[-1]}: HTTP {e.code}" + (f" · {detail}" if detail else "")
                log("失败", last)
            except urllib.error.URLError as e:
                last = f"{engine}@{instance.split('//')[-1]}: 连不上（{e.reason}）"
                log("失败", last)
            except Exception as e:  # noqa: BLE001
                last = f"{engine}@{instance.split('//')[-1]}: {e}"
                log("失败", last)
    return None, f"翻译失败 · {last or '没有可用引擎'}"


# ---------------------------------------------------------------- 单实例 IPC

def socket_path():
    base = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
    return os.path.join(base, SOCK_NAME)


def notify_running(payload):
    """把命令发给已经开着的窗口。成功返回 True；没有实例/连不上返回 False。"""
    path = socket_path()
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(0.8)
    try:
        s.connect(path)
    except FileNotFoundError:
        return False            # 没开，正常路径
    except ConnectionRefusedError:
        _drop_stale_socket(path)  # 文件在但没人听：上次被 kill -9 的残留
        return False
    except OSError as e:
        # 超时之类：窗口可能正忙，别删它的 socket
        log("连接已有窗口出错:", e)
        return False

    try:
        s.sendall(json.dumps(payload).encode() + b"\n")
        # 等对方 ack：能读到 'ok' 才算真的送到窗口手里
        try:
            s.settimeout(1.5)
            ack = s.recv(16)
        except OSError:
            ack = b""
        if ack.strip() != b"ok":
            log("已有窗口无应答，当作没开:", ack)
            return False
        return True
    except OSError as e:
        log("发送命令失败:", e)
        return False
    finally:
        try:
            s.close()
        except OSError:
            pass


def _drop_stale_socket(path):
    """socket 文件还在但没人监听（比如上次进程被 -9 杀掉），删掉它。"""
    try:
        if os.path.exists(path):
            os.unlink(path)
            log("清理残留 socket:", path)
    except OSError as e:
        log("清理残留 socket 失败:", e)


# ---------------------------------------------------------------- 界面

class TranslateWindow(Gtk.Window):
    def __init__(self, app, initial_text=""):
        super().__init__(application=app, title="翻译")
        self.set_default_size(1040, 580)
        self.set_size_request(760, 420)
        self.add_css_class("translate-window")

        self._gen = 0                 # 每次请求自增，回包时用它丢弃过期结果
        self._timer_id = 0            # 防抖定时器
        self._auto_close_id = 0
        self._user_edited = False     # 用户手改过原文 -> 不再失焦/超时关闭
        self._suppress = False        # set_text 时抑制 buffer changed
        self._override = os.environ.get("HUACI_DST") or None
        self._armed = False

        # ---------------- 顶部工具条 ----------------
        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        bar.add_css_class("toolbar")

        self._dir_lbl = Gtk.Label(label="自动")
        self._dir_lbl.add_css_class("dir-chip")
        self._dir_lbl.set_xalign(0)
        bar.append(self._dir_lbl)

        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        bar.append(spacer)

        self._copy_btn = Gtk.Button(label="复制译文")
        self._copy_btn.connect("clicked", lambda *_: self._copy())
        self._reload_btn = Gtk.Button(label="重新取词")
        self._reload_btn.connect("clicked", lambda *_: self._reload_selection(async_read=True))
        self._clear_btn = Gtk.Button(label="清空")
        self._clear_btn.connect("clicked", lambda *_: self._clear())
        for b in (self._copy_btn, self._reload_btn, self._clear_btn):
            bar.append(b)

        # ---------------- 左右分栏 ----------------
        paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        paned.set_wide_handle(True)
        paned.set_position(518)
        paned.set_resize_start_child(True)
        paned.set_resize_end_child(True)
        paned.set_shrink_start_child(True)
        paned.set_shrink_end_child(True)
        # Gtk.Paned 的子项默认不撑满高度：不设 vexpand 的话两个窗格只有内容那么高，
        # 下面留一大片空窗口背景，译文长一点就被裁掉
        paned.set_vexpand(True)

        # 左侧：可编辑原文
        self.src_view = self._make_view("src-view", editable=True)
        self.src_buf = self.src_view.get_buffer()
        self.src_buf.connect("changed", self._on_src_changed)
        self._placeholder = Gtk.Label(label="在这里输入或粘贴要翻译的文字…")
        self._placeholder.add_css_class("placeholder")
        self._placeholder.set_can_target(False)
        self._placeholder.set_halign(Gtk.Align.START)
        self._placeholder.set_valign(Gtk.Align.START)
        self._placeholder.set_margin_top(14)
        self._placeholder.set_margin_start(16)
        src_overlay = Gtk.Overlay()
        src_overlay.set_vexpand(True)
        src_overlay.set_hexpand(True)
        src_overlay.set_child(self._frame(self.src_view))
        src_overlay.add_overlay(self._placeholder)
        paned.set_start_child(src_overlay)

        # 右侧：只读译文（可选中复制）
        self.dst_view = self._make_view("dst-view", editable=False)
        self.dst_buf = self.dst_view.get_buffer()
        self._tag_wait = self.dst_buf.create_tag("wait", foreground="#f9e2af")
        self._tag_err = self.dst_buf.create_tag("err", foreground="#f38ba8")
        self._tag_muted = self.dst_buf.create_tag("muted", foreground="#6c7086")
        paned.set_end_child(self._frame(self.dst_view))

        # ---------------- 底部提示 ----------------
        self.hint = Gtk.Label(
            label="Esc 关闭 · Ctrl+Enter 翻译 · Ctrl+Shift+C 复制译文 · "
                  "Ctrl+R 重新取词 · Ctrl+E 切换译文语言"
        )
        self.hint.set_xalign(0)
        self.hint.add_css_class("hint")

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        root.set_margin_top(12)
        root.set_margin_bottom(10)
        root.set_margin_start(14)
        root.set_margin_end(14)
        root.append(bar)
        root.append(paned)
        root.append(self.hint)
        self.set_child(root)

        # ---------------- 快捷键 ----------------
        keys = Gtk.EventControllerKey()
        # CAPTURE：不管焦点在哪个子控件上，Esc/组合键都先被这里接住
        keys.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        keys.connect("key-pressed", self._on_key)
        self.add_controller(keys)

        self.connect("notify::is-active", self._on_active)

        if initial_text:
            self._set_source(initial_text, translate_now=True)
        else:
            self._suppress = True
            self.src_buf.set_text("")  # 确保 placeholder 与空 buffer 状态同步
            self._suppress = False
            self._refresh_placeholder()
            self._update_dir_label()
            GLib.idle_add(self._focus_source)

        self._arm_auto_close()

    # ------------------------------------------------------------ 构件

    def _make_view(self, css_class, editable):
        v = Gtk.TextView()
        v.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        v.set_editable(editable)
        v.set_cursor_visible(editable)
        v.set_can_focus(True)
        v.set_top_margin(10)
        v.set_bottom_margin(10)
        v.set_left_margin(12)
        v.set_right_margin(12)
        v.add_css_class(css_class)
        return v

    def _frame(self, view):
        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        sw.set_child(view)
        sw.set_vexpand(True)
        sw.set_hexpand(True)
        sw.add_css_class("pane-frame")
        return sw

    # ------------------------------------------------------------ 文本读写

    def _src_text(self):
        return self.src_buf.get_text(
            self.src_buf.get_start_iter(), self.src_buf.get_end_iter(), False
        )

    def _dst_text(self):
        return self.dst_buf.get_text(
            self.dst_buf.get_start_iter(), self.dst_buf.get_end_iter(), False
        )

    def _set_source(self, text, translate_now=False):
        self._suppress = True
        self.src_buf.set_text(text)
        self._suppress = False
        end = self.src_buf.get_end_iter()
        self.src_buf.place_cursor(end)
        self._refresh_placeholder()
        if translate_now:
            self._translate_now()
        else:
            self._schedule_translate()

    def _set_dst(self, text, tag=None):
        self.dst_buf.set_text("")
        if not text:
            return
        end = self.dst_buf.get_end_iter()
        if tag is not None:
            self.dst_buf.insert_with_tags(end, text, tag)
        else:
            self.dst_buf.insert(end, text)

    def _refresh_placeholder(self):
        empty = not self._src_text().strip()
        self._placeholder.set_visible(empty)

    def _update_dir_label(self):
        text = self._src_text()
        if self._override:
            self._dir_lbl.set_label(f"译文固定：{lang_name(self._override)}")
        elif text.strip():
            self._dir_lbl.set_label(f"自动：{lang_name(target_lang(text))}")
        else:
            self._dir_lbl.set_label("自动：按原文判断")

    def _focus_source(self):
        self.src_view.grab_focus()
        return False

    # ------------------------------------------------------------ 翻译调度

    def _on_src_changed(self, _buf):
        if self._suppress:
            return
        self._user_edited = True
        self._cancel_auto_close()
        self._refresh_placeholder()
        self._update_dir_label()
        self._schedule_translate()

    def _schedule_translate(self):
        self._cancel_timer()
        self._timer_id = GLib.timeout_add(DEBOUNCE_MS, self._on_debounce)

    def _on_debounce(self):
        self._timer_id = 0
        self._translate_now()
        return False

    def _cancel_timer(self):
        if self._timer_id:
            GLib.source_remove(self._timer_id)
            self._timer_id = 0

    def _translate_now(self):
        self._cancel_timer()
        text = self._src_text().strip()
        self._update_dir_label()
        if not text:
            self._set_dst("")
            self._gen += 1
            return
        dst = self._override or target_lang(text)
        self._gen += 1
        gen = self._gen
        self._set_dst(f"翻译中…（{lang_name(dst)}）", self._tag_wait)
        threading.Thread(target=self._worker, args=(gen, text, dst), daemon=True).start()

    def _worker(self, gen, text, dst):
        out, err = translate(text, dst)
        GLib.idle_add(self._apply, gen, out, err, dst)

    def _apply(self, gen, out, err, dst):
        if gen != self._gen:
            log("丢弃过期结果 gen=%s 当前=%s" % (gen, self._gen))
            return False
        if err:
            self._set_dst(err, self._tag_err)
        else:
            self._set_dst(out)
        self.hint.set_label(
            f"译文语言：{lang_name(dst)} · Esc 关闭 · Ctrl+Shift+C 复制译文 · Ctrl+E 切换语言"
        )
        return False

    # ------------------------------------------------------------ 动作

    def _copy(self):
        text = self._dst_text().strip()
        if not text:
            self._flash("还没有译文")
            return
        try:
            # 用 wl-copy 而不是 GdkClipboard：进程退出后 wl-copy 会留在后台持有
            # 剪贴板内容，GTK 自己持有的话窗口一关内容就没了
            subprocess.run(["wl-copy"], input=text, text=True, timeout=5, check=True)
            self._flash("已复制译文到剪贴板")
        except Exception as e:  # noqa: BLE001
            log("复制失败:", e)
            self._flash("复制失败")

    def _clear(self):
        self._suppress = True
        self.src_buf.set_text("")
        self._suppress = False
        self._user_edited = False
        self._arm_auto_close()
        self._refresh_placeholder()
        self._update_dir_label()
        self._gen += 1
        self._set_dst("")
        self._flash("已清空，直接输入即可")
        self._focus_source()

    def _reload_selection(self, async_read=False):
        """重新从 PRIMARY/剪贴板取词。async_read=True 时放后台，避免卡住界面。"""
        self._flash("正在取词…")
        if not async_read:
            text = read_selection()
            self._apply_reload(text)
            return

        def work():
            text = read_selection()
            GLib.idle_add(self._apply_reload, text)

        threading.Thread(target=work, daemon=True).start()

    def _apply_reload(self, text):
        if text.strip():
            self._set_source(text.strip(), translate_now=True)
            self._flash("已重新取词")
        else:
            self._flash("没读到选中文本，可直接输入")
        self.present()
        GLib.idle_add(self._focus_source)
        return False

    def _cycle_lang(self):
        cur = self._override
        try:
            i = LANG_CYCLE.index(cur)
        except ValueError:
            i = 0
        self._override = LANG_CYCLE[(i + 1) % len(LANG_CYCLE)]
        self._update_dir_label()
        self._flash("译文语言：" + ("自动判断" if self._override is None else lang_name(self._override)))
        self._translate_now()

    def _flash(self, msg):
        self.hint.set_label(msg)
        GLib.timeout_add(2500, self._restore_hint)

    def _restore_hint(self):
        self.hint.set_label(
            "Esc 关闭 · Ctrl+Enter 翻译 · Ctrl+Shift+C 复制译文 · "
            "Ctrl+R 重新取词 · Ctrl+E 切换译文语言"
        )
        return False

    # ------------------------------------------------------------ 生命周期

    def _arm_auto_close(self):
        self._cancel_auto_close()
        if KEEP_OPEN or self._user_edited:
            return
        self._auto_close_id = GLib.timeout_add(AUTO_CLOSE_MS, self._auto_close)

    def _cancel_auto_close(self):
        if self._auto_close_id:
            GLib.source_remove(self._auto_close_id)
            self._auto_close_id = 0

    def _auto_close(self):
        self._auto_close_id = 0
        if not self._user_edited:
            log("无操作超时，自动关闭")
            self.close()
        return False

    def _on_active(self, *_):
        if self.is_active():
            self._armed = True
            self._arm_auto_close()
        elif self._armed:
            # 点别的窗口就收起，符合「划词弹窗」的直觉；
            # 但用户已在原文里改过字，说明在编辑，就别抢着关掉
            if self._user_edited or KEEP_OPEN:
                return
            GLib.timeout_add(150, self._maybe_close)

    def _maybe_close(self):
        if not self.is_active() and not self._user_edited:
            self.close()
        return False

    def _on_key(self, _ctrl, keyval, _code, state):
        ctrl = bool(state & Gdk.ModifierType.CONTROL_MASK)
        shift = bool(state & Gdk.ModifierType.SHIFT_MASK)
        if DEBUG:
            log("key: %s ctrl=%s shift=%s" % (Gdk.keyval_name(keyval), ctrl, shift))

        if keyval == Gdk.KEY_Escape:
            self.close()
            return True
        if not ctrl:
            return False
        if keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self._translate_now()
            return True
        if shift and keyval in (Gdk.KEY_c, Gdk.KEY_C):
            self._copy()
            return True
        if keyval in (Gdk.KEY_r, Gdk.KEY_R):
            self._reload_selection(async_read=True)
            return True
        if keyval in (Gdk.KEY_e, Gdk.KEY_E):
            self._cycle_lang()
            return True
        if keyval in (Gdk.KEY_l, Gdk.KEY_L):
            self._focus_source()
            return True
        return False

    # 外部（第二次 Super+D）调用的入口
    def handle_command(self, payload):
        text = (payload or {}).get("text") or ""
        if text.strip():
            self._set_source(text.strip(), translate_now=True)
            self._flash("已更新原文")
        else:
            self._flash("没有读到新的选中文本")
        self.present()
        GLib.idle_add(self._focus_source)
        return False


# ---------------------------------------------------------------- 入口

def serve(app, window):
    """监听本地 socket，让后续 Super+D 复用这个窗口。

    用标准库 socket 而不是 Gio.SocketService：PyGObject 里
    Gio.SocketService.add_address 的实际签名和 C 文档对不上（实测
    TypeError: takes exactly 5 arguments (3 given)），直接 bind+listen 更可控。
    """
    path = socket_path()
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        srv.bind(path)
    except OSError:
        # bind 失败通常意味着另一个实例已经占住了它（竞态：两个 Super+D 同时启动）。
        # 只有「连一下拒绝」才说明文件是死的，可以删掉重来；否则让位给活着的那个。
        if notify_running({"cmd": "show", "text": ""}):
            log("另一个实例已持有 socket，本进程退出监听")
            srv.close()
            return None
        _drop_stale_socket(path)
        try:
            srv.bind(path)
        except OSError as e:
            log("socket 监听失败（不影响翻译）:", e)
            srv.close()
            return None
    try:
        srv.listen(8)
        srv.setblocking(False)
    except OSError as e:
        log("socket listen 失败（不影响翻译）:", e)
        srv.close()
        return None
    log("监听", path)
    app._srv = srv  # 挂在 app 上，避免被 GC

    def on_accept(_fd, _cond):
        try:
            conn, _ = srv.accept()
        except OSError:
            return True
        # accept 在 GLib 主循环线程里，绝不能在这里同步 recv：
        # 对方迟迟不发数据会把整个窗口卡住。丢给线程读，读完回主线程。
        conn.setblocking(False)

        def read():
            data = b""
            try:
                conn.settimeout(0.8)
                while not data.endswith(b"\n") and len(data) < 1 << 20:
                    chunk = conn.recv(65536)
                    if not chunk:
                        break
                    data += chunk
                payload = json.loads(data.decode() or "{}")
            except Exception as e:  # noqa: BLE001
                log("读取命令失败:", e)
                payload = {}
            GLib.idle_add(handle, payload)
            try:
                conn.sendall(b"ok\n")
            except OSError as e:
                log("回 ack 失败:", e)
            try:
                conn.close()
            except OSError:
                pass

        def handle(payload):
            window.handle_command(payload)
            return False

        threading.Thread(target=read, daemon=True).start()
        return True

    channel = GLib.IOChannel.unix_new(srv.fileno())
    app._watch = GLib.io_add_watch(channel, GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN, on_accept)
    app._channel = channel
    return srv


def main():
    GLib.set_prgname("Translate.py")  # 让 app-id 匹配 niri 的浮动窗口规则

    selection = read_selection()
    if notify_running({"cmd": "show", "text": selection}):
        log("已有窗口，已转发取词结果")
        return 0

    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )
    app = Gtk.Application(application_id=None)

    def on_activate(_app):
        win = TranslateWindow(_app, initial_text=selection)
        # 必须挂到 application 上：否则 GApplication 认为自己没有窗口，
        # activate 一返回主循环就退出，翻译线程会被一起杀掉
        _app.add_window(win)
        serve(_app, win)
        win.present()

    app.connect("activate", on_activate)
    return app.run([])


def selftest():
    """非 GUI 部分自检：python3 translate.py --selftest"""
    print("socket_path:", socket_path())
    print("target_lang(你好):", target_lang("你好"))
    print("target_lang(hello):", target_lang("hello"))
    print("target_lang(こんにちは):", target_lang("こんにちは"))
    print("engine_order(short):", engine_order("hi"))
    print("engine_order(long):", engine_order("x" * 1500)[:1])
    out, err = translate("你好，今天天气不错", "en")
    print("translate:", repr(out), "err=", err)
    return 0 if out else 1


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    sys.exit(main())
