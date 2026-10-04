// chinese_wbtest.mbt
//
// GBK / gb18030 的规范级测试。
// 每个期望值标注来源：[spec] = encoding.bs（@ 2c3853e）条文；
// [CPython] = 独立实现现算。两处实现有分歧的字节（0x80 解码端、
// a3a0、U+E5E5、gbk 的 € 编码端）以规范为准并在此单测覆盖，
// 差分向量生成器会自动把它们排除。

///|
fn cp_str(cp : Int) -> String {
  String::from_iter([cp.unsafe_to_char()].iter())
}

///|
fn cps_str(cps : Array[Int]) -> String {
  let chars : Array[Char] = []
  for cp in cps {
    chars.push(cp.unsafe_to_char())
  }
  String::from_iter(chars.iter())
}

///|
fn replacement_str() -> String {
  String::from_iter([replacement_char()].iter())
}

///|
test "GBK/gb18030: fresh-byte semantics per spec" {
  // [spec §gb18030-decoder] 0x80 → U+20AC（CPython 的 gbk/gb18030 都拒绝此字节——分歧）
  @test.assert_eq(decode(bytes_of_ints([0x80]), "GBK"), Ok(cp_str(0x20AC)))
  @test.assert_eq(decode(bytes_of_ints([0x80]), "gb18030"), Ok(cp_str(0x20AC)))
  // [spec] 0xFF 非法起始 → replacement
  @test.assert_eq(decode(bytes_of_ints([0xFF]), "GBK"), Ok(replacement_str()))
  // [spec] ASCII 直通（含 0x00 与 0x7F）
  @test.assert_eq(
    decode(bytes_of_ints([0x00, 0x41, 0x7F]), "GBK"),
    Ok(cps_str([0x00, 0x41, 0x7F])),
  )
}

///|
test "GBK/gb18030: two-byte anchors" {
  // [CPython] 0xA1A1 → U+3000（GB2312 全角空格）
  @test.assert_eq(
    decode(bytes_of_ints([0xA1, 0xA1]), "GBK"),
    Ok(cp_str(0x3000)),
  )
  // [CPython] 0xD6D0 0xCEC4 → 中文
  @test.assert_eq(
    decode(bytes_of_ints([0xD6, 0xD0, 0xCE, 0xC4]), "GBK"),
    Ok(cps_str([0x4E2D, 0x6587])),
  )
  // [CPython] 0x8140 → U+4E02（index gb18030 首项）
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0x40]), "gb18030"),
    Ok(cp_str(0x4E02)),
  )
  // [spec] 0xA3A0 也映射 U+3000（规范为兼容存量内容的显式例外；
  // CPython 在此给 U+E5E5——分歧，本库以规范为准）
  @test.assert_eq(
    decode(bytes_of_ints([0xA3, 0xA0]), "GBK"),
    Ok(cp_str(0x3000)),
  )
}

///|
test "gb18030: four-byte anchors" {
  // [spec+CPython] 81 30 81 30（pointer 0，ranges 首项）→ U+0080
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0x30, 0x81, 0x30]), "gb18030"),
    Ok(cp_str(0x80)),
  )
  // [CPython] 90 30 81 30（pointer 189000）→ U+10000
  @test.assert_eq(
    decode(bytes_of_ints([0x90, 0x30, 0x81, 0x30]), "gb18030"),
    Ok(cp_str(0x10000)),
  )
  // [spec 注释] pointer 7457 = 81 35 F4 37 → U+E7C7（ranges 特例）
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0x35, 0xF4, 0x37]), "gb18030"),
    Ok(cp_str(0xE7C7)),
  )
  // [CPython] 81 30 84 36 → U+00A5
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0x30, 0x84, 0x36]), "gb18030"),
    Ok(cp_str(0xA5)),
  )
  // [spec] pointer 39980 落在 (39419, 189000) 空区间 → replacement
  @test.assert_eq(
    decode(bytes_of_ints([0x84, 0x31, 0xDD, 0x30]), "gb18030"),
    Ok(replacement_str()),
  )
}

