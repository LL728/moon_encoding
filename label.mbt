// label.mbt
//
// WHATWG label 解析：按规范做 ASCII 大小写不敏感匹配，得到规范编码名。

///|
/// ASCII 大小写折叠：规范的 label 匹配对 ASCII 不区分大小写。
/// 只折叠 A-Z——label 表里全是 ASCII，非 ASCII 字符保持原样即可保证永不匹配。
fn ascii_lowercase(s : String) -> String {
  String::from_iter(s.iter().map(fn(c) { c.to_ascii_lowercase() }))
}

///|
/// 把 WHATWG label 解析为规范编码名（ASCII 大小写不敏感）。
/// label 不在标准定义的 228 个之内时返回 `EncodingError::UnknownLabel`。
pub fn label_to_encoding(label : String) -> Result[String, EncodingError] {
  match label_lookup(ascii_lowercase(label)) {
    Some(name) => Ok(name)
    None => Err(EncodingError::UnknownLabel(label))
  }
}
