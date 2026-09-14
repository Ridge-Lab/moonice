///|
test "JSON API returns useful typed errors and exact snapshot IDs" {
  guard @json.parse(
      @moonice.run_request(reference_bundle, "{\"action\":\"inspect\"}"),
    )
    is { "ok": True, "result": { "snapshots": Array(snapshots), .. }, .. } else {
    fail("Expected inspect result")
  }
  guard snapshots[0] is { "id": String(_), .. } else {
    fail("Snapshot ID must remain a string")
  }
  guard @json.parse(
      @moonice.run_request(
        reference_bundle, "{\"action\":\"scan\",\"filter\":{\"field\":\"missing\",\"op\":\"is_null\"}}",
      ),
    )
    is { "ok": False, "error": { "code": String("FIELD_NOT_FOUND"), .. }, .. } else {
    fail("Expected typed filter error")
  }
  guard @json.parse(
      @moonice.run_request(delete_bundle, "{\"action\":\"scan\"}"),
    )
    is {
      "ok": True,
      "result": { "scan": { "matched_rows": Number(2, ..), .. }, .. },
      ..
    } else {
    fail("Expected two surviving rows")
  }
}
