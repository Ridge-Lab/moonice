///|
test "inclusive projections never exclude matching source values" {
  let field : Field = {
    id: 1,
    name: "x",
    required: false,
    field_type: Json::string("long"),
  }
  for
    transform in [
      "identity", "truncate[1]", "truncate[10]", "bucket[16]", "void", "future",
    ] {
    for source in -30..<31 {
      let value = Integer(source.to_int64())
      guard transform_partition(value, field.field_type, transform)
        is Some(partition) else {
        continue
      }
      for literal in -35..<36 {
        for op in [Eq, Lt, Le, Gt, Ge] {
          let p = Compare(1, op, Integer(literal.to_int64()))
          if p.matches(Map([(1, value)])) {
            assert_false(transformed_exclusion(field, transform, partition, p))
          }
        }
      }
    }
  }
}

///|
test "calendar boundaries retain strict-comparison boundary partitions" {
  let field : Field = {
    id: 1,
    name: "ts",
    required: false,
    field_type: Json::string("timestamp"),
  }
  for transform in ["year", "month", "day", "hour"] {
    for source in [-86400000001L, -86400000000L, -1L, 0L, 1L, 951782400000000L] {
      let partition = transform_partition(
        Integer(source),
        field.field_type,
        transform,
      ).unwrap()
      for delta in [-1L, 0L, 1L] {
        for op in [Eq, Lt, Le, Gt, Ge] {
          let p = Compare(1, op, Integer(source + delta))
          if p.matches(Map([(1, Integer(source))])) {
            assert_false(transformed_exclusion(field, transform, partition, p))
          }
        }
      }
    }
  }
}
