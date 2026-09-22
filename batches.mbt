///|
/// Counters for a complete scan. Unlike ScanResult this contains no row array.
pub(all) struct ScanSummary {
  snapshot_id : Int64
  schema : Schema
  read_rows : Int
  deleted_rows : Int
  matched_rows : Int
  scanned_files : Int
  delete_files : Int
} derive(Debug, ToJson)

///|
/// Emit matching rows in batches, after deletes and schema validation.
/// Each emitted array is owned by the caller and is never reused or cleared.
/// A callback error stops further scanning. Earlier batches remain delivered
/// if a later read fails; callers needing atomic output must stage it themselves.
/// Files are still decoded in memory (at most 100,000 rows/64 MiB per file).
/// This is incremental delivery between files, not a Parquet range-read API.
pub fn scan_batches(
  metadata : TableMetadata,
  state : SnapshotState,
  predicate : Predicate,
  read_file : (String) -> Bytes raise IceError,
  emit : (Array[DataRow]) -> Unit raise IceError,
  batch_size? : Int = 1024,
) -> ScanSummary raise IceError {
  if batch_size < 1 || batch_size > 100000 {
    raise Invalid("INVALID_BATCH_SIZE", "batch_size", "Expected 1..100000")
  }
  let mut pending : Array[DataRow] = []
  let result = walk_rows(metadata, state, predicate, read_file, row => {
    pending.push(row)
    if pending.length() == batch_size {
      let ready = pending
      pending = []
      emit(ready)
    }
  })
  if !pending.is_empty() {
    emit(pending)
  }
  result
}

///|
pub fn Bundle::scan_batches(
  self : Bundle,
  predicate : Predicate,
  emit : (Array[DataRow]) -> Unit raise IceError,
  snapshot_id? : Int64,
  batch_size? : Int = 1024,
) -> ScanSummary raise IceError {
  scan_batches(
    self.metadata,
    self.load_snapshot(snapshot_id?),
    predicate,
    path => self.read_file(path),
    emit,
    batch_size~,
  )
}
