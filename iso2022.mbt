// iso2022.mbt
//
// ISO-2022-JP 的编解码，逐条实现 encoding.bs（whatwg/encoding @ 2c3853e）的
// §iso-2022-jp-decoder 与 §iso-2022-jp-encoder。
//
// 不可简化之处（易错点逐条写明）：
// - 解码器有 **7 个状态**（ASCII / Roman / katakana / Leading byte / Trailing byte /
//   Escape start / Escape）与 **4 个变量**（decoder state、decoder output state、
//   leading、output 布尔量）。`output` 布尔量必须实现：ASCII/Roman/katakana/Leading
//   byte 处理字节的分支把它置 false，只有 Escape 识别成功时置 true，且若进入 Escape
//   时它已是 true，识别成功**仍返回 error**（连续转义序列）。
// - output state 只在 Escape 识别成功时随 state 一起写；两处转义失败路径都回退到它
//   （非法转义不会把解码器打回 ASCII），Trailing byte 的失败路径回退到 Leading byte，
//   ASCII/Roman/katakana/Leading byte 的失败路径**只**置 output=false、不改 state。
// - katakana 状态**不查表**：码点 = 0xFF61 − 0x21 + byte。
//   `index ISO-2022-JP katakana`（63 项）只有编码器用（半角→全角预转换）。
// - 识别的转义序列恰好 5 条：ESC ( B → ASCII、ESC ( J → Roman、ESC ( I → katakana、
//   ESC $ @ 与 ESC $ B → Leading byte（两者共用同一条规则与同一张 jis0208）；编码器
//   只输出 ESC $ B，从不输出 ESC $ @。
// - Trailing byte 的非法第二字节被**吞掉不回退**（含 0x0A/0x0D/0x7F）——
//   与 EUC-JP 会回退 ASCII 字节相反。
// - EOF 分支按状态不同：Escape start → error 且不恢复；Escape → 把 0x24/0x28
//   放回队列后 error；Leading byte → finished 不报错；Trailing byte → error；
//   ASCII/Roman/katakana → finished。流式调用（consume）看不到 EOF，这些分支
//   只在 finish 里触发。
// - 编码器只有 1 个状态（ASCII|Roman|jis0208）：U+000E/U+000F/U+001B 在 ASCII/Roman 下
//   **error with U+FFFD**（不是原码点，规范为防攻击如此）；U+000A/U+000D 无特殊规则；
//   U+2212 → U+FF0D；半角片假名先查 katakana 索引转全角；每个转义输出都把码点
//   restore 回队列，故同一个码点分两次 handler 调用处理。
//
// CPython 分歧（以规范为准，用例见 iso2022_wbtest.mbt）：CPython 解码器拒绝
// ESC ( I（规范识别为 katakana）且把 0x0E/0x0F 当普通字符（规范报错）；CPython 编码器
// 拒绝 U+FF61（规范转全角）并把 U+000E/U+000F/U+001B 原样输出（规范报 U+FFFD）。

///|
/// ISO-2022-JP 解码器的 7 个状态（§iso-2022-jp-decoder 的 handler 分支标签）。
priv enum Iso2022JpDecoderState {
  Ascii
  Roman
  Katakana
  LeadingByte
  TrailingByte
  EscapeStart
  Escape
}

///|
/// 解码器状态：规范 §iso-2022-jp-decoder 的 4 个关联变量。
/// 全部存在实例上，故转义序列与双字节字符可以跨 consume 调用被切开。
priv struct Iso2022JpState {
  mut state : Iso2022JpDecoderState
  mut output_state : Iso2022JpDecoderState
  mut leading : Int32
  mut output : Bool
}

///|
fn Iso2022JpState::new() -> Iso2022JpState {
  {
    state: Iso2022JpDecoderState::Ascii,
    output_state: Iso2022JpDecoderState::Ascii,
    leading: 0,
    output: false,
  }
}

