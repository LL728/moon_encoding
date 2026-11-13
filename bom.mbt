// bom.mbt
//
// 规范 §6.1 "Legacy hooks for standards" 的三个入口：BOM sniff、decode 钩子、
// 以及 decode 钩子的流式形态（AutoDecoder）。
//
// 规范原文（encoding.bs @ 2c3853e）：
//   To BOM sniff an I/O queue of bytes ioQueue: let BOM be the result of
//   peeking 3 bytes ... for each row in the table, if BOM starts with the
//   bytes given in the first column, return the encoding; otherwise return null.
//   To decode ... let BOMEncoding be the result of BOM sniffing ioQueue; if
//   non-null, set encoding to it and read three bytes (UTF-8) or two bytes
//   otherwise; then process with error mode "replacement".
//
// 规范特别说明：decode 无法把"我发现了 BOM、你给的 encoding 作废"回传给调用方，
// 故 BOM sniff 被单独暴露成钩子。本文件同样保留这个区分。

///|
/// 按规范 §6.1 的 BOM 表判定输入开头的字节序标记，返回对应编码的规范名。
/// 只看前 3 字节，不消费、不改写输入；不足 3 字节时按可匹配的前缀判定
/// （`FE FF` / `FF FE` 两字节即可确认，`EF BB BF` 需三字节）。
pub fn bom_sniff(bytes : Bytes) -> String? {
  let n = bytes.length()
  if n >= 3 &&
    bytes[0].to_int() == 0xEF &&
    bytes[1].to_int() == 0xBB &&
    bytes[2].to_int() == 0xBF {
    Some("UTF-8")
  } else if n >= 2 && bytes[0].to_int() == 0xFE && bytes[1].to_int() == 0xFF {
    Some("UTF-16BE")
  } else if n >= 2 && bytes[0].to_int() == 0xFF && bytes[1].to_int() == 0xFE {
    Some("UTF-16LE")
  } else {
    None
  }
}

///|
/// 规范 §6.1 的 decode 钩子：BOM 优先于调用方给的 fallback label，
/// 命中时**吞掉** BOM 字节（UTF-8 三个、其余两个），剩余字节按 replacement 模式解码。
/// fallback label 本身仍要能解析（未知 label 照常报 `UnknownLabel`）。
pub fn decode_auto(
  bytes : Bytes,
  fallback_label : String,
) -> Result[String, EncodingError] {
  // 规范先确定 fallback encoding（get an encoding 失败即结束），再看 BOM。
  let fallback = match label_to_encoding(fallback_label) {
    Err(e) => return Err(e)
    Ok(name) => name
  }
  let bom = bom_sniff(bytes)
  let name = match bom {
    Some(bom_name) => bom_name
    None => fallback
  }
  let skip = match bom {
    Some(bom_name) => if bom_name == "UTF-8" { 3 } else { 2 }
    None => 0
  }
  let decoder = match Decoder::new(name) {
    Err(e) => return Err(e)
    Ok(d) => d
  }
  // 库源码不能复用 wbtest 里的切片辅助函数，这里就地构造剩余字节。
  let rest : Array[Byte] = []
  let mut i = skip
  while i < bytes.length() {
    rest.push(bytes[i])
    i = i + 1
  }
  let head = decoder.consume(Bytes::from_array(rest.exact_view()))
  let tail = decoder.finish()
  if tail.is_empty() {
    Ok(head)
  } else {
    Ok(head + tail)
  }
}

///|
/// 流式 BOM 感知解码器 —— 规范 §6.1 decode 钩子的流式形态。
///
/// 为什么是独立类型而不是 `Decoder` 本身：BOM 未定案前必须缓冲字节、定案后要换成
/// BOM 指示的解码器，这要求改 `Decoder` 的字段；而 `Decoder` 已承载 175 项测试与 CLI，
/// 为了把回归风险压到零，这里用独立类型承担「先嗅探、后转交」这一段生命周期。
pub struct AutoDecoder {
  /// 定案前的回退编码（规范名）。
  priv fallback : String
  /// 定案前缓冲的字节；`inner` 一旦为 `Some` 即不再使用。
  priv pending : Array[Byte]
  /// 定案后的实际解码器；`None` 表示 BOM 尚未定案。
  priv mut inner : Decoder?
}

