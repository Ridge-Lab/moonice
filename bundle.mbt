///|
/// An offline transport for standard Iceberg bytes, not a replacement table format.
pub(all) struct Bundle {
  metadata : TableMetadata
  files : Map[String, Bytes]
} derive(Debug)

///|
pub(all) struct SnapshotState {
  snapshot : Snapshot
  schema : Schema
  manifests : Array[Manifest]
  entries : Array[ManifestEntry]
} derive(Debug, ToJson)

///|
/// Open an offline bundle. Raw metadata is a string to preserve 64-bit JSON IDs
/// when a browser or another JSON consumer transports the outer document.
pub fn open_bundle(source : String) -> Bundle raise IceError {
  if source.length() > 128 * 1024 * 1024 {
    raise Invalid(
      "RESOURCE_LIMIT", "$", "Bundle JSON exceeds 128 MiB of code units",
    )
  }
  let root = @json.parse(source) catch {
    _ => raise Invalid("INVALID_JSON", "$", "Bundle is not valid JSON")
  }
  if int_value(
      json_field(root, "moonice_bundle_version"),
      "moonice_bundle_version",
    ) !=
    1 {
    raise Invalid(
      "UNSUPPORTED_BUNDLE", "$", "Only bundle version 1 is supported",
    )
  }
  let metadata = parse_metadata(
    text_value(json_field(root, "metadata"), "metadata"),
  )
  let encoded = object(json_field(root, "files"), "files")
  if encoded.length() > 10000 {
    raise Invalid("RESOURCE_LIMIT", "files", "Bundle exceeds 10,000 objects")
  }
  let files : Map[String, Bytes] = Map([])
  let mut total = 0L
  for path, data in encoded {
    let bytes = @base64.decode(text_value(data, "files.\{path}")) catch {
      _ => raise Invalid("INVALID_BASE64", path, "Object is not valid base64")
    }
    total += bytes.length().to_int64()
    if bytes.length() > 64 * 1024 * 1024 || total > 128L * 1024L * 1024L {
      raise Invalid(
        "RESOURCE_LIMIT", path, "Object exceeds 64 MiB or decoded bundle exceeds 128 MiB",
      )
    }
    files[path] = bytes
  }
  { metadata, files }
}

///|
pub fn Bundle::read_file(self : Bundle, path : String) -> Bytes raise IceError {
  match self.files.get(path) {
    Some(bytes) => bytes
    None =>
      raise Invalid(
        "MISSING_FILE", path, "Referenced object is absent from this bundle",
      )
  }
}

///|
/// Load one snapshot using caller-provided storage. No directory listing is
/// required. Only live entries are returned; deleted manifest entries are history.
pub fn load_snapshot(
  metadata : TableMetadata,
  read_file : (String) -> Bytes raise IceError,
  snapshot_id? : Int64,
) -> SnapshotState raise IceError {
  let snapshot = match snapshot_id {
    Some(id) => metadata.snapshot(id~)
    None => metadata.snapshot()
  }
  let schema_id = if snapshot_id is Some(_) {
    snapshot.schema_id.unwrap_or(metadata.current_schema_id)
  } else {
    metadata.current_schema_id
  }
  let schema = metadata.schema(schema_id)
  let manifests = decode_manifest_list(read_file(snapshot.manifest_list))
  let entries : Array[ManifestEntry] = []
  let paths : Map[String, Bool] = Map([])
  let live_paths : Map[String, Bool] = Map([])
  for manifest in manifests {
    if paths.contains(manifest.path) {
      raise Invalid(
        "DUPLICATE_MANIFEST",
        manifest.path,
        "Manifest appears twice in a snapshot",
      )
    }
    paths[manifest.path] = true
    if !metadata.partition_specs.iter().any(s => s.id == manifest.spec_id) {
      raise Invalid(
        "SPEC_NOT_FOUND",
        manifest.path,
        "Manifest partition spec is not retained",
      )
    }
    if manifest.sequence_number > snapshot.sequence_number {
      raise Invalid(
        "INVALID_SEQUENCE",
        manifest.path,
        "Manifest sequence exceeds snapshot sequence",
      )
    }
    for entry in decode_manifest(read_file(manifest.path), manifest) {
      let spec = self_spec(metadata, entry.spec_id)
      if entry.file.partition.length() != spec.fields.length() ||
        !spec.fields.iter().all(f => entry.file.partition.contains(f.name)) {
        raise Invalid(
          "INVALID_PARTITION",
          entry.file.path,
          "Partition values disagree with the manifest partition spec",
        )
      }
      if entry.sequence_number > entry.file_sequence_number {
        raise Invalid(
          "INVALID_SEQUENCE",
          entry.file.path,
          "Data sequence cannot exceed file sequence",
        )
      }
      if entry.sequence_number > snapshot.sequence_number ||
        entry.file_sequence_number > snapshot.sequence_number {
        raise Invalid(
          "INVALID_SEQUENCE",
          entry.file.path,
          "File sequence exceeds snapshot sequence",
        )
      }
      if entry.status != 2 {
        if live_paths.contains(entry.file.path) {
          raise Invalid(
            "DUPLICATE_FILE",
            entry.file.path,
            "Live file occurs twice in the snapshot",
          )
        }
        live_paths[entry.file.path] = true
        entries.push(entry)
      }
    }
  }
  { snapshot, schema, manifests, entries }
}

///|
fn self_spec(
  metadata : TableMetadata,
  id : Int,
) -> PartitionSpec raise IceError {
  match metadata.partition_specs.iter().find_first(s => s.id == id) {
    Some(s) => s
    None =>
      raise Invalid(
        "SPEC_NOT_FOUND", "partition-spec", "Partition spec is missing",
      )
  }
}

///|
pub fn Bundle::load_snapshot(
  self : Bundle,
  snapshot_id? : Int64,
) -> SnapshotState raise IceError {
  load_snapshot(self.metadata, path => self.read_file(path), snapshot_id?)
}
