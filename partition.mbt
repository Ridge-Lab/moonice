///|
fn floor_div(n : Int64, d : Int64) -> Int64 {
  let q = n / d
  if n % d < 0L {
    q - 1L
  } else {
    q
  }
}

///|
fn transform_width(name : String, prefix : String) -> Int? {
  guard name.has_prefix(prefix) && name.has_suffix("]") else { return None }
  let body = name[prefix.length():name.length() - 1]
  if body.is_empty() || !body.iter().all(c => c >= '0' && c <= '9') {
    return None
  }
  let n = @string.parse_int(body) catch { _ => return None }
  if n > 0 {
    Some(n)
  } else {
    None
  }
}

///|
// Iceberg uses Murmur3 x86_32, seed 0; integers use an eight-byte LE encoding.
fn bucket_hash(bytes : Bytes) -> UInt {
  fn rot(x : UInt, n : Int) -> UInt {
    (x << n) | (x >> (32 - n))
  }
  fn mix(k : UInt) -> UInt {
    rot(k * 0xcc9e2d51U, 15) * 0x1b873593U
  }
  let mut h = 0U
  let blocks = bytes.length() / 4
  for i in 0..<blocks {
    let pos = i * 4
    let k = bytes[pos].to_uint() |
      (bytes[pos + 1].to_uint() << 8) |
      (bytes[pos + 2].to_uint() << 16) |
      (bytes[pos + 3].to_uint() << 24)
    h = rot(h ^ mix(k), 13) * 5U + 0xe6546b64U
  }
  let mut tail = 0U
  for i in (blocks * 4)..<bytes.length() {
    tail = tail | (bytes[i].to_uint() << (8 * (i - blocks * 4)))
  }
  if bytes.length() % 4 != 0 {
    h = h ^ mix(tail)
  }
  h = h ^ bytes.length().reinterpret_as_uint()
  h = (h ^ (h >> 16)) * 0x85ebca6bU
  h = (h ^ (h >> 13)) * 0xc2b2ae35U
  h ^ (h >> 16)
}

///|
// Count Gregorian leap days algebraically, including years before year zero.
fn year_start(year : Int64) -> Int64 {
  let y = year - 1L
  365L * (year - 1970L) +
  floor_div(y, 4L) -
  492L -
  (floor_div(y, 100L) - 19L) +
  floor_div(y, 400L) -
  4L
}

///|
fn calendar_partition(days : Int64, month : Bool) -> Int64 {
  // Covers the entire signed 32-bit date domain. Binary search avoids
  // timestamp libraries whose supported calendar range differs by backend.
  let mut lo = -6000000L
  let mut hi = 6000001L
  while lo + 1L < hi {
    let mid = lo + (hi - lo) / 2L
    if year_start(mid) <= days {
      lo = mid
    } else {
      hi = mid
    }
  }
  if !month {
    return lo - 1970L
  }
  let leap = lo % 4L == 0L && (lo % 100L != 0L || lo % 400L == 0L)
  let lengths = [
    31L,
    if leap {
      29L
    } else {
      28L
    },
    31L,
    30L,
    31L,
    30L,
    31L,
    31L,
    30L,
    31L,
    30L,
    31L,
  ]
  let mut remaining = days - year_start(lo)
  let mut m = 0
  while m < 11 && remaining >= lengths[m] {
    remaining -= lengths[m]
    m += 1
  }
  (lo - 1970L) * 12L + m.to_int64()
}

