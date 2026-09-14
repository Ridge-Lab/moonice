///|
fn unwrap_datum(d : @avro_codec.Datum) -> @avro_codec.Datum {
  match d {
    Union(_, value) => unwrap_datum(value)
    _ => d
  }
}

///|
fn avro_field(d : @avro_codec.Datum, name : String) -> @avro_codec.Datum {
  match unwrap_datum(d) {
    Record(fields) => {
      for pair in fields {
        let (key, value) = pair
        if key == name {
          return unwrap_datum(value)
        }
      }
      @avro_codec.Null
    }
    _ => @avro_codec.Null
  }
}

///|
fn avro_long(d : @avro_codec.Datum, path : String) -> Int64 raise IceError {
  match unwrap_datum(d) {
    Long(n) => n
    Int(n) => n.to_int64()
    _ => raise Invalid("INVALID_MANIFEST", path, "Expected an Avro integer")
  }
}

///|
fn avro_int(d : @avro_codec.Datum, path : String) -> Int raise IceError {
  let n = avro_long(d, path)
  if n < -2147483648L || n > 2147483647L {
    raise Invalid("INVALID_MANIFEST", path, "Integer is outside 32-bit range")
  }
  n.to_int()
}

///|
fn avro_string(d : @avro_codec.Datum, path : String) -> String raise IceError {
  match unwrap_datum(d) {
    String(s) => s
    _ => raise Invalid("INVALID_MANIFEST", path, "Expected an Avro string")
  }
}

///|
fn avro_scalar(d : @avro_codec.Datum, path : String) -> Scalar raise IceError {
  match unwrap_datum(d) {
    Null => Missing
    Int(n) => Integer(n.to_int64())
    Long(n) => Integer(n)
    Float(n) => Real(n.to_double())
    Double(n) => Real(n)
    Boolean(b) => Boolean(b)
    String(s) => Text(s)
    Bytes(b) | Fixed(b) => Binary(b)
    _ =>
      raise Invalid(
        "INVALID_PARTITION", path, "Partition values must be primitive",
      )
  }
}

///|
fn metric_pairs(
  d : @avro_codec.Datum,
  path : String,
) -> Array[(Int, @avro_codec.Datum)] raise IceError {
  let pairs = match unwrap_datum(d) {
    Null => []
    Array(a) => a
    _ =>
      raise Invalid(
        "INVALID_METRICS", path, "Expected Iceberg's Avro logical-map array",
      )
  }
  let seen : Map[Int, Bool] = Map([])
  pairs.map(pair => {
    let id = avro_int(avro_field(pair, "key"), path)
    if id <= 0 || seen.contains(id) {
      raise Invalid(
        "INVALID_METRICS", path, "Metric field IDs must be positive and unique",
      )
    }
    seen[id] = true
    (id, avro_field(pair, "value"))
  })
}

///|
fn byte_metrics(
  d : @avro_codec.Datum,
  path : String,
) -> Map[Int, Bytes] raise IceError {
  let result : Map[Int, Bytes] = Map([])
  for pair in metric_pairs(d, path) {
    let (id, value) = pair
    match value {
      Bytes(b) => result[id] = b
      _ => raise Invalid("INVALID_METRICS", path, "Bound value must be bytes")
    }
  }
  result
}

///|
fn count_metrics(
  d : @avro_codec.Datum,
  path : String,
) -> Map[Int, Int64] raise IceError {
  let result : Map[Int, Int64] = Map([])
  for pair in metric_pairs(d, path) {
    let (id, value) = pair
    result[id] = nonnegative(avro_long(value, path), path)
  }
  result
}

///|
fn container_records(
  data : Bytes,
  path : String,
) -> Array[@avro_codec.Datum] raise IceError {
  if data.length() > 64 * 1024 * 1024 {
    raise Invalid(
      "RESOURCE_LIMIT", path, "A manifest container must not exceed 64 MiB",
    )
  }
  let (_, rows) = @avro.decode_container(data) catch {
    @avro.OcfError::UnsupportedCodec(codec) =>
      raise Invalid(
        "UNSUPPORTED_AVRO_CODEC",
        path,
        "Unsupported Avro codec: \{codec}",
      )
    err => raise Invalid("INVALID_AVRO", path, "\{Repr(err)}")
  }
  if rows.length() > 1000000 {
    raise Invalid(
      "RESOURCE_LIMIT", path, "A manifest container must not exceed one million entries",
    )
  }
  rows
}
