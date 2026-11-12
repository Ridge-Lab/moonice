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

///|
test "equality deletes and residuals see identity values absent from Parquet" {
  let bundle = @moonice.open_bundle(delete_bundle)
  let state = bundle.load_snapshot()
  let identity : @moonice.PartitionSpec = {
    id: 1,
    fields: [
      { source_id: 2, field_id: 1000, name: "area", transform: "identity", },
    ],
  }
  let metadata = {
    ..bundle.metadata,
    partition_specs: [..bundle.metadata.partition_specs, identity],
  }
  guard state.entries.iter().find_first(e => e.file.content == 1)
    is Some(source) &&
    state.entries.iter().find_first(e => e.file.content == 2) is Some(deletion) else {
    fail("Missing fixture")
  }
  // Reuse a real Parquet file whose physical IDs do not include category (2).
  // The existing global equality-delete file contains the keys "b" and null.
  let schema : @moonice.Schema = { id: 0, fields: [state.schema.fields[1]], }
  let cases : Array[(@moonice.Scalar, Int32)] = [
    (Text("b"), 1),
    (Missing, 1),
    (Text("c"), 0),
  ]
  for (value, deleted) in cases {
    let entry = {
      ..source,
      spec_id: 1,
      sequence_number: 1L,
      file: { ..source.file, content: 0, partition: Map([("area", value)]), },
    }
    let scan = @moonice.scan_rows(
      metadata,
      { ..state, schema, entries: [entry, deletion], },
      if deleted == 0 {
        Compare(2, Eq, Text("c"))
      } else {
        All
      },
      p => bundle.read_file(p),
    )
    assert_eq(scan.deleted_rows, deleted)
    assert_eq(scan.matched_rows, 1 - deleted)
    if deleted == 0 {
      assert_eq(scan.rows[0].project(schema)["category"], value)
    }
  }
}
