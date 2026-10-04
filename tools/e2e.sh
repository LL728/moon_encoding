#!/usr/bin/env bash
# 命令行端到端测试 —— CI 与本地门禁共用的**唯一** E2E 来源。
#
# 单源化的缘由：本地门禁与 ci.yml 曾各持一份 E2E，改了一边漏了另一边
# （big5 已实现但 CI 仍按未实现断言），直到真实 CI 才暴露。今后只改这里。
#
# 约定：所有断言基于真实运行输出；非 ASCII 输入一律写成十六进制字节
# （printf 可直接吃），不依赖终端编码；错误路径必须非零退出且消息逐字匹配。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.moon/bin:${PATH}"
if command -v python3 >/dev/null 2>&1 && python3 -c "" >/dev/null 2>&1; then
  PY=python3
else
  PY=python   # Windows 商店占位符 python3 存在但不可执行（本机已知）
fi
T="$ROOT/_build/e2e"
mkdir -p "$T"

set -euo pipefail
printf 'H\xe9llo \x80\x9f \xc9lan' > "$T/in.bin"

# decode：字节 -> UTF-8 文本
moon run cmd/main --target wasm-gc -- decode windows-1252 \
  "$T/in.bin" "$T/out.txt"
"$PY" -c 'import sys; t = open(sys.argv[1], encoding="utf-8").read(); assert t == "Héllo €Ÿ Élan", repr(t)' "$T/out.txt"

# encode：往返后与原始输入逐字节相同
moon run cmd/main --target wasm-gc -- encode windows-1252 \
  "$T/out.txt" "$T/back.bin"
cmp "$T/in.bin" "$T/back.bin"

# 未知 label -> 非零退出
if moon run cmd/main --target wasm-gc -- decode no-such-label \
  "$T/in.bin" "$T/x.txt"; then
  echo "expected failure for unknown label"; exit 1
fi

# 合法但未实现的编码 -> 非零退出且消息可读
if moon run cmd/main --target wasm-gc -- decode iso-2022-jp \
  "$T/in.bin" "$T/x.txt" > "$T/e.txt"; then
  echo "expected failure for unimplemented encoding"; exit 1
fi
grep -q 'UnsupportedEncoding("ISO-2022-JP")' "$T/e.txt"

# 不可映射字符 -> 非零退出且报出码点与位置
printf '中文' > "$T/zh.txt"
if moon run cmd/main --target wasm-gc -- encode windows-1252 \
  "$T/zh.txt" "$T/zh.bin" > "$T/e.txt"; then
  echo "expected failure for unmappable characters"; exit 1
fi
grep -q 'Unmappable(20013, 0)' "$T/e.txt"

# 跨编码端到端（F2 接线）：iso-8859-1 解出 -> iso-8859-2 编回同字节
printf 'caf\xe9' > "$T/latin.bin"
moon run cmd/main --target wasm-gc -- decode iso-8859-1 \
  "$T/latin.bin" "$T/latin.txt"
"$PY" -c 'import sys; t = open(sys.argv[1], encoding="utf-8").read(); assert t == "café", repr(t)' "$T/latin.txt"
moon run cmd/main --target wasm-gc -- encode iso-8859-2 \
  "$T/latin.txt" "$T/latin2.bin"
"$PY" -c 'import sys; b = open(sys.argv[1], "rb").read(); assert b.hex() == "636166e9", b.hex()' "$T/latin2.bin"

# koi8-r 原生字符集往返（该编码不含拉丁扩展字母），期望文本由 CPython 现算
printf '\xf0\xe1\xe2' > "$T/koi8r.bin"
moon run cmd/main --target wasm-gc -- decode koi8-r \
  "$T/koi8r.bin" "$T/koi8r.txt"
moon run cmd/main --target wasm-gc -- encode koi8-r \
  "$T/koi8r.txt" "$T/koi8r2.bin"
