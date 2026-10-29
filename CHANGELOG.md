# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

### 新增
- `DEVELOPMENT.md`：开发回顾。给出**手写与生成物的逐文件边界**
  （手写库源码 9 文件 1912 行 / CLI 91 行 / 手写测试 9 文件 2584 行 / 生成物 7 文件 39841 行）、
  关键架构决策 5 条、参考来源与许可范围表，以及 AI 使用边界。
- README「零门槛复现」：仓库自带 `demo/` 两个极小样例（`windows-1252` 与 `ISO-2022-JP`，共 16 字节），
  四条命令 + 两次比对即可验证「解码 → 回编码」逐字节一致。

### 变更
- README 校正三处口径：黄金向量 `8500+` → **8490**（按括号配对实测的条目数）；
  把 `UTF-8` 从「仅解码」括号中摘出（UTF-8 编码器已实现，规范不定义编码器的只有
  `replacement` 与 UTF-16BE/LE）；「库本身只依赖 `core`」补充说明
  `moonbitlang/x@0.5.5` 仅供命令行（`cmd/main`）读写文件使用。
- README 命令行一节注明**须在本仓库克隆的根目录**执行——在别的工程里 `moon run cmd/main`
  会命中那个工程自己的 `cmd/main`（如 `moon new` 模板打印 `Hello` 的那个），不报错但也不做转码。
- `.gitignore` 忽略 `*.generated.mbti`（`moon info` 生成的接口快照，不应入库）。

## [0.2.0] - 2026-10-21

### 新增
- **ISO-2022-JP** 完整编解码：规范 §iso-2022-jp-decoder 的 **7 个状态**
  （ASCII / Roman / katakana / Leading byte / Trailing byte / Escape start / Escape）
  与 **4 个关联变量**（decoder state、decoder output state、leading、output 布尔量）
  逐条实现——5 条转义序列（`ESC ( B` / `ESC ( J` / `ESC ( I` / `ESC $ @` / `ESC $ B`）、
  katakana 状态**不查索引**（`0xFF61 − 0x21 + byte`）、Trailing byte 的非法第二字节
  **被吞掉不回退**（对比 EUC-JP 会回放 ASCII 字节）、7 种状态各自的 end-of-queue 行为、
  编码器的 `U+000E/U+000F/U+001B → error with U+FFFD`、`U+2212 → U+FF0D`、
  半角片假名经 `index ISO-2022-JP katakana` 转全角后再查 jis0208、
  以及规范自己的"连续转义产生一个 error"注记（¥ 编码两次拼接解码得 ¥ U+FFFD ¥）
- **跨块状态**：转义序列、双字节字符、ESC 都可在任意位置被切开；状态保存在解码器实例上，
  每个切分点（含 0 与 n）+ 1200 组随机多切分均与一次性 `decode()` 一致
- **replacement** 解码：按 §14.1.1 的 `replacement error returned` 布尔量，
  至多报一次 error 后立刻 finished——非空输入**恰好一个 U+FFFD**（与长度无关，
  其余字节不再处理），空输入为空串；6 个 label 全部可达
- **x-user-defined** 编解码：`0x00..0x7F` 恒等、`0x80..0xFF → U+F780 + byte − 0x80`，
  反向同理；规范无索引表（算法定义），故复用单字节引擎 + 合成表
- `supported_encodings()` 达 **40 种**（规范全集）；228 个 label 的端到端生成套件
  （逐个解析 + 解码器可构造 + 编码可达性）
- 生成物新增 `gen_iso2022.mbt`（`index ISO-2022-JP katakana` 63 项，编码器专用）；
  ISO-2022-JP 编码反向表与 EUC-JP 共用同一条规范操作（`index pointer in index jis0208`），
  故复用 `gen_euc.mbt` 的 `euc_jp_encode_index`，不重复出表
- 新的规范级单测 `iso2022_wbtest.mbt` / `misc_wbtest.mbt`，测试数 147 → 165

### 变更
- `EncodingError::UnsupportedEncoding` 的语义收敛为"label 合法但**规范未定义编码器**"
  （`replacement` / `UTF-16BE` / `UTF-16LE`）；40 种编码现在都有解码器
