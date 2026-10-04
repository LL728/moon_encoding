// single_byte_wbtest.mbt
//
// 单字节引擎与 windows-1252 生成表的白盒测试：
// 表不变量、规范已知映射、以及 256 字节全量双向往返。

///|
/// 从 Int 数组构造 Bytes（测试辅助）。
fn bytes_of_ints(arr : Array[Int]) -> Bytes {
  let bytes : Array[Byte] = []
  for i in 0..<arr.length() {
    bytes.push(arr[i].to_byte())
  }
  Bytes::from_array(bytes.exact_view())
}

///|
/// 取 [lo, hi) 字节切片（测试辅助，流式切分用）。
fn slice_bytes(input : Bytes, lo : Int, hi : Int) -> Bytes {
  let bytes : Array[Byte] = []
  for i in lo..<hi {
    bytes.push(input[i])
  }
  Bytes::from_array(bytes.exact_view())
}

///|
test "windows-1252 decode table: 128 entries, all valid non-surrogate code points" {
  @test.assert_eq(windows_1252_decode.length(), 128)
  for i in 0..<128 {
    let cp = windows_1252_decode[i]
    // 规范数据不含解码错误位（-1），也不含代理区码点
    @test.assert_eq(cp >= 0, true)
    @test.assert_eq(cp <= 0x10FFFF, true)
    @test.assert_eq(cp < 0xD800 || cp > 0xDFFF, true)
  }
}

///|
test "windows-1252 encode table: 128 sorted unique pairs with high bytes" {
  @test.assert_eq(windows_1252_encode.length(), 256)
  let mut prev = -1
  for i in 0..<128 {
    let cp = windows_1252_encode[i * 2]
    let byte = windows_1252_encode[i * 2 + 1]
    @test.assert_eq(cp > prev, true) // 严格升序，保证二分查找唯一命中
    @test.assert_eq(byte >= 0x80, true) // 只存高位字节，ASCII 直通不进表
    @test.assert_eq(byte <= 0xFF, true)
    prev = cp
  }
}

///|
test "windows-1252: known mappings from the spec index" {
  @test.assert_eq(single_byte_decode_byte(windows_1252_decode, 0x41), 0x41) // 'A' ASCII 直通
  @test.assert_eq(single_byte_decode_byte(windows_1252_decode, 0x80), 0x20AC) // €
  @test.assert_eq(single_byte_decode_byte(windows_1252_decode, 0x93), 0x201C) // "
  @test.assert_eq(single_byte_decode_byte(windows_1252_decode, 0xA9), 0x00A9) // ©
  @test.assert_eq(single_byte_decode_byte(windows_1252_decode, 0x9F), 0x0178) // Ÿ
  @test.assert_eq(single_byte_decode_byte(windows_1252_decode, 0xFF), 0x00FF) // ÿ
  // WHATWG 把 5 个「未定义」字节定义为 C1 控制符（Python cp1252 在这些字节上
  // 直接报错）——与 Python 的差分测试把这 5 个字节记录为已知差异集。
  @test.assert_eq(single_byte_decode_byte(windows_1252_decode, 0x81), 0x0081)
  @test.assert_eq(single_byte_decode_byte(windows_1252_decode, 0x8D), 0x008D)
  @test.assert_eq(single_byte_decode_byte(windows_1252_decode, 0x8F), 0x008F)
  @test.assert_eq(single_byte_decode_byte(windows_1252_decode, 0x90), 0x0090)
  @test.assert_eq(single_byte_decode_byte(windows_1252_decode, 0x9D), 0x009D)
}

///|
test "windows-1252: reverse lookup finds known code points and rejects others" {
  @test.assert_eq(rev_lookup(windows_1252_encode, 0x20AC), 0x80) // €
  @test.assert_eq(rev_lookup(windows_1252_encode, 0x00E9), 0xE9) // é
  @test.assert_eq(rev_lookup(windows_1252_encode, 0x0178), 0x9F) // Ÿ 在 0x9F
  @test.assert_eq(rev_lookup(windows_1252_encode, 0x4E2D), -1) // 中：不在表内
  @test.assert_eq(rev_lookup(windows_1252_encode, 0x0081), 0x81) // C1 也可编码回去
}

///|
test "windows-1252: decode->encode round-trips every byte value 0x00..0xFF" {
  for byte in 0..<256 {
    let decoded = single_byte_decode(windows_1252_decode, bytes_of_ints([byte]))
    match single_byte_encode(windows_1252_encode, decoded) {
      Ok(out) => {
        @test.assert_eq(out.length(), 1)
        @test.assert_eq(out[0].to_int(), byte)
      }
      Err(e) =>
        abort("byte 0x\{byte} did not round-trip: " + @debug.to_string(e))
    }
  }
}

