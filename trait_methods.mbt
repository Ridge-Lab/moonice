// Explicit method exposure preserves the 0.2 API under MoonBit 0.10.14.
// Trait implementations no longer implicitly expose their methods.

///|
pub extend IceError with Debug::{to_repr}

///|
pub extend Bundle with Debug::{to_repr}

///|
pub extend CompareOp with Debug::{to_repr}

///|
pub extend CompareOp with ToJson::{to_json}

///|
pub extend CompareOp with Eq::{equal, not_equal}

///|
pub extend DataFile with Debug::{to_repr}

///|
pub extend DataFile with ToJson::{to_json}

///|
pub extend DataFile with Eq::{equal, not_equal}

///|
pub extend DataRow with Debug::{to_repr}

///|
pub extend DataRow with ToJson::{to_json}

///|
pub extend DataRow with Eq::{equal, not_equal}

///|
pub extend DeleteDecision with Debug::{to_repr}

///|
pub extend DeleteDecision with ToJson::{to_json}

///|
pub extend DeleteDecision with Eq::{equal, not_equal}

///|
pub extend Diagnosis with Debug::{to_repr}

///|
pub extend Diagnosis with ToJson::{to_json}

///|
pub extend Field with Debug::{to_repr}

///|
pub extend Field with ToJson::{to_json}

///|
pub extend Field with Eq::{equal, not_equal}

///|
pub extend FileDecision with Debug::{to_repr}

///|
pub extend FileDecision with ToJson::{to_json}

///|
pub extend Finding with Debug::{to_repr}

///|
pub extend Finding with ToJson::{to_json}

///|
pub extend Finding with Eq::{equal, not_equal}

///|
pub extend Manifest with Debug::{to_repr}

///|
pub extend Manifest with ToJson::{to_json}

///|
pub extend Manifest with Eq::{equal, not_equal}

///|
pub extend ManifestEntry with Debug::{to_repr}

///|
pub extend ManifestEntry with ToJson::{to_json}

///|
pub extend ManifestEntry with Eq::{equal, not_equal}

///|
pub extend PartitionField with Debug::{to_repr}

///|
pub extend PartitionField with ToJson::{to_json}

///|
pub extend PartitionField with Eq::{equal, not_equal}

///|
pub extend PartitionSpec with Debug::{to_repr}

///|
pub extend PartitionSpec with ToJson::{to_json}

///|
pub extend PartitionSpec with Eq::{equal, not_equal}

///|
pub extend Predicate with Debug::{to_repr}

///|
pub extend Predicate with ToJson::{to_json}

///|
pub extend Predicate with Eq::{equal, not_equal}

///|
pub extend Scalar with Debug::{to_repr}

///|
pub extend Scalar with ToJson::{to_json}

///|
pub extend Scalar with Eq::{equal, not_equal}

///|
pub extend ScanPlan with Debug::{to_repr}

///|
pub extend ScanPlan with ToJson::{to_json}

///|
pub extend ScanResult with Debug::{to_repr}

///|
pub extend ScanResult with ToJson::{to_json}

///|
pub extend ScanSummary with Debug::{to_repr}

///|
pub extend ScanSummary with ToJson::{to_json}

///|
pub extend Schema with Debug::{to_repr}

///|
pub extend Schema with ToJson::{to_json}

///|
pub extend Schema with Eq::{equal, not_equal}

///|
pub extend SchemaChange with Debug::{to_repr}

///|
pub extend SchemaChange with ToJson::{to_json}

///|
pub extend Snapshot with Debug::{to_repr}

///|
pub extend Snapshot with ToJson::{to_json}

///|
pub extend Snapshot with Eq::{equal, not_equal}

///|
pub extend SnapshotDiff with Debug::{to_repr}

///|
pub extend SnapshotDiff with ToJson::{to_json}

///|
pub extend SnapshotRef with Debug::{to_repr}

///|
pub extend SnapshotRef with ToJson::{to_json}

///|
pub extend SnapshotRef with Eq::{equal, not_equal}

///|
pub extend SnapshotState with Debug::{to_repr}

///|
pub extend SnapshotState with ToJson::{to_json}

///|
pub extend TableMetadata with Debug::{to_repr}

///|
pub extend TableMetadata with ToJson::{to_json}

///|
pub extend IceError with Show::{output, to_string}
