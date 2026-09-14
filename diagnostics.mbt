///|
pub(all) struct Finding {
  severity : String
  code : String
  path : String
  explanation : String
  snapshot_id : Int64?
} derive(Debug, Eq, ToJson)

///|
pub(all) struct Diagnosis {
  checked_snapshots : Int
  checked_objects : Int
  findings : Array[Finding]
} derive(Debug, ToJson)

///|
/// Inspect every retained snapshot. Failures are localized; other snapshots are
/// still inspected. Unreferenced bundled objects are reported, never deleted.
pub fn Bundle::diagnose(self : Bundle) -> Diagnosis {
  let findings = []
  let objects : Map[String, Bool] = Map([])
  let mut checked_snapshots = 0
  let mut complete = true
  for snapshot in self.metadata.snapshots {
    objects[snapshot.manifest_list] = true
    if snapshot.parent_id is Some(id) &&
      !self.metadata.snapshots.iter().any(s => s.id == id) {
      findings.push({
        severity: "info",
        code: "EXPIRED_PARENT",
        path: snapshot.manifest_list,
        explanation: "Parent is not retained; snapshot expiration is permitted",
        snapshot_id: Some(snapshot.id),
      })
    }
    try {
      let state = load_snapshot(
        self.metadata,
        path => {
          objects[path] = true
          self.read_file(path)
        },
        snapshot_id=snapshot.id,
      )
      checked_snapshots += 1
      for entry in state.entries {
        objects[entry.file.path] = true
        match self.files.get(entry.file.path) {
          None =>
            findings.push({
              severity: "error",
              code: "MISSING_FILE",
              path: entry.file.path,
              explanation: "Live data/delete file is absent from the bundle",
              snapshot_id: Some(snapshot.id),
            })
          Some(bytes) => {
            if bytes.length().to_int64() != entry.file.size_bytes {
              findings.push({
                severity: "error",
                code: "FILE_LENGTH",
                path: entry.file.path,
                explanation: "Object size differs from manifest metadata",
                snapshot_id: Some(snapshot.id),
              })
            }
            if entry.file.format != "PARQUET" {
              findings.push({
                severity: "warning",
                code: "UNSUPPORTED_FILE_FORMAT",
                path: entry.file.path,
                explanation: "Metadata is inspectable, but row execution requires Parquet",
                snapshot_id: Some(snapshot.id),
              })
            }
          }
        }
        if entry.file.lower_bounds.is_empty() &&
          entry.file.record_count > 0L &&
          entry.file.content == 0 {
          findings.push({
            severity: "info",
            code: "NO_LOWER_BOUNDS",
            path: entry.file.path,
            explanation: "Missing lower bounds limit file pruning; unknown statistics retain files",
            snapshot_id: Some(snapshot.id),
          })
        }
      }
    } catch {
      Invalid(code, path, explanation) => {
        complete = false
        findings.push({
          severity: "error",
          code,
          path,
          explanation,
          snapshot_id: Some(snapshot.id),
        })
      }
    }
  }
  if complete {
    for path, _ in self.files {
      if !objects.contains(path) {
        findings.push({
          severity: "info",
          code: "UNREFERENCED_IN_BUNDLE",
          path,
          explanation: "No live reference in retained snapshots; this is not proof that remote deletion is safe",
          snapshot_id: None,
        })
      }
    }
  }
  { checked_snapshots, checked_objects: objects.length(), findings }
}

///|
pub(all) struct SchemaChange {
  field_id : Int
  kind : String
  before : Field?
  after : Field?
} derive(Debug, ToJson)

///|
pub(all) struct SnapshotDiff {
  from_id : Int64
  to_id : Int64
  added : Array[ManifestEntry]
  removed : Array[ManifestEntry]
  retained_files : Int
  added_records : Int64
  removed_records : Int64
  schema_changes : Array[SchemaChange]
} derive(Debug, ToJson)

///|
/// Physical file/record changes, not a logical row-level changelog. Rewrites may
/// remove and re-add the same logical rows; delete files are reported separately.
pub fn diff_snapshots(
  before : SnapshotState,
  after : SnapshotState,
) -> SnapshotDiff {
  let old : Map[String, ManifestEntry] = Map([])
  let new : Map[String, ManifestEntry] = Map([])
  for entry in before.entries {
    old[entry.file.path] = entry
  }
  for entry in after.entries {
    new[entry.file.path] = entry
  }
  let added = []
  let removed = []
  let mut retained_files = 0
  let mut added_records = 0L
  let mut removed_records = 0L
  for path, entry in new {
    if old.contains(path) {
      retained_files += 1
    } else {
      added.push(entry)
      if entry.file.content == 0 {
        added_records += entry.file.record_count
      }
    }
  }
  for path, entry in old {
    if !new.contains(path) {
      removed.push(entry)
      if entry.file.content == 0 {
        removed_records += entry.file.record_count
      }
    }
  }
  let schema_changes = []
  for field in before.schema.fields {
    match after.schema.field(field.id) {
      None =>
        schema_changes.push({
          field_id: field.id,
          kind: "removed",
          before: Some(field),
          after: None,
        })
      Some(current) =>
        if current != field {
          schema_changes.push({
            field_id: field.id,
            kind: if field.field_type == current.field_type &&
              field.required == current.required {
              "renamed"
            } else {
              "changed"
            },
            before: Some(field),
            after: Some(current),
          })
        }
    }
  }
  for field in after.schema.fields {
    if before.schema.field(field.id) is None {
      schema_changes.push({
        field_id: field.id,
        kind: "added",
        before: None,
        after: Some(field),
      })
    }
  }
  {
    from_id: before.snapshot.id,
    to_id: after.snapshot.id,
    added,
    removed,
    retained_files,
    added_records,
    removed_records,
    schema_changes,
  }
}
