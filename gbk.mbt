// gbk.mbt
//
// GBK / gb18030 编解码，逐条实现 encoding.bs（whatwg/encoding @ 2c3853e）的
// §gb18030-decoder、§gb18030-encoder、§gbk-decoder、§gbk-encoder。
//
// 规范原文（不可凭记忆简化）：
// - GBK 的解码器**就是** gb18030 的解码器（一套状态机、两张表服务两个名字）；
// - GBK 的编码器是 gb18030 编码器置 is-GBK 标志（€→0x80、禁止 4 字节回退）；
// - 解码错误/截断按 replacement 模式输出 U+FFFD；错误路径带字节重放
//   （规范的 Restore 操作）；
// - 编码侧：U+E5E5 明确不可编码；18 条 PUA 侧表（2005/2022 兼容）；
//   index pointer 取**首次**出现（§index pointer，encoding.bs:774）。

///|
/// 解码挂起状态，对应规范 gb18030 first / second / third（0 = 未占用）。
priv struct ChineseState {
  mut first : Int
  mut second : Int
  mut third : Int
}

///|
fn ChineseState::new() -> ChineseState {
  { first: 0, second: 0, third: 0, }
}

///|
fn ChineseState::has_pending(self : ChineseState) -> Bool {
  self.first != 0 || self.second != 0 || self.third != 0
}

///|
fn ChineseState::reset(self : ChineseState) -> Unit {
  self.first = 0
  self.second = 0
  self.third = 0
}

///|
/// 替换字符 U+FFFD（字面量后直接方法调用在本工具链会解析失败，故包一层）。
fn replacement_char() -> Char {
  let cp : Int = 0xFFFD
  cp.unsafe_to_char()
}

///|
/// 整数 → 字节（值域 0..255，调用方保证）。
fn int_to_byte(x : Int) -> Byte {
  x.to_byte()
}

///|
/// 码点 → 字符（表值构造上恒为合法标量，同 single_byte.mbt 的约定）。
fn int_to_char(cp : Int) -> Char {
  cp.unsafe_to_char()
}

