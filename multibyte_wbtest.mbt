// multibyte_wbtest.mbt
//
// Big5 / Shift_JIS 的规范级测试。
// 期望值来源：[spec] = encoding.bs（@ 2c3853e）条文或 vendored 表数据；
// [CPython] = 独立实现现算。CPython 与规范的已知分歧（EUDC PUA、双码点
// 命名序列、0x80、817c 的 FF0D/2212）以规范为准，差分向量自动排除。

///|
test "Big5: fresh-byte semantics per spec" {
  // [spec] ASCII 直通（含 0x7F）
  @test.assert_eq(
    decode(bytes_of_ints([0x41, 0x7F]), "Big5"),
    Ok(cps_str([0x41, 0x7F])),
  )
  // [spec] 0x80 / 0xA0 / 0xFF 均报错 → replacement（CPython 同样拒绝——两边一致）
  let rep = replacement_str()
  @test.assert_eq(decode(bytes_of_ints([0x80]), "Big5"), Ok(rep))
  @test.assert_eq(decode(bytes_of_ints([0xA0]), "Big5"), Ok(rep))
  @test.assert_eq(decode(bytes_of_ints([0xFF]), "Big5"), Ok(rep))
}

///|
test "Big5: two-byte anchors" {
  // [CPython] a140 → U+3000（指针 5024 = 过滤区起点）
  @test.assert_eq(
    decode(bytes_of_ints([0xA1, 0x40]), "Big5"),
    Ok(cp_str(0x3000)),
  )
  // [CPython] 你好 = a741 a66e
  @test.assert_eq(
    decode(bytes_of_ints([0xA7, 0x41, 0xA6, 0x6E]), "Big5"),
    Ok(cps_str([0x4F60, 0x597D])),
  )
  // [CPython] a451 → 十（与 U+5341 的“取最后出现”规则配套的往返锚点）
  @test.assert_eq(
    decode(bytes_of_ints([0xA4, 0x51]), "Big5"),
    Ok(cp_str(0x5341)),
  )
}

///|
test "Big5: named two-code-point sequences (spec table, CPython rejects)" {
  // [spec] 指针 1133 = 88 62 → U+00CA U+0304；1135 → U+00CA U+030C
  @test.assert_eq(
    decode(bytes_of_ints([0x88, 0x62]), "Big5"),
    Ok(cps_str([0x00CA, 0x0304])),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0x88, 0x64]), "Big5"),
    Ok(cps_str([0x00CA, 0x030C])),
  )
  // [spec] 1164 = 88 A3 → U+00EA U+0304；1166 → U+00EA U+030C
  @test.assert_eq(
    decode(bytes_of_ints([0x88, 0xA3]), "Big5"),
    Ok(cps_str([0x00EA, 0x0304])),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0x88, 0xA5]), "Big5"),
    Ok(cps_str([0x00EA, 0x030C])),
  )
}

///|
test "Big5: invalid trail restores ASCII bytes (spec)" {
  // [spec] 81 7F：0x7F 不在合法尾字节范围但属 ASCII → U+FFFD 后重放 0x7F
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0x7F]), "Big5"),
    Ok(cps_str([0xFFFD, 0x7F])),
  )
  // [spec] 81 41：trail 合法但 index[?] 为空且 0x41 是 ASCII → U+FFFD + 'A'
  //（8141 指针 = 157+1 = 158；该位点在 vendored 表中为空位）
  match big5_index[158] {
    -1 =>
      @test.assert_eq(
        decode(bytes_of_ints([0x81, 0x41]), "Big5"),
        Ok(cps_str([0xFFFD, 0x41])),
      )
    _ => ignore(true) // 表数据若有变化，此构造不再触发错误路径
  }
  // [spec] 非 ASCII 尾字节落空（81 A0 不是合法 trail 的一部分…… A0 被排除）
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0xA0]), "Big5"),
    Ok(replacement_str()),
  )
}

///|
test "Big5: end-of-queue flushes pending lead as a single U+FFFD" {
  let rep = replacement_str()
  match Decoder::new("Big5") {
    Ok(d) => {
      @test.assert_eq(d.consume(bytes_of_ints([0xA1])), "")
      @test.assert_eq(d.finish(), rep)
    }
    Err(e) => abort(@debug.to_string(e))
  }
}

