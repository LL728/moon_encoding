name = "LL728/moon_encoding"

version = "0.1.0"

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
]

description = "WHATWG Encoding Standard 的 MoonBit 实现：label 解析、流式编解码 API，覆盖 GBK、Big5、Shift_JIS 等传统字符集"

preferred_target = "wasm-gc"

import {
  "moonbitlang/x@0.5.5",
}
