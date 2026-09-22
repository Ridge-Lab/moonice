///|
test "independent compressed dictionary and multiple-row-group parquet files" {
  guard @json.parse(codec_reference) is Array(cases) else {
    fail("Missing codec oracle")
  }
  for item in cases {
    guard item
      is {
        "codec": String(codec),
        "bytes": String(encoded),
        "length": Number(length, ..),
        ..
      } else {
      fail("Bad codec oracle")
    }
    let file : @moonice.DataFile = {
      content: 0,
      path: codec + ".parquet",
      format: "PARQUET",
      partition: Map([]),
      record_count: 4L,
      size_bytes: length.to_int64(),
      lower_bounds: Map([]),
      upper_bounds: Map([]),
      null_counts: Map([]),
      nan_counts: Map([]),
      equality_ids: [],
    }
    let bytes = @base64.decode(encoded)
    if codec == "gzip" || codec == "zstd" {
      try @moonice.read_data_rows(bytes, file) catch {
        @moonice.Invalid(code, path, message) => {
          assert_eq(code, "PARQUET_DECODE")
          assert_eq(path, file.path)
          assert_true(message.contains("Unsupported parquet codec"))
        }
      } noraise {
        _ => fail("Update the compatibility matrix when a new codec works")
      }
      continue
    }
    let rows = @moonice.read_data_rows(bytes, file)
    assert_eq(rows.length(), 4)
    assert_eq(rows[0].values[1], Integer(-1L))
    assert_eq(rows[1].values[1], Integer(9007199254740993L))
    assert_eq(rows[2].values[2], Missing)
    assert_eq(rows[3].values[2], Text("repeat"))
    assert_eq(rows[3].position, 3L)
  }
}
