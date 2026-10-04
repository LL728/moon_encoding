// multibyte.mbt
//
// Big5 与 Shift_JIS 的编解码，逐条实现 encoding.bs（whatwg/encoding @ 2c3853e）的
// §big5-decoder、§big5-encoder、§shift_jis-decoder、§shift_jis-encoder。
//
// 与 GBK 状态机的差异（都按规范，不可凭记忆合并）：
// - 两者都只有**一个**挂起字节（lead），无需 first/second/third；
// - Big5：trail 偏移 0x40/0x62（第二段是 0xA1 起）；4 个指针对应**双码点**
//   命名序列（规范为规避 PUA 而设）；新鲜字节 0x80/0xA0/0xFF 报错；
//   编码端只允许 pointer >= 5024（避开低位/HKSCS 行）且 6 个码点取最后出现。
// - Shift_JIS：0x80 单字节往返（U+0080）；0xA1..0xDF 是半角片假名直算；
//   指针 8836..10715 是 EUDC PUA（0xE000-8836+pointer，即 U+E000..U+E757）；编码端有 ¥→0x5C、
//   U+203E→0x7E、U+2212→U+FF0D 三个特例，并排除指针 8272..8835（NEC 重复行）。

///|
/// 单挂起字节状态（Big5 lead / Shift_JIS lead，0 = 未占用）。
priv struct LeadState {
  mut lead : Int
}

///|
fn LeadState::new() -> LeadState {
  { lead: 0, }
}

///|
/// Big5 双码点命名序列（§big5-decoder 表格，规范为规避 PUA）：
/// (指针, 码点1, 码点2) 按指针升序，供二分。
let big5_named_sequences : Array[Int] = [
  1133, 0x00CA, 0x0304, 1135, 0x00CA, 0x030C, 1164, 0x00EA, 0x0304, 1166, 0x00EA,
  0x030C,
]

///|
/// 命中命名序列时返回 [码点1, 码点2]，否则返回空数组。
fn big5_sequence_lookup(pointer : Int) -> Array[Int] {
  let mut lo = 0
  let mut hi = big5_named_sequences.length() / 3 - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let p = big5_named_sequences[mid * 3]
    if p == pointer {
      let out : Array[Int] = [
        big5_named_sequences[mid * 3 + 1],
        big5_named_sequences[mid * 3 + 2],
      ]
      return out
    }
    if p < pointer {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  let empty : Array[Int] = []
  empty
}

///|
/// 在 (码点, 指针) 扁平升序反向表上二分，返回指针；找不到返回 -1。
/// Big5 / Shift_JIS / EUC-JP / EUC-KR 的编码反向表共用此查找。
fn encode_index_lookup(encode_index : Array[Int], cp : Int) -> Int {
  let mut lo = 0
  let mut hi = encode_index.length() / 2 - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let v = encode_index[mid * 2]
    if v == cp {
      return encode_index[mid * 2 + 1]
    }
    if v < cp {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  -1
}

///|
/// Big5 解码一个字节块（§big5-decoder）。
fn big5_consume(state : LeadState, input : Bytes) -> String {
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
    if state.lead != 0 {
      let lead = state.lead
      state.lead = 0
      let mut pointer = -1
      if (b >= 0x40 && b <= 0x7E) || (b >= 0xA1 && b <= 0xFE) {
        let offset = if b < 0x7F { 0x40 } else { 0x62 }
        pointer = (lead - 0x81) * 157 + (b - offset)
      }
      if pointer >= 0 {
        let named = big5_sequence_lookup(pointer)
        if named.length() == 2 {
          out.push(int_to_char(named[0]))
          out.push(int_to_char(named[1]))
          continue
        }
        if pointer < big5_index.length() && big5_index[pointer] >= 0 {
          out.push(int_to_char(big5_index[pointer]))
          continue
        }
      }
      if b < 0x80 {
        let restored : Array[Int] = [b]
        replay = replay_prepend(replay, r, restored)
        r = 0
      }
      out.push(replacement_char())
    } else if b < 0x80 {
      out.push(int_to_char(b))
    } else if b >= 0x81 && b <= 0xFE {
      state.lead = b
    } else {
      out.push(replacement_char()) // 0x80 / 0xA0 / 0xFF 等
    }
  }
  String::from_iter(out.iter())
}

///|
/// Big5 流结束：有挂起 lead → 单个 U+FFFD（§big5-decoder end-of-queue）。
fn big5_finish(state : LeadState) -> String {
  if state.lead != 0 {
    state.lead = 0
    let out : Array[Char] = [replacement_char()]
    return String::from_iter(out.iter())
  }
  ""
}

///|
/// Big5 编码（§big5-encoder + §index Big5 pointer 规则，反向表由生成器按
/// 过滤（pointer >= 5024）+ 六码点取最后出现生成）。
fn big5_encode(text : String) -> Result[Bytes, EncodingError] {
  let out : Array[Byte] = []
  let mut index = 0
  for c in text {
    let cp = c.to_int()
    if cp < 0x80 {
      out.push(int_to_byte(cp))
    } else {
      let pointer = encode_index_lookup(big5_encode_index, cp)
      if pointer < 0 {
        return Err(EncodingError::Unmappable(cp, index))
      }
      let lead = pointer / 157 + 0x81
      let trail = pointer % 157
      let offset = if trail < 0x3F { 0x40 } else { 0x62 }
      out.push(int_to_byte(lead))
      out.push(int_to_byte(trail + offset))
    }
    index += 1
  }
  Ok(Bytes::from_array(out.exact_view()))
}

///|
/// Shift_JIS 解码一个字节块（§shift_jis-decoder，含 EUDC PUA 区间）。
fn shift_jis_consume(state : LeadState, input : Bytes) -> String {
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
    if state.lead != 0 {
      let lead = state.lead
      state.lead = 0
      let mut pointer = -1
      if (b >= 0x40 && b <= 0x7E) || (b >= 0x80 && b <= 0xFC) {
        let offset = if b < 0x7F { 0x40 } else { 0x41 }
        let lead_offset = if lead < 0xA0 { 0x81 } else { 0xC1 }
        pointer = (lead - lead_offset) * 188 + (b - offset)
      }
      if pointer >= 0 {
        // EUDC：Windows 互通遗留的 PUA 区（U+E000..U+E7C7），先于 index 查询
        if pointer >= 8836 && pointer <= 10715 {
          out.push(int_to_char(0xE000 - 8836 + pointer))
          continue
        }
        if pointer < jis0208_index.length() && jis0208_index[pointer] >= 0 {
          out.push(int_to_char(jis0208_index[pointer]))
          continue
        }
      }
      if b < 0x80 {
        let restored : Array[Int] = [b]
        replay = replay_prepend(replay, r, restored)
        r = 0
      }
      out.push(replacement_char())
    } else if b < 0x80 || b == 0x80 {
      out.push(int_to_char(b)) // ASCII 与 0x80 → U+0080（CPython 在 0x80 报错——分歧）
    } else if b >= 0xA1 && b <= 0xDF {
      out.push(int_to_char(0xFF61 - 0xA1 + b)) // 半角片假名 U+FF61..U+FF9F
    } else if (b >= 0x81 && b <= 0x9F) || (b >= 0xE0 && b <= 0xFC) {
      state.lead = b
    } else {
      out.push(replacement_char()) // 0xA0 / 0xFD..0xFF
    }
  }
  String::from_iter(out.iter())
}

