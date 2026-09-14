///|
pub(all) struct ScanResult {
  snapshot_id : Int64
  schema : Schema
  rows : Array[DataRow]
  read_rows : Int
  deleted_rows : Int
  matched_rows : Int
  truncated : Bool
} derive(Debug, ToJson)

///|
fn equality_key(
  row : DataRow,
  ids : Array[Int],
  require_present : Bool,
) -> String raise IceError {
  let values : Array[Scalar] = []
  for id in ids {
    if require_present && !row.values.contains(id) {
      raise Invalid(
        "MISSING_EQUALITY_FIELD",
        row.file_path,
        "Equality delete column ID \{id} is absent",
      )
    }
    let value = row.values.get(id).unwrap_or(Missing)
    if value is Real(_) {
      raise Invalid(
        "UNSUPPORTED_EQUALITY_TYPE",
        row.file_path,
        "Floating-point equality delete keys are not supported",
      )
    }
    values.push(value)
  }
  values.to_json().stringify()
}

///|
/// Apply deletes before residual filtering and projection. The limit only limits
/// returned rows; counters describe the complete bounded scan.
pub fn scan_rows(
  metadata : TableMetadata,
  state : SnapshotState,
  predicate : Predicate,
  read_file : (String) -> Bytes raise IceError,
  limit? : Int = 1000,
) -> ScanResult raise IceError {
  if limit < 0 || limit > 100000 {
    raise Invalid("INVALID_LIMIT", "limit", "Expected 0..100000")
  }
  let plan = plan_scan(metadata, state, predicate)
  let deletions = state.entries.filter(e => e.file.content != 0)
  let delete_rows : Map[String, Array[DataRow]] = Map([])
  let result = []
  let mut read_rows = 0
  let mut deleted_rows = 0
  let mut matched_rows = 0
  let mut total_delete_rows = 0
  for decision in plan.decisions {
    if !decision.kept {
      continue
    }
    let entry = decision.entry
    let rows = read_data_rows(read_file(entry.file.path), entry.file)
    read_rows += rows.length()
    if read_rows > 1000000 {
      raise Invalid(
        "RESOURCE_LIMIT", "scan", "Scan exceeds one million data rows",
      )
    }
    let positions : Map[Int64, Bool] = Map([])
    let equality : Array[(Array[Int], Map[String, Bool])] = []
    for deletion in deletions {
      if !explain_delete(metadata, entry, deletion).applies {
        continue
      }
      let drows = match delete_rows.get(deletion.file.path) {
        Some(rows) => rows
        None => {
          let rows = read_data_rows(
            read_file(deletion.file.path),
            deletion.file,
          )
          total_delete_rows += rows.length()
          if total_delete_rows > 100000 {
            raise Invalid(
              "RESOURCE_LIMIT", "scan", "Scan exceeds 100,000 delete rows",
            )
          }
          delete_rows[deletion.file.path] = rows
          rows
        }
      }
      if deletion.file.content == 1 {
        for row in drows {
          guard row.values.get(2147483546) is Some(Text(path)) &&
            row.values.get(2147483545) is Some(Integer(pos)) &&
            pos >= 0L else {
            raise Invalid(
              "INVALID_POSITION_DELETE",
              deletion.file.path,
              "Expected reserved file_path and nonnegative pos fields",
            )
          }
          if path == entry.file.path {
            if pos >= entry.file.record_count {
              raise Invalid(
                "INVALID_POSITION_DELETE",
                deletion.file.path,
                "Delete position exceeds data file row count",
              )
            }
            positions[pos] = true
          }
        }
      } else {
        let keys = Map([])
        if deletion.file.equality_ids.is_empty() {
          raise Invalid(
            "MISSING_EQUALITY_FIELD",
            deletion.file.path,
            "Equality IDs must be nonempty",
          )
        }
        for row in drows {
          keys[equality_key(row, deletion.file.equality_ids, true)] = true
        }
        equality.push((deletion.file.equality_ids, keys))
      }
    }
    for row in rows {
      let mut deleted = positions.contains(row.position)
      for pair in equality {
        let (ids, keys) = pair
        if keys.contains(equality_key(row, ids, false)) {
          deleted = true
          break
        }
      }
      if deleted {
        deleted_rows += 1
        continue
      }
      // Validate selected schema even for rows later excluded by the predicate.
      ignore(row.project(state.schema))
      if predicate.matches(row.values) {
        matched_rows += 1
        if result.length() < limit {
          result.push(row)
        }
      }
    }
  }
  {
    snapshot_id: state.snapshot.id,
    schema: state.schema,
    rows: result,
    read_rows,
    deleted_rows,
    matched_rows,
    truncated: matched_rows > result.length(),
  }
}

///|
pub fn Bundle::scan(
  self : Bundle,
  predicate : Predicate,
  snapshot_id? : Int64,
  limit? : Int = 1000,
) -> ScanResult raise IceError {
  scan_rows(
    self.metadata,
    self.load_snapshot(snapshot_id?),
    predicate,
    path => self.read_file(path),
    limit~,
  )
}
