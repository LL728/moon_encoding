name = "LL728/moon_encoding"

version = "0.2.0"

readme = "README.md"

repository = "https://github.com/LL728/moon_encoding"

license = "Apache-2.0"

keywords = [
  "encoding",
  "charset",
  "whatwg",
  "unicode",
  "gbk",
  "big5",
  "shift_jis",
  "iso-2022-jp",
]

description = "WHATWG Encoding Standard 的 MoonBit 实现：label 解析、流式解码与一次性编码 API，覆盖规范定义的全部 40 种编码（含 GBK、Big5、Shift_JIS、ISO-2022-JP）"

preferred_target = "wasm-gc"

import {
  "moonbitlang/x@0.5.5",
}
