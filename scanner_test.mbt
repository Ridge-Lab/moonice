///|
test "position and nullable equality deletes apply before filters" {
  let bundle = @moonice.open_bundle(delete_bundle)
  let result = bundle.scan(All)
  let ids = result.rows.map(row => row.values[1])
  assert_eq(result.read_rows, 5)
  assert_eq(result.deleted_rows, 3)
  assert_eq(result.matched_rows, 2)
  assert_true(ids.contains(Integer(2L)))
  assert_true(ids.contains(Integer(4L)))
  let filtered = bundle.scan(Compare(1, Eq, Integer(2L)))
  assert_eq(filtered.rows.length(), 1)
  assert_eq(filtered.rows[0].values[2], Text("new"))
}

///|
test "all historical scans match PyIceberg row values by selected schema" {
  let bundle = @moonice.open_bundle(reference_bundle)
  guard @json.parse(reference_bundle)
    is { "reference": { "cases": Array(cases), .. }, .. } else {
    fail("Missing oracle")
  }
  for item in cases {
    guard item
      is {
        "snapshot_id": String(id),
        "filter": String(label),
        "rows": Array(expected),
        ..
      } else {
      fail("Bad oracle")
    }
    let snapshot_id : Int64 = @json.from_json(Json::string(id))
    let predicate : @moonice.Predicate = if label == "all" {
      All
    } else {
      Compare(1, Ge, Integer(10L))
    }
    let result = bundle.scan(predicate, snapshot_id~)
    assert_eq(result.rows.length(), expected.length())
    for row in result.rows {
      let id = row.values[1]
      let found = expected
        .iter()
        .find_first(j => {
          match j {
            { "id": Number(n, ..), .. } => id == Integer(n.to_int64())
            _ => false
          }
        })
      guard found is Some(j) else { fail("Unexpected data row") }
      let projection = row.project(result.schema)
      for field in result.schema.fields {
        guard j is Object(values) else { fail("Bad row") }
        let expected_value = values.get(field.name).unwrap_or(Json::null())
        let actual = projection[field.name]
        match expected_value {
          Null => assert_eq(actual, Missing)
          String(s) => assert_eq(actual, Text(s))
          Number(n, ..) => assert_eq(actual, Integer(n.to_int64()))
          _ => fail("Unsupported oracle value")
        }
      }
    }
  }
}

///|
test "limit reports truncation without changing delete or match counters" {
  let bundle = @moonice.open_bundle(delete_bundle)
  let result = bundle.scan(All, limit=1)
  assert_eq(result.rows.length(), 1)
  assert_eq(result.deleted_rows, 3)
  assert_eq(result.matched_rows, 2)
  assert_true(result.truncated)
}

///|
test "missing applicable delete file fails instead of resurrecting rows" {
  let bundle = @moonice.open_bundle(delete_bundle)
  bundle.files.remove("memory://moonice-deletes/equality.parquet")
  try bundle.scan(All) catch {
    @moonice.Invalid(code, _, _) => assert_eq(code, "MISSING_FILE")
  } noraise {
    _ => fail("Must not silently ignore a delete file")
  }
}
