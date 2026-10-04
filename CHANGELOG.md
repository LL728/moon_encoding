# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

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
  `supported_encodings()` 达 **37 种**（除 ISO-2022-JP/replacement/x-user-defined
  三个可裁剪项外全部接线）
- **规范不定义 UTF-16 编码器**（`§get an encoder` 断言）：encode(utf-16*) 如实返回
  UnsupportedEncoding，由单测与 CI 端到端共同钉住
- UTF 差分向量：`tools/utf_ref.py`——UTF-8 203+139（0 分歧）、UTF-16BE 87、
  UTF-16LE 80 解码向量（各三百余次 CPython strict 报错跳过：孤立代理/奇数长度/非法序列）
- 文件转码 CLI：`decode` / `encode` / `list` 子命令，失败非零退出并打印原因；
  `list` 输出 `supported_encodings()` 的 37 个规范名（CI 断言行数与关键项）
- 演示：`tools/make_demo.py` 把**真实执行**的命令流程渲染为
  `docs/demo.gif`（136 帧 / 10.5 秒，内置自检：期望不符即失败），
  并同步生成文字实录 `docs/demo_transcript.txt`（完整输出 + 退出码、路径脱敏、
  无时间戳可复现）；README 新增「演示」一节
- CI：格式检查、`moon check --deny-warn`、构建、wasm-gc 与 js 双后端测试、
  生成物新鲜度、命令行端到端（windows-1252 / iso-8859 / koi8-r /
  GBK↔gb18030 / gb18030 四字节往返 / Big5 / Shift_JIS / EUC-JP 含 SS3 / EUC-KR / UTF-8 往返 / UTF-16 解码 + 编码器拒绝 + 错误路径）
- 双许可证：代码 Apache-2.0，WHATWG 数据 BSD-3-Clause（`LICENSE-WHATWG`）
