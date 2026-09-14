///|
/// Parse v2 table metadata without I/O. Malformed input and other format versions
/// are rejected; missing historical parents are allowed because snapshots expire.
pub fn parse_metadata(source : String) -> TableMetadata raise IceError {
  let root = @json.parse(source) catch {
    _ => raise Invalid("INVALID_JSON", "$", "Metadata is not valid JSON")
  }
  object(root, "$") |> ignore
  let version = int_value(json_field(root, "format-version"), "format-version")
  if version != 2 {
    raise Invalid(
      "UNSUPPORTED_VERSION",
      "format-version",
      "Only Iceberg v2 is supported; received \{version}",
    )
  }
  let schemas = array_value(json_field(root, "schemas"), "schemas").map(
    parse_schema,
  )
  let specs = array_value(
    json_field(root, "partition-specs"),
    "partition-specs",
  ).map(parse_partition_spec)
  let snapshots = match json_field(root, "snapshots") {
    Null => []
    j => array_value(j, "snapshots").map(parse_snapshot)
  }
  let refs : Array[SnapshotRef] = []
  match json_field(root, "refs") {
    Null => ()
    j =>
      for name, value in object(j, "refs") {
        let kind = text_value(json_field(value, "type"), "refs.\{name}.type")
        if kind != "branch" && kind != "tag" {
          raise Invalid(
            "INVALID_REF",
            "refs.\{name}",
            "Reference type must be branch or tag",
          )
        }
        refs.push({
          name,
          snapshot_id: long_value(
            json_field(value, "snapshot-id"),
            "refs.\{name}.snapshot-id",
          ),
          kind,
        })
      }
  }
  let current = opt_long(
    json_field(root, "current-snapshot-id"),
    "current-snapshot-id",
  )
  let table : TableMetadata = {
    uuid: text_value(json_field(root, "table-uuid"), "table-uuid"),
    location: text_value(json_field(root, "location"), "location"),
    current_schema_id: int_value(
      json_field(root, "current-schema-id"),
      "current-schema-id",
    ),
    default_spec_id: int_value(
      json_field(root, "default-spec-id"),
      "default-spec-id",
    ),
    last_sequence_number: nonnegative(
      long_value(
        json_field(root, "last-sequence-number"),
        "last-sequence-number",
      ),
      "last-sequence-number",
    ),
    current_snapshot_id: if current == Some(-1L) {
      None
    } else {
      current
    },
    schemas,
    partition_specs: specs,
    snapshots,
    refs,
  }
  validate_metadata(table)
  table
}

///|
fn parse_schema(j : Json) -> Schema raise IceError {
  let id = int_value(json_field(j, "schema-id"), "schema.schema-id")
  if json_field(j, "type") != Json::string("struct") {
    raise Invalid(
      "INVALID_SCHEMA",
      "schema[\{id}]",
      "Schema type must be struct",
    )
  }
  let fields = array_value(json_field(j, "fields"), "schema.fields").map(f => {
    let field : Field = {
      id: int_value(json_field(f, "id"), "field.id"),
      name: text_value(json_field(f, "name"), "field.name"),
      required: bool_value(json_field(f, "required"), "field.required"),
      field_type: json_field(f, "type"),
    }
    if field.id <= 0 ||
      field.id > 2147483447 ||
      field.name.is_empty() ||
      field.field_type is Null {
      raise Invalid(
        "INVALID_SCHEMA",
        "schema[\{id}]",
        "Fields need positive IDs, nonempty names and a type",
      )
    }
    field
  })
  let ids : Map[Int, Bool] = Map([])
  let names : Map[String, Bool] = Map([])
  for f in fields {
    if ids.contains(f.id) || names.contains(f.name) {
      raise Invalid(
        "DUPLICATE_FIELD",
        "schema[\{id}]",
        "Duplicate field ID or name",
      )
    }
    ids[f.id] = true
    names[f.name] = true
  }
  { id, fields }
}

