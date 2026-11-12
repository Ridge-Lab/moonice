///|
/// Read explicit top-level physical-name aliases from Iceberg table metadata.
/// Names in the current logical schema do not establish a physical ID.
pub fn parse_name_mapping(source : String) -> Map[String, Int32] raise IceError {
  let path = "schema.name-mapping.default"
  if source.length() > 8 * 1024 * 1024 {
    raise Invalid("RESOURCE_LIMIT", "metadata", "Metadata exceeds 8 MiB")
  }
  let metadata = @json.parse(source) catch {
    _ => raise Invalid("INVALID_JSON", "metadata", "Invalid table metadata")
  }
  let result = Map([])
  let property = json_field(json_field(metadata, "properties"), path)
  if property is Null {
    return result
  }
  let mapping = @json.parse(text_value(property, path)) catch {
    _ =>
      raise Invalid(
        "INVALID_NAME_MAPPING", path, "Name mapping must contain a JSON list",
      )
  }
  let seen = Map([])
  for item in array_value(mapping, path) {
    let raw = json_field(item, "field-id")
    // Iceberg permits historical aliases with no corresponding field ID.
    if raw is Null {
      continue
    }
    let id = int_value(raw, path)
    guard id > 0 && !seen.contains(id) else {
      raise Invalid(
        "INVALID_NAME_MAPPING", path, "Duplicate or invalid top-level field ID",
      )
    }
    seen[id] = true
    for value in array_value(json_field(item, "names"), path) {
      let name = text_value(value, path)
      guard !result.contains(name) else {
        raise Invalid(
          "INVALID_NAME_MAPPING", path, "Ambiguous physical column name",
        )
      }
      result[name] = id
    }
  }
  result
}

///|
fn projection_field(field : Field) -> Unit raise IceError {
  guard field.field_type
    is String(
      "boolean"
      | "int"
      | "long"
      | "date"
      | "time"
      | "timestamp"
      | "timestamptz"
      | "float"
      | "double"
      | "string"
      | "binary"
    ) else {
    raise Invalid(
      "UNSUPPORTED_TYPE",
      field.name,
      "Projection requires a supported top-level scalar",
    )
  }
}

///|
fn select_schema(
  schema : Schema,
  names : Array[String],
) -> Schema raise IceError {
  guard !names.is_empty() else {
    raise Invalid("INVALID_PROJECTION", "columns", "Select at least one column")
  }
  let seen = Map([])
  let fields = []
  for name in names {
    let field = schema.field_named(name)
    guard !seen.contains(field.id) else {
      raise Invalid("INVALID_PROJECTION", name, "Duplicate output column")
    }
    projection_field(field)
    seen[field.id] = true
    fields.push(field)
  }
  { ..schema, fields, }
}

///|
fn predicate_ids(p : Predicate, needed : Map[Int32, Bool]) -> Unit {
  match p {
    All => ()
    Compare(id, _, _) | IsNull(id) | NotNull(id) => needed[id] = true
    And(a, b) | Or(a, b) => {
      predicate_ids(a, needed)
      predicate_ids(b, needed)
    }
  }
}
