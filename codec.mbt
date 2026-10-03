// codec.mbt
//
// 公共编解码接口：错误类型、流式 Decoder、一次性 decode / encode。
//
// 错误语义对齐 WHATWG Encoding Standard（encoding.bs @ 2c3853e）：
// - 解码为 replacement 模式：错误字节输出 U+FFFD（规范 "process a queue" 的 replacement 分支）；
// - 编码为 fatal 模式：不可映射字符直接报错（规范导出的 "encode or fail" 操作）。
//   规范另定义 html 模式（输出 &#码点; 形式，供 HTML 表单用），本库暴露 fatal 原语，
//   替换策略交还调用方——规范本身也鼓励非浏览器实现采用适合自己的 API。

///|
/// 编解码过程中可能的错误。
pub enum EncodingError {
  /// label 不在 WHATWG Encoding Standard 定义的 228 个 label 之内。
  UnknownLabel(String)
  /// label 合法，但该编码尚未实现——本项目按里程碑逐步补齐，见 README 的覆盖范围。
  UnsupportedEncoding(String)
  /// 编码时遇到目标编码无法表示的字符（fatal 模式）。
  /// 第一个参数是码点值，第二个是它在输入中的字符位置。
  Unmappable(Int, Int)
} derive(Eq, @debug.Debug)

///|
/// 流式解码器：`consume` 逐块喂入字节，`finish` 冲刷结尾。
/// 字段私有：可解码的编码在构造时已解析成表，放开写会让外部破坏状态。
pub struct Decoder {
  priv decode_table : Array[Int]
}

///|
/// 由 WHATWG label 构造解码器（ASCII 大小写不敏感）。
/// label 合法但尚未实现的编码返回 `UnsupportedEncoding`。
pub fn Decoder::new(label : String) -> Result[Decoder, EncodingError] {
  match label_to_encoding(label) {
    Err(e) => Err(e)
    Ok(encoding) =>
      match encoding {
        "windows-1252" => {
          let decoder : Decoder = { decode_table: windows_1252_decode, }
          Ok(decoder)
        }
        _ => Err(EncodingError::UnsupportedEncoding(encoding))
      }
  }
}

///|
/// 喂入一个字节块，返回新解出的文本。
/// 单字节编码无跨块状态：任意切分的结果与整段解码一致。
pub fn Decoder::consume(self : Decoder, chunk : Bytes) -> String {
  single_byte_decode(self.decode_table, chunk)
}

///|
/// 结束流，冲刷未完成的输入。单字节编码没有滞留字节，恒返回空串；
/// 多字节编码（后续里程碑）会在这里把截断的字节序列补成 U+FFFD。
pub fn Decoder::finish(_self : Decoder) -> String {
  ""
}

///|
/// 一次性解码整段字节（等价于 new + consume + finish）。
pub fn decode(input : Bytes, label : String) -> Result[String, EncodingError] {
  match Decoder::new(label) {
    Err(e) => Err(e)
    Ok(decoder) => {
      let head = decoder.consume(input)
      let tail = decoder.finish()
      if tail.is_empty() {
        Ok(head)
      } else {
        Ok(head + tail)
      }
    }
  }
}

///|
/// 一次性编码：文本 -> 字节（fatal 模式，对应规范 `encode or fail`）。
/// 目标编码无法表示的字符返回 `Unmappable(码点, 字符位置)`。
pub fn encode(text : String, label : String) -> Result[Bytes, EncodingError] {
  match label_to_encoding(label) {
    Err(e) => Err(e)
    Ok(encoding) =>
      match encoding {
        "windows-1252" => single_byte_encode(windows_1252_encode, text)
        _ => Err(EncodingError::UnsupportedEncoding(encoding))
      }
  }
}
