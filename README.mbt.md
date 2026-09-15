# MoonIce API examples

For setup, supported formats and the interactive inspector, see [README.md](README.md).

## Bind predicates to stable field IDs

```mbt check
///|
test "bind a filter using the current column name" {
  let schema : @moonice.Schema = {
    id: 1,
    fields: [
      {
        id: 2,
        name: "region",
        required: false,
        field_type: Json::string("string"),
      },
    ],
  }
  let p = @moonice.parse_predicate(
    "{\"field\":\"region\",\"op\":\"=\",\"value\":\"北京\"}", schema,
  )
  assert_true(p.matches(Map([(2, @moonice.Text("北京"))])))
  assert_false(p.matches(Map([(2, @moonice.Missing)])))
}
```

## Preserve row identity across schema changes

```mbt check
///|
test "renaming preserves field values and new columns null-fill" {
  let row : @moonice.DataRow = {
    file_path: "memory://table/data.parquet",
    position: 0L,
    values: Map([(2, @moonice.Text("北京"))]),
  }
  let schema : @moonice.Schema = {
    id: 1,
    fields: [
      {
        id: 2,
        name: "region",
        required: false,
        field_type: Json::string("string"),
      },
      {
        id: 3,
        name: "note",
        required: false,
        field_type: Json::string("string"),
      },
    ],
  }
  let result = row.project(schema)
  assert_eq(result.get("region"), Some(@moonice.Text("北京")))
  assert_eq(result.get("note"), Some(@moonice.Missing))
}
```

## Integration flow

```mbt nocheck
///|
let metadata = @moonice.parse_metadata(raw_metadata_json)

///|
let state = @moonice.load_snapshot(metadata, path => storage_read(path))

///|
let predicate = @moonice.parse_predicate(filter_json, state.schema)

///|
let plan = @moonice.plan_scan(metadata, state, predicate)

///|
let result = @moonice.scan_rows(metadata, state, predicate, path => {
  storage_read(path)
})
```

`storage_read` is an application-provided `(String) -> Bytes raise @moonice.IceError` callback. It receives original object URIs and does not need directory listing. Core APIs never open sockets or local files themselves. For a complete executable integration using public library APIs and standard file bytes, run `moon run --target js examples/library_read`. See [the source](examples/library_read/main.mbt) and [integration notes](docs/ECOSYSTEM.md#在另一个-moonbit-项目中接入).
