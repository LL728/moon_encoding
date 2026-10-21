// misc.mbt
//
// Legacy miscellaneous 组里两个算法型编码（规范没有索引表，全部由算法定义），
// 逐条实现 encoding.bs（whatwg/encoding @ 2c3853e）的 §replacement-decoder 与
// §x-user-defined-decoder / §x-user-defined-encoder。
//
// - replacement：解码器带一个 **replacement error returned 布尔量**（初值 false）：
//   「EOF → finished；若该布尔量为 false 则置 true 并返回 error；否则返回 finished」。
//   于是**至多报一次 error**，此后立刻 finished——而 finished 会让规范的
//   "process a queue" 循环整体终止，剩余字节永不被处理。故：
//   **非空输入恒输出恰好 1 个 U+FFFD（与输入长度无关），空输入输出空串，EOF 从不报错。**
//   规范 §get an encoder 断言 encoding 不是 replacement，故它**没有编码器**：
//   encode 如实返回 UnsupportedEncoding（与 UTF-16BE/LE 同款）。
// - x-user-defined：字节 0x00..0x7F 恒等，0x80..0xFF → U+F780 + 字节 − 0x80；
//   反向同理。两侧都恰好是"单字节引擎 + 无空位表"，故这里只合成表，编解码
//   完全复用 single_byte.mbt 的 single_byte_decode / single_byte_encode。

///|
/// replacement 解码器状态：error_returned 与 finished 两个布尔量（§14.1.1）。
priv struct ReplacementState {
  mut error_returned : Bool
  mut finished : Bool
}

///|
fn ReplacementState::new() -> ReplacementState {
  { error_returned: false, finished: false, }
}

///|
/// replacement 解码一个字节块（§replacement-decoder 逐步翻译）。
/// 第一个字节 → 一个 U+FFFD 且 error_returned := true；第二个字节 → finished，
/// 整个流程结束（该字节被消费、其后字节一律不再读）。
fn replacement_decode(state : ReplacementState, input : Bytes) -> String {
  let out : Array[Char] = []
  for _ in 0..<input.length() {
    if state.finished {
      break
    }
    if state.error_returned {
      state.finished = true
      break
    }
    state.error_returned = true
    out.push(replacement_char())
  }
  String::from_iter(out.iter())
}

///|
/// replacement 流结束：EOF 恒为 finished，从不报错，故无滞留输出。
fn replacement_finish(state : ReplacementState) -> String {
  state.finished = true
  ""
}

///|
/// x-user-defined 解码表：下标 = 字节 − 0x80，值 = U+F780 + 下标。
/// 128 项全部非空（规范算法无错误位），故解码永不产生 U+FFFD。
fn x_user_defined_decode_table() -> Array[Int32] {
  let table : Array[Int32] = []
  for i in 0..<128 {
    table.push(0xF780 + i)
  }
  table
}

///|
/// x-user-defined 编码反向表：(码点, 字节) 对按码点升序，与生成的单字节表同构，
/// 直接喂给 single_byte_encode 的二分查找。
fn x_user_defined_encode_table() -> Array[Int32] {
  let table : Array[Int32] = []
  for i in 0..<128 {
    table.push(0xF780 + i)
    table.push(0x80 + i)
  }
  table
}
