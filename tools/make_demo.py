#!/usr/bin/env python3
"""把**真实执行**的演示流程渲染成终端风格 GIF + 文字实录，供 README 内嵌。

设计要点：
- 每一帧文字都来自真实运行的命令：stdout/stderr 按 UTF-8 解码（管道捕获
  不受本机 GBK 控制台影响），退出码如实呈现；脚本内置自检，任一期望
  不满足即非零退出，杜绝"演示与行为不符"。
- 渲染只是呈现：SimHei 单字体（本机实测拉丁 8px 等宽、中文 15px），
  手算终端网格——拉丁 1 格 8px、中文 2 格 16px，与终端双宽语义一致。
- GIF 共用调色板（从均匀抽样的帧取样，避免超大临时图）+ optimize +
  disposal=1，沿用 moonvorbis 已验证的写法，防止滚动时底色抖动。
- 文字实录 docs/demo_transcript.txt 同步生成、含完整输出与退出码，
  作为 GIF 内容未被加工的凭据；其中本机用户路径统一脱敏。
- 输出不含时间戳，重复运行结果稳定，便于提交。

用法：
    python tools/make_demo.py
产出：
    docs/demo.gif + docs/demo_transcript.txt
"""

import os
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "_build" / "d"  # 演示工作目录（_build 已被 .gitignore 忽略）
OUT_GIF = ROOT / "docs" / "demo.gif"
OUT_TXT = ROOT / "docs" / "demo_transcript.txt"

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\simhei.ttf",
    r"C:\Windows\Fonts\simsun.ttc",
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
]
FONT_SIZE = 15
CELL_W = 8       # 拉丁 1 格（SimHei 实测 8px 等宽）
CELL_H = 18
WIDE = 16        # 中文 2 格
COLS = 100
ROWS = 28
PAD_X, PAD_Y = 16, 12

BG = (12, 12, 12)
PROMPT = (80, 200, 120)
CMD = (210, 210, 210)
OUTC = (170, 170, 170)
ERR = (235, 95, 95)
DIM = (120, 120, 120)

PROMPT_STR = "moon_encoding> "

# 演示流程：全部为真实命令。fixture 用 printf 的 \xNN 形式（纯 ASCII 源，
# 不依赖任何终端编码）；moon 命令与 README 用法一致。
SCENES = [
    ["moon", "run", "cmd/main", "--", "list"],
    ["bash", "-c", r"printf '\xd6\xd0\xce\xc4' > _build/d/cn.bin"],
    ["bash", "-c", r"printf '\xa7\x41\xa6\x6e' > _build/d/hant.bin"],
    ["bash", "-c", r"printf '\x93\xfa\x96\x7b\x8c\xea' > _build/d/ja_sjis.bin"],
    ["bash", "-c", r"printf '\xc6\xfc\xcb\xdc\xb8\xec' > _build/d/ja_euc.bin"],
    ["bash", "-c", r"printf '\xc7\xd1\xb1\xb9\xbe\xee' > _build/d/ko.bin"],
    ["bash", "-c", r"printf '\xff\xfe\x41\x00\x3d\xd8\x00\xde' > _build/d/u16.bin"],
    ["bash", "-c", r"printf '\xe4\xb8\xad\xe6\x96\x87' > _build/d/zh.txt"],
    # —— 正常路径：多编码互转 ——
    ["moon", "run", "cmd/main", "--", "decode", "gbk", "_build/d/cn.bin", "_build/d/cn.txt"],
    ["xxd", "-p", "_build/d/cn.txt"],
    ["moon", "run", "cmd/main", "--", "encode", "gb18030", "_build/d/cn.txt", "_build/d/cn2.bin"],
    ["bash", "-c", r"cmp _build/d/cn.bin _build/d/cn2.bin && echo 'OK: byte-identical'"],
    ["moon", "run", "cmd/main", "--", "decode", "big5", "_build/d/hant.bin", "_build/d/hant.txt"],
    ["moon", "run", "cmd/main", "--", "decode", "shift_jis", "_build/d/ja_sjis.bin", "_build/d/ja1.txt"],
    ["moon", "run", "cmd/main", "--", "decode", "euc-jp", "_build/d/ja_euc.bin", "_build/d/ja2.txt"],
    ["moon", "run", "cmd/main", "--", "decode", "euc-kr", "_build/d/ko.bin", "_build/d/ko.txt"],
    ["moon", "run", "cmd/main", "--", "decode", "utf-16le", "_build/d/u16.bin", "_build/d/u16.txt"],
    ["xxd", "-p", "_build/d/u16.txt"],
    # —— 错误路径：真实非零退出 + 真实错误文本 ——
    ["moon", "run", "cmd/main", "--", "decode", "no-such-label", "_build/d/cn.bin", "_build/d/x.txt"],
    ["moon", "run", "cmd/main", "--", "decode", "iso-2022-jp", "_build/d/cn.bin", "_build/d/x.txt"],
    ["moon", "run", "cmd/main", "--", "encode", "windows-1252", "_build/d/zh.txt", "_build/d/zh.bin"],
    ["moon", "run", "cmd/main", "--", "encode", "utf-16le", "_build/d/cn.txt", "_build/d/x.bin"],
    # —— 收尾：全量测试 ——
    ["moon", "test"],
]


