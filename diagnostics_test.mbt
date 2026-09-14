///|
test "snapshot diff distinguishes rewrites from logical row changes" {
  let bundle = @moonice.open_bundle(reference_bundle)
  let snapshots = bundle.metadata.snapshots
  let first = bundle.load_snapshot(snapshot_id=snapshots[0].id)
  let second = bundle.load_snapshot(snapshot_id=snapshots[1].id)
  let third = bundle.load_snapshot()
  let append = @moonice.diff_snapshots(first, second)
  assert_eq(append.added_records, 2L)
  assert_eq(append.removed_records, 0L)
  let overwrite = @moonice.diff_snapshots(second, third)
  assert_eq(overwrite.added_records, 2L)
  assert_eq(overwrite.removed_records, 3L)
  assert_true(
    overwrite.schema_changes
    .iter()
    .any(c => c.kind == "renamed" && c.field_id == 2),
  )
  assert_true(overwrite.schema_changes.iter().any(c => c.kind == "added"))
}

///|
test "diagnosis localizes a missing object without treating incomplete traversal as safe cleanup" {
  let bundle = @moonice.open_bundle(reference_bundle)
  assert_false(
    bundle.diagnose().findings.iter().any(f => f.severity == "error"),
  )
  let path = bundle.metadata.snapshots[0].manifest_list
  bundle.files.remove(path)
  let diagnosis = bundle.diagnose()
  assert_true(
    diagnosis.findings
    .iter()
    .any(f => f.code == "MISSING_FILE" && f.path == path),
  )
  assert_false(
    diagnosis.findings.iter().any(f => f.code == "UNREFERENCED_IN_BUNDLE"),
  )
  assert_true(diagnosis.checked_snapshots > 0)
}
