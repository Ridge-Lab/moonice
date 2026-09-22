///|
test "batch output equals materialized scan and retains independent arrays" {
  let bundle = @moonice.open_bundle(delete_bundle)
  let batches : Array[Array[@moonice.DataRow]] = []
  let summary = bundle.scan_batches(
    All,
    batch => batches.push(batch),
    batch_size=1,
  )
  let expected = bundle.scan(All)
  assert_eq(batches.length(), 2)
  assert_eq(batches[0].length(), 1)
  assert_eq(batches[1].length(), 1)
  assert_eq(batches[0][0], expected.rows[0])
  assert_eq(batches[1][0], expected.rows[1])
  assert_eq(summary.read_rows, 5)
  assert_eq(summary.deleted_rows, 3)
  assert_eq(summary.matched_rows, 2)
  assert_eq(summary.scanned_files, 2)
  assert_eq(summary.delete_files, 2)
}

///|
test "batch size is validated and empty scans emit no empty batches" {
  let bundle = @moonice.open_bundle(delete_bundle)
  let count = Ref(0)
  let summary = bundle.scan_batches(Compare(1, Eq, Integer(999L)), _ => {
    count.val += 1
  })
  assert_eq(count.val, 0)
  assert_eq(summary.matched_rows, 0)
  for size in [0, -1, 100001] {
    try bundle.scan_batches(All, _ => (), batch_size=size) catch {
      @moonice.Invalid(code, _, _) => assert_eq(code, "INVALID_BATCH_SIZE")
    } noraise {
      _ => fail("Invalid batch size accepted")
    }
  }
}

///|
test "callback failure stops reads and propagates the original error" {
  let bundle = @moonice.open_bundle(reference_bundle)
  let state = bundle.load_snapshot()
  let reads : Array[String] = []
  try
    @moonice.scan_batches(
      bundle.metadata,
      state,
      All,
      path => {
        reads.push(path)
        bundle.read_file(path)
      },
      _ => raise @moonice.Invalid("SINK_FAILED", "consumer", "stop"),
      batch_size=1,
    )
  catch {
    @moonice.Invalid(code, path, _) => {
      assert_eq(code, "SINK_FAILED")
      assert_eq(path, "consumer")
    }
  } noraise {
    _ => fail("Callback failure lost")
  }
  assert_eq(reads.length(), 1)
}

///|
test "delete files are read once while shared indexes serve multiple data files" {
  let bundle = @moonice.open_bundle(delete_bundle)
  let state = bundle.load_snapshot()
  let reads : Map[String, Int] = Map([])
  let summary = @moonice.scan_batches(
    bundle.metadata,
    state,
    All,
    path => {
      reads[path] = reads.get(path).unwrap_or(0) + 1
      bundle.read_file(path)
    },
    _ => (),
  )
  assert_eq(summary.delete_files, 2)
  assert_true(reads.iter().all(pair => pair.1 == 1))
}

///|
test "late input failure preserves already delivered batches without a success summary" {
  let bundle = @moonice.open_bundle(reference_bundle)
  let state = bundle.load_snapshot()
  let reads = Ref(0)
  let emitted = Ref(0)
  try
    @moonice.scan_batches(
      bundle.metadata,
      state,
      All,
      path => {
        reads.val += 1
        if reads.val == 2 {
          raise @moonice.Invalid("IO_FAILED", path, "simulated read failure")
        }
        bundle.read_file(path)
      },
      batch => emitted.val += batch.length(),
      batch_size=1,
    )
  catch {
    @moonice.Invalid(code, _, _) => assert_eq(code, "IO_FAILED")
  } noraise {
    _ => fail("Must fail on incomplete input")
  }
  assert_true(emitted.val > 0)
}
