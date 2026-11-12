///|
// Verification adapter only. Expected values come from independent Python tools.
fn main raise {
  let args = @env.args()
  let source = @fs.read_file_to_string(args[args.length() - 1])
  guard @json.parse(source) is Array(cases) else {
    abort("Expected case array")
  }
  let results = cases.map(item => {
    guard item is Object(fields) &&
      fields.get("type") is Some(String(kind)) &&
      fields.get("transform") is Some(String(transform)) &&
      fields.get("input") is Some(input) else {
      abort("Invalid case")
    }
    let value : @moonice.Scalar = match (kind, input) {
      (_, Null) => Missing
      ("string", String(s)) => Text(s)
      ("binary", String(s)) => Binary(@base64.decode(s))
      (_, String(s)) => Integer(@json.from_json(Json(s)))
      _ => abort("Unsupported case value")
    }
    if transform == "manifest-list" {
      guard value is Binary(data) else { abort("Expected Avro bytes") }
      return Json(@moonice.decode_manifest_list(data)) catch {
        @moonice.Invalid(code, _, _) => Json(code)
      }
    }
    if transform == "parquet-select" {
      guard value is Binary(data) && fields.get("rows") is Some(Number(n, ..)) else {
        abort("Expected Parquet bytes and row count")
      }
      let file : @moonice.DataFile = {
        path: "oracle.parquet",
        format: "PARQUET",
        content: 0,
        record_count: n.to_int64(),
        size_bytes: data.length().to_int64(),
        partition: Map([]),
        equality_ids: [],
        lower_bounds: Map([]),
        upper_bounds: Map([]),
        null_counts: Map([]),
        nan_counts: Map([]),
      }
      let rows = @moonice.read_data_rows(data, file, field_ids=[2])
      return Json(rows.map(row => row.values[2].display_json()))
    }
    if transform == "parquet-fields" {
      guard value is Binary(data) else { abort("Expected Parquet bytes") }
      return Json(
        @moonice.parquet_field_ids(data) catch {
          error => {
            println("Parquet preflight: \{error}")
            abort("Reference failure")
          }
        },
      )
    }
    match @moonice.transform_partition(value, Json(kind), transform) {
      Some(Integer(n)) => Json(n)
      Some(Text(s)) => Json(s)
      Some(Binary(b)) => Json(@base64.encode(b))
      Some(Missing) => Json::null()
      _ => abort("Unsupported transform in reference corpus")
    }
  })
  println(Json(results).stringify())
}
