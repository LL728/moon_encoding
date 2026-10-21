// iso2022_wbtest.mbt
//
// ISO-2022-JP 的规范级测试。
// 期望值来源：[spec] = encoding.bs（@ 2c3853e）条文；[数据] = vendored
// indexes.json 现算；[CPython] = 独立实现现算。CPython 与规范的已知分歧
// （ESC ( I、0x0E/0x0F、U+FF61、U+000E/U+000F/U+001B、Roman 状态下直接输出
// ASCII 字节、截断序列）一律以规范为准，并在对应用例里注明。

///|
/// ESC ( I 后接 0x21..0x5F 的字节串（katakana 状态全区间）。
fn katakana_range_bytes() -> Bytes {
  let bs : Array[Int32] = [0x1B, 0x28, 0x49]
  for b in 0x21..<0x60 {
    bs.push(b)
  }
  bytes_of_ints(bs)
}

///|
/// ESC ( I 后接 0x21..0x5F 的期望输出：U+FF61..U+FF9F（算术，不查任何索引）。
fn katakana_range_str() -> String {
  let cps : Array[Int32] = []
  for b in 0x21..<0x60 {
    cps.push(0xFF61 - 0x21 + b)
  }
  cps_str(cps)
}

///|
test "ISO-2022-JP: ASCII / Roman / katakana states and the five escape sequences" {
  // [spec] ASCII：0x00..0x7F 直通（0x7F 也在区间内）
  @test.assert_eq(
    decode(bytes_of_ints([0x41, 0x7F]), "ISO-2022-JP"),
    Ok(cps_str([0x41, 0x7F])),
  )
  // [spec] ESC ( J → Roman：0x5C → U+00A5、0x7E → U+203E，其余原样
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x28, 0x4A, 0x5C, 0x7E, 0x41]), "ISO-2022-JP"),
    Ok(cps_str([0x00A5, 0x203E, 0x41])),
  )
  // [spec] ESC ( B 回 ASCII：同样的 0x5C/0x7E 变回 ASCII
  @test.assert_eq(
    decode(
      bytes_of_ints([0x1B, 0x28, 0x4A, 0x5C, 0x1B, 0x28, 0x42, 0x5C, 0x7E]),
      "ISO-2022-JP",
    ),
    Ok(cps_str([0x00A5, 0x5C, 0x7E])),
  )
  // [spec] ESC ( I → katakana：全部 0x21..0x5F 映射到 U+FF61..U+FF9F
  @test.assert_eq(
    decode(katakana_range_bytes(), "ISO-2022-JP"),
    Ok(katakana_range_str()),
  )
  // [spec] ESC $ @ 与 ESC $ B 完全等价（同一状态、同一 index jis0208）
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x24, 0x40, 0x21, 0x21]), "ISO-2022-JP"),
    Ok(cp_str(0x3000)),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x24, 0x42, 0x21, 0x21]), "ISO-2022-JP"),
    Ok(cp_str(0x3000)),
  )
  // [数据/spec] 日本語：指针 (0x46-0x21)*94 + 0x7C-0x21 = 3569 等
  @test.assert_eq(
    decode(
      bytes_of_ints([
        0x1B, 0x24, 0x42, 0x46, 0x7C, 0x4B, 0x5C, 0x38, 0x6C, 0x1B, 0x28, 0x42,
      ]),
      "ISO-2022-JP",
    ),
    Ok(cps_str([0x65E5, 0x672C, 0x8A9E])),
  )
}

///|
test "ISO-2022-JP: 0x0E / 0x0F / high bytes are errors (CPython divergence)" {
  let rep = replacement_str()
  // [spec] ASCII 分支显式排除 0x0E、0x0F；0x80..0xFF 落 Otherwise
  @test.assert_eq(decode(bytes_of_ints([0x0E]), "ISO-2022-JP"), Ok(rep))
  @test.assert_eq(decode(bytes_of_ints([0x0F]), "ISO-2022-JP"), Ok(rep))
  @test.assert_eq(decode(bytes_of_ints([0x80]), "ISO-2022-JP"), Ok(rep))
  @test.assert_eq(decode(bytes_of_ints([0xFF]), "ISO-2022-JP"), Ok(rep))
  // [spec] Roman 同样排除；katakana 区间外（0x20/0x60/0x7F）也报错
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x28, 0x4A, 0x0E]), "ISO-2022-JP"),
    Ok(rep),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x28, 0x49, 0x20]), "ISO-2022-JP"),
    Ok(rep),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x28, 0x49, 0x60]), "ISO-2022-JP"),
    Ok(rep),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x28, 0x49, 0x7F]), "ISO-2022-JP"),
    Ok(rep),
  )
  // [CPython 分歧] cp932/iso2022_jp 把 0x0E/0x0F 原样解出，规范要求 U+FFFD
}

