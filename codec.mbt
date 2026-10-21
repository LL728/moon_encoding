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
  /// label 合法，但该编码**规范未定义编码器**（replacement / UTF-16BE / UTF-16LE，
  /// 见 §get an encoder 的断言）或本构建尚未接线——两者都如实报出而不静默失败。
  UnsupportedEncoding(String)
  /// 编码时遇到目标编码无法表示的字符（fatal 模式）。
  /// 第一个参数是码点值，第二个是它在输入中的字符位置。
  Unmappable(Int32, Int32)
} derive(Eq, @debug.Debug)

///|
/// 显式声明 trait 方法提升（新编译器弃用隐式提升，见 implicit_impl_as_method）。
pub extend EncodingError with Eq::{not_equal, equal}

///|
pub extend EncodingError with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 解码器内部状态：单字节表驱动（x-user-defined 也合成一张表走这条通路）、
/// 中文多字节状态机（GBK/gb18030 共用——规范规定 GBK 的解码器就是 gb18030 的
/// 解码器）、日文/韩文状态机、UTF 状态机，以及 replacement 的一次性错误状态。
enum DecoderState {
  SingleByte(Array[Int32])
  Chinese(ChineseState)
  Big5(LeadState)
  ShiftJis(LeadState)
  EucJp(EucJpState)
  EucKr(LeadState)
  Iso2022Jp(Iso2022JpState)
  Replacement(ReplacementState)
  Utf8(Utf8State)
  Utf16(Utf16State)
}

///|
/// 流式解码器：`consume` 逐块喂入字节，`finish` 冲刷结尾。
/// 字段私有：可解码的编码在构造时已解析成状态，放开写会让外部破坏状态。
pub struct Decoder {
  priv state : DecoderState
}

///|
/// 由 WHATWG label 构造解码器（ASCII 大小写不敏感）。
/// 规范的 40 种编码都有解码器，故这里全部可构造；末尾的 `UnsupportedEncoding`
/// 分支只作为防御（label 表与接线漂移时如实报错，而不是静默失败）。
pub fn Decoder::new(label : String) -> Result[Decoder, EncodingError] {
  match label_to_encoding(label) {
    Err(e) => Err(e)
    Ok(encoding) =>
      match single_byte_tables(encoding) {
        Some((decode_table, _)) => {
          let decoder : Decoder = {
            state: DecoderState::SingleByte(decode_table),
          }
          Ok(decoder)
        }
        None =>
          match encoding {
            "GBK" | "gb18030" => {
              let decoder : Decoder = {
                state: DecoderState::Chinese(ChineseState::new()),
              }
              Ok(decoder)
            }
            "Big5" => {
              let decoder : Decoder = {
                state: DecoderState::Big5(LeadState::new()),
              }
              Ok(decoder)
            }
            "Shift_JIS" => {
              let decoder : Decoder = {
                state: DecoderState::ShiftJis(LeadState::new()),
              }
              Ok(decoder)
            }
            "EUC-JP" => {
              let decoder : Decoder = {
                state: DecoderState::EucJp(EucJpState::new()),
              }
              Ok(decoder)
            }
            "EUC-KR" => {
              let decoder : Decoder = {
                state: DecoderState::EucKr(LeadState::new()),
              }
              Ok(decoder)
            }
            "ISO-2022-JP" => {
              let decoder : Decoder = {
                state: DecoderState::Iso2022Jp(Iso2022JpState::new()),
              }
              Ok(decoder)
            }
            // 规范没有 x-user-defined 的索引表（纯算法），故合成一张无空位的
            // 单字节表走既有引擎；replacement 只带"是否已报过 error"两个布尔量。
            "x-user-defined" => {
              let decoder : Decoder = {
                state: DecoderState::SingleByte(x_user_defined_decode_table()),
              }
              Ok(decoder)
            }
            "replacement" => {
              let decoder : Decoder = {
                state: DecoderState::Replacement(ReplacementState::new()),
              }
              Ok(decoder)
            }
            "UTF-8" => {
              let decoder : Decoder = {
                state: DecoderState::Utf8(Utf8State::new()),
              }
              Ok(decoder)
            }
            "UTF-16BE" => {
              let decoder : Decoder = {
                state: DecoderState::Utf16(Utf16State::new(true)),
              }
              Ok(decoder)
            }
            "UTF-16LE" => {
              let decoder : Decoder = {
                state: DecoderState::Utf16(Utf16State::new(false)),
              }
              Ok(decoder)
            }
            _ => Err(EncodingError::UnsupportedEncoding(encoding))
          }
      }
  }
}