///|
/// index gb18030 ranges code point（§gb18030-decoder 配套算法）：
/// - pointer 落在 (39419, 189000) 开区间或大于 1237575 → 无（此处 -1 表示错误）
/// - pointer == 7457 → U+E7C7（规范特例，0x81 0x35 0xF4 0x37）
/// - 否则取 ranges 中 ≤ pointer 的最后一项：cp_offset + pointer − offset
fn ranges_code_point(pointer : Int) -> Int {
  if (pointer > 39419 && pointer < 189000) || pointer > 1237575 {
    return -1
  }
  if pointer == 7457 {
    return 0xE7C7
  }
  let mut lo = 0
  let mut hi = gb18030_ranges.length() / 2 - 1
  let mut found = -1
  while lo <= hi {
    let mid = (lo + hi) / 2
    if gb18030_ranges[mid * 2] <= pointer {
      found = mid
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  if found < 0 {
    return -1
  }
  gb18030_ranges[found * 2 + 1] + (pointer - gb18030_ranges[found * 2])
}

///|
/// index gb18030 ranges pointer（§gb18030-encoder 配套算法）：
/// - U+E7C7 → 7457
/// - 否则取 ranges 中 ≤ code point 的最后一项：pointer_offset + cp − offset
/// 返回 -1 表示无法编码（码点低于 ranges 首项，仅会出现在 ASCII 之前短路不到的场景）。
fn ranges_pointer(code_point : Int) -> Int {
  if code_point == 0xE7C7 {
    return 7457
  }
  let mut lo = 0
  let mut hi = gb18030_ranges.length() / 2 - 1
  let mut found = -1
  while lo <= hi {
    let mid = (lo + hi) / 2
    if gb18030_ranges[mid * 2 + 1] <= code_point {
      found = mid
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  if found < 0 {
    return -1
  }
  gb18030_ranges[found * 2] + (code_point - gb18030_ranges[found * 2 + 1])
}

///|
/// 编码侧 index pointer：在「码点 → 首次 pointer」反向表上二分。
/// 原 index 含重复且非升序，反向表由生成器按首次出现去重升序生成。
fn gb18030_encode_pointer(code_point : Int) -> Int {
  let mut lo = 0
  let mut hi = gb18030_encode_index.length() / 2 - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let cp = gb18030_encode_index[mid * 2]
    if cp == code_point {
      return gb18030_encode_index[mid * 2 + 1]
    }
    if cp < code_point {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  -1
}

// 18 条 PUA 侧表：encoding.bs §gb18030-encoder 的表格逐条转录
// （2005/2022 修订的兼容映射，形如 (码点, 字节1, 字节2)，按码点升序）。

///|
let gbk_pua_side_table : Array[Int] = [
  0xE78D, 0xA6, 0xD9, 0xE78E, 0xA6, 0xDA, 0xE78F, 0xA6, 0xDB, 0xE790, 0xA6, 0xDC,
  0xE791, 0xA6, 0xDD, 0xE792, 0xA6, 0xDE, 0xE793, 0xA6, 0xDF, 0xE794, 0xA6, 0xEC,
  0xE795, 0xA6, 0xED, 0xE796, 0xA6, 0xF3, 0xE81E, 0xFE, 0x59, 0xE826, 0xFE, 0x61,
  0xE82B, 0xFE, 0x66, 0xE82C, 0xFE, 0x67, 0xE832, 0xFE, 0x6D, 0xE843, 0xFE, 0x7E,
  0xE854, 0xFE, 0x90, 0xE864, 0xFE, 0xA0,
]

///|
/// 侧表查询：命中返回 [字节1, 字节2]，未命中返回空数组。
fn pua_side_lookup(code_point : Int) -> Array[Int] {
  let mut lo = 0
  let mut hi = gbk_pua_side_table.length() / 3 - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let cp = gbk_pua_side_table[mid * 3]
    if cp == code_point {
      let out : Array[Int] = [
        gbk_pua_side_table[mid * 3 + 1],
        gbk_pua_side_table[mid * 3 + 2],
      ]
      return out
    }
    if cp < code_point {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  let empty : Array[Int] = []
  empty
}

///|
/// 把重放字节插回队首（规范 Restore 操作）：新的重放队列 =
/// 恢复字节 ++ 剩余未消费的旧重放，消费游标归零。
fn replay_prepend(
  replay : Array[Byte],
  consumed : Int,
  restored : Array[Int],
) -> Array[Byte] {
  let fresh : Array[Byte] = []
  for v in restored {
    fresh.push(v.to_byte())
  }
  for k in consumed..<replay.length() {
    fresh.push(replay[k])
  }
  fresh
}

///|
/// gb18030 解码一个字节块（规范 handler 逐步翻译）。
/// 块尾未完成的 first/second/third 留在 state 里跨块续传；
/// 截断收尾由 chinese_finish 处理（end-of-queue → 一次 error → U+FFFD）。
fn chinese_consume(state : ChineseState, input : Bytes) -> String {
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
    if state.third != 0 {
      if b < 0x30 || b > 0x39 {
        // Restore «second, third, byte»；三个状态归零；返回 error
        let restored : Array[Int] = [state.second, state.third, b]
        replay = replay_prepend(replay, r, restored)
        r = 0
        state.reset()
        out.push(replacement_char())
      } else {
        let pointer = (state.first - 0x81) * 12600 +
          (state.second - 0x30) * 1260 +
          (state.third - 0x81) * 10 +
          (b - 0x30)
        state.reset()
        let cp = ranges_code_point(pointer)
        if cp < 0 {
          out.push(replacement_char())
        } else {
          out.push(int_to_char(cp))
        }
      }
    } else if state.second != 0 {
      if b >= 0x81 && b <= 0xFE {
        state.third = b
      } else {
        // Restore «second, byte»；first 由 error 消化为 U+FFFD
        let restored : Array[Int] = [state.second, b]
        replay = replay_prepend(replay, r, restored)
        r = 0
        state.reset()
        out.push(replacement_char())
      }
    } else if state.first != 0 {
      if b >= 0x30 && b <= 0x39 {
        state.second = b
      } else {
        let lead = state.first
        state.first = 0
        let mut pointer = -1
        if (b >= 0x40 && b <= 0x7E) || (b >= 0x80 && b <= 0xFE) {
          let offset = if b < 0x7F { 0x40 } else { 0x41 }
          pointer = (lead - 0x81) * 190 + (b - offset)
        }
        let mut cp = -1
        if pointer >= 0 && pointer < gb18030_index.length() {
          cp = gb18030_index[pointer]
        }
        if cp >= 0 {
          out.push(int_to_char(cp))
        } else {
          if b < 0x80 {
            // ASCII 字节恢复重放（规范：restore byte 再 error）
            let restored : Array[Int] = [b]
            replay = replay_prepend(replay, r, restored)
            r = 0
          }
          out.push(replacement_char())
        }
      }
    } else if b < 0x80 {
      out.push(b.unsafe_to_char())
    } else if b == 0x80 {
      out.push(int_to_char(0x20AC)) // 规范：0x80 → U+20AC（CPython 的 gbk/gb18030 在此分歧）
    } else if b >= 0x81 && b <= 0xFE {
      state.first = b
    } else {
      out.push(replacement_char()) // 0xFF 等非法起始
    }
  }
  String::from_iter(out.iter())
}

///|
/// 流结束：规范 end-of-queue——有挂起状态则归零并返回一次 error（单个 U+FFFD），
/// 无论挂起了 1 个还是 3 个字节。
fn chinese_finish(state : ChineseState) -> String {
  if state.has_pending() {
    state.reset()
    let out : Array[Char] = [replacement_char()]
    return String::from_iter(out.iter())
  }
  ""
}

///|
/// gb18030 / GBK 编码（§gb18030-encoder 逐步翻译；is_gbk = GBK 标志）。
/// 不可映射时返回规范 fatal 模式的 Unmappable（码点, 字符位置）。
fn chinese_encode(text : String, is_gbk : Bool) -> Result[Bytes, EncodingError] {
  let out : Array[Byte] = []
  let mut index = 0
  for c in text {
    let cp = c.to_int()
    if cp < 0x80 {
      out.push(cp.to_byte())
    } else if cp == 0xE5E5 {
      // 规范明确：U+E5E5 不可编码（0xA3 0xA0 映射 U+3000，无法往返）
      return Err(EncodingError::Unmappable(cp, index))
    } else if is_gbk && cp == 0x20AC {
      out.push(int_to_byte(0x80))
    } else {
      let side = pua_side_lookup(cp)
      if side.length() == 2 {
        out.push(side[0].to_byte())
        out.push(side[1].to_byte())
      } else {
        let pointer = gb18030_encode_pointer(cp)
        if pointer >= 0 {
          let lead = pointer / 190 + 0x81
          let trail = pointer % 190
          let offset = if trail < 0x3F { 0x40 } else { 0x41 }
          out.push(lead.to_byte())
          out.push((trail + offset).to_byte())
        } else {
          if is_gbk {
            return Err(EncodingError::Unmappable(cp, index))
          }
          let mut p = ranges_pointer(cp)
          if p < 0 {
            return Err(EncodingError::Unmappable(cp, index))
          }
          let byte1 = p / 12600
          p = p % 12600
          let byte2 = p / 1260
          p = p % 1260
          let byte3 = p / 10
          let byte4 = p % 10
          out.push((byte1 + 0x81).to_byte())
          out.push((byte2 + 0x30).to_byte())
          out.push((byte3 + 0x81).to_byte())
          out.push((byte4 + 0x30).to_byte())
        }
      }
    }
    index += 1
  }
  Ok(Bytes::from_array(out.exact_view()))
}
