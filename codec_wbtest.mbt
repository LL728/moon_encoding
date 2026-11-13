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
test "decode: unknown label is rejected, every valid label decodes" {
  let input = bytes_of_ints([0x41])
  @test.assert_eq(
    decode(input, "no-such-label"),
    Err(EncodingError::UnknownLabel("no-such-label")),
  )
  // 40 种编码全部接线后，规范的每个 label 都能构造出解码器；
  // 曾经用作"合法但未实现"样本的三个编码现在都真的能解出内容
  @test.assert_eq(decode(input, "iso-2022-jp"), Ok("A"))
  @test.assert_eq(decode(input, "x-user-defined"), Ok("A"))
  @test.assert_eq(decode(input, "replacement"), Ok(replacement_str()))
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
test "encode: unknown label and spec-without-encoder are distinct errors" {
  match encode("x", "no-such-label") {
    Err(EncodingError::UnknownLabel(l)) => @test.assert_eq(l, "no-such-label")
    other => abort("expected UnknownLabel, got " + @debug.to_string(other))
  }
  // 规范 §get an encoder 不定义 replacement 与 UTF-16BE/LE 的编码器
  @test.assert_eq(
    encode("x", "replacement"),
    Err(EncodingError::UnsupportedEncoding("replacement")),
  )
  @test.assert_eq(
    encode("x", "utf-16le"),
    Err(EncodingError::UnsupportedEncoding("UTF-16LE")),
  )
  // ISO-2022-JP 现在可编码（曾经也是"未实现"样本）
  @test.assert_eq(encode("x", "iso-2022-jp"), Ok(bytes_of_ints([0x78])))
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

///|
test "bom: 三种前缀都命中" {
  @test.assert_eq(bom_sniff(bytes_of_ints([0xEF, 0xBB, 0xBF])), Some("UTF-8"))
  @test.assert_eq(bom_sniff(bytes_of_ints([0xFE, 0xFF])), Some("UTF-16BE"))
  @test.assert_eq(bom_sniff(bytes_of_ints([0xFF, 0xFE])), Some("UTF-16LE"))
}

///|
test "bom: 空输入与无 BOM 返回 None" {
  @test.assert_eq(bom_sniff(bytes_of_ints([])), None)
  @test.assert_eq(bom_sniff(bytes_of_ints([0x48, 0x49])), None)
  @test.assert_eq(bom_sniff(bytes_of_ints([0x00])), None)
}

///|
// 规范 §6.1 是"peeking 3 bytes"：不足 3 字节时只能匹配 2 字节前缀，不能越界。
test "bom: 不足 3 字节按可匹配前缀判定" {
  @test.assert_eq(bom_sniff(bytes_of_ints([0xEF, 0xBB])), None)
  @test.assert_eq(bom_sniff(bytes_of_ints([0xEF])), None)
  @test.assert_eq(bom_sniff(bytes_of_ints([0xFE])), None)
  @test.assert_eq(bom_sniff(bytes_of_ints([0xFF])), None)
  @test.assert_eq(bom_sniff(bytes_of_ints([0xFE, 0xFF])), Some("UTF-16BE"))
}

///|
test "bom: 前三字节不是三种前缀返回 None" {
  @test.assert_eq(bom_sniff(bytes_of_ints([0xEF, 0xBB, 0xBE])), None)
  @test.assert_eq(bom_sniff(bytes_of_ints([0xFF, 0xEF])), None)
  @test.assert_eq(bom_sniff(bytes_of_ints([0x00, 0x00, 0x00])), None)
}

///|
test "decode_auto: 无 BOM 时按 fallback label 解码" {
  // [0x63, 0x61, 0x66, 0xE9] = windows-1252 的 café
  @test.assert_eq(
    decode_auto(bytes_of_ints([0x63, 0x61, 0x66, 0xE9]), "windows-1252"),
    Ok("café"),
  )
}

///|
// Review Focus #2：BOM 比调用方给的 label 更有权威（规范原文）。
test "decode_auto: BOM 覆盖冲突的 fallback label" {
  // [0xFF, 0xFE, 0x2D, 0x4E] = UTF-16LE BOM + U+4E2D
  @test.assert_eq(
    decode_auto(bytes_of_ints([0xFF, 0xFE, 0x2D, 0x4E]), "gbk"),
    Ok("\u4e2d"),
  )
}

///|
test "decode_auto: BOM 字节被吞掉，不产出 U+FEFF" {
  // [0xEF, 0xBB, 0xBF, 0x48, 0x69] = UTF-8 BOM + "Hi"
  @test.assert_eq(
    decode_auto(bytes_of_ints([0xEF, 0xBB, 0xBF, 0x48, 0x69]), "gbk"),
    Ok("Hi"),
  )
}

///|
// Review Focus #3：只有 BOM 时返回空串，不是 U+FEFF，也不是错误。
test "decode_auto: 只有 BOM 时返回空串" {
  @test.assert_eq(decode_auto(bytes_of_ints([0xEF, 0xBB, 0xBF]), "gbk"), Ok(""))
  @test.assert_eq(decode_auto(bytes_of_ints([0xFF, 0xFE]), "gbk"), Ok(""))
}

///|
test "decode_auto: 未知 fallback label 仍报 UnknownLabel" {
  // 规范先解析 fallback encoding，故 BOM 命中也不能跳过 label 校验
  @test.assert_eq(
    decode_auto(bytes_of_ints([0xEF, 0xBB, 0xBF, 0x48]), "no-such-label"),
    Err(EncodingError::UnknownLabel("no-such-label")),
  )
}

///|
test "decode_auto: 空输入返回空串" {
  @test.assert_eq(decode_auto(bytes_of_ints([]), "gbk"), Ok(""))
}

///|
// Review Focus #1：BOM 可能跨 chunk，必须先缓冲，不能提前判「无 BOM」。
test "new_auto: BOM 跨两个 chunk 也能识别" {
  let d = match Decoder::new_auto("gbk") {
    Ok(d) => d
    Err(e) => abort("unexpected error: " + @debug.to_string(e))
  }
  @test.assert_eq(d.consume(bytes_of_ints([0xEF])), "")
  @test.assert_eq(d.consume(bytes_of_ints([0xBB, 0xBF])), "")
  @test.assert_eq(d.consume(bytes_of_ints([0x48, 0x69])), "Hi")
  @test.assert_eq(d.finish(), "")
}

///|
test "new_auto: 无 BOM 时首块即按 fallback 透传" {
  let d = match Decoder::new_auto("windows-1252") {
    Ok(d) => d
    Err(e) => abort("unexpected error: " + @debug.to_string(e))
  }
  @test.assert_eq(d.consume(bytes_of_ints([0x63, 0x61, 0x66, 0xE9])), "café")
  @test.assert_eq(d.finish(), "")
}

///|
// 首字节不可能是任何 BOM 前缀时必须立刻透传，否则整个流会卡在缓冲里。
test "new_auto: 首字节不可能是 BOM 前缀时立即透传" {
  let d = match Decoder::new_auto("windows-1252") {
    Ok(d) => d
    Err(e) => abort("unexpected error: " + @debug.to_string(e))
  }
  @test.assert_eq(d.consume(bytes_of_ints([0x63])), "c")
  @test.assert_eq(d.consume(bytes_of_ints([0x61])), "a")
  @test.assert_eq(d.finish(), "")
}

///|
// 流式与一次性必须等价：同段字节一字节一块喂完，结果等于 decode_auto。
test "new_auto: 流式结果与一次性 decode_auto 相同" {
  let data = bytes_of_ints([0xFF, 0xFE, 0x2D, 0x4E, 0x4E, 0x2D])
  let whole = decode_auto(data, "gbk")
  let d = match Decoder::new_auto("gbk") {
    Ok(d) => d
    Err(e) => abort("unexpected error: " + @debug.to_string(e))
  }
  let mut out = ""
  let mut i = 0
  while i < data.length() {
    out = out + d.consume(bytes_of_ints([data[i].to_int()]))
    i = i + 1
  }
  out = out + d.finish()
  @test.assert_eq(Ok(out), whole)
}

///|
test "new_auto: 未知 label 报 UnknownLabel" {
  match Decoder::new_auto("no-such-label") {
    Err(EncodingError::UnknownLabel(l)) => @test.assert_eq(l, "no-such-label")
    _ => abort("expected UnknownLabel, got unknown arm")
  }
}
