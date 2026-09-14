///|
let metadata : String =
  #|{"format-version":2,"table-uuid":"demo","location":"memory://table","last-sequence-number":2,"current-schema-id":0,"schemas":[{"schema-id":0,"type":"struct","fields":[{"id":1,"name":"id","required":true,"type":"long"}]}],"default-spec-id":0,"partition-specs":[{"spec-id":0,"fields":[]}],"current-snapshot-id":9007199254740993,"snapshots":[{"snapshot-id":9007199254740993,"sequence-number":2,"timestamp-ms":1000,"manifest-list":"memory://list.avro","summary":{"operation":"append"}}],"refs":{"main":{"snapshot-id":9007199254740993,"type":"branch"}}}

///|
test "snapshot IDs survive the JavaScript safe-integer boundary" {
  let table = @moonice.parse_metadata(metadata)
  assert_eq(table.snapshot().id, 9007199254740993L)
  assert_eq(table.snapshot(ref_name="main").id, 9007199254740993L)
  assert_eq(table.schema(0).field_named("id").id, 1)
}

///|
test "missing reference is a typed failure" {
  let table = @moonice.parse_metadata(metadata)
  try table.snapshot(ref_name="absent") catch {
    @moonice.Invalid(code, _, _) => assert_eq(code, "REF_NOT_FOUND")
  } noraise {
    _ => fail("Expected an error")
  }
}

///|
test "unsupported metadata version is rejected" {
  try @moonice.parse_metadata("{\"format-version\":3}") catch {
    @moonice.Invalid(code, _, _) => assert_eq(code, "UNSUPPORTED_VERSION")
  } noraise {
    _ => fail("Expected an error")
  }
}

///|
test "invalid JSON is rejected" {
  try @moonice.parse_metadata("{") catch {
    @moonice.Invalid(code, _, _) => assert_eq(code, "INVALID_JSON")
  } noraise {
    _ => fail("Expected an error")
  }
}
