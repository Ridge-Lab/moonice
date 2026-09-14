///|
fn metric_file(lo : Int64, hi : Int64) -> DataFile {
  fn bytes(n : Int64) -> Bytes {
    Bytes::makei(8, i => ((n >> (8 * i)) & 255L).to_int().to_byte())
  }
  {
    content: 0,
    path: "data",
    format: "PARQUET",
    partition: Map([]),
    record_count: 4L,
    size_bytes: 10L,
    lower_bounds: Map([(1, bytes(lo))]),
    upper_bounds: Map([(1, bytes(hi))]),
    null_counts: Map([(1, 0L)]),
    nan_counts: Map([]),
    equality_ids: [],
  }
}

///|
test "no false pruning for exhaustive integer intervals and comparisons" {
  let schema : Schema = {
    id: 0,
    fields: [
      { id: 1, name: "x", required: false, field_type: Json::string("long") },
    ],
  }
  for lo in -5..<6 {
    for hi in lo..<6 {
      for literal in -7..<8 {
        let file = metric_file(lo.to_int64(), hi.to_int64())
        for op in [Eq, Lt, Le, Gt, Ge] {
          let p = Compare(1, op, Integer(literal.to_int64()))
          if metrics_exclusion(file, schema, p) is Some(_) {
            for value in lo..<(hi + 1) {
              assert_false(p.matches(Map([(1, Integer(value.to_int64()))])))
            }
          }
        }
      }
    }
  }
}

///|
test "unknown malformed and inverted bounds retain files" {
  let schema : Schema = {
    id: 0,
    fields: [
      { id: 1, name: "x", required: false, field_type: Json::string("long") },
    ],
  }
  let p = Compare(1, Eq, Integer(5L))
  assert_eq(metrics_exclusion(metric_file(10L, 1L), schema, p), None)
  let file = metric_file(1L, 10L)
  file.lower_bounds[1] = b"x"
  file.upper_bounds.remove(1)
  assert_eq(metrics_exclusion(file, schema, p), None)
  file.lower_bounds.remove(1)
  assert_eq(metrics_exclusion(file, schema, p), None)
}