///|
/// handler 一次调用的结果（规范返回值：continue / 码点 / error / finished）。
/// `Error` 在 replacement 模式下输出 U+FFFD 后继续；`ErrorRestore` 额外把字节
/// 放回队列头部（规范的 "restore to ioQueue" 是**前插**）。
priv enum Iso2022JpStep {
  Continue
  Emit(Char)
  Error
  ErrorRestore(Array[Int32])
  Finished
}

///|
/// handler 处理一个 item：`b` 是字节，`-1` 表示 end-of-queue（只有 finish 会传）。
fn iso2022_jp_step(st : Iso2022JpState, b : Int32) -> Iso2022JpStep {
  match st.state {
    Iso2022JpDecoderState::Ascii =>
      if b == 0x1B {
        st.state = Iso2022JpDecoderState::EscapeStart
        Iso2022JpStep::Continue
      } else if b >= 0 && b <= 0x7F && b != 0x0E && b != 0x0F {
        st.output = false
        Iso2022JpStep::Emit(int_to_char(b))
      } else if b < 0 {
        Iso2022JpStep::Finished
      } else {
        // 0x0E / 0x0F / 0x80..0xFF
        st.output = false
        Iso2022JpStep::Error
      }
    Iso2022JpDecoderState::Roman =>
      if b == 0x1B {
        st.state = Iso2022JpDecoderState::EscapeStart
        Iso2022JpStep::Continue
      } else if b == 0x5C {
        st.output = false
        Iso2022JpStep::Emit(int_to_char(0x00A5))
      } else if b == 0x7E {
        st.output = false
        Iso2022JpStep::Emit(int_to_char(0x203E))
      } else if b >= 0 && b <= 0x7F && b != 0x0E && b != 0x0F {
        st.output = false
        Iso2022JpStep::Emit(int_to_char(b))
      } else if b < 0 {
        Iso2022JpStep::Finished
      } else {
        st.output = false
        Iso2022JpStep::Error
      }
    Iso2022JpDecoderState::Katakana =>
      if b == 0x1B {
        st.state = Iso2022JpDecoderState::EscapeStart
        Iso2022JpStep::Continue
      } else if b >= 0x21 && b <= 0x5F {
        // 规范：不查 index，直接算 0xFF61 − 0x21 + byte
        st.output = false
        Iso2022JpStep::Emit(int_to_char(0xFF61 - 0x21 + b))
      } else if b < 0 {
        Iso2022JpStep::Finished
      } else {
        st.output = false
        Iso2022JpStep::Error
      }
    Iso2022JpDecoderState::LeadingByte =>
      if b == 0x1B {
        // 不报错，静默丢弃已读到的 lead 尝试（与 Trailing byte 的 0x1B 相反）
        st.state = Iso2022JpDecoderState::EscapeStart
        Iso2022JpStep::Continue
      } else if b >= 0x21 && b <= 0x7E {
        st.output = false
        st.leading = b
        st.state = Iso2022JpDecoderState::TrailingByte
        Iso2022JpStep::Continue
      } else if b < 0 {
        // EOF 不报错（前一个 lead 被丢弃）
        Iso2022JpStep::Finished
      } else {
        st.output = false
        Iso2022JpStep::Error
      }
    Iso2022JpDecoderState::TrailingByte =>
      if b == 0x1B {
        // 0x1B 被消费且不回退，作为新转义序列前缀继续解析；不改 output
        st.state = Iso2022JpDecoderState::EscapeStart
        Iso2022JpStep::Error
      } else if b >= 0x21 && b <= 0x7E {
        st.state = Iso2022JpDecoderState::LeadingByte
        let pointer = (st.leading - 0x21) * 94 + b - 0x21
        let cp = if pointer < jis0208_index.length() {
          jis0208_index[pointer]
        } else {
          -1
        }
        if cp >= 0 {
          Iso2022JpStep::Emit(int_to_char(cp))
        } else {
          Iso2022JpStep::Error
        }
      } else {
        // EOF 与非法第二字节（0x00..0x20、0x7F、0x80..0xFF）：第二字节被吞掉不回退
        st.state = Iso2022JpDecoderState::LeadingByte
        Iso2022JpStep::Error
      }
    Iso2022JpDecoderState::EscapeStart =>
      if b == 0x24 || b == 0x28 {
        st.leading = b
        st.state = Iso2022JpDecoderState::Escape
        Iso2022JpStep::Continue
      } else {
        // EOF 不恢复；非 EOF 把该字节放回队列
        st.output = false
        st.state = st.output_state
        if b < 0 {
          Iso2022JpStep::Error
        } else {
          let restored : Array[Int32] = [b]
          Iso2022JpStep::ErrorRestore(restored)
        }
      }
    Iso2022JpDecoderState::Escape => {
      let leading = st.leading
      st.leading = 0
      let mut target : Iso2022JpDecoderState? = None
      if leading == 0x28 && b == 0x42 {
        target = Some(Iso2022JpDecoderState::Ascii)
      } else if leading == 0x28 && b == 0x4A {
        target = Some(Iso2022JpDecoderState::Roman)
      } else if leading == 0x28 && b == 0x49 {
        target = Some(Iso2022JpDecoderState::Katakana)
      } else if leading == 0x24 && (b == 0x40 || b == 0x42) {
        target = Some(Iso2022JpDecoderState::LeadingByte)
      }
      match target {
        Some(s) => {
          st.state = s
          st.output_state = s
          let was_output = st.output
          st.output = true
          if was_output {
            Iso2022JpStep::Error
          } else {
            Iso2022JpStep::Continue
          }
        }
        None => {
          // EOF 只把 leading 放回；否则 leading 与该字节两个都放回
          st.output = false
          st.state = st.output_state
          let restored : Array[Int32] = if b < 0 {
            [leading]
          } else {
            [leading, b]
          }
          Iso2022JpStep::ErrorRestore(restored)
        }
      }
    }
  }
}

