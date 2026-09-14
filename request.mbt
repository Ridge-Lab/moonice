///|
fn json_object(fields : Array[(String, Json)]) -> Json {
  Json::object(Map::from_array(fields))
}

///|
pub fn Scalar::display_json(self : Scalar) -> Json {
  match self {
    Missing => Json::null()
    Boolean(b) => b.to_json()
    Integer(n) => n.to_json()
    Real(n) =>
      if n.is_nan() {
        Json::string("NaN")
      } else if n.is_inf() {
        Json::string(n.to_string())
      } else {
        n.to_json()
      }
    Text(s) => Json::string(s)
    Binary(b) => json_object([("base64", Json::string(@base64.encode(b)))])
  }
}

///|
fn scan_json(result : ScanResult) -> Json raise IceError {
  let rows = result.rows.map(row => {
    let values = row.project(result.schema)
    json_object([
      ("file", Json::string(row.file_path)),
      ("position", row.position.to_json()),
      ("values", Json::object(values.map((_, v) => v.display_json()))),
    ])
  })
  json_object([
    ("rows", rows.to_json()),
    ("read_rows", result.read_rows.to_json()),
    ("deleted_rows", result.deleted_rows.to_json()),
    ("matched_rows", result.matched_rows.to_json()),
    ("truncated", result.truncated.to_json()),
  ])
}

///|
fn request_inner(source : String, options : String) -> Json raise IceError {
  let opts = @json.parse(options) catch {
    _ => raise Invalid("INVALID_JSON", "options", "Options are not valid JSON")
  }
  ignore(object(opts, "options"))
  let bundle = open_bundle(source)
  let action = text_value(json_field(opts, "action"), "action")
  if action == "inspect" {
    return bundle.metadata.to_json()
  }
  if action == "check" {
    return bundle.diagnose().to_json()
  }
  let id = opt_long(json_field(opts, "snapshot"), "snapshot")
  let ref_name = match json_field(opts, "ref") {
    Null => None
    String(s) => Some(s)
    _ => raise Invalid("INVALID_OPTION", "ref", "Expected a reference name")
  }
  if id is Some(_) && ref_name is Some(_) {
    raise Invalid("AMBIGUOUS_SNAPSHOT", "options", "Choose snapshot or ref")
  }
  let selected = match ref_name {
    Some(name) => Some(bundle.metadata.snapshot(ref_name=name).id)
    None => id
  }
  let state = match selected {
    Some(snapshot_id) => bundle.load_snapshot(snapshot_id~)
    None => bundle.load_snapshot()
  }
  if action == "diff" {
    let from = long_value(json_field(opts, "from"), "from")
    return diff_snapshots(bundle.load_snapshot(snapshot_id=from), state).to_json()
  }
  let predicate = parse_predicate(
    json_field(opts, "filter").stringify(),
    state.schema,
  )
  let plan = plan_scan(bundle.metadata, state, predicate)
  let delete_plan = plan_deletes(bundle.metadata, state, plan)
  let base = [
    ("metadata", bundle.metadata.to_json()),
    ("snapshot", state.snapshot.to_json()),
    ("schema", state.schema.to_json()),
    ("manifests", state.manifests.to_json()),
    ("plan", plan.to_json()),
    ("deletes", delete_plan.to_json()),
  ]
  if action == "plan" {
    return json_object(base)
  }
  if action != "scan" {
    raise Invalid(
      "INVALID_ACTION", "action", "Expected inspect, plan, scan, diff, or check",
    )
  }
  let limit = opt_int(json_field(opts, "limit"), "limit").unwrap_or(1000)
  base.push(
    (
      "scan",
      scan_json(
        scan_rows(
          bundle.metadata,
          state,
          predicate,
          path => bundle.read_file(path),
          limit~,
        ),
      ),
    ),
  )
  json_object(base)
}

///|
/// Transport-neutral JSON interface used by both the CLI and browser. Int64
/// output values are decimal strings. Errors always include code/path/message.
pub fn run_request(bundle_json : String, options_json : String) -> String {
  json_object([
    ("ok", true.to_json()),
    ("result", request_inner(bundle_json, options_json)),
  ]).stringify() catch {
    Invalid(code, path, message) =>
      json_object([
        ("ok", false.to_json()),
        (
          "error",
          json_object([
            ("code", Json::string(code)),
            ("path", Json::string(path)),
            ("message", Json::string(message)),
          ]),
        ),
      ]).stringify()
  }
}
