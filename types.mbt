///|
/// A rejected input, with a stable machine-readable code and source path.
#derive(Debug)
pub(all) suberror IceError {
  Invalid(String, String, String)
}

///|
pub impl Show for IceError with fn output(self, logger) {
  match self {
    Invalid(code, path, message) =>
      logger.write_string("\{code} at \{path}: \{message}")
  }
}

///|
#derive(Debug, Eq, ToJson)
pub(all) struct Field {
  id : Int32
  name : String
  required : Bool
  field_type : Json
}

///|
#derive(Debug, Eq, ToJson)
pub(all) struct Schema {
  id : Int32
  fields : Array[Field]
}

///|
#derive(Debug, Eq, ToJson)
pub(all) struct PartitionField {
  source_id : Int32
  field_id : Int32
  name : String
  transform : String
}

///|
#derive(Debug, Eq, ToJson)
pub(all) struct PartitionSpec {
  id : Int32
  fields : Array[PartitionField]
}

///|
#derive(Debug, Eq, ToJson)
pub(all) struct Snapshot {
  id : Int64
  parent_id : Int64?
  sequence_number : Int64
  timestamp_ms : Int64
  manifest_list : String
  schema_id : Int32?
  operation : String
}

///|
#derive(Debug, Eq, ToJson)
pub(all) struct SnapshotRef {
  name : String
  snapshot_id : Int64
  kind : String
}

///|
/// Parsed Iceberg v2 metadata. IDs remain signed 64-bit integers on every target.
#derive(Debug, ToJson)
pub(all) struct TableMetadata {
  uuid : String
  location : String
  current_schema_id : Int32
  default_spec_id : Int32
  last_sequence_number : Int64
  current_snapshot_id : Int64?
  schemas : Array[Schema]
  partition_specs : Array[PartitionSpec]
  snapshots : Array[Snapshot]
  refs : Array[SnapshotRef]
}

///|
pub fn TableMetadata::schema(
  self : TableMetadata,
  id : Int32,
) -> Schema raise IceError {
  for schema in self.schemas {
    if schema.id == id {
      return schema
    }
  }
  raise Invalid("SCHEMA_NOT_FOUND", "schemas", "No schema with ID \{id}")
}

///|
pub fn Schema::field(self : Schema, id : Int32) -> Field? {
  self.fields.iter().find_first(f => f.id == id)
}

///|
pub fn Schema::field_named(
  self : Schema,
  name : String,
) -> Field raise IceError {
  match self.fields.iter().find_first(f => f.name == name) {
    Some(field) => field
    None =>
      raise Invalid(
        "FIELD_NOT_FOUND",
        "schemas[\{self.id}]",
        "Unknown field: \{name}",
      )
  }
}

///|
pub fn TableMetadata::snapshot(
  self : TableMetadata,
  id? : Int64,
  ref_name? : String,
) -> Snapshot raise IceError {
  if id is Some(_) && ref_name is Some(_) {
    raise Invalid(
      "AMBIGUOUS_SNAPSHOT", "snapshot", "Choose an ID or a reference, not both",
    )
  }
  let selected = match (id, ref_name) {
    (Some(id), None) => Some(id)
    (None, Some(name)) =>
      match self.refs.iter().find_first(r => r.name == name) {
        Some(r) => Some(r.snapshot_id)
        None =>
          raise Invalid("REF_NOT_FOUND", "refs", "Unknown reference: \{name}")
      }
    _ => self.current_snapshot_id
  }
  guard selected is Some(id) else {
    raise Invalid(
      "EMPTY_TABLE", "current-snapshot-id", "The table has no current snapshot",
    )
  }
  match self.snapshots.iter().find_first(s => s.id == id) {
    Some(snapshot) => snapshot
    None =>
      raise Invalid(
        "SNAPSHOT_NOT_FOUND",
        "snapshots",
        "Snapshot \{id} is not retained",
      )
  }
}
