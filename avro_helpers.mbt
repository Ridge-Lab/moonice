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
fn avro_int(d : @avro_codec.Datum, path : String) -> Int32 raise IceError {
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
) -> Array[(Int32, @avro_codec.Datum)] raise IceError {
  let pairs = match unwrap_datum(d) {
    Null => []
    Array(a) => a
    _ =>
      raise Invalid(
        "INVALID_METRICS", path, "Expected Iceberg's Avro logical-map array",
      )
  }
  let seen : Map[Int32, Bool] = Map([])
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
) -> Map[Int32, Bytes] raise IceError {
  let result : Map[Int32, Bytes] = Map([])
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
) -> Map[Int32, Int64] raise IceError {
  let result : Map[Int32, Int64] = Map([])
  for pair in metric_pairs(d, path) {
    let (id, value) = pair
    result[id] = nonnegative(avro_long(value, path), path)
  }
  result
}

///|
fn[T] map_container(
  data : Bytes,
  path : String,
  project : (@avro_codec.Datum) -> T raise IceError,
  check_header~ : (@avro.OcfHeader) -> Unit raise IceError = _ => (),
  decoded_budget~ : Int32 = 64 * 1048576,
) -> Array[T] raise IceError {
  if data.length() > 64 * 1024 * 1024 {
    raise Invalid(
      "RESOURCE_LIMIT", path, "A manifest container must not exceed 64 MiB",
    )
  }
  let limits : @avro.OcfLimits = {
    max_metadata_entries: 128,
    max_metadata_bytes: 1048576,
    max_block_bytes: 8 * 1048576,
    max_records_per_block: 100000,
  }
  let (header, offset) = @avro.decode_header(data, limits~) catch {
    @avro.OcfError::UnsupportedCodec(codec) =>
      raise Invalid(
        "UNSUPPORTED_AVRO_CODEC",
        path,
        "Unsupported Avro codec: \{codec}",
      )
    err => raise Invalid("INVALID_AVRO", path, "\{Repr(err)}")
  }
  check_header(header)
  let sync = header.sync_marker()
  // Validate every envelope before expanding any block. Walk a second time
  // without retaining an offset table proportional to the number of blocks.
  visit_avro_blocks(data, offset, sync, path)
  let rows : Array[T] = []
  let mut remaining = decoded_budget
  visit_avro_blocks(data, offset, sync, path, visit=(encoded, count) => {
    let limit = remaining.min(limits.max_block_bytes)
    let payload = decode_avro_block(header.codec(), encoded, limit, path)
    remaining -= payload.length()
    let decoder = @avro_codec.Decoder::new(
      payload,
      limits=@avro_codec.CodecLimits::new(
        max_bytes=payload.length(),
        max_collection_items=limits.max_records_per_block,
      ),
    ) catch {
      err => raise Invalid("INVALID_AVRO", path, "\{Repr(err)}")
    }
    for _ in 0..<count {
      let datum = @avro_codec.decode_from(header.schema(), decoder) catch {
        err => raise Invalid("INVALID_AVRO", path, "\{Repr(err)}")
      }
      rows.push(project(datum))
    }
    decoder.ensure_finished() catch {
      err => raise Invalid("INVALID_AVRO", path, "\{Repr(err)}")
    }
  })
  rows
}

///|
fn decode_avro_block(
  codec : @avro.CompressionCodec,
  encoded : BytesView,
  limit : Int32,
  path : String,
) -> Bytes raise IceError {
  match codec {
    Null => {
      if encoded.length() > limit {
        raise Invalid(
          "RESOURCE_LIMIT", path, "Manifest decoded byte budget exceeded",
        )
      }
      encoded.to_owned()
    }
    Deflate => {
      // Count with fixed decode scratch first. A rejected stream never gets
      // an output allocation proportional to its declared or decoded length.
      let output = @flate.inflate_prefix(
        encoded,
        max_output=limit,
        two_pass=true,
      ) catch {
        @flate.InflateError(@flate.OutputLimitExceeded(_), _) =>
          raise Invalid(
            "RESOURCE_LIMIT", path, "Manifest decoded byte budget exceeded",
          )
        @flate.InflateError(_, message) =>
          raise Invalid("INVALID_AVRO", path, message)
      }
      let tail = encoded[output.consumed:]
      if !tail.is_empty() && !fastavro_checksum_prefix(tail, output.data) {
        raise Invalid(
          "INVALID_AVRO", path, "Trailing bytes after DEFLATE stream",
        )
      }
      output.data
    }
  }
}

///|
// fastavro 1.12.2's writer can leave the first three big-endian Adler-32
// bytes after a raw stream (zlib.compress(payload)[2:-1]).
fn fastavro_checksum_prefix(tail : BytesView, payload : Bytes) -> Bool {
  if tail.length() != 3 {
    return false
  }
  let mut a = 1
  let mut b = 0
  for byte in payload {
    a = (a + byte.to_int()) % 65521
    b = (b + a) % 65521
  }
  tail[0].to_int() == b >> 8 &&
  tail[1].to_int() == (b & 255) &&
  tail[2].to_int() == a >> 8
}

///|
fn visit_avro_blocks(
  data : Bytes,
  offset : Int32,
  sync : Bytes,
  path : String,
  visit~ : (BytesView, Int32) -> Unit raise IceError = (_, _) => (),
) -> Unit raise IceError {
  // Avro long and compact i64 share zigzag varints. Advance past payloads
  // without copying them; translate reader errors into the Avro context.
  let reader = FooterReader::{ bytes: data, offset, nodes: 0, }
  let mut total = 0L
  while reader.offset < data.length() {
    let count = reader.integer() catch {
      _ =>
        raise Invalid(
          "INVALID_AVRO", path, "Truncated or overflowing block count",
        )
    }
    let length = reader.integer() catch {
      _ =>
        raise Invalid(
          "INVALID_AVRO", path, "Truncated or overflowing block length",
        )
    }
    if count <= 0L || count > 100000L || total > 1000000L - count {
      raise Invalid(
        "RESOURCE_LIMIT", path, "Manifest blocks exceed record budget",
      )
    }
    total += count
    if length < 0L || length > 8L * 1048576L {
      raise Invalid("RESOURCE_LIMIT", path, "Manifest block exceeds 8 MiB")
    }
    if data.length() - reader.offset < 16 ||
      length > (data.length() - reader.offset - 16).to_int64() {
      raise Invalid("INVALID_AVRO", path, "Truncated manifest block")
    }
    let start = reader.offset
    reader.offset += length.to_int()
    if data[reader.offset:reader.offset + 16] != sync {
      raise Invalid("INVALID_AVRO", path, "Manifest block sync mismatch")
    }
    visit(data[start:reader.offset], count.to_int())
    reader.offset += 16
  }
}
