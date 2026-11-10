///|
test "compact field IDs cannot wrap into a valid ID" {
  // Explicit field ID 4294967297, zigzag encoded; truncating it produces 1.
  let reader = FooterReader::{
    bytes: b"\x05\x82\x80\x80\x80\x20\x00\x00",
    offset: 0,
    nodes: 0,
  }
  try reader.value(12, 0) catch {
    Invalid(code, _, _) => assert_eq(code, "INVALID_PARQUET")
  } noraise {
    _ => fail("Oversized Thrift field ID was accepted after narrowing")
  }
}

///|
test "Parquet budgets reject inconsistent counts before decoding pages" {
  let column : FooterValue = Obj(Map([(3, Obj(Map([(5, Num(100000L))])))]))
  let group : FooterValue = Obj(Map([(1, Seq([column])), (3, Num(1L))]))
  let fields : Map[Int32, FooterValue] = Map([(3, Num(1L)), (4, Seq([group]))])
  try validate_parquet_layout(fields, b"PAR1", 4, 1) catch {
    Invalid(code, _, _) => assert_eq(code, "PARQUET_SHAPE")
  } noraise {
    _ => fail("Inconsistent column count reached page decoder")
  }
  fields[3] = Num(100000L)
  try validate_parquet_layout(fields, b"PAR1", 4, 51) catch {
    Invalid(code, _, _) => assert_eq(code, "RESOURCE_LIMIT")
  } noraise {
    _ => fail("Materialized cell budget was ignored")
  }
}

///|
test "Avro total block budget is checked without allocating records" {
  let encoder = @avro_codec.Encoder::new()
  let sync = b"0123456789abcdef"
  // Only 220 bytes: zero-width records can claim 1.1 million materializations.
  for _ in 0..<11 {
    encoder.write_long(100000L)
    encoder.write_long(0L)
    encoder.write_raw(sync[:])
  }
  try
    preflight_avro_blocks(encoder.to_bytes(), 0, sync, "memory://limits")
  catch {
    Invalid(code, _, _) => assert_eq(code, "RESOURCE_LIMIT")
  } noraise {
    _ => fail("Cumulative OCF record budget was ignored")
  }
}

///|
test "Parquet page counts and expansion limits are enforced before allocation" {
  for pair in [(100001L, 0L), (1L, 67108865L)] {
    let (count, expanded) = pair
    let encoder = @avro_codec.Encoder::new()
    encoder.write_raw(b"PAR1")
    // Compact PageHeader, DATA_PAGE, no payload; i32 and Avro long both zigzag.
    encoder.write_byte(0x15)
    encoder.write_long(0L)
    encoder.write_byte(0x15)
    encoder.write_long(expanded)
    encoder.write_byte(0x15)
    encoder.write_long(0L)
    encoder.write_byte(0x2c)
    encoder.write_byte(0x15)
    encoder.write_long(count)
    encoder.write_byte(0x00)
    encoder.write_byte(0x00)
    let bytes = encoder.to_bytes()
    let meta : FooterValue = Obj(
      Map([
        (4, Num(1L)),
        (5, Num(1L)),
        (6, Num((bytes.length() - 4).to_int64())),
        (7, Num((bytes.length() - 4).to_int64())),
        (9, Num(4L)),
      ]),
    )
    let group : FooterValue = Obj(
      Map([(1, Seq([Obj(Map([(3, meta)]))])), (3, Num(1L))]),
    )
    let fields : Map[Int32, FooterValue] = Map([(3, Num(1L)), (4, Seq([group]))])
    try validate_parquet_layout(fields, bytes, bytes.length(), 1) catch {
      Invalid(code, _, _) => assert_eq(code, "RESOURCE_LIMIT")
    } noraise {
      _ => fail("Page allocation budget was ignored")
    }
  }
}