///|
/// 喂入一个字节块，返回新解出的文本。
/// 单字节编码无跨块状态：任意切分的结果与整段解码一致。
pub fn Decoder::consume(self : Decoder, chunk : Bytes) -> String {
  match self.state {
    DecoderState::SingleByte(table) => single_byte_decode(table, chunk)
    DecoderState::Chinese(state) => chinese_consume(state, chunk)
    DecoderState::Big5(state) => big5_consume(state, chunk)
    DecoderState::ShiftJis(state) => shift_jis_consume(state, chunk)
    DecoderState::EucJp(state) => euc_jp_consume(state, chunk)
    DecoderState::EucKr(state) => euc_kr_consume(state, chunk)
    DecoderState::Iso2022Jp(state) => iso2022_jp_consume(state, chunk)
    DecoderState::Replacement(state) => replacement_decode(state, chunk)
    DecoderState::Utf8(state) => utf8_consume(state, chunk)
    DecoderState::Utf16(state) => utf16_consume(state, chunk)
  }
}

///|
/// 结束流，冲刷未完成的输入。单字节编码没有滞留字节，返回空串；
/// 中文编码在这里按规范 end-of-queue 把截断序列补成单个 U+FFFD。
pub fn Decoder::finish(self : Decoder) -> String {
  match self.state {
    DecoderState::SingleByte(_) => ""
    DecoderState::Chinese(state) => chinese_finish(state)
    DecoderState::Big5(state) => big5_finish(state)
    DecoderState::ShiftJis(state) => shift_jis_finish(state)
    DecoderState::EucJp(state) => euc_jp_finish(state)
    DecoderState::EucKr(state) => euc_kr_finish(state)
    DecoderState::Iso2022Jp(state) => iso2022_jp_finish(state)
    DecoderState::Replacement(state) => replacement_finish(state)
    DecoderState::Utf8(state) => utf8_finish(state)
    DecoderState::Utf16(state) => utf16_finish(state)
  }
}

///|
/// 本构建已接线的编码（WHATWG 规范名）——label 解析覆盖全部 40 种编码，
/// 其中这些可实际编解码；返回新数组，改它不影响内部状态。
pub fn supported_encodings() -> Array[String] {
  let out : Array[String] = []
  for name in single_byte_names {
    out.push(name)
  }
  for name in multi_byte_names {
    out.push(name)
  }
  out
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
      match single_byte_tables(encoding) {
        Some((_, encode_table)) => single_byte_encode(encode_table, text)
        None =>
          match encoding {
            "GBK" => chinese_encode(text, true)
            "gb18030" => chinese_encode(text, false)
            "Big5" => big5_encode(text)
            "Shift_JIS" => shift_jis_encode(text)
            "EUC-JP" => euc_jp_encode(text)
            "EUC-KR" => euc_kr_encode(text)
            "ISO-2022-JP" => iso2022_jp_encode(text)
            "x-user-defined" =>
              single_byte_encode(x_user_defined_encode_table(), text)
            "UTF-8" => utf8_encode(text)
            // 规范 §get an encoder 断言 encoding 不是 replacement 或
            // UTF-16BE/LE——WHATWG 不定义它们的编码器，此处如实报未支持。
            "replacement" | "UTF-16BE" | "UTF-16LE" =>
              Err(EncodingError::UnsupportedEncoding(encoding))
            _ => Err(EncodingError::UnsupportedEncoding(encoding))
          }
      }
  }
}
