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
  let mut total = 0L
  let mut batches = 0
  let result = bundle.scan_batches(
    predicate,
    rows => {
      batches += 1
      for row in rows {
        if row.values.get(1) is Some(@moonice.Integer(id)) {
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
  if result.matched_rows != 2 || total != 21L || batches != 2 {
    @sys.exit(1)
  }
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
