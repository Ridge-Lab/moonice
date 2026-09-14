///|
fn json_field(j : Json, key : String) -> Json {
  match j {
    Object(m) => m.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn object(j : Json, path : String) -> Map[String, Json] raise IceError {
  match j {
    Object(m) => m
    _ => raise Invalid("INVALID_METADATA", path, "Expected an object")
  }
}

///|
fn text_value(j : Json, path : String) -> String raise IceError {
  match j {
    String(s) => s
    _ => raise Invalid("INVALID_METADATA", path, "Expected a string")
  }
}

///|
fn array_value(j : Json, path : String) -> Array[Json] raise IceError {
  match j {
    Array(a) => a
    _ => raise Invalid("INVALID_METADATA", path, "Expected an array")
  }
}

///|
fn int_value(j : Json, path : String) -> Int raise IceError {
  match j {
    Number(n, ..) if n >= -2147483648.0 &&
      n <= 2147483647.0 &&
      n.to_int().to_double() == n => n.to_int()
    _ =>
      raise Invalid("INVALID_INTEGER", path, "Expected a signed 32-bit integer")
  }
}

///|
fn long_value(j : Json, path : String) -> Int64 raise IceError {
  match j {
    Number(_, repr=Some(s)) =>
      @json.from_json(Json::string(s)) catch {
        _ =>
          raise Invalid(
            "INVALID_INTEGER", path, "Expected a signed 64-bit integer literal",
          )
      }
    Number(n, repr=None) if n >= -9007199254740991.0 &&
      n <= 9007199254740991.0 &&
      n.to_int64().to_double() == n => n.to_int64()
    _ =>
      raise Invalid(
        "INVALID_INTEGER", path, "Expected an exact signed 64-bit integer",
      )
  }
}

///|
fn opt_long(j : Json, path : String) -> Int64? raise IceError {
  match j {
    Null => None
    _ => Some(long_value(j, path))
  }
}

///|
// UI/CLI arguments allow decimal strings without weakening metadata validation.
fn argument_long(j : Json, path : String) -> Int64 raise IceError {
  match j {
    String(s) => {
      let value = @json.parse(s) catch {
        _ =>
          raise Invalid(
            "INVALID_INTEGER", path, "Expected a decimal integer string",
          )
      }
      long_value(value, path)
    }
    _ => long_value(j, path)
  }
}

///|
fn opt_int(j : Json, path : String) -> Int? raise IceError {
  match j {
    Null => None
    _ => Some(int_value(j, path))
  }
}

///|
fn bool_value(j : Json, path : String) -> Bool raise IceError {
  match j {
    True => true
    False => false
    _ => raise Invalid("INVALID_METADATA", path, "Expected a boolean")
  }
}

///|
fn nonnegative(n : Int64, path : String) -> Int64 raise IceError {
  if n < 0 {
    raise Invalid("INVALID_INTEGER", path, "Expected a nonnegative integer")
  }
  n
}