///|
/// ISO-2022-JP 解码一个字节块（§iso-2022-jp-decoder 逐步翻译）。
/// 块尾未完成的转义序列 / 双字节由 state 跨块续传，交给下一次 consume 或 finish。
fn iso2022_jp_consume(st : Iso2022JpState, input : Bytes) -> String {
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
    match iso2022_jp_step(st, b) {
      Iso2022JpStep::Continue => ()
      Iso2022JpStep::Emit(c) => out.push(c)
      Iso2022JpStep::Error => out.push(replacement_char())
      Iso2022JpStep::ErrorRestore(restored) => {
        out.push(replacement_char())
        replay = replay_prepend(replay, r, restored)
        r = 0
      }
      // consume 从不传 end-of-queue，因此走不到 finished
      Iso2022JpStep::Finished => ()
    }
  }
  String::from_iter(out.iter())
}

///|
/// ISO-2022-JP 流结束：按当前状态触发 end-of-queue 分支，并把 error 路径
/// 放回队列的字节（0x24/0x28 或未识别的第三字节）重新处理。
/// 结果恒为 0 个或少数几个 U+FFFD/U+0024/U+0028 等字符，循环必然收敛。
fn iso2022_jp_finish(st : Iso2022JpState) -> String {
  let out : Array[Char] = []
  let mut replay : Array[Byte] = []
  let mut r = 0
  let mut running = true
  while running {
    let mut b = -1
    if r < replay.length() {
      b = replay[r].to_int()
      r += 1
    }
    match iso2022_jp_step(st, b) {
      Iso2022JpStep::Continue => ()
      Iso2022JpStep::Emit(c) => out.push(c)
      Iso2022JpStep::Error => out.push(replacement_char())
      Iso2022JpStep::ErrorRestore(restored) => {
        out.push(replacement_char())
        replay = replay_prepend(replay, r, restored)
        r = 0
      }
      Iso2022JpStep::Finished => running = false
    }
  }
  String::from_iter(out.iter())
}

///|
/// ISO-2022-JP 编码器的状态：规范只有 1 个变量（ASCII / Roman / jis0208）。
priv enum Iso2022JpEncoderState {
  AsciiMode
  RomanMode
  Jis0208Mode
} derive(Eq)

