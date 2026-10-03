// label_wbtest.mbt
//
// WHATWG label 解析的测试：大小写不敏感匹配、别名归一、错误分支。

///|
test "label: exact match resolves to canonical encoding name" {
  @test.assert_eq(label_to_encoding("windows-1252"), Ok("windows-1252"))
  @test.assert_eq(label_to_encoding("utf-8"), Ok("UTF-8"))
  @test.assert_eq(label_to_encoding("gbk"), Ok("GBK"))
}

///|
test "label: ASCII case-insensitive match" {
  @test.assert_eq(label_to_encoding("WINDOWS-1252"), Ok("windows-1252"))
  @test.assert_eq(label_to_encoding("Windows-1252"), Ok("windows-1252"))
  @test.assert_eq(label_to_encoding("UTF-8"), Ok("UTF-8"))
  @test.assert_eq(label_to_encoding("Utf8"), Ok("UTF-8"))
}

///|
test "label: WHATWG aliases map onto their canonical encoding" {
  // 规范把 iso-8859-1 / latin1 / ascii 系 label 全部归到 windows-1252
  //（数据来自本仓库 vendor 的 encodings.json，非记忆）。
  @test.assert_eq(label_to_encoding("latin1"), Ok("windows-1252"))
  @test.assert_eq(label_to_encoding("iso-8859-1"), Ok("windows-1252"))
  @test.assert_eq(label_to_encoding("ascii"), Ok("windows-1252"))
  @test.assert_eq(label_to_encoding("cp1252"), Ok("windows-1252"))
}

///|
test "label: unknown label is rejected" {
  @test.assert_eq(
    label_to_encoding("not-a-charset"),
    Err(EncodingError::UnknownLabel("not-a-charset")),
  )
  @test.assert_eq(label_to_encoding(""), Err(EncodingError::UnknownLabel("")))
  // 非 ASCII 字符不会被 ASCII 折叠，因此永远匹配不上任何 label
  @test.assert_eq(
    label_to_encoding("ütf-8"),
    Err(EncodingError::UnknownLabel("ütf-8")),
  )
}
