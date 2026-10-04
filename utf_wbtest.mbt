// utf_wbtest.mbt
//
// UTF-8 / UTF-16BE / UTF-16LE 的规范级测试。
// 期望值来源：[spec] = encoding.bs（@ 2c3853e）条文；[CPython] = 独立实现现算
//（本文件所有十六进制期望均经 CPython 复核，未手算）。CPython 一律 strict：
// 非法 UTF-8、孤立代理、奇数长度 UTF-16 都直接报错 → 差分向量自动跳过，
// 这些行为差异由下面的规范单测钉住。

///|
test "UTF-8: valid sequences decode identically to CPython" {
  // [CPython] é=c3a9、中=e4b8ad、😀=f09f9880、U+10FFFF=f48fbfbf
  @test.assert_eq(decode(bytes_of_ints([0x61, 0xC3, 0xA9]), "UTF-8"), Ok("aé"))
  @test.assert_eq(
    decode(bytes_of_ints([0xE4, 0xB8, 0xAD]), "UTF-8"),
    Ok(cp_str(0x4E2D)),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0xF0, 0x9F, 0x98, 0x80]), "UTF-8"),
    Ok(cp_str(0x1F600)),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0xF0, 0x90, 0x80, 0x80]), "UTF-8"),
    Ok(cp_str(0x10000)),
  )
  @test.assert_eq(
    decode(bytes_of_ints([0xF4, 0x8F, 0xBF, 0xBF]), "UTF-8"),
    Ok(cp_str(0x10FFFF)),
  )
}

///|
test "UTF-8: invalid continuation restores the byte (spec)" {
  // [spec] E1 80 41：0x41 不在 [80,BF] → 全状态复位 + 恢复 0x41 + error，
  // 随后 0x41 按新鲜字节输出为 'A'
  //（CPython strict 直接报错 → 差分跳过）
  @test.assert_eq(
    decode(bytes_of_ints([0xE1, 0x80, 0x41]), "UTF-8"),
    Ok(cps_str([0xFFFD, 0x41])),
  )
}

///|
test "UTF-8: overlong and surrogate-range leads are rejected per spec" {
  let rep = replacement_char()
  let rep_str = String::from_iter([rep].iter())
  // [spec] 0xC0/0xC1 是过长两字节头 → 新鲜字节分支的 Otherwise 直接 error：
  // C0 80 → C0 报错（字节被消费）、80 报错 → 两个 U+FFFD
  @test.assert_eq(
    decode(bytes_of_ints([0xC0, 0x80]), "UTF-8"),
    Ok(rep_str + rep_str),
  )
  // [spec] E0 80 80：E0 把下界提到 0xA0，首字节 80 越界 → 复位+恢复 80 报错，
  // 两个 80 都按新鲜字节各自报错 → 三个 U+FFFD
  @test.assert_eq(
    decode(bytes_of_ints([0xE0, 0x80, 0x80]), "UTF-8"),
    Ok(rep_str + rep_str + rep_str),
  )
  // [spec] ED A0 80：ED 把上界压到 0x9F（挡 UTF-16 代理区），A0 越界 → 同样三个
  @test.assert_eq(
    decode(bytes_of_ints([0xED, 0xA0, 0x80]), "UTF-8"),
    Ok(rep_str + rep_str + rep_str),
  )
  // [spec] 0xF5..0xFF 在新鲜字节分支报错
  @test.assert_eq(decode(bytes_of_ints([0xF5]), "UTF-8"), Ok(rep_str))
}

///|
test "UTF-8: truncated sequence at end-of-queue is one U+FFFD (spec)" {
  let rep_str = replacement_str()
  // 挂起 1/2/3 个字节都只报一次
  for pending in [[0xC3], [0xE1, 0x80], [0xF0, 0x9F, 0x98]] {
    match Decoder::new("utf-8") {
      Ok(d) => {
        @test.assert_eq(d.consume(bytes_of_ints(pending)), "")
        @test.assert_eq(d.finish(), rep_str)
      }
      Err(e) => abort(@debug.to_string(e))
    }
  }
}

///|
test "UTF-8: encoder matches CPython byte for byte" {
  // [CPython] 现算：é=c3a9、中=e4b8ad、😀=f09f9880、U+10FFFF=f48fbfbf
  match encode("aé", "UTF-8") {
    Ok(b) => {
      let expect = [0x61, 0xC3, 0xA9]
      @test.assert_eq(b.length(), expect.length())
      for i in 0..<expect.length() {
        @test.assert_eq(b[i].to_int(), expect[i])
      }
    }
    Err(e) => abort(@debug.to_string(e))
  }
  match encode(cp_str(0x1F600), "UTF-8") {
    Ok(b) => {
      let expect = [0xF0, 0x9F, 0x98, 0x80]
      for i in 0..<expect.length() {
        @test.assert_eq(b[i].to_int(), expect[i])
      }
    }
    Err(e) => abort(@debug.to_string(e))
  }
  match encode(cp_str(0x10FFFF), "UTF-8") {
    Ok(b) => {
      let expect = [0xF4, 0x8F, 0xBF, 0xBF]
      for i in 0..<expect.length() {
        @test.assert_eq(b[i].to_int(), expect[i])
      }
    }
    Err(e) => abort(@debug.to_string(e))
  }
  // [spec] NUL 直通
  match encode(cp_str(0x00), "UTF-8") {
    Ok(b) => @test.assert_eq(b[0].to_int(), 0x00)
    Err(e) => abort(@debug.to_string(e))
  }
}