- `tools/e2e.sh`：删除"合法但未实现编码"的过期用例（已被 ISO-2022-JP 实现取代），
  改为 iso-2022-jp（含 `ESC ( I` 与 label 别名 `csiso2022jp`）、x-user-defined、
  replacement（`hz-gb-2312` 标签 + 至多一个 U+FFFD + 无编码器拒绝）的端到端用例，
  list 断言 37 → 40 并覆盖三个新编码名
- README / 演示脚本同步到 40 种编码（`tools/make_demo.py` 的自检与 `docs/` 演示产物）

### 说明
- `ISO-2022-JP` / `replacement` / `x-user-defined` **不进入 CPython 差分向量**：
  CPython 的 `iso2022_jp` 在 `ESC ( I`、`0x0E/0x0F`、半角片假名、转义后回 ASCII
  等处与规范系统性分歧，按"规范优先"原则改由规范级单测钉住

## [0.1.2] - 2026-10-16

### 新增
- README 新增「与 MoonBit 生态现有实现的关系」：与 `f4ah6o/encoding_sjis` 的
  复用关系（无依赖、无代码复用、数据同源 WHATWG 规范）与扩展关系说明，
  附生态对比表（编码范围 / 方向 / 流式 / 合规基准 / 附加能力）

### 修复
- README 流式表述精确为「流式解码 API」——编码端是一次性 `encode()`，
  无流式编码器；并如实标注 `encoding_sjis` 同样提供流式解码

### 变更
- 适配 moon `0.1.20261012` 格式化器：`Int` → `Int32` 机械重排与一处折行
  （16 文件 197 行，零语义改动），CI 格式检查恢复通过

## [0.1.1] - 2026-10-04

### 修复
- README 的 MoonBit 示例改为「导入写在 `moon.pkg`」——MoonBit 不再在 `.mbt`
  文件内解析 `import`，旧写法在新工具链下会直接报错（消费工程实测复现并验证）

## [0.1.0] - 2026-10-04

### 新增
- WHATWG label 解析：228 个 label、ASCII 大小写不敏感、别名归一（如
  `latin1` / `ascii` / `iso-8859-1` → `windows-1252`）
- **28 种 legacy 单字节编码**的完整编解码（自 WHATWG single-byte 分组自动发现）：
  一次性 `decode` / `encode`、流式 `Decoder`、`supported_encodings()` 查询；
  replacement 解码语义、fatal 编码语义（规范 `encode or fail`）
- 数据管线：`whatwg/encoding` @ `2c3853e` 固定版本 vendor 与表生成器
  （表、编码集与 dispatch 同源生成，接线与数据不会漂移），CI 重新生成后
  `git diff --exit-code` 保证表与提交一致
- Python 差分黄金向量：以 CPython codecs 为独立预言机的 **6200+ 向量**，
  覆盖 28 种单字节 + GBK/gb18030；逐种（字节级）与逐样本（中文）自动分类
  clean/both-error/divergent 并记录分歧
- 28 张表的结构不变量、全表项往返、150 个解码错误位的 U+FFFD replacement 接线测试
- **GBK / gb18030** 完整编解码：规范 `§gb18030-decoder/encoder` 逐条实现
  （GBK 解码器按规范与 gb18030 完全别名；编码器 is-GBK 标志、18 条 PUA 侧表、
  U+E5E5 明确不可编码、ranges 公式与 U+E7C7 特例）、流式跨块状态机与三条
  Restore 重放路径、end-of-queue 截断单 U+FFFD
- 中文差分向量：`tools/chinese_ref.py` 规范参考实现与 CPython 逐样本交叉分类，
  分歧自动排除并计数（GBK 193+221、gb18030 217+258 向量）
- **Big5 / Shift_JIS** 完整编解码：规范 `§big5-decoder/encoder`、`§shift_jis-decoder/encoder`
  逐条实现——Big5 的 4 条双码点命名序列、编码端过滤（pointer ≥ 5024）与六个
  "取最后出现"码点；Shift_JIS 的 0x80 单字节往返、半角片假名、EUDC PUA 区间
  （U+E000..U+E757）、¥→0x5C / U+2212→U+FF0D 特例、NEC 重复行（8272..8835）排除；
  单挂起 lead 状态机 + Restore 重放 + end-of-queue 单 U+FFFD，全切分点跨块等价
