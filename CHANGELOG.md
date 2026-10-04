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
- 文件转码 CLI：`decode` / `encode` 子命令，失败非零退出并打印原因
- CI：格式检查、`moon check --deny-warn`、构建、wasm-gc 与 js 双后端测试、
  生成物新鲜度、命令行端到端（windows-1252 / iso-8859 / koi8-r /
  GBK↔gb18030 / gb18030 四字节往返 + 错误路径）
- 双许可证：代码 Apache-2.0，WHATWG 数据 BSD-3-Clause（`LICENSE-WHATWG`）
