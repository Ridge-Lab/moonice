///|
test "real Parquet values survive field rename and added columns null-fill" {
  let bundle = @moonice.open_bundle(reference_bundle)
  let state = bundle.load_snapshot()
  let values = []
  for entry in state.entries {
    for
      row in @moonice.read_data_rows(
        bundle.read_file(entry.file.path),
        entry.file,
      ) {
      let projected = row.project(state.schema)
      assert_eq(projected.get("note"), Some(Missing))
      if row.values.get(1) == Some(Integer(1L)) {
        assert_eq(projected.get("region"), Some(Text("北京")))
      }
      values.push(row.values[1])
    }
  }
  assert_eq(values.length(), 4)
  assert_false(values.contains(Integer(2L)))
}

///|
test "truncated and non-Parquet input reports a typed error" {
  for bytes in [b"", b"PAR1", b"PAR1xxxxPAR1"] {
    try @moonice.parquet_field_ids(bytes) catch {
      @moonice.Invalid(_, _, _) => ()
    } noraise {
      _ => fail("Malformed footer must fail")
    }
  }
}
