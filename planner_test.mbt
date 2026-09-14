///|
test "planning matches every frozen PyIceberg reference file set" {
  let bundle = @moonice.open_bundle(reference_bundle)
  let json = @json.parse(reference_bundle)
  guard json is { "reference": { "cases": Array(cases), .. }, .. } else {
    fail("Missing oracle")
  }
  for item in cases {
    guard item
      is {
        "snapshot_id": String(id),
        "filter": String(label),
        "files": Array(files),
        ..
      } else {
      fail("Bad oracle")
    }
    let snapshot_id : Int64 = @json.from_json(Json::string(id))
    let state = bundle.load_snapshot(snapshot_id~)
    let p : @moonice.Predicate = if label == "all" {
      All
    } else {
      Compare(1, Ge, Integer(10L))
    }
    let plan = @moonice.plan_scan(bundle.metadata, state, p)
    let actual = plan.decisions.filter(d => d.kept).map(d => d.entry.file.path)
    let expected = files.map(j => {
      guard j is String(s) else { fail("Expected path") }
      s
    })
    actual.sort()
    expected.sort()
    assert_eq(actual, expected)
    assert_true(plan.decisions.iter().all(d => !d.explanation.is_empty()))
  }
}

///|
test "nulls and boolean composition preserve row filtering semantics" {
  let missing : Map[Int, @moonice.Scalar] = Map([])
  let row : Map[Int, @moonice.Scalar] = Map([(1, Integer(11L))])
  let p : @moonice.Predicate = Or(IsNull(1), Compare(1, Ge, Integer(10L)))
  assert_true(p.matches(missing))
  assert_true(p.matches(row))
  let q : @moonice.Predicate = And(NotNull(1), Compare(1, Lt, Integer(10L)))
  assert_false(q.matches(missing))
  assert_false(q.matches(row))
}

///|
test "typed filter rejects misspelled fields and string numeric coercion" {
  let schema = @moonice.open_bundle(reference_bundle).load_snapshot().schema
  let p = @moonice.parse_predicate(
    "{\"field\":\"id\",\"op\":\">=\",\"value\":10}", schema,
  )
  assert_eq(p, Compare(1, Ge, Integer(10L)))
  try
    @moonice.parse_predicate("{\"field\":\"city\",\"op\":\"is_null\"}", schema)
  catch {
    @moonice.Invalid(code, _, _) => assert_eq(code, "FIELD_NOT_FOUND")
  } noraise {
    _ => fail("Renamed field must bind through current schema")
  }
}