///|
test "ISO-2022-JP: invalid trailing byte is swallowed, not restored" {
  let rep = replacement_str()
  // [spec] Trailing byte 的 Otherwise 只改状态、**不** restore 第二字节
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x24, 0x42, 0x21, 0x0A]), "ISO-2022-JP"),
    Ok(rep),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x24, 0x42, 0x21, 0x0D]), "ISO-2022-JP"),
    Ok(rep),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x24, 0x42, 0x21, 0x7F]), "ISO-2022-JP"),
    Ok(rep),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x24, 0x42, 0x21, 0x20]), "ISO-2022-JP"),
    Ok(rep),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x24, 0x42, 0x21, 0x80]), "ISO-2022-JP"),
    Ok(rep),
  )
  // [数据] pointer 108（22 2F）在 jis0208 里为空 → error，尾字节同样被吞
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x24, 0x42, 0x22, 0x2F]), "ISO-2022-JP"),
    Ok(rep),
  )
  // 对照 [spec]：EUC-KR 的同类路径**会**把 ASCII 尾字节放回队列（81 5B → U+FFFD + '['）
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0x5B]), "EUC-KR"),
    Ok(cps_str([0xFFFD, 0x5B])),
  )
}

///|
test "ISO-2022-JP: 0x1B semantics differ between Leading byte and Trailing byte" {
  let rep = replacement_str()
  // [spec] Leading byte 的 0x1B：不报错、静默丢弃 lead 尝试 → 只可能由后续转义产生 1 个 U+FFFD
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x24, 0x42, 0x1B, 0x28, 0x42]), "ISO-2022-JP"),
    Ok(rep),
  )
  // [spec] Trailing byte 的 0x1B：报错且不回退，0x1B 仍作为新转义前缀 → 同样 1 个 U+FFFD
  //（若把 0x1B 也当 continue，这里会变成 0 个）
  @test.assert_eq(
    decode(
      bytes_of_ints([0x1B, 0x24, 0x42, 0x21, 0x1B, 0x28, 0x42]),
      "ISO-2022-JP",
    ),
    Ok(rep),
  )
  // [spec] 被丢弃的 lead 不再产生码点，转义后继续解出 ASCII
  @test.assert_eq(
    decode(
      bytes_of_ints([0x1B, 0x24, 0x42, 0x21, 0x1B, 0x28, 0x42, 0x41]),
      "ISO-2022-JP",
    ),
    Ok(cps_str([0xFFFD, 0x41])),
  )
}

///|
test "ISO-2022-JP: output boolean and decoder output state" {
  let rep = replacement_str()
  // [spec] 连续两个转义序列之间没有普通字节：第二次识别成功也返回 error（output 布尔量）
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x28, 0x42, 0x1B, 0x28, 0x4A]), "ISO-2022-JP"),
    Ok(rep),
  )
  // 该 error 后 state 已是 Roman：随后的 0x5C 解成 U+00A5
  @test.assert_eq(
    decode(
      bytes_of_ints([0x1B, 0x28, 0x42, 0x1B, 0x28, 0x4A, 0x5C]),
      "ISO-2022-JP",
    ),
    Ok(cps_str([0xFFFD, 0x00A5])),
  )
  // [spec] 非法转义**不会**打回 ASCII，而是退回 output state（这里是 katakana）：
  // ESC ( I 后 ESC X → U+FFFD，被放回的 'X'(0x58) 在 katakana 下是 U+FF98
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x28, 0x49, 0x1B, 0x58]), "ISO-2022-JP"),
    Ok(cps_str([0xFFFD, 0xFF98])),
  )
  // [spec] Escape 的失败路径把 leading 与第三字节**两个**都放回队列
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x28, 0x58]), "ISO-2022-JP"),
    Ok(cps_str([0xFFFD, 0x28, 0x58])),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x24, 0x58]), "ISO-2022-JP"),
    Ok(cps_str([0xFFFD, 0x24, 0x58])),
  )
  // [spec] 放回的字节在 output state（katakana）下重新解析
  @test.assert_eq(
    decode(bytes_of_ints([0x1B, 0x28, 0x49, 0x1B, 0x24, 0x58]), "ISO-2022-JP"),
    Ok(cps_str([0xFFFD, 0xFF64, 0xFF98])),
  )
}