- 多字节差分向量：`tools/multibyte_ref.py`（encode-map 规则与表生成器单一来源），
  Big5 193+225、Shift_JIS 269+283 向量，3 处规范/CPython 分歧自动排除
- **EUC-JP / EUC-KR** 完整编解码：规范 `§euc-jp` / `§euc-kr` 逐条实现——EUC-JP 的
  SS2（0x8E+半角片假名）/ SS3（0x8F+jis0212，标志在通用分支强制复位）序列、
  共享 jis0208 指针空间（94 列）、与 Shift_JIS 同款的 ¥/overbar/U+2212 特例、
  半角片假名两字节编码；EUC-KR 单 lead + 0x41..0xFE 单偏移（无 GBK 的 0x7F/0x80 分界、
  无任何编码特例）；两者 fresh 字节 0x80/0xA0/0xFF 报错（分别对比 GBK 的 U+20AC、
  Shift_JIS 的 U+0080）；`supported_encodings()` 达 34 种
- EUC 表：`gen_euc.mbt`（jis0212 8836、EUC-KR 索引 23940 与 17048 码点反向表、
  EUC-JP 7326 码点反向表并断言全部指针 < 8836 —— 规范 §euc-jp-encoder 注记）；
  四个多字节编码的二分查找收敛为共享 `encode_index_lookup`
- EUC 差分向量：EUC-JP 234+211（**57 处**规范/CPython 表格分歧自动排除，
  如 a1dd 的 FF0D/2212）、EUC-KR 190+227（0 处真分歧）
- **UTF-8 / UTF-16BE / UTF-16LE** 解码 + UTF-8 编码：规范 `§utf-8-decoder/encoder`、
  `§shared-utf-16-decoder` 逐条实现——UTF-8 的过长/越界/代理区头防线（C0/C1、
  E0→A0、ED→9F、F0→90、F4→8F）、非法延续字节的**全状态复位 + 重放**、
  截断单 U+FFFD；共享 UTF-16 的字节序标志、孤立低代理报错、未配对高代理时
  **恢复当前码元两字节**（字符不丢）、end-of-queue 单 U+FFFD；
  `supported_encodings()` 达 **37 种**（当时 ISO-2022-JP/replacement/x-user-defined
  三个可裁剪项尚未接线；三者已在 [0.2.0] 补齐至 40 种）
- **规范不定义 UTF-16 编码器**（`§get an encoder` 断言）：encode(utf-16*) 如实返回
  UnsupportedEncoding，由单测与 CI 端到端共同钉住
- UTF 差分向量：`tools/utf_ref.py`——UTF-8 203+139（0 分歧）、UTF-16BE 87、
  UTF-16LE 80 解码向量（各三百余次 CPython strict 报错跳过：孤立代理/奇数长度/非法序列）
- 文件转码 CLI：`decode` / `encode` / `list` 子命令，失败非零退出并打印原因；
  `list` 输出 `supported_encodings()` 的 37 个规范名（当时值；现为 40，见 [0.2.0]）
- 演示：`tools/make_demo.py` 把**真实执行**的命令流程渲染为
  `docs/demo.gif`（136 帧 / 10.5 秒，内置自检：期望不符即失败），
  并同步生成文字实录 `docs/demo_transcript.txt`（完整输出 + 退出码、路径脱敏、
  无时间戳可复现）；README 新增「演示」一节
- CI：格式检查、`moon check --deny-warn`、构建、wasm-gc 与 js 双后端测试、
  生成物新鲜度、命令行端到端（windows-1252 / iso-8859 / koi8-r /
  GBK↔gb18030 / gb18030 四字节往返 / Big5 / Shift_JIS / EUC-JP 含 SS3 / EUC-KR / UTF-8 往返 / UTF-16 解码 + 编码器拒绝 + 错误路径）
- 双许可证：代码 Apache-2.0，WHATWG 数据 BSD-3-Clause（`LICENSE-WHATWG`）
- 适配 MoonBit 新编译器的 `implicit_impl_as_method`（`EncodingError` 显式 trait 方法提升）
