///|
pub(all) struct FileDecision {
  entry : ManifestEntry
  kept : Bool
  reason_code : String
  explanation : String
} derive(Debug, ToJson)

///|
pub(all) struct ScanPlan {
  snapshot_id : Int64
  schema : Schema
  predicate : Predicate
  decisions : Array[FileDecision]
  retained_bytes : Int64
  pruned_bytes : Int64
} derive(Debug, ToJson)

///|
fn partition_exclusion(
  metadata : TableMetadata,
  entry : ManifestEntry,
  schema : Schema,
  p : Predicate,
) -> String? {
  let spec = match
    metadata.partition_specs.iter().find_first(s => s.id == entry.spec_id) {
    Some(s) => s
    None => return None
  }
  match p {
    All => None
    And(a, b) =>
      match partition_exclusion(metadata, entry, schema, a) {
        Some(r) => Some(r)
        None => partition_exclusion(metadata, entry, schema, b)
      }
    Or(a, b) =>
      match
        (
          partition_exclusion(metadata, entry, schema, a),
          partition_exclusion(metadata, entry, schema, b),
        ) {
        (Some(_), Some(_)) => Some("Both OR branches exclude this partition")
        _ => None
      }
    Compare(id, _, _) | IsNull(id) | NotNull(id) => {
      for pf in spec.fields {
        if pf.source_id == id {
          if entry.file.partition.get(pf.name) is Some(value) &&
            schema.field(id) is Some(field) {
            if transformed_exclusion(field, pf.transform, value, p) {
              return Some(
                "\{pf.transform} partition \{pf.name} cannot satisfy this predicate",
              )
            }
          }
        }
      }
      None
    }
  }
}

///|
/// Inclusive planning: every retained file still requires residual row filtering.
pub fn plan_scan(
  metadata : TableMetadata,
  state : SnapshotState,
  predicate : Predicate,
) -> ScanPlan raise IceError {
  predicate.validate(state.schema)
  let decisions : Array[FileDecision] = []
  let mut retained_bytes = 0L
  let mut pruned_bytes = 0L
  for entry in state.entries {
    if entry.file.content != 0 {
      continue
    }
    let (code, explanation) = if entry.file.record_count == 0 {
      ("EMPTY_FILE", Some("File contains zero records"))
    } else if partition_exclusion(metadata, entry, state.schema, predicate)
      is Some(reason) {
      ("PARTITION", Some(reason))
    } else {
      ("METRICS", metrics_exclusion(entry.file, state.schema, predicate))
    }
    let kept = explanation is None
    if kept {
      retained_bytes += entry.file.size_bytes
    } else {
      pruned_bytes += entry.file.size_bytes
    }
    decisions.push({
      entry,
      kept,
      reason_code: if kept {
        "MAY_MATCH"
      } else {
        code
      },
      explanation: explanation.unwrap_or(
        "No exclusion proof; retain file and evaluate residual rows",
      ),
    })
  }
  {
    snapshot_id: state.snapshot.id,
    schema: state.schema,
    predicate,
    decisions,
    retained_bytes,
    pruned_bytes,
  }
}