///|
test "windows-1252: encode->decode round-trips every encodable code point" {
  for i in 0..<128 {
    let cp = windows_1252_encode[i * 2]
    let expected_byte = windows_1252_encode[i * 2 + 1]
    let text = String::from_iter([cp.unsafe_to_char()].iter())
    match single_byte_encode(windows_1252_encode, text) {
      Ok(out) => {
        @test.assert_eq(out.length(), 1)
        @test.assert_eq(out[0].to_int(), expected_byte)
        @test.assert_eq(single_byte_decode(windows_1252_decode, out), text)
      }
      Err(e) =>
        abort("code point 0x\{cp} did not encode: " + @debug.to_string(e))
    }
  }
}

// ---------------------------------------------------------------------------
// F2：全部 28 种单字节编码的公共不变量（编码集由生成器自动发现）。

///|
test "all single-byte encodings: dispatch resolves every generated name" {
  @test.assert_eq(single_byte_names.length(), 28)
  for k in 0..<single_byte_names.length() {
    let name = single_byte_names[k]
    match single_byte_tables(name) {
      Some((decode_table, encode_table)) => {
        // 解码表 128 项；每项是合法非代理码点或 -1（规范 index null）
        @test.assert_eq(decode_table.length(), 128)
        for i in 0..<128 {
          let cp = decode_table[i]
          @test.assert_eq(
            cp == -1 ||
            (cp >= 0 && cp <= 0x10FFFF && (cp < 0xD800 || cp > 0xDFFF)),
            true,
          )
        }
        // 编码表：成对、码点严格升序（保证二分唯一命中）、字节只含高位区
        @test.assert_eq(encode_table.length() % 2, 0)
        let mut prev = -1
        for i in 0..<(encode_table.length() / 2) {
          let cp = encode_table[i * 2]
          let byte = encode_table[i * 2 + 1]
          @test.assert_eq(cp > prev, true)
          @test.assert_eq(byte >= 0x80 && byte <= 0xFF, true)
          prev = cp
        }
      }
      None => abort("dispatch missing for " + name)
    }
  }
}

///|
test "all single-byte encodings: rev_lookup agrees with every encode-table entry" {
  for k in 0..<single_byte_names.length() {
    let name = single_byte_names[k]
    match single_byte_tables(name) {
      Some((_, encode_table)) =>
        for i in 0..<(encode_table.length() / 2) {
          @test.assert_eq(
            rev_lookup(encode_table, encode_table[i * 2]),
            encode_table[i * 2 + 1],
          )
        }
      None => abort("dispatch missing for " + name)
    }
  }
}

///|
test "all single-byte encodings: decode-error bytes output U+FFFD (replacement)" {
  // 28 张表共 150 个 index null 位（ISO-8859-8/-8-I 共用同一索引各计一次），
  // 这些位置是 replacement 语义的真实覆盖。
  let replacement_cp : Int = 0xFFFD
  let replacement = String::from_iter([replacement_cp.unsafe_to_char()].iter())
  let mut error_bytes = 0
  for k in 0..<single_byte_names.length() {
    let name = single_byte_names[k]
    match single_byte_tables(name) {
      Some((decode_table, _)) =>
        for i in 0..<128 {
          if decode_table[i] == -1 {
            error_bytes += 1
            @test.assert_eq(
              decode(bytes_of_ints([i + 0x80]), name),
              Ok(replacement),
            )
          }
        }
      None => abort("dispatch missing for " + name)
    }
  }
  @test.assert_eq(error_bytes, 150)
}

///|
test "all single-byte encodings: round-trips for every table entry" {
  for k in 0..<single_byte_names.length() {
    let name = single_byte_names[k]
    match single_byte_tables(name) {
      Some((decode_table, encode_table)) => {
        // 解码表每个非错误字节 -> 文本 -> 编码必须还原同一字节
        //（生成器断言过码点无重复，因此反向表命中唯一）
        for i in 0..<128 {
          if decode_table[i] != -1 {
            let byte = i + 0x80
            let text = single_byte_decode(decode_table, bytes_of_ints([byte]))
            match single_byte_encode(encode_table, text) {
              Ok(out) => {
                @test.assert_eq(out.length(), 1)
                @test.assert_eq(out[0].to_int(), byte)
              }
              Err(e) =>
                abort(
                  name + " round-trip encode failed: " + @debug.to_string(e),
                )
            }
          }
        }
        // 编码表每个码点 -> 字节 -> 解码必须还原同一码点
        for i in 0..<(encode_table.length() / 2) {
          let cp = encode_table[i * 2]
          let text = String::from_iter([cp.unsafe_to_char()].iter())
          match single_byte_encode(encode_table, text) {
            Ok(out) =>
              @test.assert_eq(single_byte_decode(decode_table, out), text)
            Err(e) => abort(name + " encode failed: " + @debug.to_string(e))
          }
        }
      }
      None => abort("dispatch missing for " + name)
    }
  }
}