cmp "$T/koi8r.bin" "$T/koi8r2.bin"
"$PY" -c 'import sys; expect = bytes.fromhex("f0e1e2").decode("koi8_r"); t = open(sys.argv[1], encoding="utf-8").read(); assert t == expect, t.encode("utf-8").hex()' "$T/koi8r.txt"

# 中文端到端（F3 接线）：GBK 字节 -> UTF-8 文本 -> gb18030 字节（2 字节段逐字节相同）
printf '\xd6\xd0\xce\xc4' > "$T/cn.bin"
moon run cmd/main --target wasm-gc -- decode gbk \
  "$T/cn.bin" "$T/cn.txt"
"$PY" -c 'import sys; b = open(sys.argv[1], "rb").read(); assert b.hex() == "e4b8ade69687", b.hex()' "$T/cn.txt"
moon run cmd/main --target wasm-gc -- encode gb18030 \
  "$T/cn.txt" "$T/cn2.bin"
cmp "$T/cn.bin" "$T/cn2.bin"

# gb18030 四字节真往返：U+1F600 <-> 4 字节 <-> UTF-8
"$PY" -c 'import sys; open(sys.argv[1], "wb").write(chr(0x1F600).encode("gb18030"))' "$T/astral.bin"
moon run cmd/main --target wasm-gc -- decode gb18030 \
  "$T/astral.bin" "$T/astral.txt"
"$PY" -c 'import sys; b = open(sys.argv[1], "rb").read(); assert b.hex() == "f09f9880", b.hex()' "$T/astral.txt"
moon run cmd/main --target wasm-gc -- encode gb18030 \
  "$T/astral.txt" "$T/astral2.bin"
cmp "$T/astral.bin" "$T/astral2.bin"

# Big5 端到端（F4 接线）：你好 = a741 a66e，UTF-8 往返逐字节一致
printf '\xa7\x41\xa6\x6e' > "$T/hant.bin"
moon run cmd/main --target wasm-gc -- decode big5 \
  "$T/hant.bin" "$T/hant.txt"
"$PY" -c 'import sys; b = open(sys.argv[1], "rb").read(); assert b.hex() == "e4bda0e5a5bd", b.hex()' "$T/hant.txt"
moon run cmd/main --target wasm-gc -- encode big5 \
  "$T/hant.txt" "$T/hant2.bin"
cmp "$T/hant.bin" "$T/hant2.bin"

# Shift_JIS 端到端：日本語 + 0x80（U+0080）+ 半角片假名（U+FF61）
printf '\x93\xfa\x96\x7b\x8c\xea' > "$T/ja.bin"
moon run cmd/main --target wasm-gc -- decode shift_jis \
  "$T/ja.bin" "$T/ja.txt"
"$PY" -c 'import sys; b = open(sys.argv[1], "rb").read(); assert b.hex() == "e697a5e69cace8aa9e", b.hex()' "$T/ja.txt"
moon run cmd/main --target wasm-gc -- encode shift_jis \
  "$T/ja.txt" "$T/ja2.bin"
cmp "$T/ja.bin" "$T/ja2.bin"
printf '\x80\xa1' > "$T/sjis_misc.bin"
moon run cmd/main --target wasm-gc -- decode shift_jis \
  "$T/sjis_misc.bin" "$T/sjis_misc.txt"
"$PY" -c 'import sys; b = open(sys.argv[1], "rb").read(); assert b.hex() == "c280efbda1", b.hex()' "$T/sjis_misc.txt"
moon run cmd/main --target wasm-gc -- encode shift_jis \
  "$T/sjis_misc.txt" "$T/sjis_misc2.bin"
cmp "$T/sjis_misc.bin" "$T/sjis_misc2.bin"

# EUC-JP 端到端（F5 接线）：日本語，含 SS3 三字节序列
printf '\xc6\xfc\xcb\xdc\xb8\xec' > "$T/ja_euc.bin"
moon run cmd/main --target wasm-gc -- decode euc-jp \
  "$T/ja_euc.bin" "$T/ja_euc.txt"