///|
/// Evaluate a supported Iceberg v2 transform. None means unsupported type,
/// unknown/malformed transform, or arithmetic outside its representable domain.
/// Some(Missing) is a known null partition, distinct from an unknown result.
/// Timestamp inputs are signed microseconds since the Unix epoch, date inputs
/// are signed days. String truncation counts Unicode code points.
pub fn transform_partition(
  value : Scalar,
  field_type : Json,
  transform : String,
) -> Scalar? {
  let supported = match field_type {
    String(
      "int"
      | "long"
      | "date"
      | "time"
      | "timestamp"
      | "timestamptz"
      | "string"
      | "binary"
      | "boolean"
      | "float"
      | "double"
    ) => true
    _ => false
  }
  if !supported {
    return None
  }
  let valid_value = match (field_type, value) {
    (_, Missing) => true
    (String("int" | "date"), Integer(n)) =>
      n >= -2147483648L && n <= 2147483647L
    (String("long" | "time" | "timestamp" | "timestamptz"), Integer(_)) => true
    (String("string"), Text(_))
    | (String("binary"), Binary(_))
    | (String("boolean"), Boolean(_))
    | (String("float" | "double"), Real(_)) => true
    _ => false
  }
  if !valid_value {
    return None
  }
  if transform == "void" {
    return Some(Missing)
  }
  if transform == "identity" {
    return Some(value)
  }
  let bucket = transform_width(transform, "bucket[")
  let truncate = transform_width(transform, "truncate[")
  let time = ["year", "month", "day", "hour"].contains(transform)
  if bucket is None && truncate is None && !time {
    return None
  }
  let allowed = if bucket is Some(_) {
    field_type
    is String(
      "int"
      | "long"
      | "date"
      | "time"
      | "timestamp"
      | "timestamptz"
      | "string"
      | "binary"
    )
  } else if truncate is Some(_) {
    field_type is String("int" | "long" | "string" | "binary")
  } else {
    field_type is String("timestamp" | "timestamptz") ||
    (field_type == Json::string("date") && transform != "hour")
  }
  if !allowed {
    return None
  }
  if value == Missing {
    return Some(Missing)
  }
  if bucket is Some(n) {
    let bytes = match (field_type, value) {
      (
        String("int" | "long" | "date" | "time" | "timestamp" | "timestamptz"),
        Integer(v),
      ) => Bytes::makei(8, i => ((v >> (i * 8)) & 255L).to_int().to_byte())
      (String("string"), Text(s)) => @utf8.encode(s)
      (String("binary"), Binary(b)) => b
      _ => return None
    }
    return Some(
      Integer(
        ((bucket_hash(bytes) & 0x7fffffffU) % n.reinterpret_as_uint()).to_int64(),
      ),
    )
  }
  if truncate is Some(width) {
    return match (field_type, value) {
      (String("int" | "long") as kind, Integer(v)) => {
        let w = width.to_int64()
        let remainder = (v % w + w) % w
        let min = if kind == Json::string("int") {
          -2147483648L
        } else {
          -9223372036854775808L
        }
        if v < min + remainder {
          None
        } else {
          Some(Integer(v - remainder))
        }
      }
      (String("string"), Text(s)) =>
        Some(Text(String::from_iter(s.iter().take(width))))
      (String("binary"), Binary(b)) =>
        Some(Binary(b[:Int::min(width, b.length())].to_owned()))
      _ => None
    }
  }
  let (days, hours) = match (field_type, value) {
    (String("date"), Integer(v)) if v >= -2147483648L && v <= 2147483647L =>
      (v, None)
    (String("timestamp" | "timestamptz"), Integer(v)) =>
      (floor_div(v, 86400000000L), Some(floor_div(v, 3600000000L)))
    _ => return None
  }
  let n = match transform {
    "day" => days
    "year" => calendar_partition(days, false)
    "month" => calendar_partition(days, true)
    "hour" =>
      match hours {
        Some(h) => h
        None => return None
      }
    _ => return None
  }
  if n < -2147483648L || n > 2147483647L {
    None
  } else {
    Some(Integer(n))
  }
}

///|
fn transformed_exclusion(
  field : Field,
  transform : String,
  partition : Scalar,
  predicate : Predicate,
) -> Bool {
  // Void and unknown transforms reveal nothing about the source column.
  if transform == "void" ||
    transform_partition(Missing, field.field_type, transform) is None {
    return false
  }
  match predicate {
    IsNull(_) => partition != Missing
    NotNull(_) => partition == Missing
    Compare(_, op, value) => {
      if partition == Missing {
        return true
      }
      guard transform_partition(value, field.field_type, transform)
        is Some(bound) &&
        scalar_compare(partition, bound) is Some(c) else {
        return false
      }
      if transform == "identity" {
        !compare_matches(op, c)
      } else if transform_width(transform, "bucket[") is Some(_) {
        // Hash ordering tells us nothing about source ordering.
        op == Eq && c != 0
      } else {
        // Inclusive projection deliberately retains the boundary partition.
        match op {
          Eq => c != 0
          Lt | Le => c > 0
          Gt | Ge => c < 0
        }
      }
    }
    _ => false
  }
}
