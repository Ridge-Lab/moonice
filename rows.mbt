///|
#derive(Debug, Eq, ToJson)
pub(all) struct DataRow {
  file_path : String
  position : Int64
  values : Map[Int32, Scalar]
}

///|
fn parquet_scalar(value : @parquet.Value) -> Scalar {
  match value {
    Null => Missing
    Boolean(v) => Boolean(v)
    Int32(v) => Integer(v.to_int64())
    Int64(v) | TimestampMicros(v) => Integer(v)
    Float(v) => Real(v.to_double())
    Double(v) => Real(v)
    String(v) => Text(v)
    Binary(v) => Binary(v)
  }
}

///|
/// Materialize bounded Parquet rows with original positions and physical IDs.
/// Select top-level columns with field_ids. This physical reader does not
/// apply Iceberg deletes, defaults, or partition constants; use scan_rows for a table.
pub fn read_data_rows(
  bytes : Bytes,
  file : DataFile,
  field_ids? : Array[Int32],
  name_mapping~ : Map[String, Int32] = Map([]),
) -> Array[DataRow] raise IceError {
  let wanted = match field_ids {
    None => None
    Some(ids) => {
      let selection = Map([])
      for id in ids {
        guard id > 0 && !selection.contains(id) else {
          raise Invalid(
            "INVALID_PROJECTION",
            file.path,
            "Physical field IDs must be positive and unique",
          )
        }
        selection[id] = true
      }
      guard !selection.is_empty() else {
        raise Invalid(
          "INVALID_PROJECTION",
          file.path,
          "Select at least one field ID",
        )
      }
      Some(selection)
    }
  }
  read_file_columns(bytes, file, wanted, name_mapping)
}

///|
fn read_file_columns(
  bytes : Bytes,
  file : DataFile,
  wanted : Map[Int32, Bool]?,
  aliases : Map[String, Int32],
  identity_ids~ : Map[Int32, Bool] = Map([]),
) -> Array[DataRow] raise IceError {
  if file.format != "PARQUET" {
    raise Invalid(
      "UNSUPPORTED_FILE_FORMAT",
      file.path,
      "Row execution requires Parquet",
    )
  }
  if bytes.length().to_int64() != file.size_bytes {
    raise Invalid(
      "FILE_LENGTH",
      file.path,
      "File length does not match manifest",
    )
  }
  if file.record_count > 100000L || bytes.length() > 64 * 1024 * 1024 {
    raise Invalid(
      "RESOURCE_LIMIT",
      file.path,
      "Row reading is limited to 100,000 rows and 64 MiB per file",
    )
  }
  let (input, ids) = match wanted {
    None => (Some(bytes), parquet_field_ids(bytes))
    Some(ids) => projected_parquet(bytes, file, ids, aliases, identity_ids)
  }
  guard input is Some(input) else {
    // Projection of only missing (new or identity-partitioned) columns.
    return Array::makei(file.record_count.to_int(), i => {
      file_path: file.path,
      position: i.to_int64(),
      values: Map([]),
    })
  }
  let parquet = @parquet.read_bytes(input) catch {
    error => raise Invalid("PARQUET_DECODE", file.path, error.to_string())
  }
  if parquet.row_count().to_int64() != file.record_count ||
    parquet.columns().length() != ids.length() {
    raise Invalid(
      "PARQUET_SHAPE",
      file.path,
      "Footer/manifest/decoded dimensions differ",
    )
  }
  parquet
  .rows()
  .mapi((i, row) => {
    let values = Map([])
    for column, value in row {
      values[ids[column]] = parquet_scalar(value)
    }
    { file_path: file.path, position: i.to_int64(), values, }
  })
}

///|
/// Project by field ID, so renamed columns survive and newly added columns null-fill.
pub fn DataRow::project(
  self : DataRow,
  schema : Schema,
) -> Map[String, Scalar] raise IceError {
  let result = Map([])
  for field in schema.fields {
    let value = self.values.get(field.id).unwrap_or(Missing)
    if field.required && value == Missing {
      raise Invalid(
        "REQUIRED_FIELD_MISSING",
        field.name,
        "Required field is absent or null in data",
      )
    }
    let compatible = match (field.field_type, value) {
      (String("int" | "date"), Integer(n)) =>
        n >= -2147483648L && n <= 2147483647L
      (String("boolean"), Boolean(_))
      | (String("long" | "time" | "timestamp" | "timestamptz"), Integer(_))
      | (String("float" | "double"), Real(_))
      | (String("string"), Text(_))
      | (String("binary"), Binary(_)) => true
      (
        String(
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
        ),
        Missing,
      ) => true
      _ => false
    }
    if !compatible {
      raise Invalid(
        "UNSUPPORTED_TYPE",
        field.name,
        "Unsupported type or incompatible Parquet value",
      )
    }
    result[field.name] = value
  }
  result
}