"$PY" -c 'import sys; exp = "".join(chr(c).encode("utf-8").hex() for c in (0x65E5, 0x672C, 0x8A9E)); b = open(sys.argv[1], "rb").read(); assert b.hex() == exp, b.hex()' "$T/ja_euc.txt"
moon run cmd/main --target wasm-gc -- encode euc-jp \
  "$T/ja_euc.txt" "$T/ja_euc2.bin"
cmp "$T/ja_euc.bin" "$T/ja_euc2.bin"
printf '\x8f\xa2\xaf' > "$T/ss3.bin"
moon run cmd/main --target wasm-gc -- decode euc-jp \
  "$T/ss3.bin" "$T/ss3.txt"
"$PY" -c 'import sys; b = open(sys.argv[1], "rb").read(); assert b.hex() == "cb98", b.hex()' "$T/ss3.txt"

# EUC-KR 端到端：韩国어（期望 UTF-8 由 CPython 现算，避免手写 hex）
printf '\xc7\xd1\xb1\xb9\xbe\xee' > "$T/ko.bin"
moon run cmd/main --target wasm-gc -- decode euc-kr \
  "$T/ko.bin" "$T/ko.txt"
"$PY" -c 'import sys; exp = "".join(chr(c).encode("utf-8").hex() for c in (0xD55C, 0xAD6D, 0xC5B4)); b = open(sys.argv[1], "rb").read(); assert b.hex() == exp, b.hex()' "$T/ko.txt"
moon run cmd/main --target wasm-gc -- encode euc-kr \
  "$T/ko.txt" "$T/ko2.bin"
cmp "$T/ko.bin" "$T/ko2.bin"

# UTF-8 端到端（F6 接线）：完整往返
printf 'Aé中' > "$T/u8.bin"
moon run cmd/main --target wasm-gc -- decode utf-8 \
  "$T/u8.bin" "$T/u8.txt"
"$PY" -c 'import sys; b = open(sys.argv[1], "rb").read(); assert b.hex() == "41c3a9e4b8ad", b.hex()' "$T/u8.txt"
moon run cmd/main --target wasm-gc -- encode utf-8 \
  "$T/u8.txt" "$T/u8b.bin"
cmp "$T/u8.bin" "$T/u8b.bin"

# UTF-16LE：BOM + A + 😀（U+1F600 代理对），BOM 不嗅探、按 U+FEFF 解出
"$PY" -c 'import sys; open(sys.argv[1], "wb").write((chr(0xFEFF) + "A" + chr(0x1F600)).encode("utf-16-le"))' "$T/u16le.bin"
moon run cmd/main --target wasm-gc -- decode utf-16le \
  "$T/u16le.bin" "$T/u16le.txt"
"$PY" -c 'import sys; b = open(sys.argv[1], "rb").read(); assert b.hex() == "efbbbf41f09f9880", b.hex()' "$T/u16le.txt"

# UTF-16BE decode
printf '\x4e\x2d\x00\x41' > "$T/u16be.bin"
moon run cmd/main --target wasm-gc -- decode utf-16be \
  "$T/u16be.bin" "$T/u16be.txt"
"$PY" -c 'import sys; b = open(sys.argv[1], "rb").read(); assert b.hex() == "e4b8ad41", b.hex()' "$T/u16be.txt"

# 规范不定义 UTF-16 编码器 -> 非零退出且消息可读
if moon run cmd/main --target wasm-gc -- encode utf-16le \
  "$T/u16le.txt" "$T/u16le.bin" > "$T/e.txt"; then
  echo "expected failure: spec defines no UTF-16 encoder"; exit 1
fi
grep -q 'UnsupportedEncoding("UTF-16LE")' "$T/e.txt"

# list：37 种编码清单（F7a）
moon run cmd/main --target wasm-gc -- list > "$T/list.txt"
grep -q "支持 37 种编码" "$T/list.txt"
grep -q "Shift_JIS" "$T/list.txt"
grep -q "UTF-16LE" "$T/list.txt"
echo "E2E_ALL_PASS"