///|
/// Shift_JIS 流结束：有挂起 lead → 单个 U+FFFD。
fn shift_jis_finish(state : LeadState) -> String {
  if state.lead != 0 {
    state.lead = 0
    let out : Array[Char] = [replacement_char()]
    return String::from_iter(out.iter())
  }
  ""
}

///|
/// Shift_JIS 编码（§shift_jis-encoder：ASCII/U+0080、¥→0x5C、U+203E→0x7E、
/// 半角片假名、U+2212→U+FF0D、再走排除 8272..8835 的反向索引）。
fn shift_jis_encode(text : String) -> Result[Bytes, EncodingError] {
  let out : Array[Byte] = []
  let mut index = 0
  for c in text {
    let mut cp = c.to_int()
    if cp < 0x80 || cp == 0x80 {
      out.push(int_to_byte(cp))
    } else if cp == 0x00A5 {
      out.push(int_to_byte(0x5C))
    } else if cp == 0x203E {
      out.push(int_to_byte(0x7E))
    } else if cp >= 0xFF61 && cp <= 0xFF9F {
      out.push(int_to_byte(cp - 0xFF61 + 0xA1))
    } else {
      if cp == 0x2212 {
        cp = 0xFF0D // 规范：U+2212 归一到全角减号后再查索引
      }
      let pointer = encode_index_lookup(shift_jis_encode_index, cp)
      if pointer < 0 {
        return Err(EncodingError::Unmappable(cp, index))
      }
      let lead = pointer / 188
      let lead_offset = if lead < 0x1F { 0x81 } else { 0xC1 }
      let trail = pointer % 188
      let offset = if trail < 0x3F { 0x40 } else { 0x41 }
      out.push(int_to_byte(lead + lead_offset))
      out.push(int_to_byte(trail + offset))
    }
    index += 1
  }
  Ok(Bytes::from_array(out.exact_view()))
}
