// utf.mbt
//
// UTF-8 与 UTF-16BE/LE 的编解码，逐条实现 encoding.bs（whatwg/encoding @ 2c3853e）的
// §utf-8-decoder、§utf-8-encoder、§shared-utf-16-decoder。
//
// 关键规范事实（全部读原文后落代码，不可凭记忆）：
// - UTF-8 解码：0xC0/0xC1（过长两字节头）与 0xF5..0xFF 在**新鲜字节**分支直接报错；
//   0xE0 → 下界 0xA0、0xED → 上界 0x9F（挡住过长与 UTF-16 代理区）、
//   0xF0 → 下界 0x90、0xF4 → 上界 0x8F（挡住 >U+10FFFF）；
//   **非法延续字节 → 全状态复位 + 恢复该字节 + error**（该字节随后按新鲜字节重处理）；
//   序列在 end-of-queue 截断 → 恰好一个 U+FFFD。
//   规范注明这些约束等价于 Unicode 的 "Best Practices for Using U+FFFD"。
// - UTF-16 解码：共享状态机 + 字节序标志；未配对**低**代理 → error（两字节已消费）；
//   高代理后跟非低代理 → 恢复**当前码元**的两字节 + error（高代理本身被消化为
//   一个 U+FFFD，当前码元原样重处理不丢字符）；end-of-queue 有挂起 → 一个 U+FFFD。
// - **规范不定义 UTF-16 编码器**（§get an encoder 断言 encoding 不是
//   replacement 或 UTF-16BE/LE）——编解码入口对 utf-16 返回 UnsupportedEncoding。
// - BOM 不属于解码器算法（属于 decode 钩子）。本库不做 BOM 嗅探（已知限制），
//   因此 UTF-16 输入里的 BOM 会作为 U+FEFF 字符解出——与 CPython 的
//   utf-16-be / utf-16-le 行为一致。

///|
/// UTF-8 解码状态：规范的 code point / bytes seen / bytes needed /
/// lower boundary / upper boundary（初始 0 / 0 / 0 / 0x80 / 0xBF）。
priv struct Utf8State {
  mut code_point : Int
  mut bytes_seen : Int
  mut bytes_needed : Int
  mut lower_boundary : Int
  mut upper_boundary : Int
}

///|
fn Utf8State::new() -> Utf8State {
  {
    code_point: 0,
    bytes_seen: 0,
    bytes_needed: 0,
    lower_boundary: 0x80,
    upper_boundary: 0xBF,
  }
}

///|
fn Utf8State::has_pending(self : Utf8State) -> Bool {
  self.bytes_needed != 0
}

///|
fn Utf8State::reset(self : Utf8State) -> Unit {
  self.code_point = 0
  self.bytes_seen = 0
  self.bytes_needed = 0
  self.lower_boundary = 0x80
  self.upper_boundary = 0xBF
}

///|
/// UTF-8 解码一个字节块（§utf-8-decoder 逐步翻译）。
fn utf8_consume(state : Utf8State, input : Bytes) -> String {
  let bytes = input.to_array()
  let out : Array[Char] = []
  let mut replay : Array[Byte] = []
  let mut r = 0
  let mut i = 0
  while i < bytes.length() || r < replay.length() {
    let mut b = -1
    if r < replay.length() {
      b = replay[r].to_int()
      r += 1
    } else {
      b = bytes[i].to_int()
      i += 1
    }
    if state.bytes_needed == 0 {
      // 新鲜字节：ASCII 直通；合法序列头设置状态；其余（0x80..0xC1、0xF5..0xFF）报错
      if b < 0x80 {
        out.push(int_to_char(b))
      } else if b >= 0xC2 && b <= 0xDF {
        state.bytes_needed = 1
        state.code_point = b & 0x1F
      } else if b >= 0xE0 && b <= 0xEF {
        if b == 0xE0 {
          state.lower_boundary = 0xA0 // 挡住过长（U+0000..U+07FF 用三字节）
        }
        if b == 0xED {
          state.upper_boundary = 0x9F // 挡住 UTF-16 代理区
        }
        state.bytes_needed = 2
        state.code_point = b & 0xF
      } else if b >= 0xF0 && b <= 0xF4 {
        if b == 0xF0 {
          state.lower_boundary = 0x90 // 挡住过长四字节
        }
        if b == 0xF4 {
          state.upper_boundary = 0x8F // 挡住 >U+10FFFF
        }
        state.bytes_needed = 3
        state.code_point = b & 0x7
      } else {
        out.push(replacement_char()) // 0x80..0xC1（含过长头 C0/C1）、0xF5..0xFF
      }
    } else if b < state.lower_boundary || b > state.upper_boundary {
      // 非法延续字节：全状态复位、恢复该字节（它将按新鲜字节重处理）、报错
      state.reset()
      let restored : Array[Int] = [b]
      replay = replay_prepend(replay, r, restored)
      r = 0
      out.push(replacement_char())
    } else {
      state.lower_boundary = 0x80
      state.upper_boundary = 0xBF
      state.code_point = (state.code_point << 6) | (b & 0x3F)
      state.bytes_seen += 1
      if state.bytes_seen == state.bytes_needed {
        out.push(int_to_char(state.code_point))
        state.code_point = 0
        state.bytes_seen = 0
        state.bytes_needed = 0
      }
    }
  }
  String::from_iter(out.iter())
}

