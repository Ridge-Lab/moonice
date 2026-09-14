///|
pub(all) struct DeleteDecision {
  data_path : String
  delete_path : String
  applies : Bool
  reason_code : String
  explanation : String
} derive(Debug, Eq, ToJson)

///|
fn same_partition(a : ManifestEntry, b : ManifestEntry) -> Bool {
  if a.spec_id != b.spec_id ||
    a.file.partition.length() != b.file.partition.length() {
    return false
  }
  for key, value in a.file.partition {
    if b.file.partition.get(key) != Some(value) {
      return false
    }
  }
  true
}

///|
/// Decide delete-file applicability by Iceberg v2 data sequence and partition.
/// Position file paths are matched against each delete row during execution.
pub fn explain_delete(
  metadata : TableMetadata,
  data : ManifestEntry,
  deletion : ManifestEntry,
) -> DeleteDecision raise IceError {
  if data.file.content != 0 ||
    (deletion.file.content != 1 && deletion.file.content != 2) {
    raise Invalid(
      "INVALID_DELETE_PAIR",
      deletion.file.path,
      "Expected a data file and a position/equality delete file",
    )
  }
  let spec = match
    metadata.partition_specs.iter().find_first(s => s.id == deletion.spec_id) {
    Some(s) => s
    None =>
      raise Invalid(
        "SPEC_NOT_FOUND",
        deletion.file.path,
        "Delete partition spec is absent",
      )
  }
  let equality = deletion.file.content == 2
  let sequence_ok = if equality {
    data.sequence_number < deletion.sequence_number
  } else {
    data.sequence_number <= deletion.sequence_number
  }
  let partition_ok = same_partition(data, deletion) ||
    (equality && spec.fields.is_empty())
  let (applies, code, detail) = if !sequence_ok {
    (
      false,
      "SEQUENCE",
      if equality {
        "Equality deletes require data sequence < delete sequence"
      } else {
        "Position deletes require data sequence <= delete sequence"
      },
    )
  } else if !partition_ok {
    (
      false, "PARTITION", "Partition spec or values differ; delete does not apply",
    )
  } else {
    (
      true,
      "APPLIES",
      if equality {
        "Equality keys must be applied before projection"
      } else {
        "Match file_path and zero-based position in the delete rows"
      },
    )
  }
  {
    data_path: data.file.path,
    delete_path: deletion.file.path,
    applies,
    reason_code: code,
    explanation: detail,
  }
}

///|
pub fn plan_deletes(
  metadata : TableMetadata,
  state : SnapshotState,
  plan : ScanPlan,
) -> Array[DeleteDecision] raise IceError {
  if state.snapshot.id != plan.snapshot_id {
    raise Invalid(
      "SNAPSHOT_MISMATCH", "plan", "Delete planning requires the same snapshot",
    )
  }
  let result = []
  for decision in plan.decisions {
    if decision.kept {
      for deletion in state.entries {
        if deletion.file.content != 0 {
          result.push(explain_delete(metadata, decision.entry, deletion))
        }
      }
    }
  }
  result
}
