///|
test "partition transforms match independent PyIceberg vectors" {
  guard @json.parse(partition_reference) is Array(cases) else {
    fail("Missing oracle")
  }
  for item in cases {
    guard item
      is {
        "type": String(kind),
        "transform": String(transform),
        "input": input,
        "expected": expected,
        ..
      } else {
      fail("Bad oracle")
    }
    let value : @moonice.Scalar = match (kind, input) {
      (_, Null) => Missing
      ("string", String(s)) => Text(s)
      (_, _) => Integer(@json.from_json(input))
    }
    guard @moonice.transform_partition(value, Json::string(kind), transform)
      is Some(actual) else {
      fail("Unsupported reference case: \{item.stringify()}")
    }
    assert_eq(actual.display_json(), expected)
  }
}

///|
test "unknown transforms and integer underflow never become pruning proofs" {
  assert_eq(
    @moonice.transform_partition(
      Integer(-9223372036854775808L),
      Json::string("long"),
      "truncate[10]",
    ),
    None,
  )
  assert_eq(
    @moonice.transform_partition(
      Integer(-2147483648L),
      Json::string("int"),
      "truncate[10]",
    ),
    None,
  )
  for
    transform in ["unknown", "bucket[0]", "truncate[-1]", "bucket[2147483648]"] {
    assert_eq(
      @moonice.transform_partition(Missing, Json::string("long"), transform),
      None,
    )
  }
  assert_eq(
    @moonice.transform_partition(Missing, Json::string("date"), "hour"),
    None,
  )
  assert_eq(
    @moonice.transform_partition(
      Binary(b"abcde"),
      Json::string("binary"),
      "truncate[3]",
    ),
    Some(Binary(b"abc")),
  )
}

///|
test "partition evolution and snappy rows match an actual PyIceberg table" {
  let bundle = @moonice.open_bundle(partitioned_bundle)
  let state = bundle.load_snapshot()
  assert_eq(bundle.metadata.partition_specs.length(), 2)
  assert_eq(state.entries.map(e => e.spec_id).iter().collect().length(), 6)
  guard @json.parse(partitioned_bundle)
    is { "reference": { "cases": Array(cases), .. }, .. } else {
    fail("Missing oracle")
  }
  for item in cases {
    guard item
      is { "predicate": filter, "ids": Array(ids), "files": Array(files), .. } else {
      fail("Bad oracle")
    }
    let p = @moonice.parse_predicate(filter.stringify(), state.schema)
    let plan = @moonice.plan_scan(bundle.metadata, state, p)
    let kept = plan.decisions.filter(d => d.kept).map(d => d.entry.file.path)
    // Conservative planning may retain a boundary partition, never drop one
    // the independent reader needs. Row results must still match exactly.
    for file in files {
      guard file is String(path) else { fail("Bad file") }
      assert_true(kept.contains(path))
    }
    let result = bundle.scan(p)
    let actual = result.rows.map(row => {
      match row.values[1] {
        Integer(n) => n
        _ => -1L
      }
    })
    let expected = ids.map(j => {
      match j {
        Number(n, ..) => n.to_int64()
        _ => -2L
      }
    })
    actual.sort()
    expected.sort()
    assert_eq(actual, expected)
  }
  let p = @moonice.parse_predicate(
    "{\"field\":\"ts\",\"op\":\">=\",\"value\":\"1709251200000000\"}",
    state.schema,
  )
  // Remove column stats to prove exclusion comes from the historical specs.
  for entry in state.entries {
    entry.file.lower_bounds.clear()
    entry.file.upper_bounds.clear()
    entry.file.null_counts.clear()
  }
  let plan = @moonice.plan_scan(bundle.metadata, state, p)
  assert_eq(plan.decisions.filter(d => d.kept).length(), 2)
  assert_true(
    plan.decisions
    .filter(d => !d.kept)
    .iter()
    .all(d => d.reason_code == "PARTITION"),
  )
}
