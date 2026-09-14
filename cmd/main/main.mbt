///|
fn usage() -> Unit {
  println("MoonIce 0.1.0 — Iceberg v2 snapshot inspector")
  println("moon run cmd/main --target js -- <action> <bundle> [options]")
  println("Actions: inspect, plan, scan, diff, check")
  println(
    "Options: --snapshot ID | --ref NAME, --filter JSON, --filter-file PATH, --limit N, --from ID",
  )
  println(
    "Pack local standard files: pack <metadata.json> --objects <uri-to-local-path.json> --out <bundle.json>",
  )
}

///|
fn execute(args : Array[String]) -> Int raise {
  if args.length() < 2 || args[1] == "--help" || args[1] == "help" {
    usage()
    return 0
  }
  if args.length() < 3 {
    usage()
    return 2
  }
  let action = args[1]
  let input = args[2]
  let opts : Map[String, String] = Map([])
  let mut i = 3
  while i < args.length() {
    let name = args[i]
    if ![
        "--snapshot", "--ref", "--filter", "--filter-file", "--limit", "--from",
        "--objects", "--out",
      ].contains(name) ||
      i + 1 >= args.length() ||
      opts.contains(name) {
      println("Invalid, missing, or repeated option: \{name}")
      return 2
    }
    opts[name] = args[i + 1]
    i += 2
  }
  if action == "pack" {
    guard opts.get("--objects") is Some(mapping) &&
      opts.get("--out") is Some(output) else {
      usage()
      return 2
    }
    guard @json.parse(@fs.read_file_to_string(mapping)) is Object(objects) else {
      println("Object map must be a JSON object of URI -> local file path")
      return 2
    }
    if @fs.path_exists(output) {
      println("Refusing to overwrite existing output: \{output}")
      return 2
    }
    let files : Map[String, Json] = Map([])
    for uri, path in objects {
      guard path is String(local_path) else {
        println("Expected local path for \{uri}")
        return 2
      }
      files[uri] = Json::string(
        @base64.encode(@fs.read_file_to_bytes(local_path)),
      )
    }
    let bundle : Json = {
      "moonice_bundle_version": 1,
      "metadata": @fs.read_file_to_string(input),
      "files": Json::object(files),
    }
    ignore(@moonice.open_bundle(bundle.stringify()))
    @fs.write_string_to_file(output, bundle.stringify(indent=2))
    println("Packed \{files.length()} objects into \{output}")
    return 0
  }
  if !["inspect", "plan", "scan", "diff", "check"].contains(action) {
    usage()
    return 2
  }
  let options : Map[String, Json] = Map([("action", Json::string(action))])
  for name in ["snapshot", "ref", "from"] {
    if opts.get("--\{name}") is Some(value) {
      options[name] = Json::string(value)
    }
  }
  if opts.get("--limit") is Some(value) {
    options["limit"] = @json.parse(value)
  }
  if opts.contains("--filter") && opts.contains("--filter-file") {
    println("Choose --filter or --filter-file")
    return 2
  }
  if opts.get("--filter") is Some(value) {
    options["filter"] = @json.parse(value)
  }
  if opts.get("--filter-file") is Some(path) {
    options["filter"] = @json.parse(@fs.read_file_to_string(path))
  }
  let result = @json.parse(
    @moonice.run_request(
      @fs.read_file_to_string(input),
      Json::object(options).stringify(),
    ),
  )
  println(result.stringify(indent=2))
  if result is { "ok": False, .. } {
    return 1
  }
  if action == "check" &&
    result is { "result": { "findings": Array(findings), .. }, .. } &&
    findings.iter().any(f => f is { "severity": String("error"), .. }) {
    return 1
  }
  0
}

///|
// Node supplies both the runtime executable and script path. Keep the script
// path as argv[0], matching the native and Wasm command-line conventions.
#cfg(target="js")
fn cli_args() -> Array[String] {
  let args = @env.args()
  if args.is_empty() {
    []
  } else {
    args[1:].to_owned()
  }
}

///|
#cfg(not(target="js"))
fn cli_args() -> Array[String] {
  @env.args()
}

///|
fn main {
  let code = execute(cli_args()) catch {
    error => {
      println("MoonIce: \{error}")
      2
    }
  }
  if code != 0 {
    @sys.exit(code)
  }
}
