///|
priv enum DeleteIndex {
  Positions(Map[String, Map[Int64, Bool]])
  Equality(Array[Int], Map[String, Bool])
}

///|
// Built once per distinct delete file, shared by every applicable data file.
fn index_deletes(
  rows : Array[DataRow],
  file : DataFile,
) -> DeleteIndex raise IceError {
  if file.content == 1 {
    let by_path : Map[String, Map[Int64, Bool]] = Map([])
    for row in rows {
      guard row.values.get(2147483546) is Some(Text(path)) &&
        row.values.get(2147483545) is Some(Integer(pos)) &&
        pos >= 0L else {
        raise Invalid(
          "INVALID_POSITION_DELETE",
          file.path,
          "Expected reserved file_path and nonnegative pos fields",
        )
      }
      let positions = match by_path.get(path) {
        Some(p) => p
        None => {
          let p = Map([])
          by_path[path] = p
          p
        }
      }
      positions[pos] = true
    }
    Positions(by_path)
  } else {
    if file.equality_ids.is_empty() {
      raise Invalid(
        "MISSING_EQUALITY_FIELD",
        file.path,
        "Equality IDs must be nonempty",
      )
    }
    let keys = Map([])
    for row in rows {
      keys[equality_key(row, file.equality_ids, true)] = true
    }
    Equality(file.equality_ids, keys)
  }
}
