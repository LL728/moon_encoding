// single_byte.mbt
//
// 28 种 legacy 单字节编码共用的表驱动引擎（F1 先接 windows-1252）。
// 解码表：下标 = 字节 - 0x80，表值 = 码点，-1 表规范 index null（解码错误）。
// 编码表：(码点, 字节) 按码点升序的扁平对，供二分查找。

///|
/// 解码一个字节：0x00..0x7F 是 ASCII 直通；0x80..0xFF 查表，
/// 表值 -1 按规范 replacement 模式输出 U+FFFD。
fn single_byte_decode_byte(decode_table : Array[Int], b : Int) -> Int {
  if b < 0x80 {
    b
  } else {
    let cp = decode_table[b - 0x80]
    if cp < 0 {
      0xFFFD
    } else {
      cp
    }
  }
}

///|
/// 解码一段字节。单字节编码没有跨块状态，任意切分结果都与整段一致。
fn single_byte_decode(decode_table : Array[Int], input : Bytes) -> String {
  let chars : Array[Char] = []
  for i in 0..<input.length() {
    let cp = single_byte_decode_byte(decode_table, input[i].to_int())
    // cp 只会是 ASCII、WHATWG 表内合法码点（规范数据不含代理区）或 0xFFFD，
    // 构造上恒为合法标量，故用 unsafe_to_char 免去 Option 分支。
    chars.push(cp.unsafe_to_char())
  }
  String::from_iter(chars.iter())
}

///|
/// 在 (码点, 字节) 扁平有序表上二分查找码点，返回字节；找不到返回 -1。
fn rev_lookup(encode_table : Array[Int], cp : Int) -> Int {
  let mut lo = 0
  let mut hi = encode_table.length() / 2 - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let c = encode_table[mid * 2]
    if c == cp {
      return encode_table[mid * 2 + 1]
    }
    if c < cp {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  -1
}

///|
/// 编码文本为字节：ASCII 直通，高位码点走二分表。
/// 找不到映射即规范 fatal 模式（`encode or fail`）的错误，
/// 返回不可映射的码点与它在输入中的字符位置。
fn single_byte_encode(
  encode_table : Array[Int],
  text : String,
) -> Result[Bytes, EncodingError] {
  let out : Array[Byte] = []
  let mut index = 0
  for c in text {
    let cp = c.to_int()
    let b = if cp < 0x80 { cp } else { rev_lookup(encode_table, cp) }
    if b < 0 {
      return Err(EncodingError::Unmappable(cp, index))
    }
    out.push(b.to_byte())
    index += 1
  }
  Ok(Bytes::from_array(out.exact_view()))
}