///|
/// UTF-8 流结束：序列截断 → 恰好一个 U+FFFD（§utf-8-decoder end-of-queue）。
fn utf8_finish(state : Utf8State) -> String {
  if state.has_pending() {
    state.reset()
    let out : Array[Char] = [replacement_char()]
    return String::from_iter(out.iter())
  }
  ""
}

///|
/// UTF-8 编码（§utf-8-encoder：按码点区间定 count/offset，逐 6 位发延续字节）。
/// 所有输入字符都是合法标量，三个区间必然命中，规范上不会失败。
fn utf8_encode(text : String) -> Result[Bytes, EncodingError] {
  let out : Array[Byte] = []
  for c in text {
    let cp = c.to_int()
    if cp < 0x80 {
      out.push(int_to_byte(cp))
    } else {
      let mut count = 0
      let mut offset = 0
      if cp <= 0x07FF {
        count = 1
        offset = 0xC0
      } else if cp <= 0xFFFF {
        count = 2
        offset = 0xE0
      } else {
        count = 3
        offset = 0xF0
      }
      out.push(int_to_byte((cp >> (6 * count)) + offset))
      let mut left = count
      while left > 0 {
        let temp = cp >> (6 * (left - 1))
        out.push(int_to_byte(0x80 | (temp & 0x3F)))
        left -= 1
      }
    }
  }
  Ok(Bytes::from_array(out.exact_view()))
}

///|
/// 共享 UTF-16 解码状态：lead byte / lead surrogate（-1 = null）+ 字节序标志。
priv struct Utf16State {
  mut lead_byte : Int
  mut lead_surrogate : Int
  is_be : Bool
}

///|
fn Utf16State::new(is_be : Bool) -> Utf16State {
  { lead_byte: -1, lead_surrogate: -1, is_be, }
}

///|
fn Utf16State::has_pending(self : Utf16State) -> Bool {
  self.lead_byte >= 0 || self.lead_surrogate >= 0
}

///|
fn Utf16State::reset(self : Utf16State) -> Unit {
  self.lead_byte = -1
  self.lead_surrogate = -1
}

///|
/// 共享 UTF-16 解码一个字节块（§shared-utf-16-decoder 逐步翻译）。
fn utf16_consume(state : Utf16State, input : Bytes) -> String {
  let bytes = input.to_array()
  let out : Array[Char] = []
  let mut replay : Array[Byte] = []
  let mut r = 0
  let mut i = 0
  while i < bytes.length() || r < replay.length() {
    let mut b = -1
    if r < replay.length() {
      b = replay[r].to_int()
      r += 1
    } else {
      b = bytes[i].to_int()
      i += 1
    }
    if state.lead_byte < 0 {
      state.lead_byte = b
      continue
    }
    let unit = if state.is_be {
      (state.lead_byte << 8) | b
    } else {
      (b << 8) | state.lead_byte
    }
    state.lead_byte = -1
    if state.lead_surrogate >= 0 {
      let lead = state.lead_surrogate
      state.lead_surrogate = -1
      if unit >= 0xDC00 && unit <= 0xDFFF {
        out.push(
          int_to_char(0x10000 + ((lead - 0xD800) << 10) + (unit - 0xDC00)),
        )
        continue
      }
      // 高代理未配对：恢复**当前码元**的两字节并报错——
      // 高代理被消化为一个 U+FFFD，当前码元随后按新鲜流程原样重处理
      let hi = unit >> 8
      let lo = unit & 0xFF
      let restored : Array[Int] = if state.is_be { [hi, lo] } else { [lo, hi] }
      replay = replay_prepend(replay, r, restored)
      r = 0
      out.push(replacement_char())
      continue
    }
    if unit >= 0xD800 && unit <= 0xDBFF {
      state.lead_surrogate = unit
      continue
    }
    if unit >= 0xDC00 && unit <= 0xDFFF {
      out.push(replacement_char()) // 孤立低代理（规范：不输出代理本身）
      continue
    }
    out.push(int_to_char(unit))
  }
  String::from_iter(out.iter())
}

///|
/// 共享 UTF-16 流结束：有挂起的首字节或高代理 → 一个 U+FFFD。
fn utf16_finish(state : Utf16State) -> String {
  if state.has_pending() {
    state.reset()
    let out : Array[Char] = [replacement_char()]
    return String::from_iter(out.iter())
  }
  ""
}
