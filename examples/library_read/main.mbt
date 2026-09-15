///|
fn demonstrate() -> Unit raise {
  // The bundle holds unchanged standard file bytes; applications may supply
  // their own URI -> Bytes callback instead of this offline object map.
  let bundle = @moonice.open_bundle(
    @fs.read_file_to_string("fixtures/deletes.icebundle.json"),
  )
  let read = path => bundle.read_file(path)
  let state = @moonice.load_snapshot(bundle.metadata, read)

  // Reading the current data files alone leaves deleted rows visible.
  let mut physical_rows = 0
  for entry in state.entries {
    if entry.file.content == 0 {
      physical_rows += @moonice.read_data_rows(
        read(entry.file.path),
        entry.file,
      ).length()
    }
  }
  let visible = @moonice.scan_rows(bundle.metadata, state, All, read)
  println("physical_rows=\{physical_rows}")
  println("deleted_rows=\{visible.deleted_rows}")
  println("visible_rows=\{visible.matched_rows}")

  let predicate = @moonice.parse_predicate(
    "{\"field\":\"id\",\"op\":\"=\",\"value\":\"2\"}",
    state.schema,
  )
  let plan = @moonice.plan_scan(bundle.metadata, state, predicate)
  let associations = @moonice.plan_deletes(bundle.metadata, state, plan)
  for decision in associations {
    println("delete_applies=\{decision.applies} reason=\{decision.reason_code}")
  }
  let selected = @moonice.scan_rows(bundle.metadata, state, predicate, read)
  for row in selected.rows {
    // Projection uses the selected schema's field IDs. JSON integer values
    // are decimal strings so a JavaScript caller cannot round Int64 values.
    let values = row
      .project(selected.schema)
      .map((_, value) => value.display_json())
    println(Json::object(values).stringify())
  }
}

///|
fn main {
  demonstrate() catch {
    error => {
      println("Library example failed: \{error}")
      @sys.exit(1)
    }
  }
}