///|
test "Big5 encoder: spec anchors and six-cps last-pointer rule" {
  // [CPython] 你好 → a741 a66e；U+3000 → a140
  match encode(cps_str([0x4F60, 0x597D]), "Big5") {
    Ok(b) => {
      @test.assert_eq(b.length(), 4)
      @test.assert_eq(b[0].to_int(), 0xA7)
      @test.assert_eq(b[1].to_int(), 0x41)
      @test.assert_eq(b[2].to_int(), 0xA6)
      @test.assert_eq(b[3].to_int(), 0x6E)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  match encode(cp_str(0x3000), "Big5") {
    Ok(b) => {
      @test.assert_eq(b[0].to_int(), 0xA1)
      @test.assert_eq(b[1].to_int(), 0x40)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [spec/index] U+20AC 在 index Big5 的位点 5529 → a3 e1（CPython 拒编——
  // 分歧，差分向量自动排除；以规范为准）
  match encode(cp_str(0x20AC), "Big5") {
    Ok(b) => {
      @test.assert_eq(b[0].to_int(), 0xA3)
      @test.assert_eq(b[1].to_int(), 0xE1)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [spec] 不在表内的码点 → Unmappable（阿拉伯文，两边一致拒编）
  @test.assert_eq(
    encode(cp_str(0x0641), "Big5"),
    Err(EncodingError::Unmappable(0x0641, 0)),
  )
  // [spec §index Big5 pointer] 六个“取最后出现”码点：以 U+5341 为例，
  // 从原始表独立算出首/末指针，证明规则生效且运行时用的是“末”。
  let mut first_ptr = -1
  let mut last_ptr = -1
  for p in 5024..<big5_index.length() {
    if big5_index[p] == 0x5341 {
      if first_ptr < 0 {
        first_ptr = p
      }
      last_ptr = p
    }
  }
  @test.assert_eq(first_ptr >= 0, true)
  @test.assert_eq(last_ptr > first_ptr, true) // 该码点确实重复，规则才有意义
  let lead = last_ptr / 157 + 0x81
  let trail = last_ptr % 157
  let offset = if trail < 0x3F { 0x40 } else { 0x62 }
  match encode(cp_str(0x5341), "Big5") {
    Ok(b) => {
      @test.assert_eq(b.length(), 2)
      @test.assert_eq(b[0].to_int(), lead)
      @test.assert_eq(b[1].to_int(), trail + offset)
      // 往返：末指针字节解码回同一码点
      @test.assert_eq(decode(b, "Big5"), Ok(cp_str(0x5341)))
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // 过滤规则：编码产物的头字节不得落在 0x81..0xA0（pointer < 5024 被排除）
  match encode(cps_str([0x4F60, 0x3000, 0x5341, 0x2550]), "Big5") {
    Ok(b) => {
      @test.assert_eq(b.length() % 2, 0)
      let mut i = 0
      while i < b.length() {
        @test.assert_eq(b[i].to_int() >= 0xA1, true)
        i += 2
      }
    }
    Err(e) => abort(@debug.to_string(e))
  }
}

///|
test "Shift_JIS: fresh-byte semantics per spec" {
  // [spec] ASCII 与 0x80 → 同值（CPython 拒绝 0x80——分歧，以规范为准）
  @test.assert_eq(
    decode(bytes_of_ints([0x41, 0x7F]), "Shift_JIS"),
    Ok(cps_str([0x41, 0x7F])),
  )
  @test.assert_eq(decode(bytes_of_ints([0x80]), "Shift_JIS"), Ok(cp_str(0x80)))
  // [spec] 半角片假名直算：A1 → U+FF61、DF → U+FF9F（CPython 一致）
  @test.assert_eq(
    decode(bytes_of_ints([0xA1]), "Shift_JIS"),
    Ok(cp_str(0xFF61)),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0xDF]), "Shift_JIS"),
    Ok(cp_str(0xFF9F)),
  )
  // [spec] A0 / FD / FE / FF 报错（CPython 同样拒绝）
  let rep = replacement_str()
  @test.assert_eq(decode(bytes_of_ints([0xA0]), "Shift_JIS"), Ok(rep))
  @test.assert_eq(decode(bytes_of_ints([0xFD]), "Shift_JIS"), Ok(rep))
  @test.assert_eq(decode(bytes_of_ints([0xFF]), "Shift_JIS"), Ok(rep))
}

///|
test "Shift_JIS: two-byte anchors and EUDC PUA range" {
  // [CPython+表] 8140 → U+3000；82A0 → U+3042
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0x40]), "Shift_JIS"),
    Ok(cp_str(0x3000)),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0x82, 0xA0]), "Shift_JIS"),
    Ok(cp_str(0x3042)),
  )
  // [CPython] 日本語 = 93fa 967b 8cea
  @test.assert_eq(
    decode(bytes_of_ints([0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA]), "Shift_JIS"),
    Ok(cps_str([0x65E5, 0x672C, 0x8A9E])),
  )
  // [spec] EUDC：指针 8836..10715 是 PUA（CPython 在此区间报错——分歧，以规范为准）
  // F0 40 → 指针 8836 → U+E000；F9 FC → 指针 10715 → 0xE000-8836+10715 = U+E757
  @test.assert_eq(
    decode(bytes_of_ints([0xF0, 0x40]), "Shift_JIS"),
    Ok(cp_str(0xE000)),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0xF9, 0xFC]), "Shift_JIS"),
    Ok(cp_str(0xE757)),
  )
}

