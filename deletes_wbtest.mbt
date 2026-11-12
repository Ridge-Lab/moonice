///|
fn delete_test_metadata() -> TableMetadata {
  {
    uuid: "test",
    location: "memory://test",
    current_schema_id: 0,
    default_spec_id: 0,
    last_sequence_number: 10L,
    current_snapshot_id: None,
    schemas: [],
    partition_specs: [
      { id: 0, fields: [], },
      {
        id: 1,
        fields: [
          {
            source_id: 1,
            field_id: 1000,
            name: "region",
            transform: "identity",
          },
        ],
      },
    ],
    snapshots: [],
    refs: [],
  }
}

///|
fn delete_test_entry(
  content : Int32,
  sequence : Int64,
  spec~ : Int32 = 0,
  region~ : String = "east",
) -> ManifestEntry {
  let file = metric_file(0L, 3L)
  {
    manifest_path: "manifest",
    spec_id: spec,
    status: 1,
    snapshot_id: 1L,
    sequence_number: sequence,
    file_sequence_number: sequence,
    file: {
      ..file,
      content,
      path: if content == 0 {
        "data"
      } else {
        "delete"
      },
      partition: if spec == 0 {
        Map([])
      } else {
        Map([("region", Text(region))])
      },
      equality_ids: if content == 2 {
        [1]
      } else {
        []
      },
    },
  }
}

///|
test "NaN identity partitions match for delete applicability" {
  let nan = 0x7ff8000000000000L.reinterpret_as_double()
  let data = delete_test_entry(0, 1L, spec=1)
  let deletion = delete_test_entry(1, 2L, spec=1)
  data.file.partition["region"] = Real(nan)
  deletion.file.partition["region"] = Real(nan)
  assert_true(explain_delete(delete_test_metadata(), data, deletion).applies)
}

///|
test "identity projection follows the data file spec and preserves stored nulls" {
  let original = delete_test_metadata()
  let identity = original.partition_specs[1].fields[0]
  let bucket = {
    ..identity,
    field_id: 1001,
    name: "hash",
    transform: "bucket[16]",
  }
  let metadata = {
    ..original,
    default_spec_id: 2,
    partition_specs: [
      { id: 1, fields: [bucket, identity], },
      { id: 2, fields: [bucket], },
    ],
  }
  let data = delete_test_entry(0, 1L, spec=1)
  data.file.partition["hash"] = Integer(5L)
  fn resolve(
    spec : Int32,
    values : Map[Int32, Scalar],
  ) -> Map[Int32, Scalar] raise IceError {
    let row : DataRow = { file_path: data.file.path, position: 0L, values, }
    restore_identity_columns(metadata, { ..data, spec_id: spec, }, [row])
    row.values
  }
  assert_eq(resolve(1, Map([])).get(1), Some(Text("east")))
  assert_eq(resolve(1, Map([(1, Missing)])).get(1), Some(Missing))
  assert_eq(
    resolve(1, Map([(1, Text("physical"))])).get(1),
    Some(Text("physical")),
  )
  assert_eq(resolve(2, Map([])).get(1), None)
  data.file.partition["region"] = Missing
  assert_eq(resolve(1, Map([])).get(1), Some(Missing))
  data.file.partition.remove("region")
  assert_eq(resolve(1, Map([])).get(1), None)
}

///|
test "delete sequence boundary matrix follows Iceberg v2" {
  let metadata = delete_test_metadata()
  for data_seq in 0..<5 {
    for delete_seq in 0..<5 {
      let data = delete_test_entry(0, data_seq.to_int64())
      let positional = delete_test_entry(1, delete_seq.to_int64())
      let equality = delete_test_entry(2, delete_seq.to_int64())
      assert_eq(
        explain_delete(metadata, data, positional).applies,
        data_seq <= delete_seq,
      )
      assert_eq(
        explain_delete(metadata, data, equality).applies,
        data_seq < delete_seq,
      )
    }
  }
}

///|
test "unpartitioned equality deletes are global while position deletes are not" {
  let metadata = delete_test_metadata()
  let data = delete_test_entry(0, 1L, spec=1)
  assert_true(explain_delete(metadata, data, delete_test_entry(2, 2L)).applies)
  assert_false(explain_delete(metadata, data, delete_test_entry(1, 2L)).applies)
  assert_true(
    explain_delete(metadata, data, delete_test_entry(1, 2L, spec=1)).applies,
  )
  assert_false(
    explain_delete(
      metadata,
      data,
      delete_test_entry(2, 2L, spec=1, region="west"),
    ).applies,
  )
}
