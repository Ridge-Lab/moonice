///|
fn test_footer_object(fields : Map[Int32, FooterValue]) -> FooterValue {
  Obj(fields, b"")
}

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
  let column : FooterValue = test_footer_object(
    Map([(3, test_footer_object(Map([(5, Num(100000L))])))]),
  )
  let group : FooterValue = test_footer_object(
    Map([(1, Seq([column])), (3, Num(1L))]),
  )
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
  try visit_avro_blocks(encoder.to_bytes(), 0, sync, "memory://limits") catch {
    Invalid(code, _, _) => assert_eq(code, "RESOURCE_LIMIT")
  } noraise {
    _ => fail("Cumulative OCF record budget was ignored")
  }
}

///|
test "OCF decoded byte budget spans blocks and accepts its exact boundary" {
  // fastavro 1.12.2 wrote two single-datum blocks with an Avro long each.
  let sync = b"0123456789abcdef"
  let magic = b"Obj\x01\x04\x14avro.codec"
  let schema = b"\x16avro.schema\x0c\"long\"\x00"
  for
    (codec, first, second) in [
      (b"\x08null", b"\x02\x02\x0e", b"\x02\x02\x10"),
      (
        b"\x0edeflate", b"\x02\x0c\xe3\x03\x00\x00\x0f\x00", b"\x02\x0c\x13\x00\x00\x00\x11\x00",
      ),
    ] {
    let file = magic + codec + schema + sync + first + sync + second + sync
    fn long(d : @avro_codec.Datum) -> Int64 raise IceError {
      avro_long(d, "long")
    }
    assert_eq(map_container(file, "test", long, decoded_budget=2), [7L, 8L])
    try map_container(file, "test", long, decoded_budget=1) catch {
      Invalid(code, _, _) => assert_eq(code, "RESOURCE_LIMIT")
    } noraise {
      _ =>
        fail("Second block was allowed to exceed the remaining decoded bytes")
    }
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
    let meta : FooterValue = test_footer_object(
      Map([
        (4, Num(1L)),
        (5, Num(1L)),
        (6, Num((bytes.length() - 4).to_int64())),
        (7, Num((bytes.length() - 4).to_int64())),
        (9, Num(4L)),
      ]),
    )
    let group : FooterValue = test_footer_object(
      Map([(1, Seq([test_footer_object(Map([(3, meta)]))])), (3, Num(1L))]),
    )
    let fields : Map[Int32, FooterValue] = Map([(3, Num(1L)), (4, Seq([group]))])
    try validate_parquet_layout(fields, bytes, bytes.length(), 1) catch {
      Invalid(code, _, _) => assert_eq(code, "RESOURCE_LIMIT")
    } noraise {
      _ => fail("Page allocation budget was ignored")
    }
  }
}

///|
test "explicit IDs and identity partition values take precedence over legacy aliases" {
  let root = test_footer_object(Map([(4, Blob(b"root")), (5, Num(2L))]))
  fn leaf(name : Bytes, id : Int64?) -> FooterValue {
    let field = Map([(1, Num(2L)), (3, Num(1L)), (4, Blob(name))])
    if id is Some(n) {
      field[9] = Num(n)
    }
    test_footer_object(field)
  }
  let wanted = Map([(7, true)])
  let names = Map([("old", 7)])
  let (_, chosen) = projection_leaves(
    [root, leaf(b"old", None), leaf(b"new", Some(7L))],
    wanted,
    names,
    Map([]),
  )
  assert_eq(chosen.map(c => c.ordinal), [1])
  let idless = [root, leaf(b"old", None), leaf(b"unmapped", None)]
  let (_, mapped) = projection_leaves(idless, wanted, names, Map([]))
  assert_eq(mapped.map(c => c.ordinal), [0])
  let (_, from_partition) = projection_leaves(
    idless,
    wanted,
    names,
    Map([(7, true)]),
  )
  assert_true(from_partition.is_empty())
}