def find_font() -> str:
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return path
    raise SystemExit("找不到 CJK 字体，用 --font 指定路径（候选均不存在）")


def sanitize(text: str) -> str:
    """脱敏本机用户路径（transcript 与帧内容共用）。"""
    home = str(Path.home())
    if home:
        text = text.replace(home, "<home>")
    return text.replace("C:\\Users\\1510", "<user>")


def run(argv):
    """真实执行一条命令，返回 (显示名, stdout行, stderr首行, exit码)。"""
    env = dict(os.environ)
    env["PATH"] = str(Path.home() / ".moon" / "bin") + os.pathsep + env.get("PATH", "")
    proc = subprocess.run(argv, cwd=ROOT, capture_output=True, env=env)
    out = proc.stdout.decode("utf-8", errors="replace").replace("\r\n", "\n")
    err = proc.stderr.decode("utf-8", errors="replace").replace("\r\n", "\n")
    if argv[0] == "bash":
        display = argv[2]
    elif argv[:4] == ["moon", "run", "cmd/main", "--"]:
        display = "moon run cmd/main -- " + " ".join(argv[4:])
    else:
        display = " ".join(argv)
    err_head = next((ln.strip() for ln in err.split("\n") if ln.strip()), "")
    return display, sanitize(out), sanitize(err_head), proc.returncode


def verify(display: str, out: str, code: int, argv) -> None:
    """演示自检：期望与真实行为不符立即失败（GIF 不会展示"编造"的结果）。"""
    if argv[-1] == "list":
        assert code == 0 and "支持 37 种编码" in out, "list 输出异常"
        assert out.count("\n  ") >= 37, "list 行数不足 37"
    if argv[:2] == ["moon", "test"]:
        assert code == 0 and "failed: 0" in out, "moon test 未全绿"
    if argv[:2] == ["moon", "run"] and "decode gbk" in display:
        assert code == 0, "decode gbk 失败"
    if "cmp" in display:
        assert code == 0, "cmp 判定不一致"
    if "decode no-such-label" in display:
        assert code != 0 and "UnknownLabel" in out, "未知 label 错误文本不符"
    if "decode iso-2022-jp" in display:
        assert code != 0 and 'UnsupportedEncoding("ISO-2022-JP")' in out, "未实现编码错误不符"
    if "encode windows-1252" in display and "zh.txt" in display:
        assert code != 0 and "Unmappable(20013, 0)" in out, "不可映射错误不符"
    if "encode utf-16le" in display:
        assert code != 0 and 'UnsupportedEncoding("UTF-16LE")' in out, "UTF-16 编码器拒绝不符"


def build_lines():
    """执行全部命令，产出渲染事件：[(kind, text)]。kind: prompt/cmd/out/err/dim"""
    transcript = [
        "# moon_encoding 演示实录（与 docs/demo.gif 由同一脚本生成）",
        "# 全部输出来自真实命令的真实 stdout/stderr，退出码如实记录；",
        "# 本机用户路径已脱敏；不含时间戳，可复现。生成方式：",
        "#     python tools/make_demo.py",
        "",
    ]
    events = []
    for argv in SCENES:
        display, out, err_head, code = run(argv)
        verify(display, out, code, argv)
        events.append(("prompt", PROMPT_STR))
        events.append(("cmd", display))
        transcript.append("$ " + display)
        out_lines = out.split("\n")
        if out_lines and out_lines[-1] == "":
            out_lines.pop()
        shown = out_lines
        if len(out_lines) > 40:
            shown = out_lines[-24:]
            events.append(("dim",
                           f"…（完整输出共 {len(out_lines)} 行，仅显示末尾；全文见 transcript）"))
        for line in shown:
            events.append(("out", line))
        if err_head:
            events.append(("err", err_head if len(err_head) <= 100 else err_head[:97] + "…"))
        events.append(("dim", f"[exit {code}]"))
        transcript.extend(out_lines)
        if err_head:
            transcript.append("(stderr) " + err_head)
        transcript.append(f"[exit {code}]")
        transcript.append("")
    OUT_TXT.parent.mkdir(parents=True, exist_ok=True)
    OUT_TXT.write_text("\n".join(transcript) + "\n", encoding="utf-8")
    print(f"transcript: {OUT_TXT}（{len(transcript)} 行）")
    return events


def batch_outs(events, long_run=10, step=3):
    """把连续的输出行按批折叠：短输出逐行（节奏感），长输出每帧 step 行（控体积）。"""
    out, i = [], 0
    while i < len(events):
        kind, text = events[i]
        if kind == "out":
            run = [text]
            j = i + 1
            while j < len(events) and events[j][0] == "out":
                run.append(events[j][1])
                j += 1
            k = 1 if len(run) <= long_run else step
            for m in range(0, len(run), k):
                group = run[m:m + k]
                out.append(("out", "\n".join(group), 75 + 45 * (len(group) - 1)))
            i = j
        else:
            dur = {"prompt": 90, "cmd": 0, "err": 150, "dim": 120}.get(kind, 75)
            out.append((kind, text, dur))
            i += 1
    return out


