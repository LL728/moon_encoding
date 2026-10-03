# moon_encoding

[![CI](https://github.com/LL728/moon_encoding/actions/workflows/ci.yml/badge.svg)](https://github.com/LL728/moon_encoding/actions/workflows/ci.yml)

WHATWG Encoding Standard 的 MoonBit 实现：完整的 label 解析（228 个）、
流式编解码 API 与文件转码命令行工具，按里程碑覆盖该标准定义的 40 种编码。

数据表直接由 [whatwg/encoding](https://github.com/whatwg/encoding) 的规范源数据生成
（固定版本 `2c3853e`，与 Rust `encoding_rs` 的表生成同源），不经过任何二手实现。

## 编码覆盖状态

WHATWG Encoding Standard 共定义 40 种编码、228 个 label。
**label 解析已全部完成**；编解码按里程碑推进：

| 分组 | 编码 | 状态 |
| --- | --- | --- |
| 单字节（28 种） | `windows-1252`（含 `latin1` / `ascii` / `iso-8859-1` 等别名） | ✅ 已实现 |
| | 其余 27 种（`ISO-8859-2..16`、`windows-1250..1258`、`KOI8-R/U`、`IBM866`、`macintosh` 等） | ⏳ 计划中 |
| 中文 | `GBK` / `gb18030`、`Big5` | ⏳ 计划中 |
| 日韩 | `Shift_JIS`、`EUC-JP`、`EUC-KR` | ⏳ 计划中 |
| Unicode | `UTF-8`、`UTF-16BE`、`UTF-16LE` | ⏳ 计划中 |
| 其他 | `ISO-2022-JP`、`replacement`、`x-user-defined` | ⏳ 视进度 |

尚未实现的编码会返回明确的 `UnsupportedEncoding` 错误（而不是静默失败），
未知 label 返回 `UnknownLabel`——两者可区分。

## 安装

```bash
moon add LL728/moon_encoding
```

库本身只依赖 `moonbitlang/core`（随工具链自带）。

## 使用

### 一次性解码 / 编码

```moonbit
import "LL728/moon_encoding"
import "moonbitlang/core/debug"

pub fn example(bytes : Bytes) -> Unit {
  // 字节 -> 文本（解码错误按规范替换为 U+FFFD）
  match @moon_encoding.decode(bytes, "windows-1252") {
    Ok(text) => println(text)
    Err(e) => println("解码失败: " + @debug.to_string(e))
  }
  // 文本 -> 字节（fatal 模式：不可映射字符直接报错）
  match @moon_encoding.encode("Héllo €", "windows-1252") {
    Ok(out) => println("\{out.length()} 字节")
    Err(e) => println("编码失败: " + @debug.to_string(e))
  }
}
```

### 流式解码

```moonbit
// chunk : Bytes —— 逐块到达的字节
match @moon_encoding.Decoder::new("windows-1252") {
  Ok(decoder) => {
    let mut text = ""
    text = text + decoder.consume(chunk) // 单字节编码无跨块状态，任意切分结果与整段一致
    text = text + decoder.finish()
  }
  Err(e) => println("创建解码器失败: " + @debug.to_string(e))
}
```

### 错误类型

```moonbit
pub enum EncodingError {
  UnknownLabel(String)           // label 不在标准定义的 228 个之内
  UnsupportedEncoding(String)    // label 合法，编码尚未实现
  Unmappable(Int, Int)           // 编码遇不可映射字符：码点 + 字符位置
} derive(Eq, @debug.Debug)
```

错误语义对齐 WHATWG 规范（`encoding.bs`）：解码为 **replacement** 模式
（错误字节 → U+FFFD），编码为 **fatal** 模式（规范的 `encode or fail` 操作，
替换策略交还调用方）。

## 命令行

```bash
# 字节 -> UTF-8 文本
moon run cmd/main -- decode <label> <input> <output>
# UTF-8 文本 -> 目标编码字节
moon run cmd/main -- encode <label> <input> <output>

# 示例
moon run cmd/main -- decode windows-1252 legacy.txt utf8.txt
moon run cmd/main -- encode latin1 utf8.txt legacy.txt
```

失败一律以非零退出码结束并打印原因，便于脚本使用：

```text
$ moon run cmd/main -- decode gbk in.bin out.txt
解码失败: UnsupportedEncoding("GBK")
$ echo $?
1
```

## 验证方式

- **单元与属性测试**：label 解析、表不变量、规范已知映射、256 字节全量双向往返、
  1200 组随机切分的流式等价性。
- **Python 差分测试**：以 CPython 的 `cp1252` 编解码为独立预言机，
  378 个黄金向量（318 解码 + 60 编码）由 `tools/gen_vectors.py` 生成并提交进仓库。
  CPython 与 WHATWG 在 5 个字节（`0x81` `0x8D` `0x8F` `0x90` `0x9D`）上存在
  设计性差异——前者报错、后者映射为 C1 控制符——生成器在生成时会验证这一差异，
  这 5 个字节改由对照 vendored 规范表的单元测试覆盖。
- **新鲜度检查**：CI 重新生成全部表与向量后 `git diff --exit-code`，
  保证提交内容永远等于生成器产物。

```bash
python tools/generate_tables.py   # 由 vendored 规范数据生成 label/编码表
python tools/gen_vectors.py       # 由 CPython cp1252 生成差分向量
moon fmt && moon check --deny-warn && moon test
```

## 代码结构

| 文件 | 职责 |
| --- | --- |
| `label.mbt` | label 解析入口（ASCII 大小写不敏感匹配） |
| `single_byte.mbt` | 28 种单字节编码共用的表驱动编解码引擎 |
| `codec.mbt` | 公共 API：`EncodingError`、流式 `Decoder`、`decode` / `encode` |
| `gen_label.mbt` / `gen_single_byte.mbt` | 生成物：label 表与单字节编解码表（勿手改） |
| `gen_w1252_vectors_wbtest.mbt` | 生成物：CPython 差分黄金向量（勿手改） |
| `cmd/main/` | 文件转码 CLI |
| `tools/` | 规范数据 vendor、两个生成器 |

## 已知限制

- 仅 `windows-1252` 可编解码（见覆盖状态表）；其余编码当前返回 `UnsupportedEncoding`。
- 未实现 BOM 嗅探与 `decode()` 的自动 BOM 覆写；label 由调用方显式给出。
- 编码侧只提供 fatal 模式原语；规范中 HTML 表单用的 `&#码点;` 替换模式（html 模式）
  尚未提供。
- 单字节编码不含跨块状态，流式 API 已就位；多字节编码的跨块状态机随对应里程碑加入。

## 参考与许可

- 代码采用 [Apache-2.0](LICENSE)。
- 数据表源自 [WHATWG Encoding Standard](https://encoding.spec.whatwg.org/)，
  © WHATWG (Apple, Google, Mozilla, Microsoft)，按 [BSD 3-Clause](LICENSE-WHATWG) 授权
  （规范仓库 LICENSE 文件原文说明：并入源码的部分以 BSD-3-Clause 授权）。
- 表生成流程参考 [encoding_rs](https://github.com/hsivonen/encoding_rs) 的
  `generate-encoding-data.py`（同为 `(Apache-2.0 OR MIT)`，本项目未移植其代码，
  仅沿用其钉定的 whatwg/encoding 版本以保证数据同源）。
- 差分预言机：CPython 标准库 `codecs` 的 `cp1252`（PSF 许可）。
