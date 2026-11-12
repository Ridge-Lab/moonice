///|
#derive(Debug, ToJson)
pub(all) struct ScanResult {
  snapshot_id : Int64
  schema : Schema
  rows : Array[DataRow]
  read_rows : Int32
  deleted_rows : Int32
  matched_rows : Int32
  truncated : Bool
}

///|
fn equality_key(
  row : DataRow,
  ids : Array[Int32],
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
  Json(values).stringify()
}

///|
// Iceberg column projection resolves physically absent field IDs from identity
// partitions before filters and equality deletes. A stored null is present.
fn restore_identity_columns(
  metadata : TableMetadata,
  entry : ManifestEntry,
  rows : Array[DataRow],
  wanted? : Map[Int32, Bool],
) -> Unit raise IceError {
  guard rows.length() > 0 else { return }
  guard metadata.partition_specs.iter().find_first(s => s.id == entry.spec_id)
    is Some(spec) else {
    raise Invalid(
      "SPEC_NOT_FOUND",
      entry.file.path,
      "Data partition spec is absent",
    )
  }
  // A flat Parquet file uses the same physical column IDs for every row.
  for field in spec.fields {
    if field.transform == "identity" &&
      (wanted is None || (wanted is Some(ids) && ids.contains(field.source_id))) &&
      !rows[0].values.contains(field.source_id) &&
      entry.file.partition.get(field.name) is Some(value) {
      if rows[0].values.length() + 1 > 5000000 / rows.length() {
        raise Invalid(
          "RESOURCE_LIMIT",
          entry.file.path,
          "Partition projection exceeds five million cells",
        )
      }
      for row in rows {
        row.values[field.source_id] = value
      }
    }
  }
}

///|
fn walk_rows(
  metadata : TableMetadata,
  state : SnapshotState,
  predicate : Predicate,
  read_file : (String) -> Bytes raise IceError,
  on_row : (DataRow) -> Unit raise IceError,
  columns? : Array[String],
  name_mapping~ : Map[String, Int32] = Map([]),
) -> ScanSummary raise IceError {
  let plan = plan_scan(metadata, state, predicate)
  let output = match columns {
    None => state.schema
    Some(names) => select_schema(state.schema, names)
  }
  let needed : Map[Int32, Bool] = Map([])
  let validation = if columns is Some(_) {
    predicate_ids(predicate, needed)
    for field in output.fields {
      needed[field.id] = true
    }
    let fields = state.schema.fields.filter(field => needed.contains(field.id))
    for field in fields {
      projection_field(field)
    }
    { ..state.schema, fields, }
  } else {
    state.schema
  }
  let deletions = state.entries.filter(e => e.file.content != 0)
  let indexes : Map[String, DeleteIndex] = Map([])
  let mut read_rows = 0
  let mut deleted_rows = 0
  let mut matched_rows = 0
  let mut total_delete_rows = 0
  let mut scanned_files = 0
  for decision in plan.decisions {
    if !decision.kept {
      continue
    }
    let entry = decision.entry
    scanned_files += 1
    let applicable = deletions.filter(d => {
      explain_delete(metadata, entry, d).applies
    })
    let physical = if columns is Some(_) {
      let ids = needed.copy()
      for deletion in applicable {
        for id in deletion.file.equality_ids {
          ids[id] = true
        }
      }
      Some(ids)
    } else {
      None
    }
    let identity_ids = Map([])
    if columns is Some(_) &&
      metadata.partition_specs.iter().find_first(s => s.id == entry.spec_id)
      is Some(spec) {
      for field in spec.fields {
        if field.transform == "identity" &&
          entry.file.partition.contains(field.name) {
          identity_ids[field.source_id] = true
        }
      }
    }
    let rows = read_file_columns(
      read_file(entry.file.path),
      entry.file,
      physical,
      name_mapping,
      identity_ids~,
    )
    read_rows += rows.length()
    if read_rows > 1000000 {
      raise Invalid(
        "RESOURCE_LIMIT", "scan", "Scan exceeds one million data rows",
      )
    }
    restore_identity_columns(metadata, entry, rows, wanted?=physical)
    let positions : Map[Int64, Bool] = Map([])
    let equality : Array[(Array[Int32], Map[String, Bool])] = []
    for deletion in applicable {
      let index = match indexes.get(deletion.file.path) {
        Some(index) => index
        None => {
          let delete_ids = if columns is Some(_) {
            let ids : Map[Int32, Bool] = Map([])
            if deletion.file.content == 1 {
              ids[2147483546] = true
              ids[2147483545] = true
            } else {
              for id in deletion.file.equality_ids {
                ids[id] = true
              }
            }
            Some(ids)
          } else {
            None
          }
          let rows = read_file_columns(
            read_file(deletion.file.path),
            deletion.file,
            delete_ids,
            name_mapping,
          )
          total_delete_rows += rows.length()
          if total_delete_rows > 100000 {
            raise Invalid(
              "RESOURCE_LIMIT", "scan", "Scan exceeds 100,000 delete rows",
            )
          }
          let index = index_deletes(rows, deletion.file)
          indexes[deletion.file.path] = index
          index
        }
      }
      match index {
        Positions(by_path) =>
          if by_path.get(entry.file.path) is Some(selected) {
            for pos, _ in selected {
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
        Equality(ids, keys) => equality.push((ids, keys))
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
      ignore(row.project(validation))
      if predicate.matches(row.values) {
        matched_rows += 1
        if columns is Some(_) {
          let values = Map([])
          for field in output.fields {
            values[field.id] = row.values.get(field.id).unwrap_or(Missing)
          }
          on_row({ ..row, values, })
        } else {
          on_row(row)
        }
      }
    }
  }
  {
    snapshot_id: state.snapshot.id,
    schema: output,
    read_rows,
    deleted_rows,
    matched_rows,
    scanned_files,
    delete_files: indexes.length(),
  }
}

///|
/// Apply deletes before residual filtering and projection. The limit limits
/// returned rows; counters still describe the complete bounded scan.
pub fn scan_rows(
  metadata : TableMetadata,
  state : SnapshotState,
  predicate : Predicate,
  read_file : (String) -> Bytes raise IceError,
  limit~ : Int32 = 1000,
  columns? : Array[String],
  name_mapping~ : Map[String, Int32] = Map([]),
) -> ScanResult raise IceError {
  if limit < 0 || limit > 100000 {
    raise Invalid("INVALID_LIMIT", "limit", "Expected 0..100000")
  }
  let rows = []
  let summary = walk_rows(
    metadata,
    state,
    predicate,
    read_file,
    row => if rows.length() < limit { rows.push(row) },
    columns?,
    name_mapping~,
  )
  {
    snapshot_id: summary.snapshot_id,
    schema: summary.schema,
    rows,
    read_rows: summary.read_rows,
    deleted_rows: summary.deleted_rows,
    matched_rows: summary.matched_rows,
    truncated: summary.matched_rows > rows.length(),
  }
}

///|
pub fn Bundle::scan(
  self : Bundle,
  predicate : Predicate,
  snapshot_id? : Int64,
  limit~ : Int32 = 1000,
  columns? : Array[String],
  name_mapping~ : Map[String, Int32] = Map([]),
) -> ScanResult raise IceError {
  scan_rows(
    self.metadata,
    self.load_snapshot(snapshot_id?),
    predicate,
    path => self.read_file(path),
    limit~,
    columns?,
    name_mapping~,
  )
}