///|
test "ISO-2022-JP: end-of-queue behaviour differs per state" {
  let rep = replacement_str()
  // [spec] ASCII / Roman / katakana → finished，无输出
  for tail in [[], [0x1B, 0x28, 0x4A], [0x1B, 0x28, 0x49]] {
    let d = match Decoder::new("ISO-2022-JP") {
      Ok(d) => d
      Err(e) => abort(@debug.to_string(e))
    }
    @test.assert_eq(d.consume(bytes_of_ints(tail)), "")
    @test.assert_eq(d.finish(), "")
  }
  // [spec] Leading byte + EOF → finished，**不报错**（lead 被丢弃）
  let lead = match Decoder::new("ISO-2022-JP") {
    Ok(d) => d
    Err(e) => abort(@debug.to_string(e))
  }
  @test.assert_eq(lead.consume(bytes_of_ints([0x1B, 0x24, 0x42])), "")
  @test.assert_eq(lead.finish(), "")
  // [spec] Trailing byte + EOF → error；state 回 leading byte，第二次 finish 不再报错
  let trail = match Decoder::new("ISO-2022-JP") {
    Ok(d) => d
    Err(e) => abort(@debug.to_string(e))
  }
  @test.assert_eq(trail.consume(bytes_of_ints([0x1B, 0x24, 0x42, 0x21])), "")
  @test.assert_eq(trail.finish(), rep)
  @test.assert_eq(trail.finish(), "")
  // [spec] Escape start + EOF → error，且 0x1B 已被消费、不恢复
  let esc_start = match Decoder::new("ISO-2022-JP") {
    Ok(d) => d
    Err(e) => abort(@debug.to_string(e))
  }
  @test.assert_eq(esc_start.consume(bytes_of_ints([0x1B])), "")
  @test.assert_eq(esc_start.finish(), rep)
  // [spec] Escape + EOF → 把 0x24/0x28 放回队列后 error：U+FFFD + U+0024 / U+0028
  for pair in [[0x1B, 0x24], [0x1B, 0x28]] {
    let d = match Decoder::new("ISO-2022-JP") {
      Ok(d) => d
      Err(e) => abort(@debug.to_string(e))
    }
    @test.assert_eq(d.consume(bytes_of_ints(pair)), "")
    @test.assert_eq(d.finish(), cps_str([0xFFFD, pair[1]]))
  }
  // [spec] output state 为 katakana 时，放回的 0x24 按 katakana 解成 U+FF64
  let katakana_pending = match Decoder::new("ISO-2022-JP") {
    Ok(d) => d
    Err(e) => abort(@debug.to_string(e))
  }
  @test.assert_eq(
    katakana_pending.consume(bytes_of_ints([0x1B, 0x28, 0x49, 0x1B, 0x24])),
    "",
  )
  @test.assert_eq(katakana_pending.finish(), cps_str([0xFFFD, 0xFF64]))
}

