///|
test "sequence inheritance applies only to newly added entries" {
  assert_eq(inherited_sequence(@avro_codec.Null, 1, 7L, "seq"), 7L)
  assert_eq(inherited_sequence(@avro_codec.Long(3L), 0, 7L, "seq"), 3L)
  for status in [0, 2] {
    try inherited_sequence(@avro_codec.Null, status, 7L, "seq") catch {
      Invalid(code, _, _) => assert_eq(code, "MISSING_SEQUENCE")
    } noraise {
      _ => fail("Null sequence must be rejected")
    }
  }
}

///|
test "Avro logical maps retain exact integer values" {
  let d = @avro_codec.Array([
    @avro_codec.Record([
      ("key", @avro_codec.Int(1)),
      ("value", @avro_codec.Long(9007199254740993L)),
    ]),
  ])
  assert_eq(count_metrics(d, "metrics").get(1), Some(9007199254740993L))
}

///|
test "invalid containers and byte length mismatches fail explicitly" {
  try decode_manifest_list(b"invalid") catch {
    Invalid(code, _, _) => assert_eq(code, "INVALID_AVRO")
  } noraise {
    _ => fail("Expected error")
  }
  let manifest : Manifest = {
    path: "x",
    length: 20L,
    spec_id: 0,
    content: 0,
    sequence_number: 1L,
    min_sequence_number: 1L,
    added_snapshot_id: 1L,
  }
  try decode_manifest(b"x", manifest) catch {
    Invalid(code, _, _) => assert_eq(code, "MANIFEST_LENGTH_MISMATCH")
  } noraise {
    _ => fail("Expected error")
  }
}
