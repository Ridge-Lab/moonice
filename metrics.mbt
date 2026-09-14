///|
fn little_integer(bytes : Bytes, width : Int) -> Int64? {
  if bytes.length() != width {
    return None
  }
  let mut n = 0L
  for i in 0..<width {
    n = n | (bytes[i].to_int().to_int64() << (8 * i))
  }
  Some(if width == 4 { n.to_int().to_int64() } else { n })
}

///|
fn decode_bound(bytes : Bytes, field : Field) -> Scalar? {
  match field.field_type {
    String("int" | "date") => little_integer(bytes, 4).map(n => Integer(n))
    String("long" | "time" | "timestamp" | "timestamptz") =>
      little_integer(bytes, 8).map(n => Integer(n))
    String("double") =>
      little_integer(bytes, 8).map(n => Real(n.reinterpret_as_double()))
    String("string") => {
      let s = @utf8.decode(bytes) catch { _ => return None }
      Some(Text(s))
    }
    String("boolean") =>
      if bytes.length() == 1 {
        Some(Boolean(bytes[0] != 0))
      } else {
        None
      }
    String("binary") => Some(Binary(bytes))
    // Unknown or unsupported encodings retain the file, including float bounds.
    _ => None
  }
}

///|
/// Return an exclusion proof, never a guess that a file is irrelevant.
fn metrics_exclusion(
  file : DataFile,
  schema : Schema,
  p : Predicate,
) -> String? {
  match p {
    All => None
    And(a, b) =>
      match metrics_exclusion(file, schema, a) {
        Some(r) => Some(r)
        None => metrics_exclusion(file, schema, b)
      }
    Or(a, b) =>
      match
        (metrics_exclusion(file, schema, a), metrics_exclusion(file, schema, b)) {
        (Some(a), Some(b)) => Some("Both OR branches excluded: \{a}; \{b}")
        _ => None
      }
    IsNull(id) =>
      if file.null_counts.get(id) == Some(0L) {
        Some("field \{id}: null_count = 0")
      } else {
        None
      }
    NotNull(id) =>
      if file.null_counts.get(id) == Some(file.record_count) {
        Some("field \{id}: every row is null")
      } else {
        None
      }
    Compare(id, op, value) => {
      if file.null_counts.get(id) == Some(file.record_count) {
        return Some("field \{id}: every row is null")
      }
      let field = match schema.field(id) {
        Some(f) => f
        None => return None
      }
      // Floating-point ordering with NaNs needs more information than min/max.
      if field.field_type is String("float" | "double") &&
        file.nan_counts.get(id) != Some(0L) {
        return None
      }
      let lower = file.lower_bounds.get(id).bind(b => decode_bound(b, field))
      let upper = file.upper_bounds.get(id).bind(b => decode_bound(b, field))
      if (lower, upper) is (Some(lo), Some(hi)) {
        if scalar_compare(lo, hi) is Some(c) && c > 0 {
          return None
        }
      }
      let lo = lower.bind(v => scalar_compare(v, value))
      let hi = upper.bind(v => scalar_compare(v, value))
      let below = match (op, lo) {
        (Eq | Lt, Some(c)) => c > 0 || (op == Lt && c == 0)
        (Le, Some(c)) => c > 0
        _ => false
      }
      let above = match (op, hi) {
        (Eq | Gt, Some(c)) => c < 0 || (op == Gt && c == 0)
        (Ge, Some(c)) => c < 0
        _ => false
      }
      if below {
        Some("field \{id}: lower bound excludes the predicate")
      } else if above {
        Some("field \{id}: upper bound excludes the predicate")
      } else {
        None
      }
    }
  }
}