///|
/// ISO-2022-JP 编码（§iso-2022-jp-encoder 逐步翻译）。
/// 内层 while 就是"再一次 handler 调用"：需要输出转义序列的分支都会 restore
/// 当前码点，故同一码点可能分两三次调用处理（与规范逐字对应）。
fn iso2022_jp_encode(text : String) -> Result[Bytes, EncodingError] {
  let out : Array[Byte] = []
  let mut state = Iso2022JpEncoderState::AsciiMode
  let mut index = 0
  for c in text {
    let mut cp = c.to_int()
    let mut again = true
    while again {
      again = false
      if (
          state == Iso2022JpEncoderState::AsciiMode ||
          state == Iso2022JpEncoderState::RomanMode
        ) &&
        (cp == 0x0E || cp == 0x0F || cp == 0x1B) {
        // 规范：error with U+FFFD（不是 codePoint），且不 restore 该码点
        return Err(EncodingError::Unmappable(0xFFFD, index))
      } else if state == Iso2022JpEncoderState::AsciiMode && cp <= 0x7F {
        out.push(int_to_byte(cp))
      } else if state == Iso2022JpEncoderState::RomanMode &&
        cp <= 0x7F &&
        cp != 0x5C &&
        cp != 0x7E {
        out.push(int_to_byte(cp))
      } else if state == Iso2022JpEncoderState::RomanMode && cp == 0x00A5 {
        out.push(int_to_byte(0x5C))
      } else if state == Iso2022JpEncoderState::RomanMode && cp == 0x203E {
        out.push(int_to_byte(0x7E))
      } else if cp <= 0x7F && state != Iso2022JpEncoderState::AsciiMode {
        // ASCII 码点但不在 ASCII 状态：回退码点，回到 ASCII（ESC ( B）
        state = Iso2022JpEncoderState::AsciiMode
        again = true
        out.push(int_to_byte(0x1B))
        out.push(int_to_byte(0x28))
        out.push(int_to_byte(0x42))
      } else if (cp == 0x00A5 || cp == 0x203E) &&
        state != Iso2022JpEncoderState::RomanMode {
        state = Iso2022JpEncoderState::RomanMode
        again = true
        out.push(int_to_byte(0x1B))
        out.push(int_to_byte(0x28))
        out.push(int_to_byte(0x4A))
      } else {
        if cp == 0x2212 {
          cp = 0xFF0D // 规范：先归一，错误也报归一后的码点
        }
        if cp >= 0xFF61 && cp <= 0xFF9F {
          // 半角片假名 → 全角（index ISO-2022-JP katakana，编码器专用；生成时
          // 已断言 63 项全非空）
          cp = iso2022_jp_katakana_index[cp - 0xFF61]
        }
        let pointer = encode_index_lookup(euc_jp_encode_index, cp)
        if pointer < 0 {
          if state == Iso2022JpEncoderState::Jis0208Mode {
            // 不可编码且正在 jis0208：先回退码点并回到 ASCII，error 下一次调用才出
            state = Iso2022JpEncoderState::AsciiMode
            again = true
            out.push(int_to_byte(0x1B))
            out.push(int_to_byte(0x28))
            out.push(int_to_byte(0x42))
          } else {
            return Err(EncodingError::Unmappable(cp, index))
          }
        } else if state != Iso2022JpEncoderState::Jis0208Mode {
          state = Iso2022JpEncoderState::Jis0208Mode
          again = true
          out.push(int_to_byte(0x1B))
          out.push(int_to_byte(0x24))
          out.push(int_to_byte(0x42))
        } else {
          out.push(int_to_byte(pointer / 94 + 0x21))
          out.push(int_to_byte(pointer % 94 + 0x21))
        }
      }
    }
    index += 1
  }
  // end-of-queue：非 ASCII 状态补一个 ESC ( B（规范步骤 1）
  if state != Iso2022JpEncoderState::AsciiMode {
    out.push(int_to_byte(0x1B))
    out.push(int_to_byte(0x28))
    out.push(int_to_byte(0x42))
  }
  Ok(Bytes::from_array(out.exact_view()))
}
