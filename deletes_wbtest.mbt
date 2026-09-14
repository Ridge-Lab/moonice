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
      { id: 0, fields: [] },
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
  content : Int,
  sequence : Int64,
  spec? : Int = 0,
  region? : String = "east",
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
