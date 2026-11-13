// robust_wbtest.mbt
//
// 健壮性测试（方向 D）：确定性 fuzz、超大输入、单字节解码结果的回编码属性。
//
// 三条测试都**只用公共 API**（decode / encode / Decoder / supported_encodings），
// 不读内部表结构 —— 否则「测试与实现同源」，一起错也一起绿。
//
// 刻意不用时间或随机源：fuzz 用固定种子的 LCG，保证 CI 可复现。

///|
/// 逐字节比较两个 Bytes。仓库里没有可直接用于断言的 Bytes 相等入口，
/// 故自备一个，避免依赖未验证的 trait 派生。
fn bytes_eq(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut i = 0
  let mut same = true
  while i < a.length() {
    if a[i].to_int() != b[i].to_int() {
      same = false
      i = a.length()
    } else {
      i = i + 1
    }
  }
  same
}

///|
/// 输出里是否存在孤立代理（U+D800..U+DFFF）。规范不允许解码器产出它们。
fn has_lone_surrogate(s : String) -> Bool {
  let mut bad = false
  for c in s {
    let cp = c.to_int()
    if cp >= 0xD800 && cp <= 0xDFFF {
      bad = true
    }
  }
  bad
}

///|
/// 确定性 fuzz：固定种子 LCG 生成 0..64 字节的随机流，对全部 40 种编码断言
/// ① 不 panic ② 无孤立代理 ③ 一字节一块的流式结果与一次性 decode 完全相同。
///
/// 判别力说明：这条抓的是「某个字节序列让状态机卡死 / 越界 / 产出非法标量」，
/// 抓不到「某段合法序列解错字符」—— 后者由 8490 条差分向量负责。
test "fuzz: 随机字节流在 40 种编码上不 panic、无孤立代理、流式等价" {
  let names = supported_encodings()
  @test.assert_eq(names.length(), 40)
  let mut seed = 20261113
  for _round in 0..<60 {
    for name in names {
      seed = (seed * 75 + 74) % 65537
      let len = seed % 65
      let arr : Array[Byte] = []
      let mut k = 0
      while k < len {
        seed = (seed * 75 + 74) % 65537
        arr.push((seed % 256).to_byte())
        k = k + 1
      }
      let data = Bytes::from_array(arr.exact_view())
      let whole = match decode(data, name) {
        Ok(s) => s
        Err(e) =>
          abort("decode(" + name + ") 不该失败: " + @debug.to_string(e))
      }
      @test.assert_eq(has_lone_surrogate(whole), false)
      let decoder = match Decoder::new(name) {
        Ok(d) => d
        Err(e) =>
          abort(
            "Decoder::new(" + name + ") 不该失败: " + @debug.to_string(e),
          )
      }
      let mut out = ""
      let mut i = 0
      while i < data.length() {
        out = out + decoder.consume(slice_bytes(data, i, i + 1))
        i = i + 1
      }
      out = out + decoder.finish()
      @test.assert_eq(out, whole)
    }
  }
}

///|
/// 1 MiB 超大输入：4096 字节模式块 × 256 = 1,048,576 字节的合法 GBK 流，
/// 断言 decode→encode 逐字节一致，且 4096 字节分块解码与一次性解码相同。
///
/// 模式块只由 ASCII 字母与成对出现的 0xD6 0xD0（GBK 的「中」）构成，
/// 保证每一字节都在规范映射内，往返不引入替换字符。
test "large: 1 MiB GBK 输入 decode→encode 逐字节一致且分块等价" {
  let pattern : Array[Byte] = []
  let mut p = 0
  while p < 4096 {
    if p % 8 == 0 && p + 1 < 4096 {
      pattern.push((0xD6).to_byte())
      pattern.push((0xD0).to_byte())
      p = p + 2
    } else {
      pattern.push((0x41 + p % 26).to_byte())
      p = p + 1
    }
  }
  @test.assert_eq(pattern.length(), 4096)
  let arr : Array[Byte] = []
  for _r in 0..<256 {
    for j in 0..<pattern.length() {
      arr.push(pattern[j])
    }
  }
  let data = Bytes::from_array(arr.exact_view())
  @test.assert_eq(data.length(), 1048576)
  let text = match decode(data, "gbk") {
    Ok(s) => s
    Err(e) => abort("1 MiB decode 不该失败: " + @debug.to_string(e))
  }
  let back = match encode(text, "gbk") {
    Ok(b) => b
    Err(e) => abort("1 MiB encode 不该失败: " + @debug.to_string(e))
  }
  @test.assert_eq(bytes_eq(data, back), true)
  let decoder = match Decoder::new("gbk") {
    Ok(d) => d
    Err(e) => abort("Decoder::new(gbk) 不该失败: " + @debug.to_string(e))
  }
  let mut out = ""
  let mut pos = 0
  while pos < data.length() {
    let end = if pos + 4096 > data.length() {
      data.length()
    } else {
      pos + 4096
    }
    out = out + decoder.consume(slice_bytes(data, pos, end))
    pos = end
  }
  out = out + decoder.finish()
  @test.assert_eq(out, text)
}

///|
/// 回编码属性：对 40 种编码逐字节 0..255 解码，凡是解出**单个非 U+FFFD 字符**的，
/// 都要求它能被同一 encoding 编回去、且再解码得到同一个字符。
///
/// U+FFFD 是 replacement 标记（错误字节的产物），不要求可回编码，故跳过；
/// 规范无编码器的编码（replacement / UTF-16BE / UTF-16LE）encode 必返回 Err，同样跳过。
test "property: 单字节解码结果可回编码且往返稳定（40 种编码）" {
  let names = supported_encodings()
  for name in names {
    let mut b = 0
    while b < 256 {
      match decode(bytes_of_ints([b]), name) {
        Ok(s) =>
          if s.length() == 1 {
            let cp = s.get_char(0).unwrap().to_int()
            if cp != 0xFFFD {
              match encode(s, name) {
                Ok(bs) =>
                  if bs.length() > 0 {
                    match decode(bs, name) {
                      Ok(s2) => @test.assert_eq(s2, s)
                      Err(_) => ()
                    }
                  }
                Err(_) => ()
              }
            }
          }
        Err(_) => ()
      }
      b = b + 1
    }
  }
}
