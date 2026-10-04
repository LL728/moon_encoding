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
- Python 差分黄金向量：以 CPython codecs 为独立预言机的 **5300+ 向量**，
  覆盖 28 种编码；生成器逐种自动分类 clean/both-error/divergent 字节并记录分歧
- 28 张表的结构不变量、全表项往返、150 个解码错误位的 U+FFFD replacement 接线测试
- 文件转码 CLI：`decode` / `encode` 子命令，失败非零退出并打印原因
- CI：格式检查、`moon check --deny-warn`、构建、wasm-gc 与 js 双后端测试、
  生成物新鲜度、命令行端到端（成功往返 + 三类错误路径）
- 双许可证：代码 Apache-2.0，WHATWG 数据 BSD-3-Clause（`LICENSE-WHATWG`）
