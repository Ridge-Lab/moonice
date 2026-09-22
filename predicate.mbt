///|
pub(all) enum CompareOp {
  Eq
  Lt
  Le
  Gt
  Ge
} derive(Debug, Eq, ToJson)

///|
/// Predicates bind to stable field IDs. Missing values never satisfy comparisons.
pub(all) enum Predicate {
  All
  Compare(Int, CompareOp, Scalar)
  IsNull(Int)
  NotNull(Int)
  And(Predicate, Predicate)
  Or(Predicate, Predicate)
} derive(Debug, Eq, ToJson)

///|
fn scalar_compare(a : Scalar, b : Scalar) -> Int? {
  match (a, b) {
    (Integer(x), Integer(y)) => Some(x.compare(y))
    (Real(x), Real(y)) =>
      if x.is_nan() || y.is_nan() {
        None
      } else {
        Some(x.compare(y))
      }
    (Text(x), Text(y)) => Some(@utf8.encode(x).lexical_compare(@utf8.encode(y)))
    (Binary(x), Binary(y)) => Some(x.lexical_compare(y))
    (Boolean(x), Boolean(y)) =>
      Some(if x == y { 0 } else if x { 1 } else { -1 })
    _ => None
  }
}

///|
fn compare_matches(op : CompareOp, c : Int) -> Bool {
  match op {
    Eq => c == 0
    Lt => c < 0
    Le => c <= 0
    Gt => c > 0
    Ge => c >= 0
  }
}

///|
pub fn Predicate::matches(self : Predicate, row : Map[Int, Scalar]) -> Bool {
  match self {
    All => true
    Compare(id, op, value) =>
      match scalar_compare(row.get(id).unwrap_or(Missing), value) {
        Some(c) => compare_matches(op, c)
        None => false
      }
    IsNull(id) => row.get(id).unwrap_or(Missing) == Missing
    NotNull(id) => row.get(id).unwrap_or(Missing) != Missing
    And(a, b) => a.matches(row) && b.matches(row)
    Or(a, b) => a.matches(row) || b.matches(row)
  }
}

///|
fn predicate_field(schema : Schema, id : Int) -> Field raise IceError {
  match schema.field(id) {
    Some(f) => f
    None =>
      raise Invalid(
        "FIELD_NOT_FOUND",
        "field:\{id}",
        "Predicate field is absent from the selected schema",
      )
  }
}

///|
pub fn Predicate::validate(
  self : Predicate,
  schema : Schema,
) -> Unit raise IceError {
  fn walk(p : Predicate, depth : Int) -> Unit raise IceError {
    if depth > 64 {
      raise Invalid("RESOURCE_LIMIT", "filter", "Predicate nesting exceeds 64")
    }
    match p {
      All => ()
      IsNull(id) | NotNull(id) => ignore(predicate_field(schema, id))
      Compare(id, _, value) => {
        let f = predicate_field(schema, id)
        let valid = match (f.field_type, value) {
          (String("int" | "date"), Integer(v)) =>
            v >= -2147483648L && v <= 2147483647L
          (String("long" | "time" | "timestamp" | "timestamptz"), Integer(_)) =>
            true
          (String("float" | "double"), Real(v)) => !v.is_nan() && !v.is_inf()
          (String("string"), Text(_))
          | (String("boolean"), Boolean(_))
          | (String("binary"), Binary(_)) => true
          _ => false
        }
        if !valid {
          raise Invalid(
            "PREDICATE_TYPE",
            f.name,
            "Literal does not match a supported primitive field type",
          )
        }
      }
      And(a, b) | Or(a, b) => {
        walk(a, depth + 1)
        walk(b, depth + 1)
      }
    }
  }
  walk(self, 0)
}

///|
/// JSON grammar: {field: name, op: =|<|<=|>|>=|is_null|not_null, value: literal},
/// {and: [predicate,predicate]} or {or: [...]}; null means all rows.
pub fn parse_predicate(
  source : String,
  schema : Schema,
) -> Predicate raise IceError {
  let root = @json.parse(source) catch {
    _ => raise Invalid("INVALID_JSON", "filter", "Invalid predicate JSON")
  }
  fn parse(j : Json, depth : Int) -> Predicate raise IceError {
    if depth > 64 {
      raise Invalid("RESOURCE_LIMIT", "filter", "Predicate nesting exceeds 64")
    }
    if j is Null {
      return All
    }
    let obj = object(j, "filter")
    for key in ["and", "or"] {
      if obj.get(key) is Some(children) {
        let children = array_value(children, "filter.\{key}")
        if children.length() != 2 || obj.length() != 1 {
          raise Invalid(
            "INVALID_FILTER", "filter", "Boolean expressions require exactly two children",
          )
        }
        let a = parse(children[0], depth + 1)
        let b = parse(children[1], depth + 1)
        return if key == "and" { And(a, b) } else { Or(a, b) }
      }
    }
    let f = schema.field_named(
      text_value(json_field(j, "field"), "filter.field"),
    )
    let op = text_value(json_field(j, "op"), "filter.op")
    let null_check = op == "is_null" || op == "not_null"
    if obj.length() != (if null_check { 2 } else { 3 }) ||
      obj.iter().any(pair => !["field", "op", "value"].contains(pair.0)) {
      raise Invalid(
        "INVALID_FILTER", "filter", "Unexpected or missing predicate fields",
      )
    }
    if op == "is_null" {
      return IsNull(f.id)
    }
    if op == "not_null" {
      return NotNull(f.id)
    }
    let op = match op {
      "=" => Eq
      "<" => Lt
      "<=" => Le
      ">" => Gt
      ">=" => Ge
      _ => raise Invalid("INVALID_FILTER", "filter.op", "Unsupported operator")
    }
    let jvalue = json_field(j, "value")
    let value = match f.field_type {
      String("int" | "long" | "date" | "time" | "timestamp" | "timestamptz") =>
        Integer(argument_long(jvalue, "filter.value"))
      String("float" | "double") =>
        match jvalue {
          Number(n, ..) => Real(n)
          _ => raise Invalid("PREDICATE_TYPE", f.name, "Expected a number")
        }
      String("string") => Text(text_value(jvalue, "filter.value"))
      String("boolean") => Boolean(bool_value(jvalue, "filter.value"))
      _ =>
        raise Invalid(
          "UNSUPPORTED_TYPE",
          f.name,
          "JSON filtering does not support this type",
        )
    }
    Compare(f.id, op, value)
  }
  let p = parse(root, 0)
  p.validate(schema)
  p
}