def wrap(text: str, cols: int):
    """按终端列宽折行（中文算 2 列）。"""
    lines, cur, width = [], "", 0
    for ch in text:
        w = 2 if ord(ch) > 0x2E80 else 1
        if width + w > cols:
            lines.append(cur)
            cur, width = "", 0
        cur += ch
        width += w
    lines.append(cur)
    return lines


def render(events, font, path: str):
    cols = (COLS * CELL_W - 2 * PAD_X) // CELL_W
    width = COLS * CELL_W + 2 * PAD_X
    height = ROWS * CELL_H + 2 * PAD_Y

    # 展开为逐帧行快照：prompt 单独成行、命令分块打字、输出逐行出现
    frames = []  # (lines, duration_ms, cursor_on)
    visible = []  # [[text, color, cont]]
    for i, (kind, text, _dur0) in enumerate(batch_outs(events)):
        if kind == "prompt":
            visible.append([text, PROMPT, False])
        elif kind == "cmd":
            chunks = [text[j:j + 18] for j in range(0, len(text), 18)] or [""]
            for chunk in chunks:
                # 打字动画逐块推进**同一行**的文本；最终外观是一整行按列宽
                # 折行（wrap），而不是被分块硬切成短行
                visible[-1] = [visible[-1][0] + chunk, CMD, False]
                frames.append((_window(visible, cols), 55, True))
            continue
        else:
            color = {"out": OUTC, "err": ERR}.get(kind, DIM)
            for part in text.split("\n"):
                visible.append([part, color, False])
            dur = {"prompt": 90, "out": 75, "err": 150, "dim": 120}[kind]
            frames.append((_window(visible, cols), dur, i % 2 == 0))
            continue
    frames.append((_window(visible, cols), 600, False))  # 定格收尾

    images = [draw(w, font, cursor) for w, _, cursor in frames]

    # 共用调色板：从均匀抽样的帧取样，避免超大临时图
    sample_idx = list(range(0, len(images), max(1, len(images) // 24)))[:24]
    strip = Image.new("RGB", (width, height * len(sample_idx)))
    for slot, i in enumerate(sample_idx):
        y = slot * height
        strip.paste(images[i], (0, y, width, y + height))
    palette = strip.quantize(colors=32, method=Image.MEDIANCUT)
    quantized = [im.quantize(palette=palette, dither=Image.FLOYDSTEINBERG)
                 for im in images]

    OUT_GIF.parent.mkdir(parents=True, exist_ok=True)
    quantized[0].save(
        OUT_GIF,
        save_all=True,
        append_images=quantized[1:],
        duration=[dur for _, dur, _ in frames],
        loop=0,
        optimize=True,
        disposal=1,
    )
    total = sum(dur for _, dur, _ in frames) / 1000
    size = OUT_GIF.stat().st_size
    print(f"写入 {OUT_GIF}（{size / 1024:.0f} KB，{len(quantized)} 帧，"
          f"{total:.1f} 秒，{width}×{height}）")
    return len(quantized), size, total


def _window(visible, cols):
    """折行 + 底部对齐的可见窗口。"""
    flat = []
    for text, color, cont in visible:
        segs = wrap(text, cols)
        for j, seg in enumerate(segs):
            flat.append([seg, color, j > 0])
    return flat[-ROWS:]


def draw(window, font, cursor_on):
    width = COLS * CELL_W + 2 * PAD_X
    height = ROWS * CELL_H + 2 * PAD_Y
    img = Image.new("RGB", (width, height), BG)
    d = ImageDraw.Draw(img)
    top = PAD_Y + (ROWS - len(window)) * CELL_H  # 底部对齐
    for r, (text, color, cont) in enumerate(window):
        x = PAD_X + (CELL_W if cont else 0)
        y = top + r * CELL_H
        for ch in text:
            d.text((x, y), ch, font=font, fill=color)
            x += WIDE if ord(ch) > 0x2E80 else CELL_W
    if cursor_on and window:
        last = window[-1][0]
        lx = PAD_X + sum(WIDE if ord(c) > 0x2E80 else CELL_W for c in last)
        y = top + (len(window) - 1) * CELL_H
        d.rectangle([lx + 2, y + 3, lx + 2 + CELL_W - 3, y + CELL_H - 5], fill=PROMPT)
    return img


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    for f in WORK.glob("*"):
        if f.is_file():
            f.unlink()  # 清掉上次演示的残留，保证可复现
    font_path = find_font()
    print(f"字体：{font_path}")
    events = build_lines()
    n, size, secs = render(events, ImageFont.truetype(font_path, FONT_SIZE), font_path)
    assert size < 3 * 1024 * 1024, f"GIF 过大：{size / 1024:.0f} KB"
    print(f"自检通过：{n} 帧，{secs:.1f} 秒，{size / 1024:.0f} KB < 3072 KB")


if __name__ == "__main__":
    main()
