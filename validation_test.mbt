///|
test "misspelled and extraneous filter fields cannot silently change a query" {
  let schema = @moonice.parse_metadata(metadata).schema(0)
  for
    source in [
      "{\"field\":\"id\",\"op\":\">=\",\"value\":\"1\",\"limit\":2}", "{\"field\":\"id\",\"op\":\"is_null\",\"value\":1}",
      "{\"field\":\"id\",\"op\":\"=\",\"vaule\":1}",
    ] {
    try @moonice.parse_predicate(source, schema) catch {
      @moonice.Invalid(code, _, _) => assert_eq(code, "INVALID_FILTER")
    } noraise {
      _ => fail("Invalid query was accepted: \{source}")
    }
  }
}

///|
test "ambiguous partition identities and negative schema IDs fail at metadata load" {
  for
    source in [
      metadata.replace(old="\"schema-id\":0", new="\"schema-id\":-1"),
      metadata.replace(old="\"spec-id\":0", new="\"spec-id\":-1"),
      metadata.replace(
        old="\"spec-id\":0,\"fields\":[]",
        new="\"spec-id\":0,\"fields\":[{\"source-id\":1,\"field-id\":1000,\"name\":\"a\",\"transform\":\"identity\"},{\"source-id\":1,\"field-id\":1000,\"name\":\"b\",\"transform\":\"bucket[16]\"}]",
      ),
    ] {
    try @moonice.parse_metadata(source) catch {
      @moonice.Invalid(code, _, _) =>
        assert_true(code == "INVALID_SCHEMA" || code == "INVALID_SPEC")
    } noraise {
      _ => fail("Ambiguous metadata was accepted")
    }
  }
}
