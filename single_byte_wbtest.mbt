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
      Err(e) => abort("byte 0x\{byte} did not round-trip: \{e}")
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
      Err(e) => abort("code point 0x\{cp} did not encode: \{e}")
    }
  }
}
