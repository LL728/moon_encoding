// euc_wbtest.mbt
//
// EUC-JP / EUC-KR 的规范级测试。
// 期望值来源：[spec] = encoding.bs（@ 2c3853e）条文；[数据] = vendored
// indexes.json；[CPython] = 独立实现现算。CPython 与规范的已知分歧
// （a1dd 的 FF0D/2212、8141 的 AB02、Python 拒绝的重放输入）以规范为准。

///|
test "EUC-JP: fresh-byte semantics per spec" {
  // [spec] ASCII 直通（含 0x7F）
  @test.assert_eq(
    decode(bytes_of_ints([0x41, 0x7F]), "EUC-JP"),
    Ok(cps_str([0x41, 0x7F])),
  )
  // [spec] 0x80 / 0xA0 / 0xFF 报错——**与 Shift_JIS 的 0x80→U+0080 不同**
  //（CPython 在 0x80 上同样拒绝，两边一致）
  let rep = replacement_str()
  @test.assert_eq(decode(bytes_of_ints([0x80]), "EUC-JP"), Ok(rep))
  @test.assert_eq(decode(bytes_of_ints([0xA0]), "EUC-JP"), Ok(rep))
  @test.assert_eq(decode(bytes_of_ints([0xFF]), "EUC-JP"), Ok(rep))
}

///|
test "EUC-JP: SS2 katakana and SS3 jis0212 sequences" {
  // [CPython+spec] 8E A1 → U+FF61（SS2 半角片假名单字节）
  @test.assert_eq(
    decode(bytes_of_ints([0x8E, 0xA1]), "EUC-JP"),
    Ok(cp_str(0xFF61)),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0x8E, 0xDF]), "EUC-JP"),
    Ok(cp_str(0xFF9F)),
  )
  // [数据+CPython] 8F A2 AF → jis0212[108] = U+02D8（SS3 三字节，Python 也支持）
  @test.assert_eq(
    decode(bytes_of_ints([0x8F, 0xA2, 0xAF]), "EUC-JP"),
    Ok(cp_str(0x02D8)),
  )
  // [数据] 8F A1 A1 → jis0212[0] 为空且尾字节非 ASCII → 单个 U+FFFD
  //（CPython 在此同样报错——两边一致）
  @test.assert_eq(
    decode(bytes_of_ints([0x8F, 0xA1, 0xA1]), "EUC-JP"),
    Ok(replacement_str()),
  )
}

///|
test "EUC-JP: two-byte anchors and the FF0D/2212 divergence" {
  // [CPython] A1A1 → U+3000；C6FC → U+65E5（日本語首字节）
  @test.assert_eq(
    decode(bytes_of_ints([0xA1, 0xA1]), "EUC-JP"),
    Ok(cp_str(0x3000)),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0xC6, 0xFC, 0xCB, 0xDC, 0xB8, 0xEC]), "EUC-JP"),
    Ok(cps_str([0x65E5, 0x672C, 0x8A9E])),
  )
  // [数据/spec] A1DD → jis0208[60] = U+FF0D（CPython 给 U+2212——分歧，以规范为准；
  // 差分向量按逐样本分类自动排除）
  @test.assert_eq(
    decode(bytes_of_ints([0xA1, 0xDD]), "EUC-JP"),
    Ok(cp_str(0xFF0D)),
  )
}

///|
test "EUC-JP: invalid trail restores ASCII bytes (spec)" {
  // [spec] A1 20：0x20 不在尾字节范围 0xA1..0xFE，且是 ASCII → U+FFFD 后重放 0x20
  //（CPython 直接整段报错——Python-error 跳过，不进差分向量）
  @test.assert_eq(
    decode(bytes_of_ints([0xA1, 0x20]), "EUC-JP"),
    Ok(cps_str([0xFFFD, 0x20])),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0xA1, 0x41]), "EUC-JP"),
    Ok(cps_str([0xFFFD, 0x41])),
  )
}

