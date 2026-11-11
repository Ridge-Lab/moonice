///|
fn demonstrate() -> Unit raise {
  let bundle = @moonice.open_bundle(
    @fs.read_file_to_string("fixtures/partitioned.icebundle.json"),
  )
  let state = bundle.load_snapshot()
  // 2024-03-01T00:00:00 UTC, expressed as exact epoch microseconds.
  let predicate = @moonice.parse_predicate(
    "{\"field\":\"ts\",\"op\":\">=\",\"value\":\"1709251200000000\"}",
    state.schema,
  )
  // Count complete objects requested after metadata and manifests are loaded.
  let mut opens = 0
  let mut bytes = 0
  let read = path => {
    let data = bundle.read_file(path)
    opens += 1
    bytes += data.length()
    data
  }
  let all = @moonice.scan_rows(bundle.metadata, state, All, read)
  let full_opens = opens
  let full_bytes = bytes
  let expected_ids = []
  for row in all.rows {
    if predicate.matches(row.values) &&
      row.values.get(1) is Some(@moonice.Integer(id)) {
      expected_ids.push(id)
    }
  }
  opens = 0
  bytes = 0
  let selected_ids = []
  let mut total = 0L
  let mut batches = 0
  let result = @moonice.scan_batches(
    bundle.metadata,
    state,
    predicate,
    read,
    rows => {
      batches += 1
      for row in rows {
        if row.values.get(1) is Some(@moonice.Integer(id)) {
          selected_ids.push(id)
          total += id
        }
      }
    },
    batch_size=1,
  )
  println("partition_specs=\{bundle.metadata.partition_specs.length()}")
  println(
    "batches=\{batches} matched_rows=\{result.matched_rows} id_sum=\{total}",
  )
  println(
    "scanned_files=\{result.scanned_files} delete_files=\{result.delete_files}",
  )
  println(
    "full_opens=\{full_opens} full_bytes=\{full_bytes} filtered_opens=\{opens} filtered_bytes=\{bytes}",
  )
  expected_ids.sort()
  selected_ids.sort()
  assert_eq(selected_ids, expected_ids)
  assert_eq(selected_ids, [10L, 11L])
  assert_eq(batches, 2)
  assert_eq(full_opens, 6)
  assert_eq(opens, 2)
  assert_true(bytes < full_bytes)
}

///|
fn main {
  demonstrate() catch {
    error => {
      println("Batch example failed: \{error}")
      @sys.exit(1)
    }
  }
}