///|
/// 构造流式 BOM 感知解码器。`fallback_label` 与 `decode_auto` 一样必须先能解析，
/// 未知 label 在构造期就报 `UnknownLabel`（不推迟到第一次 `consume`）。
pub fn Decoder::new_auto(
  fallback_label : String,
) -> Result[AutoDecoder, EncodingError] {
  let name = match label_to_encoding(fallback_label) {
    Err(e) => return Err(e)
    Ok(n) => n
  }
  Ok({ fallback: name, pending: [], inner: None, })
}

///|
/// 定案判定。返回值：`-1` 继续等（字节还不够且仍可能是 BOM），
/// `0` 无 BOM，`3` UTF-8（吞 3 字节），`4` UTF-16BE（吞 2 字节），`5` UTF-16LE（吞 2 字节）。
/// `at_end` 为真时不再等待，短缓冲一律按「无 BOM」定案。
fn AutoDecoder::auto_decide(self : AutoDecoder, at_end : Bool) -> Int32 {
  let n = self.pending.length()
  if n == 0 {
    return if at_end { 0 } else { -1 }
  }
  let first = self.pending[0].to_int()
  // 首字节不可能是任何 BOM 前缀：立即透传，否则整个流会卡在缓冲里。
  if first != 0xEF && first != 0xFE && first != 0xFF {
    return 0
  }
  if first == 0xEF {
    if n >= 3 {
      if self.pending[1].to_int() == 0xBB && self.pending[2].to_int() == 0xBF {
        return 3
      }
      return 0
    }
    if n == 2 && self.pending[1].to_int() != 0xBB {
      return 0
    }
    return if at_end { 0 } else { -1 }
  }
  // first 是 0xFE 或 0xFF：两字节即可定案。
  if n >= 2 {
    if first == 0xFE && self.pending[1].to_int() == 0xFF {
      return 4
    }
    if first == 0xFF && self.pending[1].to_int() == 0xFE {
      return 5
    }
    return 0
  }
  return if at_end { 0 } else { -1 }
}

///|
/// 按判定结果建立内部解码器，并把缓冲里 BOM 之后的字节立刻喂进去，返回这段文本。
/// 之后所有 `consume` / `finish` 都直接转交给 `inner`。
fn AutoDecoder::auto_settle(self : AutoDecoder, code : Int32) -> String {
  let name = if code == 3 {
    "UTF-8"
  } else if code == 4 {
    "UTF-16BE"
  } else if code == 5 {
    "UTF-16LE"
  } else {
    self.fallback
  }
  let skip = if code == 3 { 3 } else if code >= 4 { 2 } else { 0 }
  let decoder = match Decoder::new(name) {
    Ok(d) => d
    Err(_) =>
      // 规范名都由本库自身解析而来，理论上不会失败；失败则退回 fallback。
      match Decoder::new(self.fallback) {
        Ok(d) => d
        Err(_) => return ""
      }
  }
  self.inner = Some(decoder)
  let rest : Array[Byte] = []
  let mut i = skip
  while i < self.pending.length() {
    rest.push(self.pending[i])
    i = i + 1
  }
  decoder.consume(Bytes::from_array(rest.exact_view()))
}

///|
/// 喂入一个字节块。BOM 未定案时先缓冲（可能返回空串），定案后转交内部解码器。
pub fn AutoDecoder::consume(self : AutoDecoder, chunk : Bytes) -> String {
  match self.inner {
    Some(decoder) => decoder.consume(chunk)
    None => {
      for i in 0..<chunk.length() {
        self.pending.push(chunk[i])
      }
      let code = self.auto_decide(false)
      if code < 0 {
        ""
      } else {
        self.auto_settle(code)
      }
    }
  }
}

///|
/// 结束流。BOM 仍未定案时先按「无 BOM」定案，再冲刷内部解码器。
pub fn AutoDecoder::finish(self : AutoDecoder) -> String {
  match self.inner {
    Some(decoder) => decoder.finish()
    None => {
      let code = self.auto_decide(true)
      let head = self.auto_settle(code)
      let tail = match self.inner {
        Some(decoder) => decoder.finish()
        None => ""
      }
      if tail.is_empty() {
        head
      } else {
        head + tail
      }
    }
  }
}
