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
  println("  decode <label> <input> <output> [--auto]")
  println("      输入是 <label> 编码的字节，输出是 UTF-8 文本")
  println(
    "      --auto  启用规范 §6.1 的 BOM 嗅探：BOM 优先于 <label>，并吞掉 BOM 字节",
  )
  println("  encode <label> <input> <output> [--html]")
  println("      输入是 UTF-8 文本，输出是 <label> 编码的字节")
  println(
    "      --html  启用规范 §4.1 的 html 错误模式：不可映射码点写成 &#十进制; 而非报错",
  )
  println(
    "              注意：该序列无法与合法输入区分，可能造成静默数据丢失",
  )
  println("")
  println(
    "      --auto 与 --html 都省略时为既有行为（fatal 错误模式、不做 BOM 嗅探）",
  )
  println("")
  println("  list")
  println("      列出本构建支持的全部编码（WHATWG 规范名）")
  println("")
  println("示例:")
  println("  moon run cmd/main -- decode windows-1252 legacy.txt utf8.txt")
  println("  moon run cmd/main -- encode latin1 utf8.txt legacy.txt")
  println("  moon run cmd/main -- list")
}

///|
/// list：打印 supported_encodings() 的规范名（顺序即接线顺序：单字节 28 种
/// 在前、多字节与 UTF/杂项 12 种在后）。
fn list_encodings() -> Unit {
  let names = @moon_encoding.supported_encodings()
  println("支持 \{names.length()} 种编码（WHATWG 规范名）:")
  for name in names {
    println("  \{name}")
  }
}

///|
fn main {
  let args = @env.args()
  if args.length() == 2 && args[1] == "list" {
    list_encodings()
    return
  }
  if args.length() != 5 && args.length() != 6 {
    usage()
    die("需要 4 个参数: <mode> <label> <input> <output> [--auto|--html]")
  }
  let mode = args[1]
  let label = args[2]
  let input = args[3]
  let output = args[4]
  let flag = if args.length() == 6 { args[5] } else { "" }
  try {
    if mode == "decode" {
      let data = @fs.read_file_to_bytes(input)
      if flag != "" && flag != "--auto" {
        usage()
        die("decode 只接受 --auto，收到: \{flag}")
      }
      let decoded = if flag == "--auto" {
        @moon_encoding.decode_auto(data, label)
      } else {
        @moon_encoding.decode(data, label)
      }
      match decoded {
        Ok(text) => {
          @fs.write_bytes_to_file(output, @utf8.encode(text))
          println("已写入: \{output}（\{text.length()} 字符，UTF-8）")
        }
        Err(e) => die("解码失败: " + @debug.to_string(e))
      }
    } else if mode == "encode" {
      let text = @utf8.decode_lossy(@fs.read_file_to_bytes(input).exact_view())
      if flag != "" && flag != "--html" {
        usage()
        die("encode 只接受 --html，收到: \{flag}")
      }
      let encoded = if flag == "--html" {
        @moon_encoding.encode_with_mode(
          text,
          label,
          @moon_encoding.encode_error_mode_html(),
        )
      } else {
        @moon_encoding.encode(text, label)
      }
      match encoded {
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
