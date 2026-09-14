///|
// Small bounded Thrift footer inspector. Page decoding stays in mizchi/parquet.
// This reader retains field IDs that the dependency's public schema omits.
priv enum FooterValue {
  Num(Int64)
  Blob(Bytes)
  Seq(Array[FooterValue])
  Obj(Map[Int, FooterValue])
  Other
}

///|
priv struct FooterReader {
  bytes : Bytes
  mut offset : Int
  mut nodes : Int
}

///|
fn FooterReader::take(self : FooterReader, n : Int) -> Bytes raise IceError {
  if n < 0 || n > self.bytes.length() - self.offset {
    raise Invalid("INVALID_PARQUET", "footer", "Truncated compact value")
  }
  let bytes = self.bytes[self.offset:self.offset + n].to_bytes()
  self.offset += n
  bytes
}

///|
fn FooterReader::byte(self : FooterReader) -> Int raise IceError {
  self.take(1)[0].to_int()
}

///|
fn FooterReader::varint(self : FooterReader) -> UInt64 raise IceError {
  let mut value = 0UL
  for i in 0..<10 {
    let byte = self.byte()
    if i == 9 && byte > 1 {
      raise Invalid("INVALID_PARQUET", "footer", "Varint overflows 64 bits")
    }
    value = value | ((byte & 127).to_uint64() << (7 * i))
    if byte < 128 {
      return value
    }
  }
  raise Invalid("INVALID_PARQUET", "footer", "Unterminated varint")
}

///|
fn FooterReader::integer(self : FooterReader) -> Int64 raise IceError {
  let n = self.varint()
  (n >> 1).reinterpret_as_int64() ^ -(n & 1UL).reinterpret_as_int64()
}

///|
fn FooterReader::length(self : FooterReader) -> Int raise IceError {
  let n = self.varint()
  if n > 1048576UL {
    raise Invalid(
      "RESOURCE_LIMIT", "footer", "Compact collection exceeds limit",
    )
  }
  n.to_int()
}

///|
fn FooterReader::value(
  self : FooterReader,
  kind : Int,
  depth : Int,
  collection? : Bool = false,
) -> FooterValue raise IceError {
  self.nodes += 1
  if depth > 32 || self.nodes > 100000 {
    raise Invalid(
      "RESOURCE_LIMIT", "footer", "Compact structure exceeds depth/node limit",
    )
  }
  match kind {
    1 | 2 => {
      if collection {
        ignore(self.byte())
      }
      Other
    }
    3 => {
      ignore(self.byte())
      Other
    }
    4 | 5 | 6 => Num(self.integer())
    7 => {
      ignore(self.take(8))
      Other
    }
    8 => Blob(self.take(self.length()))
    9 | 10 => {
      let header = self.byte()
      let n = if header >> 4 == 15 { self.length() } else { header >> 4 }
      let values = []
      for _ in 0..<n {
        values.push(self.value(header & 15, depth + 1, collection=true))
      }
      Seq(values)
    }
    11 => {
      let n = self.length()
      if n > 0 {
        let types = self.byte()
        for _ in 0..<n {
          ignore(self.value(types >> 4, depth + 1, collection=true))
          ignore(self.value(types & 15, depth + 1, collection=true))
        }
      }
      Other
    }
    12 => {
      let values = Map([])
      let mut previous = 0
      while true {
        let header = self.byte()
        if header == 0 {
          break
        }
        let id = if header >> 4 == 0 {
          self.integer().to_int()
        } else {
          previous + (header >> 4)
        }
        if id <= 0 || id > 32767 || values.contains(id) {
          raise Invalid(
            "INVALID_PARQUET", "footer", "Invalid or duplicate Thrift field ID",
          )
        }
        previous = id
        values[id] = self.value(header & 15, depth + 1)
      }
      Obj(values)
    }
    _ => raise Invalid("INVALID_PARQUET", "footer", "Unknown compact type")
  }
}

///|
fn footer_num(fields : Map[Int, FooterValue], id : Int) -> Int64? {
  match fields.get(id) {
    Some(Num(n)) => Some(n)
    Some(Blob(_) | Seq(_) | Obj(_) | Other) | None => None
  }
}

///|
/// Return flat leaf field IDs in Parquet column order; never guess from names.
pub fn parquet_field_ids(bytes : Bytes) -> Array[Int] raise IceError {
  let n = bytes.length()
  if n < 12 || bytes[:4] != b"PAR1" || bytes[n - 4:] != b"PAR1" {
    raise Invalid("INVALID_PARQUET", "footer", "Missing PAR1 magic")
  }
  let length = little_integer(bytes[n - 8:n - 4].to_bytes(), 4).unwrap_or(-1L)
  if length < 0 || length > (n - 12).to_int64() || length > 8L * 1024L * 1024L {
    raise Invalid("INVALID_PARQUET", "footer", "Invalid footer length")
  }
  let reader = FooterReader::{
    bytes: bytes[n - 8 - length.to_int():n - 8].to_bytes(),
    offset: 0,
    nodes: 0,
  }
  guard reader.value(12, 0) is Obj(fields) else {
    raise Invalid("INVALID_PARQUET", "footer", "Expected metadata struct")
  }
  guard footer_num(fields, 3) is Some(rows) && rows >= 0L && rows <= 100000L else {
    raise Invalid(
      "RESOURCE_LIMIT", "footer", "Parquet footer exceeds 100,000 row limit",
    )
  }
  guard fields.get(2) is Some(Seq(elements)) && elements.length() > 0 else {
    raise Invalid("INVALID_PARQUET", "schema", "Schema is absent")
  }
  guard elements[0] is Obj(root) &&
    footer_num(root, 5) == Some((elements.length() - 1).to_int64()) else {
    raise Invalid(
      "UNSUPPORTED_NESTED", "schema", "Only flat primitive Parquet schemas are supported",
    )
  }
  let ids = []
  let seen = Map([])
  for i in 1..<elements.length() {
    guard elements[i] is Obj(leaf) &&
      footer_num(leaf, 1) is Some(_) &&
      footer_num(leaf, 5).unwrap_or(0L) == 0L &&
      footer_num(leaf, 3) != Some(2L) else {
      raise Invalid(
        "UNSUPPORTED_NESTED", "schema", "Repeated or nested fields are not supported",
      )
    }
    guard footer_num(leaf, 9) is Some(id) && id > 0L && id <= 2147483647L else {
      raise Invalid(
        "MISSING_FIELD_ID", "schema", "Every leaf requires an explicit positive Parquet field_id",
      )
    }
    if seen.contains(id) {
      raise Invalid(
        "DUPLICATE_FIELD", "schema", "Parquet field IDs are not unique",
      )
    }
    seen[id] = true
    ids.push(id.to_int())
  }
  ids
}
