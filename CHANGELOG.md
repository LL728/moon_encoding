# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

### 新增
- WHATWG label 解析：228 个 label、ASCII 大小写不敏感、别名归一（如
  `latin1` / `ascii` / `iso-8859-1` → `windows-1252`）
- `windows-1252` 编解码：一次性 `decode` / `encode`、流式 `Decoder`
  （replacement 解码语义、fatal 编码语义，对齐规范 `encode or fail`）
- 数据管线：`whatwg/encoding` @ `2c3853e` 固定版本 vendor 与表生成器，
  CI 重新生成后 `git diff --exit-code` 保证表与提交一致
- Python 差分黄金向量：以 CPython `cp1252` 为独立预言机的 378 个向量
  （318 解码 + 60 编码），生成器自检 5 字节的规范/CPython 设计性分歧
- 文件转码 CLI：`decode` / `encode` 子命令，失败非零退出并打印原因
- CI：格式检查、`moon check --deny-warn`、构建、wasm-gc 与 js 双后端测试、
  生成物新鲜度、命令行端到端（成功往返 + 三类错误路径）
- 双许可证：代码 Apache-2.0，WHATWG 数据 BSD-3-Clause（`LICENSE-WHATWG`）
