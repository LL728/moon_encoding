// euc.mbt
//
// EUC-JP 与 EUC-KR 的编解码，逐条实现 encoding.bs（whatwg/encoding @ 2c3853e）的
// §euc-jp-decoder、§euc-jp-encoder、§euc-kr-decoder、§euc-kr-encoder。
//
// 与前面编码的差异（都按规范，不可凭记忆合并）：
// - EUC-JP：SS2（0x8E + 半角片假名单字节）、SS3（0x8F + jis0212 三字节序列，
//   jis0212 标志在通用分支里**无论是否命中都复位**）；双字节走共享 jis0208
//   （同一指针空间，94 列布局，见 gen_big5_sjis.mbt 注释）；
//   编码端与 Shift_JIS 同款特例（¥→0x5C、U+203E→0x7E、U+2212→U+FF0D），
//   半角片假名编码为两字节 0x8E + (cp-0xFF61+0xA1)；
//   新鲜字节 0x80/0xA0/0xFF 报错——**与 Shift_JIS 的 0x80→U+0080 不同**。
// - EUC-KR：单 lead、尾字节区间 0x41..0xFE 用**单一偏移 0x41**（没有 GBK 的
//   0x7F/0x80 分界），编码端无任何特例；新鲜字节 0x80/0xA0/0xFF 报错——
//   **与 GBK 的 0x80→U+20AC 不同**。

///|
/// EUC-JP 状态：lead + SS3 的 jis0212 标志（§euc-jp-decoder）。
priv struct EucJpState {
  mut lead : Int
  mut jis0212 : Bool
}

///|
fn EucJpState::new() -> EucJpState {
  { lead: 0, jis0212: false, }
}

///|
fn EucJpState::has_pending(self : EucJpState) -> Bool {
  self.lead != 0
}

///|
fn EucJpState::reset(self : EucJpState) -> Unit {
  self.lead = 0
  self.jis0212 = false
}

///|
/// EUC-JP 解码一个字节块（§euc-jp-decoder 逐步翻译）。
fn euc_jp_consume(state : EucJpState, input : Bytes) -> String {
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
    if state.lead == 0x8E && b >= 0xA1 && b <= 0xDF {
      // SS2：0x8E + 半角片假名单字节 → U+FF61..U+FF9F
      state.lead = 0
      out.push(int_to_char(0xFF61 - 0xA1 + b))
    } else if state.lead == 0x8F && b >= 0xA1 && b <= 0xFE {
      // SS3：置 jis0212 标志，第二个字节转为 lead，等第三个字节
      state.jis0212 = true
      state.lead = b
    } else if state.lead != 0 {
      let lead = state.lead
      state.lead = 0
      let mut cp = -1
      if lead >= 0xA1 && lead <= 0xFE && b >= 0xA1 && b <= 0xFE {
        let pointer = (lead - 0xA1) * 94 + (b - 0xA1)
        let table = if state.jis0212 { jis0212_index } else { jis0208_index }
        if pointer < table.length() {
          cp = table[pointer]
        }
      }
      // 规范：无论是否命中，jis0212 标志都要复位
      state.jis0212 = false
      if cp >= 0 {
        out.push(int_to_char(cp))
      } else {
        if b < 0x80 {
          let restored : Array[Int] = [b]
          replay = replay_prepend(replay, r, restored)
          r = 0
        }
        out.push(replacement_char())
      }
    } else if b < 0x80 {
      out.push(int_to_char(b))
    } else if b == 0x8E || b == 0x8F || (b >= 0xA1 && b <= 0xFE) {
      state.lead = b
    } else {
      out.push(replacement_char()) // 0x80 / 0xA0 / 0xFF 等
    }
  }
  String::from_iter(out.iter())
}

///|
/// EUC-JP 流结束：有挂起 lead → 单个 U+FFFD（§euc-jp-decoder end-of-queue）。
fn euc_jp_finish(state : EucJpState) -> String {
  if state.has_pending() {
    state.reset()
    let out : Array[Char] = [replacement_char()]
    return String::from_iter(out.iter())
  }
  ""
}

///|
/// EUC-JP 编码（§euc-jp-encoder：ASCII、¥、overbar、半角片假名两字节 SS2、
/// U+2212→U+FF0D，再走共享 jis0208 的首次出现反向表）。
fn euc_jp_encode(text : String) -> Result[Bytes, EncodingError] {
  let out : Array[Byte] = []
  let mut index = 0
  for c in text {
    let mut cp = c.to_int()
    if cp < 0x80 {
      out.push(int_to_byte(cp))
    } else if cp == 0x00A5 {
      out.push(int_to_byte(0x5C))
    } else if cp == 0x203E {
      out.push(int_to_byte(0x7E))
    } else if cp >= 0xFF61 && cp <= 0xFF9F {
      out.push(int_to_byte(0x8E))
      out.push(int_to_byte(cp - 0xFF61 + 0xA1))
    } else {
      if cp == 0x2212 {
        cp = 0xFF0D // 规范：归一后再查索引，错误也报归一后的码点
      }
      let pointer = encode_index_lookup(euc_jp_encode_index, cp)
      if pointer < 0 {
        return Err(EncodingError::Unmappable(cp, index))
      }
      out.push(int_to_byte(pointer / 94 + 0xA1))
      out.push(int_to_byte(pointer % 94 + 0xA1))
    }
    index += 1
  }
  Ok(Bytes::from_array(out.exact_view()))
}

///|
/// EUC-KR 解码一个字节块（§euc-kr-decoder：尾字节 0x41..0xFE 单偏移 0x41）。
fn euc_kr_consume(state : LeadState, input : Bytes) -> String {
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
      let mut cp = -1
      if b >= 0x41 && b <= 0xFE {
        let pointer = (lead - 0x81) * 190 + (b - 0x41)
        if pointer < euc_kr_index.length() {
          cp = euc_kr_index[pointer]
        }
      }
      if cp >= 0 {
        out.push(int_to_char(cp))
      } else {
        if b < 0x80 {
          let restored : Array[Int] = [b]
          replay = replay_prepend(replay, r, restored)
          r = 0
        }
        out.push(replacement_char())
      }
    } else if b < 0x80 {
      out.push(int_to_char(b))
    } else if b >= 0x81 && b <= 0xFE {
      state.lead = b
    } else {
      out.push(replacement_char()) // 0x80 / 0xA0 / 0xFF 等（与 GBK 的 0x80→U+20AC 不同）
    }
  }
  String::from_iter(out.iter())
}

///|
/// EUC-KR 流结束：有挂起 lead → 单个 U+FFFD。
fn euc_kr_finish(state : LeadState) -> String {
  if state.lead != 0 {
    state.lead = 0
    let out : Array[Char] = [replacement_char()]
    return String::from_iter(out.iter())
  }
  ""
}

///|
/// EUC-KR 编码（§euc-kr-encoder：ASCII 直通，其余查首次出现反向表，
/// lead = ptr/190 + 0x81、trail = ptr%190 + 0x41）。
fn euc_kr_encode(text : String) -> Result[Bytes, EncodingError] {
  let out : Array[Byte] = []
  let mut index = 0
  for c in text {
    let cp = c.to_int()
    if cp < 0x80 {
      out.push(int_to_byte(cp))
    } else {
      let pointer = encode_index_lookup(euc_kr_encode_index, cp)
      if pointer < 0 {
        return Err(EncodingError::Unmappable(cp, index))
      }
      out.push(int_to_byte(pointer / 190 + 0x81))
      out.push(int_to_byte(pointer % 190 + 0x41))
    }
    index += 1
  }
  Ok(Bytes::from_array(out.exact_view()))
}