///|
test "GBK/gb18030: spec Restore paths" {
  // [spec] 81 30 81 41：第四字节非数字 → U+FFFD，随后重放 30 81 41
  // → '0' + (81,41 为合法对) index[1]=U+4E04
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0x30, 0x81, 0x41]), "GBK"),
    Ok(cps_str([0xFFFD, 0x30, 0x4E04])),
  )
  // [spec] 81 30 20：第三字节非 81..FE → U+FFFD，重放 30 20 → '0' ' '
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0x30, 0x20]), "GBK"),
    Ok(cps_str([0xFFFD, 0x30, 0x20])),
  )
  // [spec] 81 20：尾字节不在合法尾字节范围且为 ASCII → U+FFFD，重放 20 → ' '
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0x20]), "GBK"),
    Ok(cps_str([0xFFFD, 0x20])),
  )
  // [spec] 81 FF：非法尾字节且非 ASCII → 仅 U+FFFD（0xFF 被消化，不重放）
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0xFF]), "GBK"),
    Ok(replacement_str()),
  )
}

///|
test "GBK/gb18030: end-of-queue flushes pending as a single U+FFFD" {
  let rep = replacement_str()
  // 挂起 1 / 2 / 3 个字节，规范 end-of-queue 都只返回一次 error
  let d1 = Decoder::new("gb18030")
  match d1 {
    Ok(d) => {
      @test.assert_eq(d.consume(bytes_of_ints([0x81])), "")
      @test.assert_eq(d.finish(), rep)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  let d2 = Decoder::new("gb18030")
  match d2 {
    Ok(d) => {
      @test.assert_eq(d.consume(bytes_of_ints([0x81, 0x30])), "")
      @test.assert_eq(d.finish(), rep)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  let d3 = Decoder::new("GBK")
  match d3 {
    Ok(d) => {
      @test.assert_eq(d.consume(bytes_of_ints([0x81, 0x30, 0x81])), "")
      @test.assert_eq(d.finish(), rep)
    }
    Err(e) => abort(@debug.to_string(e))
  }
}

///|
test "GBK/gb18030: chunked decode equals whole decode at every split position" {
  // 语料覆盖：合法对、中文、4 字节、0x80、0xFF、三条 Restore 路径、ASCII/数字
  let corpus = [
    0x81, 0x40, 0xD6, 0xD0, 0xCE, 0xC4, 0x90, 0x30, 0x81, 0x30, 0x80, 0xFF, 0x81,
    0x30, 0x81, 0x41, 0x81, 0x30, 0x20, 0x81, 0x20, 0x41, 0x20, 0x30, 0xA1, 0xA1,
    0xA3, 0xA0, 0x81, 0x35, 0xF4, 0x37, 0xFE, 0xFE, 0x09, 0x84, 0x31, 0xDD, 0x30,
  ]
  let input = bytes_of_ints(corpus)
  let n = input.length()
  let whole = match Decoder::new("gb18030") {
    Ok(d) => d.consume(input) + d.finish()
    Err(e) => abort(@debug.to_string(e))
  }
  // 每个切分点两段
  for split in 0..<(n + 1) {
    let d = match Decoder::new("gb18030") {
      Ok(d) => d
      Err(e) => abort(@debug.to_string(e))
    }
    let got = d.consume(slice_bytes(input, 0, split)) +
      d.consume(slice_bytes(input, split, n)) +
      d.finish()
    @test.assert_eq(got, whole)
  }
  // 确定性 LCG 多段切分（小素数模，无溢出）
  let mut seed = 4242
  for _round in 0..<1200 {
    let d = match Decoder::new("gb18030") {
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

///|
test "GBK encoder: spec anchors" {
  // [CPython] 中文 → d6 d0 c e c4（gbk 与 gb18030 的 2 字节一致）
  match encode(cps_str([0x4E2D, 0x6587]), "GBK") {
    Ok(b) => {
      @test.assert_eq(b.length(), 4)
      @test.assert_eq(b[0].to_int(), 0xD6)
      @test.assert_eq(b[1].to_int(), 0xD0)
      @test.assert_eq(b[2].to_int(), 0xCE)
      @test.assert_eq(b[3].to_int(), 0xC4)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [spec] is-GBK：€ → 0x80（CPython 的 gbk 拒编 €——分歧，以规范为准）
  match encode(cp_str(0x20AC), "GBK") {
    Ok(b) => {
      @test.assert_eq(b.length(), 1)
      @test.assert_eq(b[0].to_int(), 0x80)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [spec] is-GBK：4 字节一律 Unmappable（U+10000，位置 0）
  @test.assert_eq(
    encode(cp_str(0x10000), "GBK"),
    Err(EncodingError::Unmappable(0x10000, 0)),
  )
}

///|
test "gb18030 encoder: spec anchors" {
  // [CPython] € → a2 e3（index 内的 2 字节）
  match encode(cp_str(0x20AC), "gb18030") {
    Ok(b) => {
      @test.assert_eq(b.length(), 2)
      @test.assert_eq(b[0].to_int(), 0xA2)
      @test.assert_eq(b[1].to_int(), 0xE3)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [CPython] U+10000 → 90 30 81 30
  match encode(cp_str(0x10000), "gb18030") {
    Ok(b) => {
      @test.assert_eq(b.length(), 4)
      @test.assert_eq(b[0].to_int(), 0x90)
      @test.assert_eq(b[1].to_int(), 0x30)
      @test.assert_eq(b[2].to_int(), 0x81)
      @test.assert_eq(b[3].to_int(), 0x30)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [spec] U+E5E5 明确不可编码（CPython 能编 a3a0——分歧，以规范为准）
  @test.assert_eq(
    encode(cp_str(0xE5E5), "gb18030"),
    Err(EncodingError::Unmappable(0xE5E5, 0)),
  )
  // [spec 侧表] U+E78D → a6 d9（CPython 一致）
  match encode(cp_str(0xE78D), "gb18030") {
    Ok(b) => {
      @test.assert_eq(b[0].to_int(), 0xA6)
      @test.assert_eq(b[1].to_int(), 0xD9)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [CPython] U+3000 → a1a1（首次出现；a3a0 是第二出现，index pointer 取首）
  match encode(cp_str(0x3000), "gb18030") {
    Ok(b) => {
      @test.assert_eq(b[0].to_int(), 0xA1)
      @test.assert_eq(b[1].to_int(), 0xA1)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [spec] Unmappable 报出码点与字符位置（gb18030 下唯一不可编码的是 U+E5E5）
  @test.assert_eq(
    encode(cps_str([0x61, 0xE5E5, 0x62]), "gb18030"),
    Err(EncodingError::Unmappable(0xE5E5, 1)),
  )
}

///|
test "GBK/gb18030: encode->decode round-trips across the spec's tricky paths" {
  // 覆盖：index 内 2 字节、侧表 PUA、4 字节、GBK 的 €→0x80、U+3000 首次出现
  // 不含侧表码点：规范的侧表是**故意不对称**的（见下一条测试）
  let gb18030_cps = [0x4E02, 0x3000, 0x80, 0x10000, 0xE7C7, 0x20AC, 0x4E2D]
  for cp in gb18030_cps {
    let text = cp_str(cp)
    match encode(text, "gb18030") {
      Ok(b) => @test.assert_eq(decode(b, "gb18030"), Ok(text))
      Err(e) => abort("gb18030 encode \{cp}: " + @debug.to_string(e))
    }
  }
  let gbk_cps = [0x4E02, 0x3000, 0x20AC, 0x4E2D, 0x6587]
  for cp in gbk_cps {
    let text = cp_str(cp)
    match encode(text, "GBK") {
      Ok(b) => @test.assert_eq(decode(b, "GBK"), Ok(text))
      Err(e) => abort("GBK encode \{cp}: " + @debug.to_string(e))
    }
  }
}

///|
test "gb18030: side table is intentionally asymmetric (spec §gb18030-encoder)" {
  // [spec] 编码端经侧表：U+E78D → a6 d9（兼容 GB18030-2005 存量内容）
  match encode(cp_str(0xE78D), "gb18030") {
    Ok(b) => {
      @test.assert_eq(b.length(), 2)
      @test.assert_eq(b[0].to_int(), 0xA6)
      @test.assert_eq(b[1].to_int(), 0xD9)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [spec/index 数据] 解码端不走侧表：a6 d9 按 index gb18030 给 U+FE10。
  // 这就是规范所称 "asymmetric encoder table"——刻意不保证这一对往返；
  // CPython 在此两个方向都不同（解码给 U+E78D），差分向量会自动排除。
  @test.assert_eq(
    decode(bytes_of_ints([0xA6, 0xD9]), "gb18030"),
    Ok(cp_str(0xFE10)),
  )
}

///|
test "GBK and gb18030 decode identically (spec: same decoder)" {
  // 规范：GBK 的解码器就是 gb18030 的——含 4 字节与 0x80 行为
  let samples = [
    [0x80],
    [0xD6, 0xD0],
    [0x90, 0x30, 0x81, 0x30],
    [0x81, 0x30, 0x81, 0x41],
    [0x81, 0xFF],
    [0xA3, 0xA0],
  ]
  for s in samples {
    let input = bytes_of_ints(s)
    @test.assert_eq(decode(input, "GBK"), decode(input, "gb18030"))
  }
}

///|
test "invariants: generated Chinese tables" {
  // index：23940 项（126 个头字节 × 190），无空位、无代理区
  @test.assert_eq(gb18030_index.length(), 23940)
  for i in 0..<23940 {
    let cp = gb18030_index[i]
    @test.assert_eq(cp >= 0, true)
    @test.assert_eq(cp <= 0x10FFFF, true)
    @test.assert_eq(cp < 0xD800 || cp > 0xDFFF, true)
  }
  // ranges：207 对，两列都严格升序（二分查找的依据）
  @test.assert_eq(gb18030_ranges.length(), 414)
  let mut prev_p = -1
  let mut prev_c = -1
  for i in 0..<207 {
    let p = gb18030_ranges[i * 2]
    let c = gb18030_ranges[i * 2 + 1]
    @test.assert_eq(p > prev_p, true)
    @test.assert_eq(c > prev_c, true)
    prev_p = p
    prev_c = c
  }
  // 编码反向表：23939 个唯一码点（0x3000 恰好重复一次），按码点升序
  @test.assert_eq(gb18030_encode_index.length(), 47878)
  let mut prev_cp = -1
  for i in 0..<23939 {
    let cp = gb18030_encode_index[i * 2]
    @test.assert_eq(cp > prev_cp, true)
    prev_cp = cp
  }
  // PUA 侧表：18 条 × 3，按码点升序，首末与规范表格一致
  @test.assert_eq(gbk_pua_side_table.length(), 54)
  @test.assert_eq(gbk_pua_side_table[0], 0xE78D)
  @test.assert_eq(gbk_pua_side_table[51], 0xE864)
  let mut prev_side = -1
  for i in 0..<18 {
    let cp = gbk_pua_side_table[i * 3]
    @test.assert_eq(cp > prev_side, true)
    prev_side = cp
  }
}

///|
test "invariants: every legal 4-byte pointer maps to a valid code point" {
  // 全量扫描合法 pointer 空间：ranges_code_point 结果必须是合法非代理码点
  let mut checked = 0
  let mut p = 0
  while p <= 39419 {
    let cp = ranges_code_point(p)
    if cp >= 0 {
      @test.assert_eq(cp <= 0x10FFFF, true)
      @test.assert_eq(cp < 0xD800 || cp > 0xDFFF, true)
      checked += 1
    }
    p += 1
  }
  p = 189000
  while p <= 1237575 {
    let cp = ranges_code_point(p)
    if cp >= 0 {
      @test.assert_eq(cp <= 0x10FFFF, true)
      @test.assert_eq(cp < 0xD800 || cp > 0xDFFF, true)
      checked += 1
    }
    p += 1
  }
  // 两个区间的合法 pointer 数：39420 + (1237576 - 189000) = 1,087,996
  @test.assert_eq(checked, 1087996)
}

///|
test "supported_encodings covers the wired set and label aliases route there" {
  // 28 单字节 + GBK/gb18030/Big5/Shift_JIS
  let names = supported_encodings()
  @test.assert_eq(names.length(), 32)
  let mut found_gbk = false
  let mut found_gb18030 = false
  let mut found_big5 = false
  let mut found_sjis = false
  for n in names {
    if n == "GBK" {
      found_gbk = true
    }
    if n == "gb18030" {
      found_gb18030 = true
    }
    if n == "Big5" {
      found_big5 = true
    }
    if n == "Shift_JIS" {
      found_sjis = true
    }
  }
  @test.assert_eq(found_gbk, true)
  @test.assert_eq(found_gb18030, true)
  @test.assert_eq(found_big5, true)
  @test.assert_eq(found_sjis, true)
  // gb2312 / chinese 等别名经 label 归一后走同一条通路
  let input = bytes_of_ints([0xD6, 0xD0, 0xCE, 0xC4])
  @test.assert_eq(decode(input, "gb2312"), Ok(cps_str([0x4E2D, 0x6587])))
  @test.assert_eq(decode(input, "GB2312"), Ok(cps_str([0x4E2D, 0x6587])))
}
