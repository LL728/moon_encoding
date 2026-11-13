// bom.mbt
//
// 规范 §6.1 "Legacy hooks for standards" 的两个钩子：BOM sniff 与 decode。
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
