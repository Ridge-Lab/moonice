///|
/// Read a standard Avro manifest list. Only null/deflate OCF codecs are supported.
pub fn decode_manifest_list(data : Bytes) -> Array[Manifest] raise IceError {
  container_records(data, "manifest-list").map(row => {
    let m : Manifest = {
      path: avro_string(avro_field(row, "manifest_path"), "manifest_path"),
      length: nonnegative(
        avro_long(avro_field(row, "manifest_length"), "manifest_length"),
        "manifest_length",
      ),
      spec_id: avro_int(
        avro_field(row, "partition_spec_id"),
        "partition_spec_id",
      ),
      content: avro_int(avro_field(row, "content"), "content"),
      sequence_number: nonnegative(
        avro_long(avro_field(row, "sequence_number"), "sequence_number"),
        "sequence_number",
      ),
      min_sequence_number: nonnegative(
        avro_long(avro_field(row, "min_sequence_number"), "min_sequence_number"),
        "min_sequence_number",
      ),
      added_snapshot_id: avro_long(
        avro_field(row, "added_snapshot_id"),
        "added_snapshot_id",
      ),
    }
    if m.path.is_empty() ||
      (m.content != 0 && m.content != 1) ||
      m.min_sequence_number > m.sequence_number {
      raise Invalid(
        "INVALID_MANIFEST_LIST",
        m.path,
        "Invalid path, content or sequence range",
      )
    }
    m
  })
}

///|
fn inherited_sequence(
  d : @avro_codec.Datum,
  status : Int,
  inherited : Int64,
  path : String,
) -> Int64 raise IceError {
  match d {
    Null if status == 1 => inherited
    Null =>
      raise Invalid(
        "MISSING_SEQUENCE", path, "Only ADDED entries may inherit a null sequence number",
      )
    _ => nonnegative(avro_long(d, path), path)
  }
}

///|
/// Decode a v2 manifest, resolving null sequence numbers using its list entry.
pub fn decode_manifest(
  data : Bytes,
  manifest : Manifest,
) -> Array[ManifestEntry] raise IceError {
  if data.length().to_int64() != manifest.length {
    raise Invalid(
      "MANIFEST_LENGTH_MISMATCH",
      manifest.path,
      "Manifest length disagrees with the manifest list",
    )
  }
  let (header, _) = @avro.decode_header(data) catch {
    err => raise Invalid("INVALID_AVRO", manifest.path, "\{Repr(err)}")
  }
  for
    pair in [
      ("format-version", "2"),
      ("partition-spec-id", manifest.spec_id.to_string()),
      ("content", if manifest.content == 0 { "data" } else { "deletes" }),
    ] {
    let (key, expected) = pair
    guard header.metadata().get(key) is Some(value) &&
      value == @utf8.encode(expected) else {
      raise Invalid(
        "MANIFEST_HEADER",
        manifest.path,
        "Header \{key} disagrees with v2 manifest descriptor",
      )
    }
  }
  container_records(data, manifest.path).map(row => {
    let status = avro_int(avro_field(row, "status"), "status")
    if status < 0 || status > 2 {
      raise Invalid(
        "INVALID_STATUS",
        manifest.path,
        "Entry status must be 0, 1 or 2",
      )
    }
    let snapshot_id = match avro_field(row, "snapshot_id") {
      Null if status == 1 => manifest.added_snapshot_id
      d => avro_long(d, "snapshot_id")
    }
    let file = parse_data_file(avro_field(row, "data_file"))
    if (manifest.content == 0 && file.content != 0) ||
      (manifest.content == 1 && file.content == 0) {
      raise Invalid(
        "CONTENT_MISMATCH",
        manifest.path,
        "Manifest content disagrees with its file content",
      )
    }
    {
      manifest_path: manifest.path,
      spec_id: manifest.spec_id,
      status,
      snapshot_id,
      sequence_number: inherited_sequence(
        avro_field(row, "sequence_number"),
        status,
        manifest.sequence_number,
        "sequence_number",
      ),
      file_sequence_number: inherited_sequence(
        avro_field(row, "file_sequence_number"),
        status,
        manifest.sequence_number,
        "file_sequence_number",
      ),
      file,
    }
  })
}

///|
fn parse_data_file(d : @avro_codec.Datum) -> DataFile raise IceError {
  let path = avro_string(avro_field(d, "file_path"), "file_path")
  let content = avro_int(avro_field(d, "content"), "content")
  if path.is_empty() || content < 0 || content > 2 {
    raise Invalid("INVALID_DATA_FILE", path, "Invalid file path or content")
  }
  let partition : Map[String, Scalar] = Map([])
  match avro_field(d, "partition") {
    Record(fields) =>
      for pair in fields {
        let (name, value) = pair
        partition[name] = avro_scalar(value, path)
      }
    _ =>
      raise Invalid(
        "INVALID_PARTITION", path, "Partition must be an Avro record",
      )
  }
  let equality_ids = match avro_field(d, "equality_ids") {
    Null => []
    Array(a) => a.map(d => avro_int(d, "equality_ids"))
    _ =>
      raise Invalid(
        "INVALID_EQUALITY_IDS", path, "Expected an array of field IDs",
      )
  }
  if content == 2 && equality_ids.is_empty() {
    raise Invalid(
      "INVALID_EQUALITY_IDS", path, "Equality deletes require field IDs",
    )
  }
  let seen_ids : Map[Int, Bool] = Map([])
  for id in equality_ids {
    if id <= 0 || id > 2147483447 || seen_ids.contains(id) {
      raise Invalid(
        "INVALID_EQUALITY_IDS", path, "Equality IDs must be valid and unique",
      )
    }
    seen_ids[id] = true
  }
  {
    path,
    content,
    partition,
    equality_ids,
    format: avro_string(avro_field(d, "file_format"), "file_format"),
    record_count: nonnegative(
      avro_long(avro_field(d, "record_count"), "record_count"),
      "record_count",
    ),
    size_bytes: nonnegative(
      avro_long(avro_field(d, "file_size_in_bytes"), "file_size_in_bytes"),
      "file_size_in_bytes",
    ),
    lower_bounds: byte_metrics(avro_field(d, "lower_bounds"), "lower_bounds"),
    upper_bounds: byte_metrics(avro_field(d, "upper_bounds"), "upper_bounds"),
    null_counts: count_metrics(
      avro_field(d, "null_value_counts"),
      "null_value_counts",
    ),
    nan_counts: count_metrics(
      avro_field(d, "nan_value_counts"),
      "nan_value_counts",
    ),
  }
}
