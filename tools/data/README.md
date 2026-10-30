# `tools/data/` — vendored 规范数据

这两个 JSON 是 **WHATWG Encoding Standard** 的规范源数据副本，由 `tools/generate_tables.py`
读取并生成仓库根目录下的 6 个 `gen_*.mbt` 表文件。**手改无效**：CI 的「生成物新鲜度」一步会
重新生成全部表后跑 `git diff --exit-code`。

| 文件 | 字节数 | sha256 |
|---|---|---|
| `encodings.json` | 8913 | `078212b3697f60b81225b6671bd9da2604497abff0aa8e96e4d46605c02ac9e7` |
| `indexes.json` | 530213 | `b7c8961095f0b4cae8f4a16a5011e7c84047a60c1277e28ee8df9e56074ee509` |

- **上游**：<https://github.com/whatwg/encoding>
- **钉定版本**：commit `2c3853e461afd718be198772170d024e427aee21`
  （与 `tools/generate_tables.py` 里的 `REV` 常量一致；取该 commit 的 `encodings.json` / `indexes.json`）
- **本副本的自检**：`encodings.json` 解出 7 组 / **40 种编码** / **228 个 label**，
  与 README 与 `moon.mod` 的口径一致（可用 `python tools/generate_tables.py` 的输出复核）。
- **许可与再分发**：WHATWG Encoding Standard 的源码部分按 **BSD 3-Clause** 授权，
  全文见仓库根目录 [`LICENSE-WHATWG`](../../LICENSE-WHATWG)（该文件同时含规范的 CC-BY-4.0 文本）。
  本仓库对这两个数据文件的使用属于「并入源码」范畴，遵守 BSD-3-Clause 的署名要求。
- **未核验项（如实说明）**：本副本**未与上游该 commit 做过逐字节比对**（撰写时无 raw.githubusercontent
  访问）。上面的 sha256 是**本仓库内文件**的实测值，可用于日后与上游核对，但**不构成**
  「与上游逐字节一致」的断言。