///|
test "ISO-2022-JP encoder: spec anchors" {
  // (输入文本, 期望字节)：每条都标出规范出处；断言放在 test 内（test 允许 error）
  let cases : Array[(String, Array[Int32])] = [
    // [spec] 日本語 → ESC $ B 46 7C 4B 5C 38 6C ESC ( B（end-of-queue 补 ESC ( B）
    (
      cps_str([0x65E5, 0x672C, 0x8A9E]),
      [0x1B, 0x24, 0x42, 0x46, 0x7C, 0x4B, 0x5C, 0x38, 0x6C, 0x1B, 0x28, 0x42],
    ),
    // [CPython 一致] ASCII 直通；U+00A5 / U+203E 走 Roman（ESC ( J）
    ("A", [0x41]),
    (cp_str(0x00A5), [0x1B, 0x28, 0x4A, 0x5C, 0x1B, 0x28, 0x42]),
    (cp_str(0x203E), [0x1B, 0x28, 0x4A, 0x7E, 0x1B, 0x28, 0x42]),
    // [spec] U+2212 → U+FF0D（指针 60 = 21 5D）
    (cp_str(0x2212), [0x1B, 0x24, 0x42, 0x21, 0x5D, 0x1B, 0x28, 0x42]),
    // [spec] 半角片假名先转全角再查 jis0208（U+FF61 → U+3002 → 21 23；U+FF9F → U+309C → 21 2C）
    (cp_str(0xFF61), [0x1B, 0x24, 0x42, 0x21, 0x23, 0x1B, 0x28, 0x42]),
    (cp_str(0xFF9F), [0x1B, 0x24, 0x42, 0x21, 0x2C, 0x1B, 0x28, 0x42]),
    // [spec] Roman 状态下 ASCII 码点（除 0x5C/0x7E）直接输出，不回 ASCII——
    // 与 CPython 分歧（CPython 会插入 ESC ( B）
    (
      cps_str([0x41, 0x00A5, 0x42]),
      [0x41, 0x1B, 0x28, 0x4A, 0x5C, 0x42, 0x1B, 0x28, 0x42],
    ),
    (cps_str([0x00A5, 0x41]), [0x1B, 0x28, 0x4A, 0x5C, 0x41, 0x1B, 0x28, 0x42]),
    // [spec] ASCII 码点在 jis0208 状态下必须先回 ASCII
    (
      cps_str([0x4E00, 0x41]),
      [0x1B, 0x24, 0x42, 0x30, 0x6C, 0x1B, 0x28, 0x42, 0x41],
    ),
    (
      cps_str([0x41, 0x4E00]),
      [0x41, 0x1B, 0x24, 0x42, 0x30, 0x6C, 0x1B, 0x28, 0x42],
    ),
    // [spec] U+000A / U+000D 无特殊规则：ASCII 状态直出
    ("\n\r", [0x0A, 0x0D]),
    // [spec] 空文本 → 空字节
    ("", []),
  ]
  for case in cases {
    let (text, expect) = case
    match encode(text, "ISO-2022-JP") {
      Ok(b) => {
        @test.assert_eq(b.length(), expect.length())
        for i in 0..<expect.length() {
          @test.assert_eq(b[i].to_int(), expect[i])
        }
      }
      Err(e) =>
        abort("unexpected error for " + text + ": " + @debug.to_string(e))
    }
  }
}

///|
test "ISO-2022-JP encoder: U+000E/U+000F/U+001B error with U+FFFD (CPython divergence)" {
  // [spec] error 携带 U+FFFD，不是原码点（防攻击），且码点已被消费
  @test.assert_eq(
    encode(cp_str(0x000E), "ISO-2022-JP"),
    Err(EncodingError::Unmappable(0xFFFD, 0)),
  )
  @test.assert_eq(
    encode(cp_str(0x000F), "ISO-2022-JP"),
    Err(EncodingError::Unmappable(0xFFFD, 0)),
  )
  @test.assert_eq(
    encode(cps_str([0x61, 0x001B]), "ISO-2022-JP"),
    Err(EncodingError::Unmappable(0xFFFD, 1)),
  )
  // [spec] 在 jis0208 状态下先回退码点、回 ASCII，error 在下一次调用才出，
  // 但对外仍是"该字符位置上不可编码"
  @test.assert_eq(
    encode(cps_str([0x4E00, 0x001B]), "ISO-2022-JP"),
    Err(EncodingError::Unmappable(0xFFFD, 1)),
  )
  // [CPython 分歧] CPython 直接输出 0e / 0f / 1b 原始字节
}

