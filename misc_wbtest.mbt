// misc_wbtest.mbt
//
// Legacy miscellaneous 组里两个算法型编码的规范级测试：
// §14.1.1 replacement-decoder（至多一次 error → 恰好一个 U+FFFD；规范不定义编码器）
// 与 §14.5 x-user-defined-decoder / encoder（0x00..0x7F 恒等、0x80..0xFF → U+F780+）。

///|
test "replacement: at most one U+FFFD, then the whole decode stops" {
  // [spec §14.1.1] 「若 replacement error returned 为 false，置 true 并返回 error；
  // 否则返回 finished」——finished 让 process-a-queue 整体终止，剩余字节不再读
  @test.assert_eq(
    decode(bytes_of_ints([0x41]), "replacement"),
    Ok(replacement_str()),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0x41, 0x42]), "replacement"),
    Ok(replacement_str()),
  )
  // 全 256 个字节也只有 1 个 U+FFFD
  let all : Array[Int32] = []
  for b in 0..<256 {
    all.push(b)
  }
  @test.assert_eq(
    decode(bytes_of_ints(all), "replacement"),
    Ok(replacement_str()),
  )
  // 空输入：第一次读到的是 EOF → finished，从不报错
  @test.assert_eq(decode(bytes_of_ints([]), "replacement"), Ok(""))
  // 流式：第一块出 U+FFFD 并置 error_returned；第二块的首个字节触发 finished，
  // 该字节被消费，之后的 consume 一律无输出
  let d = match Decoder::new("replacement") {
    Ok(d) => d
    Err(e) => abort(@debug.to_string(e))
  }
  @test.assert_eq(
    d.consume(bytes_of_ints([0x41, 0x42, 0x43])),
    replacement_str(),
  )
  @test.assert_eq(d.consume(bytes_of_ints([0x44, 0x45])), "")
  @test.assert_eq(d.finish(), "")
  // 空块不消耗那次唯一的 error（error_returned 仍为 false），下一次非空块才产出
  let e = match Decoder::new("replacement") {
    Ok(d) => d
    Err(e) => abort(@debug.to_string(e))
  }
  @test.assert_eq(e.consume(bytes_of_ints([])), "")
  @test.assert_eq(e.consume(bytes_of_ints([0x41, 0x42])), replacement_str())
  @test.assert_eq(e.consume(bytes_of_ints([0x43])), "")
  @test.assert_eq(e.finish(), "")
}

///|
test "replacement: all six labels route to it and it has no encoder per spec" {
  // [数据] replacement 的 6 个 label（encodings.json）
  let labels : Array[String] = [
    "replacement", "csiso2022kr", "hz-gb-2312", "iso-2022-cn", "iso-2022-cn-ext",
    "iso-2022-kr",
  ]
  for label in labels {
    @test.assert_eq(label_to_encoding(label), Ok("replacement"))
    @test.assert_eq(decode(bytes_of_ints([0x41]), label), Ok(replacement_str()))
    // [spec] §get an encoder 断言 encoding 不是 replacement → 无编码器，
    // 与 UTF-16BE/LE 同款如实报 UnsupportedEncoding
    @test.assert_eq(
      encode("a", label),
      Err(EncodingError::UnsupportedEncoding("replacement")),
    )
  }
}

///|
test "x-user-defined: identity below 0x80 and U+F780+byte-0x80 above" {
  let low : Array[Int32] = []
  for b in 0..<0x80 {
    low.push(b)
  }
  // 0x00..0x7F 恒等（含 0x00、0x7F、控制字符）
  @test.assert_eq(
    decode(bytes_of_ints(low), "x-user-defined"),
    Ok(cps_str(low)),
  )
  // 0x80..0xFF → U+F780..U+F7FF
  let high : Array[Int32] = []
  let expect : Array[Int32] = []
  for b in 0x80..<0x100 {
    high.push(b)
    expect.push(0xF780 + b - 0x80)
  }
  @test.assert_eq(
    decode(bytes_of_ints(high), "x-user-defined"),
    Ok(cps_str(expect)),
  )
  // 边界锚点
  @test.assert_eq(
    decode(bytes_of_ints([0x80]), "x-user-defined"),
    Ok(cp_str(0xF780)),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0xFF]), "x-user-defined"),
    Ok(cp_str(0xF7FF)),
  )
  // 解码永不产生 U+FFFD（表内 128 项全非空）
  @test.assert_eq(
    decode(bytes_of_ints(all_byte_values()), "x-user-defined"),
    Ok(cps_str(all_byte_values_decoded())),
  )
}

///|
/// 0x00..0xFF 全 256 个字节（测试辅助）。
fn all_byte_values() -> Array[Int32] {
  let bs : Array[Int32] = []
  for b in 0..<256 {
    bs.push(b)
  }
  bs
}

///|
/// 0x00..0xFF 全字节经 x-user-defined 解码后的期望码点（0x80 起偏移 PUA）。
fn all_byte_values_decoded() -> Array[Int32] {
  let cps : Array[Int32] = []
  for b in 0..<256 {
    cps.push(if b < 0x80 { b } else { 0xF780 + b - 0x80 })
  }
  cps
}

///|
test "x-user-defined: all 256 bytes round-trip, others are unmappable" {
  // 全 256 字节解码后再编码，逐字节回到原值
  let text = cps_str(all_byte_values_decoded())
  @test.assert_eq(
    encode(text, "x-user-defined"),
    Ok(bytes_of_ints(all_byte_values())),
  )
  // [spec] 只有 ASCII 与 U+F780..U+F7FF 可编码，两侧紧邻的码点都不可编码
  @test.assert_eq(
    encode(cp_str(0xF77F), "x-user-defined"),
    Err(EncodingError::Unmappable(0xF77F, 0)),
  )
  @test.assert_eq(
    encode(cp_str(0xF800), "x-user-defined"),
    Err(EncodingError::Unmappable(0xF800, 0)),
  )
  @test.assert_eq(
    encode(cps_str([0x61, 0x4E2D]), "x-user-defined"),
    Err(EncodingError::Unmappable(0x4E2D, 1)),
  )
  // label 唯一且大小写不敏感
  @test.assert_eq(label_to_encoding("x-user-defined"), Ok("x-user-defined"))
  @test.assert_eq(label_to_encoding("X-USER-DEFINED"), Ok("x-user-defined"))
}

///|
test "x-user-defined: streaming is stateless, chunking never changes the result" {
  let input = bytes_of_ints(all_byte_values())
  let whole = match decode(input, "x-user-defined") {
    Ok(s) => s
    Err(e) => abort(@debug.to_string(e))
  }
  let n = input.length()
  for split in 0..<(n + 1) {
    let d = match Decoder::new("x-user-defined") {
      Ok(d) => d
      Err(e) => abort(@debug.to_string(e))
    }
    let got = d.consume(slice_bytes(input, 0, split)) +
      d.consume(slice_bytes(input, split, n)) +
      d.finish()
    @test.assert_eq(got, whole)
  }
  // replacement 的"只报一次"状态同样跨块：逐字节喂入也只得到 1 个 U+FFFD，
  // 且从第二个字节起整体结束
  let d = match Decoder::new("replacement") {
    Ok(d) => d
    Err(e) => abort(@debug.to_string(e))
  }
  let mut acc = ""
  for i in 0..<n {
    acc = acc + d.consume(slice_bytes(input, i, i + 1))
  }
  @test.assert_eq(acc, replacement_str())
  @test.assert_eq(d.finish(), "")
}