///|
fn parse_partition_spec(j : Json) -> PartitionSpec raise IceError {
  {
    id: int_value(json_field(j, "spec-id"), "partition-spec.spec-id"),
    fields: array_value(json_field(j, "fields"), "partition-spec.fields").map(f => {
      source_id: int_value(
        json_field(f, "source-id"),
        "partition-field.source-id",
      ),
      field_id: int_value(json_field(f, "field-id"), "partition-field.field-id"),
      name: text_value(json_field(f, "name"), "partition-field.name"),
      transform: text_value(
        json_field(f, "transform"),
        "partition-field.transform",
      ),
    }),
  }
}

///|
fn parse_snapshot(j : Json) -> Snapshot raise IceError {
  {
    id: long_value(json_field(j, "snapshot-id"), "snapshot.snapshot-id"),
    parent_id: opt_long(
      json_field(j, "parent-snapshot-id"),
      "snapshot.parent-snapshot-id",
    ),
    sequence_number: nonnegative(
      long_value(json_field(j, "sequence-number"), "snapshot.sequence-number"),
      "snapshot.sequence-number",
    ),
    timestamp_ms: long_value(
      json_field(j, "timestamp-ms"),
      "snapshot.timestamp-ms",
    ),
    manifest_list: text_value(
      json_field(j, "manifest-list"),
      "snapshot.manifest-list",
    ),
    schema_id: opt_int(json_field(j, "schema-id"), "snapshot.schema-id"),
    operation: text_value(
      json_field(json_field(j, "summary"), "operation"),
      "snapshot.summary.operation",
    ),
  }
}

///|
fn validate_metadata(table : TableMetadata) -> Unit raise IceError {
  let schemas : Map[Int, Bool] = Map([])
  for s in table.schemas {
    if schemas.contains(s.id) {
      raise Invalid("DUPLICATE_SCHEMA", "schemas", "Duplicate schema ID")
    }
    schemas[s.id] = true
  }
  if !schemas.contains(table.current_schema_id) {
    raise Invalid(
      "SCHEMA_NOT_FOUND", "current-schema-id", "Current schema is missing",
    )
  }
  let specs : Map[Int, Bool] = Map([])
  for s in table.partition_specs {
    if specs.contains(s.id) {
      raise Invalid(
        "DUPLICATE_SPEC", "partition-specs", "Duplicate partition spec ID",
      )
    }
    specs[s.id] = true
  }
  if !specs.contains(table.default_spec_id) {
    raise Invalid(
      "SPEC_NOT_FOUND", "default-spec-id", "Default partition spec is missing",
    )
  }
  let snapshots : Map[Int64, Snapshot] = Map([])
  for s in table.snapshots {
    if snapshots.contains(s.id) {
      raise Invalid("DUPLICATE_SNAPSHOT", "snapshots", "Duplicate snapshot ID")
    }
    if s.schema_id is Some(id) && !schemas.contains(id) {
      raise Invalid(
        "SCHEMA_NOT_FOUND", "snapshot.schema-id", "Snapshot schema is missing",
      )
    }
    if s.sequence_number > table.last_sequence_number {
      raise Invalid(
        "INVALID_SEQUENCE", "snapshots", "Snapshot sequence exceeds table sequence",
      )
    }
    snapshots[s.id] = s
  }
  if table.current_snapshot_id is Some(id) && !snapshots.contains(id) {
    raise Invalid(
      "SNAPSHOT_NOT_FOUND", "current-snapshot-id", "Current snapshot is missing",
    )
  }
  for r in table.refs {
    if !snapshots.contains(r.snapshot_id) {
      raise Invalid(
        "DANGLING_REF",
        "refs.\{r.name}",
        "Reference points to a missing snapshot",
      )
    }
  }
  for s in table.snapshots {
    if s.parent_id is Some(parent) && snapshots.get(parent) is Some(p) {
      if p.sequence_number >= s.sequence_number {
        raise Invalid(
          "INVALID_ANCESTRY", "snapshots", "Retained parents must have an earlier sequence",
        )
      }
    }
  }
}