///|
test "ISO-2022-JP encoder: unmappable characters report position and normalized code point" {
  // [spec] 不可编码且在 ASCII 状态 → 立即 error with codePoint
  @test.assert_eq(
    encode(cp_str(0x2603), "ISO-2022-JP"),
    Err(EncodingError::Unmappable(0x2603, 0)),
  )
  // [spec] 不可编码且在 jis0208 状态 → 先输出 ESC ( B 回 ASCII，error 在下一次调用；
  // 位置仍是该字符在输入中的下标
  @test.assert_eq(
    encode(cps_str([0x4E00, 0x2603]), "ISO-2022-JP"),
    Err(EncodingError::Unmappable(0x2603, 1)),
  )
  @test.assert_eq(
    encode(cps_str([0x61, 0x62, 0x2603]), "ISO-2022-JP"),
    Err(EncodingError::Unmappable(0x2603, 2)),
  )
  // [spec] 空文本之外的失败不返回部分输出（fatal 模式），这句只钉住接口形状
  match encode("", "ISO-2022-JP") {
    Ok(b) => @test.assert_eq(b.length(), 0)
    Err(e) => abort(@debug.to_string(e))
  }
}

///|
test "invariants: generated ISO-2022-JP katakana table" {
  // 63 项，值全部是合法非代理码点，且都能在 jis0208 反向表里查到
  @test.assert_eq(iso2022_jp_katakana_index.length(), 63)
  for i in 0..<63 {
    let cp = iso2022_jp_katakana_index[i]
    @test.assert_eq(cp > 0, true)
    @test.assert_eq(cp <= 0x10FFFF, true)
    @test.assert_eq(cp < 0xD800 || cp > 0xDFFF, true)
    @test.assert_eq(encode_index_lookup(euc_jp_encode_index, cp) >= 0, true)
    // 半角片假名的编码结果 = 其全角对应字符的编码结果
    @test.assert_eq(
      encode(cp_str(0xFF61 + i), "ISO-2022-JP"),
      encode(cp_str(cp), "ISO-2022-JP"),
    )
  }
  // [spec] 解码器 katakana 状态不查这张表：算术结果与表内容无关地成立
  @test.assert_eq(
    decode(katakana_range_bytes(), "ISO-2022-JP"),
    Ok(katakana_range_str()),
  )
}

///|
test "ISO-2022-JP: spec's own concatenation example (¥ twice decodes to ¥ U+FFFD ¥)" {
  // [spec §iso-2022-jp-encoder note] 编码 U+00A5 得 1B 28 4A 5C 1B 28 42；
  // 把两次结果拼接再解码，得到 U+00A5 U+FFFD U+00A5——正是 output 布尔量
  // 在"连续两个转义序列"上产生的那个 error。
  let once = match encode(cp_str(0x00A5), "ISO-2022-JP") {
    Ok(b) => b
    Err(e) => abort(@debug.to_string(e))
  }
  @test.assert_eq(once.length(), 7)
  let doubled : Array[Int32] = []
  for _ in 0..<2 {
    for i in 0..<once.length() {
      doubled.push(once[i].to_int())
    }
  }
  @test.assert_eq(
    decode(bytes_of_ints(doubled), "ISO-2022-JP"),
    Ok(cps_str([0x00A5, 0xFFFD, 0x00A5])),
  )
}