///|
test "UTF-8: label aliases route (utf8 is a WHATWG label)" {
  @test.assert_eq(decode(bytes_of_ints([0xC3, 0xA9]), "utf8"), Ok("é"))
  @test.assert_eq(
    decode(bytes_of_ints([0xC3, 0xA9]), "unicode-1-1-utf-8"),
    Ok("é"),
  )
}

///|
test "UTF-16LE: valid sequences decode identically to CPython" {
  // [CPython] A=4100、😀=3dd800de、BOM+A=fffe4100
  @test.assert_eq(decode(bytes_of_ints([0x41, 0x00]), "UTF-16LE"), Ok("A"))
  @test.assert_eq(
    decode(bytes_of_ints([0x3D, 0xD8, 0x00, 0xDE]), "UTF-16LE"),
    Ok(cp_str(0x1F600)),
  )
  // BOM 不属于解码器算法（本库不做嗅探）→ U+FEFF 作为字符解出；
  // CPython 的 utf-16-le 行为一致
  @test.assert_eq(
    decode(bytes_of_ints([0xFF, 0xFE, 0x41, 0x00]), "UTF-16LE"),
    Ok(cp_str(0xFEFF) + "A"),
  )
}

///|
test "UTF-16LE: unpaired surrogates follow the spec, not CPython (strict errors)" {
  let rep_str = replacement_str()
  // [spec] 孤立低代理 → error（字节已消费）
  @test.assert_eq(decode(bytes_of_ints([0x00, 0xDC]), "UTF-16LE"), Ok(rep_str))
  // [spec] 高代理后跟非低代理 → 恢复**当前码元**两字节 + error：
  // 高代理被消化为一个 U+FFFD，0041 原样重处理成 'A'（字符不丢）
  @test.assert_eq(
    decode(bytes_of_ints([0x00, 0xD8, 0x41, 0x00]), "UTF-16LE"),
    Ok(rep_str + "A"),
  )
  // [spec] 奇数长度：完整对解出 'A'，末尾 0x42 挂起为 lead byte，
  // end-of-queue 时冲刷为一个 U+FFFD
  match Decoder::new("UTF-16LE") {
    Ok(d) => {
      @test.assert_eq(d.consume(bytes_of_ints([0x41, 0x00, 0x42])), "A")
      @test.assert_eq(d.finish(), rep_str)
    }
    Err(e) => abort(@debug.to_string(e))
  }
}

///|
test "UTF-16BE: valid and truncated sequences" {
  // [CPython] A=0041、😀=d83dde00
  @test.assert_eq(decode(bytes_of_ints([0x00, 0x41]), "UTF-16BE"), Ok("A"))
  @test.assert_eq(
    decode(bytes_of_ints([0xD8, 0x3D, 0xDE, 0x00]), "UTF-16BE"),
    Ok(cp_str(0x1F600)),
  )
  // [spec] 奇数长度（CPython strict 报错 → 差分跳过）
  match Decoder::new("UTF-16BE") {
    Ok(d) => {
      @test.assert_eq(d.consume(bytes_of_ints([0x00, 0x41, 0x42])), "A")
      @test.assert_eq(d.finish(), replacement_str())
    }
    Err(e) => abort(@debug.to_string(e))
  }
}

///|
test "UTF-16: the spec defines no encoder (§get an encoder assertion)" {
  // [spec] "Assert: encoding is not replacement or UTF-16BE/LE."
  // —— WHATWG 根本不给 UTF-16 定义编码器，本库如实报未支持
  @test.assert_eq(
    encode("A", "UTF-16LE"),
    Err(EncodingError::UnsupportedEncoding("UTF-16LE")),
  )
  @test.assert_eq(
    encode("A", "UTF-16BE"),
    Err(EncodingError::UnsupportedEncoding("UTF-16BE")),
  )
  // utf-16 是 UTF-16LE 的 label（规范注记：为存量内容保留）
  @test.assert_eq(
    encode("A", "utf-16"),
    Err(EncodingError::UnsupportedEncoding("UTF-16LE")),
  )
}

///|
test "UTF-8 and UTF-16: chunked equals whole at every split position" {
  let cases : Array[(String, Array[Int])] = [
    (
      "UTF-8",
      [
        0x61, 0xC3, 0xA9, 0xE4, 0xB8, 0xAD, 0xF0, 0x9F, 0x98, 0x80, 0xE1, 0x80, 0x41,
        0xC0, 0x80, 0xED, 0xA0, 0x80, 0xF5, 0x80, 0x42,
      ],
    ),
    (
      "UTF-16LE",
      [
        0x41, 0x00, 0x3D, 0xD8, 0x00, 0xDE, 0x00, 0xDC, 0x00, 0xD8, 0x41, 0x00, 0xFF,
        0xFE, 0x42, 0x00, 0x43,
      ],
    ),
    (
      "UTF-16BE",
      [
        0x00, 0x41, 0xD8, 0x3D, 0xDE, 0x00, 0xDC, 0x00, 0xD8, 0x00, 0x41, 0xFE, 0xFF,
        0x00, 0x42, 0x00,
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
    let mut seed = 9091
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
