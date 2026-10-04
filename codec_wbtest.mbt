// codec_wbtest.mbt
//
// 公共 API 的行为测试：decode/encode、错误分支、流式切分等价性。
// 白盒：需要访问生成表做断言的测试在 single_byte_wbtest.mbt。

///|
test "decode: windows-1252 text decodes through the public API" {
  // H é l l o —— é 在 windows-1252 里是 0xE9
  let input = bytes_of_ints([0x48, 0xE9, 0x6C, 0x6C, 0x6F])
  @test.assert_eq(decode(input, "windows-1252"), Ok("Héllo"))
  @test.assert_eq(decode(input, "WINDOWS-1252"), Ok("Héllo"))
  @test.assert_eq(decode(input, "latin1"), Ok("Héllo")) // label 别名
}

///|
test "decode: C1 control bytes follow WHATWG (not Python cp1252)" {
  let input = bytes_of_ints([0x81, 0x8D, 0x8F, 0x90, 0x9D])
  match decode(input, "windows-1252") {
    Ok(s) => {
      @test.assert_eq(s.length(), 5)
      let expected = [0x0081, 0x008D, 0x008F, 0x0090, 0x009D]
      for i in 0..<5 {
        @test.assert_eq(s.get_char(i).unwrap().to_int(), expected[i])
      }
    }
    Err(e) => abort("unexpected error: " + @debug.to_string(e))
  }
}

///|
test "decode: empty input decodes to empty output" {
  @test.assert_eq(decode(bytes_of_ints([]), "windows-1252"), Ok(""))
}

///|
test "decode: unknown label and valid-but-unimplemented encoding are distinct errors" {
  let input = bytes_of_ints([0x41])
  @test.assert_eq(
    decode(input, "no-such-label"),
    Err(EncodingError::UnknownLabel("no-such-label")),
  )
  // GBK/gb18030/Big5/Shift_JIS/EUC-JP/EUC-KR 已接线；换一个合法但尚未接线的编码
  //（ISO-2022-JP 是四模式转义状态机，属独立里程碑）验证两类错误可区分
  match decode(input, "iso-2022-jp") {
    Err(EncodingError::UnsupportedEncoding(name)) =>
      @test.assert_eq(name, "ISO-2022-JP")
    other =>
      abort("expected UnsupportedEncoding, got " + @debug.to_string(other))
  }
}

///|
test "encode: mappable text produces the expected bytes" {
  match encode("Élan €", "windows-1252") {
    Ok(out) => {
      let expected = [0xC9, 0x6C, 0x61, 0x6E, 0x20, 0x80]
      @test.assert_eq(out.length(), expected.length())
      for i in 0..<expected.length() {
        @test.assert_eq(out[i].to_int(), expected[i])
      }
    }
    Err(e) => abort("unexpected error: " + @debug.to_string(e))
  }
}

///|
test "encode: empty text encodes to empty bytes" {
  match encode("", "windows-1252") {
    Ok(out) => @test.assert_eq(out.length(), 0)
    Err(e) => abort("unexpected error: " + @debug.to_string(e))
  }
}

///|
test "encode: unmappable characters fail with code point and position (fatal mode)" {
  // 规范 encode or fail：报出不可映射码点与位置，替换策略由调用方决定
  @test.assert_eq(
    encode("中文", "windows-1252"),
    Err(EncodingError::Unmappable(0x4E2D, 0)),
  )
  @test.assert_eq(
    encode("a中b", "windows-1252"),
    Err(EncodingError::Unmappable(0x4E2D, 1)),
  )
  // é 可映射，所以位置 2 才是第一个不可映射字符
  @test.assert_eq(
    encode("aé☃", "windows-1252"),
    Err(EncodingError::Unmappable(0x2603, 2)),
  )
}

///|
test "encode: unknown label and unimplemented encodings are distinct errors" {
  match encode("x", "no-such-label") {
    Err(EncodingError::UnknownLabel(l)) => @test.assert_eq(l, "no-such-label")
    other => abort("expected UnknownLabel, got " + @debug.to_string(other))
  }
  // UTF-8 已可编码；用仍未接线的 ISO-2022-JP（四模式转义状态机）验证
  match encode("x", "iso-2022-jp") {
    Err(EncodingError::UnsupportedEncoding(name)) =>
      @test.assert_eq(name, "ISO-2022-JP")
    other =>
      abort("expected UnsupportedEncoding, got " + @debug.to_string(other))
  }
}

///|
test "streaming: 1200 deterministic random partitions equal whole-input decode" {
  // 语料混入高位字节与 5 个 C1 字节；LCG 用小素数模避免 Int 溢出。
  let corpus = [
    0x48, 0xE9, 0xA9, 0x80, 0x93, 0x94, 0xC9, 0xE8, 0xFC, 0xDF, 0xB5, 0x26, 0x3C,
    0x7B, 0x81, 0x9D, 0xFF, 0xFE, 0xA0, 0xAD, 0x8D, 0x8F, 0x90, 0x7B, 0x41, 0x20,
    0xE2, 0x82, 0xAC, 0xBB, 0xAB, 0x99, 0x96, 0x97, 0x91, 0x92, 0x85, 0x86, 0x87,
    0x88, 0x98,
  ]
  let input = bytes_of_ints(corpus)
  let n = input.length()
  let whole = match Decoder::new("windows-1252") {
    Ok(d) => d.consume(input)
    Err(e) => abort("unexpected error: " + @debug.to_string(e))
  }
  let mut seed = 12345
  for _round in 0..<1200 {
    let decoder = match Decoder::new("windows-1252") {
      Ok(d) => d
      Err(e) => abort("unexpected error: " + @debug.to_string(e))
    }
    let mut out = ""
    let mut pos = 0
    while pos < n {
      seed = (seed * 75 + 74) % 65537 // Lehmer LCG，值域内无溢出
      let step = seed % 13 + 1 // 切块长度 1..13
      let end = if pos + step > n { n } else { pos + step }
      out = out + decoder.consume(slice_bytes(input, pos, end))
      pos = end
    }
    out = out + decoder.finish()
    @test.assert_eq(out, whole)
  }
}