///|
test "ISO-2022-JP: state crosses chunk boundaries (escape and double-byte splits)" {
  // (a) 转义序列被切开：chunk1 以 0x1B 结尾，chunk2 以 0x24 0x42 开头
  let d = match Decoder::new("ISO-2022-JP") {
    Ok(d) => d
    Err(e) => abort(@debug.to_string(e))
  }
  @test.assert_eq(d.consume(bytes_of_ints([0x1B])), "")
  @test.assert_eq(d.consume(bytes_of_ints([0x24, 0x42])), "")
  @test.assert_eq(
    d.consume(bytes_of_ints([0x21, 0x21])),
    cp_str(0x3000), // 转义在第一次调用里生效，双字节在第三次调用里解出
  )
  @test.assert_eq(d.finish(), "")
  // (b) 双字节 jis0208 字符被切开：lead 在 chunk1，trail 在 chunk2
  let d2 = match Decoder::new("ISO-2022-JP") {
    Ok(d) => d
    Err(e) => abort(@debug.to_string(e))
  }
  @test.assert_eq(d2.consume(bytes_of_ints([0x1B, 0x24, 0x42, 0x46])), "")
  @test.assert_eq(d2.consume(bytes_of_ints([0x7C])), cp_str(0x65E5))
  // (c) ESC 切在 ESC-start 边界：0x1B 单独一块，第三字节单独一块
  let d3 = match Decoder::new("ISO-2022-JP") {
    Ok(d) => d
    Err(e) => abort(@debug.to_string(e))
  }
  @test.assert_eq(d3.consume(bytes_of_ints([0x1B, 0x28])), "")
  @test.assert_eq(d3.consume(bytes_of_ints([0x4A])), "")
  @test.assert_eq(d3.consume(bytes_of_ints([0x5C])), cp_str(0x00A5))
  @test.assert_eq(d3.finish(), "")
  // (d) 逐块累加 == 一次性 decode()（同一段字节，含错误路径与截断序列）
  let corpus : Array[Int32] = [
    0x41, 0x1B, 0x28, 0x4A, 0x5C, 0x1B, 0x28, 0x49, 0x21, 0x1B, 0x58, 0x1B, 0x24,
    0x42, 0x46, 0x7C, 0x1B, 0x28, 0x42, 0x0E, 0x1B, 0x24, 0x42, 0x21, 0x0A, 0x1B,
    0x24, 0x42, 0x21, 0x1B, 0x28, 0x49, 0x1B, 0x24, 0x42, 0x21,
  ]
  let input = bytes_of_ints(corpus)
  let one_shot = match decode(input, "ISO-2022-JP") {
    Ok(s) => s
    Err(e) => abort(@debug.to_string(e))
  }
  // 每块 1 字节
  let byte_decoder = match Decoder::new("ISO-2022-JP") {
    Ok(d) => d
    Err(e) => abort(@debug.to_string(e))
  }
  let mut acc = ""
  for i in 0..<input.length() {
    acc = acc + byte_decoder.consume(slice_bytes(input, i, i + 1))
  }
  @test.assert_eq(acc + byte_decoder.finish(), one_shot)
  // 每块 2 字节（换一种切分再验一次）
  let pair_decoder = match Decoder::new("ISO-2022-JP") {
    Ok(d) => d
    Err(e) => abort(@debug.to_string(e))
  }
  let mut acc2 = ""
  let mut p = 0
  while p < input.length() {
    let end = if p + 2 > input.length() { input.length() } else { p + 2 }
    acc2 = acc2 + pair_decoder.consume(slice_bytes(input, p, end))
    p = end
  }
  @test.assert_eq(acc2 + pair_decoder.finish(), one_shot)
}

///|
test "ISO-2022-JP: chunked equals whole at every split position" {
  let corpus : Array[Int32] = [
    0x41, 0x7F, 0x1B, 0x28, 0x42, 0x5C, 0x1B, 0x28, 0x4A, 0x5C, 0x7E, 0x1B, 0x28,
    0x49, 0x21, 0x5F, 0x1B, 0x24, 0x40, 0x21, 0x21, 0x1B, 0x24, 0x42, 0x46, 0x7C,
    0x1B, 0x28, 0x42, 0x0E, 0x1B, 0x58, 0x1B, 0x24, 0x42, 0x21, 0x0A, 0x1B, 0x24,
    0x42, 0x21, 0x1B, 0x28, 0x42, 0x1B, 0x28, 0x49, 0x1B, 0x24, 0x42, 0x21,
  ]
  let input = bytes_of_ints(corpus)
  let n = input.length()
  let whole = match decode(input, "ISO-2022-JP") {
    Ok(s) => s
    Err(e) => abort(@debug.to_string(e))
  }
  // 每个切分点（含 0 与 n）都必须与整段一致
  for split in 0..<(n + 1) {
    let d = match Decoder::new("ISO-2022-JP") {
      Ok(d) => d
      Err(e) => abort(@debug.to_string(e))
    }
    let got = d.consume(slice_bytes(input, 0, split)) +
      d.consume(slice_bytes(input, split, n)) +
      d.finish()
    @test.assert_eq(got, whole)
  }
  // 随机多切分
  let mut seed = 20220202
  for _round in 0..<1200 {
    let d = match Decoder::new("ISO-2022-JP") {
      Ok(d) => d
      Err(e) => abort(@debug.to_string(e))
    }
    let mut out = ""
    let mut pos = 0
    while pos < n {
      seed = (seed * 75 + 74) % 65537
      let step = seed % 7 + 1
      let end = if pos + step > n { n } else { pos + step }
      out = out + d.consume(slice_bytes(input, pos, end))
      pos = end
    }
    out = out + d.finish()
    @test.assert_eq(out, whole)
  }
}