///|
test "EUC-JP: end-of-queue flushes pending lead as a single U+FFFD" {
  let rep = replacement_str()
  // 挂起 SS2 前缀（8E 无后继）
  match Decoder::new("EUC-JP") {
    Ok(d) => {
      @test.assert_eq(d.consume(bytes_of_ints([0x8E])), "")
      @test.assert_eq(d.finish(), rep)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // 挂起 SS3 中段（8F + 第二字节，缺第三字节）
  match Decoder::new("EUC-JP") {
    Ok(d) => {
      @test.assert_eq(d.consume(bytes_of_ints([0x8F, 0xA2])), "")
      @test.assert_eq(d.finish(), rep)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // 挂起普通 lead
  match Decoder::new("EUC-JP") {
    Ok(d) => {
      @test.assert_eq(d.consume(bytes_of_ints([0xC6])), "")
      @test.assert_eq(d.finish(), rep)
    }
    Err(e) => abort(@debug.to_string(e))
  }
}

///|
test "EUC-JP encoder: spec quirks and anchors" {
  // [CPython] 日本語 → c6 fc cb dc b8 ec
  match encode(cps_str([0x65E5, 0x672C, 0x8A9E]), "EUC-JP") {
    Ok(b) => {
      @test.assert_eq(b.length(), 6)
      let expect = [0xC6, 0xFC, 0xCB, 0xDC, 0xB8, 0xEC]
      for i in 0..<6 {
        @test.assert_eq(b[i].to_int(), expect[i])
      }
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [CPython+spec] 半角片假名 → 两字节 SS2；¥ → 0x5C；overbar → 0x7E
  match encode(cp_str(0xFF61), "EUC-JP") {
    Ok(b) => {
      @test.assert_eq(b.length(), 2)
      @test.assert_eq(b[0].to_int(), 0x8E)
      @test.assert_eq(b[1].to_int(), 0xA1)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  match encode(cp_str(0x00A5), "EUC-JP") {
    Ok(b) => @test.assert_eq(b[0].to_int(), 0x5C)
    Err(e) => abort(@debug.to_string(e))
  }
  match encode(cp_str(0x203E), "EUC-JP") {
    Ok(b) => @test.assert_eq(b[0].to_int(), 0x7E)
    Err(e) => abort(@debug.to_string(e))
  }
  // [CPython+spec] U+2212 归一 U+FF0D 后查表 → A1 DD（与 CPython 的字节一致，
  // 但解码端两边给不同码点——见解码侧的分歧测试）
  match encode(cp_str(0x2212), "EUC-JP") {
    Ok(b) => {
      @test.assert_eq(b[0].to_int(), 0xA1)
      @test.assert_eq(b[1].to_int(), 0xDD)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [spec] 归一后的码点同样可编：U+FF0D → A1 DD
  match encode(cp_str(0xFF0D), "EUC-JP") {
    Ok(b) => {
      @test.assert_eq(b[0].to_int(), 0xA1)
      @test.assert_eq(b[1].to_int(), 0xDD)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [CPython+spec] U+0641 不在 jis0208 → Unmappable（两边一致）
  @test.assert_eq(
    encode(cp_str(0x0641), "EUC-JP"),
    Err(EncodingError::Unmappable(0x0641, 0)),
  )
}

///|
test "EUC-KR: fresh-byte semantics per spec" {
  // [spec] ASCII 直通
  @test.assert_eq(
    decode(bytes_of_ints([0x41, 0x7F]), "EUC-KR"),
    Ok(cps_str([0x41, 0x7F])),
  )
  // [spec] 0x80 / 0xA0 / 0xFF 报错——**与 GBK 的 0x80→U+20AC 不同**
  //（CPython 同样拒绝 0x80，两边一致）
  let rep = replacement_str()
  @test.assert_eq(decode(bytes_of_ints([0x80]), "EUC-KR"), Ok(rep))
  @test.assert_eq(decode(bytes_of_ints([0xA0]), "EUC-KR"), Ok(rep))
  @test.assert_eq(decode(bytes_of_ints([0xFF]), "EUC-KR"), Ok(rep))
}

///|
test "EUC-KR: two-byte anchors and null-index cells" {
  // [CPython] A1A1 → U+3000；C7D1 B1B9 BEEE → 韩国어
  @test.assert_eq(
    decode(bytes_of_ints([0xA1, 0xA1]), "EUC-KR"),
    Ok(cp_str(0x3000)),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0xC7, 0xD1, 0xB1, 0xB9, 0xBE, 0xEE]), "EUC-KR"),
    Ok(cps_str([0xD55C, 0xAD6D, 0xC5B4])),
  )
  // [数据] 81 41 → 指针 0 = 44034 = U+AC02（CPython 拒绝该字节对——分歧，以 vendored 表为准）
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0x41]), "EUC-KR"),
    Ok(cp_str(0xAC02)),
  )
}

///|
test "EUC-KR: invalid trail restores ASCII bytes (spec)" {
  // [数据+spec] 81 5B → 指针 26 为空位，0x5B 是 ASCII → U+FFFD 后重放 '['
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0x5B]), "EUC-KR"),
    Ok(cps_str([0xFFFD, 0x5B])),
  )
  // [数据+spec] 81 80 → 指针 63 为空位，0x80 非 ASCII → 仅 U+FFFD（0x80 被消化）
  @test.assert_eq(
    decode(bytes_of_ints([0x81, 0x80]), "EUC-KR"),
    Ok(replacement_str()),
  )
}

///|
test "EUC-KR: end-of-queue flushes pending lead as a single U+FFFD" {
  let rep = replacement_str()
  match Decoder::new("EUC-KR") {
    Ok(d) => {
      @test.assert_eq(d.consume(bytes_of_ints([0xC7])), "")
      @test.assert_eq(d.finish(), rep)
    }
    Err(e) => abort(@debug.to_string(e))
  }
}

///|
test "EUC-KR encoder: spec has no quirks — plain index pointer" {
  // [CPython] 韩国어 → c7 d1 b1 b9 be ee
  match encode(cps_str([0xD55C, 0xAD6D, 0xC5B4]), "EUC-KR") {
    Ok(b) => {
      @test.assert_eq(b.length(), 6)
      let expect = [0xC7, 0xD1, 0xB1, 0xB9, 0xBE, 0xEE]
      for i in 0..<6 {
        @test.assert_eq(b[i].to_int(), expect[i])
      }
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [CPython] € → a2e6（与 Big5/Shift_JIS 不同：euc-kr 表内有 €，两边一致可编）
  match encode(cp_str(0x20AC), "EUC-KR") {
    Ok(b) => {
      @test.assert_eq(b[0].to_int(), 0xA2)
      @test.assert_eq(b[1].to_int(), 0xE6)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [CPython] U+3000 → a1a1
  match encode(cp_str(0x3000), "EUC-KR") {
    Ok(b) => {
      @test.assert_eq(b[0].to_int(), 0xA1)
      @test.assert_eq(b[1].to_int(), 0xA1)
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [CPython+spec] U+0641 不可编（两边一致）
  @test.assert_eq(
    encode(cp_str(0x0641), "EUC-KR"),
    Err(EncodingError::Unmappable(0x0641, 0)),
  )
}

///|
test "EUC-JP and EUC-KR: chunked equals whole at every split position" {
  let cases : Array[(String, Array[Int])] = [
    (
      "EUC-JP",
      [
        0xC6, 0xFC, 0xCB, 0xDC, 0xB8, 0xEC, 0x8E, 0xA1, 0x8F, 0xA2, 0xAF, 0xA1, 0x20,
        0xA1, 0x41, 0x80, 0x8E, 0x8F, 0xA1, 0xA1, 0x41, 0x7F, 0xA1, 0xA1, 0xFE, 0xFE,
      ],
    ),
    (
      "EUC-KR",
      [
        0xC7, 0xD1, 0xB1, 0xB9, 0xBE, 0xEE, 0xA1, 0xA1, 0x81, 0x5B, 0x81, 0x80, 0x81,
        0x41, 0x80, 0x41, 0x20, 0x81, 0x20, 0xA0, 0xFE, 0xFE,
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
    let mut seed = 31337
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
test "invariants: generated EUC tables" {
  // jis0212：8836 项，空位 -1，其余合法非代理码点
  @test.assert_eq(jis0212_index.length(), 8836)
  for i in 0..<8836 {
    let cp = jis0212_index[i]
    @test.assert_eq(cp >= -1 && cp <= 0x10FFFF, true)
    @test.assert_eq(cp == -1 || cp < 0xD800 || cp > 0xDFFF, true)
  }
  // index EUC-KR：23940 项（126 头字节 × 190 尾偏移），同样的合法性
  @test.assert_eq(euc_kr_index.length(), 23940)
  for i in 0..<23940 {
    let cp = euc_kr_index[i]
    @test.assert_eq(cp >= -1 && cp <= 0x10FFFF, true)
    @test.assert_eq(cp == -1 || cp < 0xD800 || cp > 0xDFFF, true)
  }
  // EUC-KR 编码反向表：17048 唯一码点、按码点升序（索引本身零重复）
  @test.assert_eq(euc_kr_encode_index.length(), 34096)
  let mut prev = -1
  for i in 0..<17048 {
    let cp = euc_kr_encode_index[i * 2]
    @test.assert_eq(cp > prev, true)
    prev = cp
  }
  // EUC-JP 编码反向表：7326 唯一码点、升序，且**所有指针 < 8836**
  //（规范 §euc-jp-encoder 的注记，生成器也断言过一次）
  @test.assert_eq(euc_jp_encode_index.length(), 14652)
  let mut prev_p = -1
  for i in 0..<7326 {
    let cp = euc_jp_encode_index[i * 2]
    let ptr = euc_jp_encode_index[i * 2 + 1]
    @test.assert_eq(cp > prev_p, true)
    @test.assert_eq(ptr < 8836, true)
    prev_p = cp
  }
}