///|
test "Shift_JIS: encoder quirks (spec §shift_jis-encoder)" {
  // [CPython+spec] 日本語 → 93fa 967b 8cea；U+FF61 → a1
  match encode(cps_str([0x65E5, 0x672C, 0x8A9E]), "Shift_JIS") {
    Ok(b) => {
      @test.assert_eq(b.length(), 6)
      @test.assert_eq(b[0].to_int(), 0x93)
      @test.assert_eq(b[1].to_int(), 0xFA)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  match encode(cp_str(0xFF61), "Shift_JIS") {
    Ok(b) => {
      @test.assert_eq(b.length(), 1)
      @test.assert_eq(b[0].to_int(), 0xA1)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [spec] U+00A5 → 0x5C、U+203E → 0x7E（CPython 一致）；
  // 并且 0x5C 解码回 ASCII 反斜杠——规范接受的不对称，显式钉住
  match encode(cp_str(0x00A5), "Shift_JIS") {
    Ok(b) => @test.assert_eq(b[0].to_int(), 0x5C)
    Err(e) => abort(@debug.to_string(e))
  }
  @test.assert_eq(decode(bytes_of_ints([0x5C]), "Shift_JIS"), Ok(cp_str(0x5C)))
  match encode(cp_str(0x203E), "Shift_JIS") {
    Ok(b) => @test.assert_eq(b[0].to_int(), 0x7E)
    Err(e) => abort(@debug.to_string(e))
  }
  // [spec] U+2212 先归一 U+FF0D 再查表；表内 FF0D 唯一位点 60 → 81 7c。
  // CPython 直接把 2212 编到 817c（字节相同），但解码端 CPython 给 2212、
  // 规范表给 FF0D——分歧在解码侧，编码字节两边一致。
  match encode(cp_str(0x2212), "Shift_JIS") {
    Ok(b) => {
      @test.assert_eq(b.length(), 2)
      @test.assert_eq(b[0].to_int(), 0x81)
      @test.assert_eq(b[1].to_int(), 0x7C)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0x7C]), "Shift_JIS"),
    Ok(cp_str(0xFF0D)),
  )
  // [CPython] U+20AC 不可编 → Unmappable（两边一致）
  @test.assert_eq(
    encode(cp_str(0x20AC), "Shift_JIS"),
    Err(EncodingError::Unmappable(0x20AC, 0)),
  )
}

///|
test "Shift_JIS: end-of-queue flushes pending lead as a single U+FFFD" {
  let rep = replacement_str()
  match Decoder::new("Shift_JIS") {
    Ok(d) => {
      @test.assert_eq(d.consume(bytes_of_ints([0x82])), "")
      @test.assert_eq(d.finish(), rep)
    }
    Err(e) => abort(@debug.to_string(e))
  }
}

///|
test "Big5 and Shift_JIS: chunked equals whole at every split position" {
  // 语料覆盖：合法对、繁体、半角、EUDC、命名序列、非法尾字节、ASCII/0x80
  let cases : Array[(String, Array[Int])] = [
    (
      "Big5",
      [
        0xA7, 0x41, 0xA6, 0x6E, 0xA1, 0x40, 0x88, 0x62, 0x81, 0x7F, 0x81, 0xA0, 0x41,
        0x20, 0x80, 0xA4, 0x51, 0xFE, 0xFE,
      ],
    ),
    (
      "Shift_JIS",
      [
        0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA, 0x82, 0xA0, 0xA1, 0xDF, 0x80, 0xF0, 0x40,
        0xF9, 0xFC, 0x82, 0x20, 0x82, 0xFF, 0x41, 0x7F, 0xA0, 0xFD,
      ],
    ),
  ]
  for case in cases {
    let (label, corpus) = case
    let input = bytes_of_ints(corpus)
    let n = input.length()
    let whole = match Decoder::new(label) {
      Ok(d) => d.consume(input) + d.finish()
      Err(e) => abort(@debug.to_string(e))
    }
    for split in 0..<(n + 1) {
      let d = match Decoder::new(label) {
        Ok(d) => d
        Err(e) => abort(@debug.to_string(e))
      }
      let got = d.consume(slice_bytes(input, 0, split)) +
        d.consume(slice_bytes(input, split, n)) +
        d.finish()
      @test.assert_eq(got, whole)
    }
    let mut seed = 777
    for _round in 0..<600 {
      let d = match Decoder::new(label) {
        Ok(d) => d
        Err(e) => abort(@debug.to_string(e))
      }
      let mut out = ""
      let mut pos = 0
      while pos < n {
        seed = (seed * 75 + 74) % 65537
        let step = seed % 5 + 1
        let end = if pos + step > n { n } else { pos + step }
        out = out + d.consume(slice_bytes(input, pos, end))
        pos = end
      }
      out = out + d.finish()
      @test.assert_eq(out, whole)
    }
  }
}

///|
test "invariants: generated Big5 / Shift_JIS tables" {
  // index Big5：19782 项，空位 -1，其余合法非代理码点
  @test.assert_eq(big5_index.length(), 19782)
  for i in 0..<19782 {
    let cp = big5_index[i]
    @test.assert_eq(cp >= -1 && cp <= 0x10FFFF, true)
    @test.assert_eq(cp == -1 || cp < 0xD800 || cp > 0xDFFF, true)
  }
  // Big5 编码反向表：按码点升序、指针全部 >= 5024（过滤规则）
  @test.assert_eq(big5_encode_index.length() % 2, 0)
  let mut prev = -1
  for i in 0..<(big5_encode_index.length() / 2) {
    let cp = big5_encode_index[i * 2]
    let ptr = big5_encode_index[i * 2 + 1]
    @test.assert_eq(cp > prev, true)
    @test.assert_eq(ptr >= 5024, true)
    prev = cp
  }
  // index jis0208：11280 项（共享指针空间）
  @test.assert_eq(jis0208_index.length(), 11280)
  for i in 0..<11280 {
    let cp = jis0208_index[i]
    @test.assert_eq(cp >= -1 && cp <= 0x10FFFF, true)
    @test.assert_eq(cp == -1 || cp < 0xD800 || cp > 0xDFFF, true)
  }
  // Shift_JIS 编码反向表：升序、**不含** 8272..8835（NEC 重复行被排除）
  @test.assert_eq(shift_jis_encode_index.length() % 2, 0)
  let mut prev_p = -1
  for i in 0..<(shift_jis_encode_index.length() / 2) {
    let cp = shift_jis_encode_index[i * 2]
    let ptr = shift_jis_encode_index[i * 2 + 1]
    @test.assert_eq(cp > prev_p, true)
    @test.assert_eq(ptr < 8272 || ptr > 8835, true)
    prev_p = cp
  }
  // 命名序列表：恰好 4 行，指针与规范表格一致且升序
  @test.assert_eq(big5_named_sequences.length(), 12)
  @test.assert_eq(big5_named_sequences[0], 1133)
  @test.assert_eq(big5_named_sequences[3], 1135)
  @test.assert_eq(big5_named_sequences[6], 1164)
  @test.assert_eq(big5_named_sequences[9], 1166)
}
