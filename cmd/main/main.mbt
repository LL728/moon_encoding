// cmd/main/main.mbt
//
// 命令行：文件级编码转换。
//   decode <label> <input> <output>   按 <label> 解码字节，写出 UTF-8 文本
//   encode <label> <input> <output>   读入 UTF-8 文本，按 <label> 写出字节
//
// 失败一律以非零退出（abort），便于脚本与 CI 断言错误路径。

///|
/// 打印错误并以非零状态退出。
/// 注意：非 native 目标上 core 的 abort 会丢弃消息参数（见 core/abort/abort.mbt），
/// 所以消息必须先经 println 输出，abort 只负责非零退出码。
fn[T] die(msg : String) -> T {
  println(msg)
  abort(msg)
}

///|
fn usage() -> Unit {
  println("moon_encoding — WHATWG 编码转换")
  println("")
  println("用法:")
  println("  decode <label> <input> <output>")
  println("      输入是 <label> 编码的字节，输出是 UTF-8 文本")
  println("  encode <label> <input> <output>")
  println("      输入是 UTF-8 文本，输出是 <label> 编码的字节")
  println("")
  println("示例:")
  println("  moon run cmd/main -- decode windows-1252 legacy.txt utf8.txt")
  println("  moon run cmd/main -- encode latin1 utf8.txt legacy.txt")
}

///|
fn main {
  let args = @env.args()
  if args.length() != 5 {
    usage()
    die("需要 4 个参数: <mode> <label> <input> <output>")
  }
  let mode = args[1]
  let label = args[2]
  let input = args[3]
  let output = args[4]
  try {
    if mode == "decode" {
      let data = @fs.read_file_to_bytes(input)
      match @moon_encoding.decode(data, label) {
        Ok(text) => {
          @fs.write_bytes_to_file(output, @utf8.encode(text))
          println("已写入: \{output}（\{text.length()} 字符，UTF-8）")
        }
        Err(e) => die("解码失败: " + @debug.to_string(e))
      }
    } else if mode == "encode" {
      let text = @utf8.decode_lossy(@fs.read_file_to_bytes(input).exact_view())
      match @moon_encoding.encode(text, label) {
        Ok(bytes) => {
          @fs.write_bytes_to_file(output, bytes)
          println(
            "已写入: \{output}（\{bytes.length()} 字节，\{label}）",
          )
        }
        Err(e) => die("编码失败: " + @debug.to_string(e))
      }
    } else {
      usage()
      die("未知命令: \{mode}（应为 decode 或 encode）")
    }
  } catch {
    @fs.IOError::IOError(msg) => die("I/O 错误: \{msg}")
  }
}
