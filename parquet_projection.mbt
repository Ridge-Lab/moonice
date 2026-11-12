///|
priv struct ProjectedLeaf {
  ordinal : Int32
  id : Int32
  name : Bytes
  physical : Int64
  schema_record : BytesView
}

///|
// Parquet schema elements are a preorder tree. Only top-level, non-repeated
// leaves can use the flat decoder. Nested leaves still occupy chunk ordinals.
fn projection_leaves(
  elements : Array[FooterValue],
  wanted : Map[Int32, Bool],
  aliases : Map[String, Int32],
  identity_ids : Map[Int32, Bool],
) -> (Int32, Array[ProjectedLeaf]) raise IceError {
  let chosen = []
  let seen = Map([])
  // Iceberg resolution order: explicit physical ID, identity partition
  // constant, then name mapping. A historical alias cannot mask an ID.
  let resolved = identity_ids.copy()
  for element in elements {
    if element is Obj(field, _) &&
      footer_num(field, 9) is Some(n) &&
      n > 0L &&
      n <= 2147483647L {
      resolved[n.to_int()] = true
    }
  }
  let all_resolved = wanted.iter().all(pair => resolved.contains(pair.0))
  let mut cursor = 0
  let mut ordinal = 0
  fn visit(depth : Int32) -> Unit raise IceError {
    guard depth <= 64 &&
      cursor < elements.length() &&
      elements[cursor] is Obj(field, encoded) else {
      raise Invalid("INVALID_PARQUET", "schema", "Invalid Parquet schema tree")
    }
    cursor += 1
    let children = footer_num(field, 5).unwrap_or(0L)
    guard children >= 0L &&
      children <= (elements.length() - cursor).to_int64() &&
      field.get(4) is Some(Blob(name)) else {
      raise Invalid("INVALID_PARQUET", "schema", "Invalid schema element")
    }
    let physical = footer_num(field, 1)
    if (physical is Some(_) && children != 0L) ||
      (depth == 0 && (physical is Some(_) || children == 0L)) {
      raise Invalid("INVALID_PARQUET", "schema", "Invalid group or leaf shape")
    }
    let declared_id = footer_num(field, 9)
    if field.contains(9) && declared_id is None {
      raise Invalid("INVALID_PARQUET", "schema", "Malformed physical field ID")
    }
    let id = match declared_id {
      Some(n) => {
        guard n > 0L && n <= 2147483647L else {
          raise Invalid(
            "MISSING_FIELD_ID", "schema", "Invalid Parquet field ID",
          )
        }
        Some(n.to_int())
      }
      None if depth == 1 => {
        guard !aliases.is_empty() || all_resolved else {
          raise Invalid(
            "MISSING_FIELD_ID", "schema", "ID-less columns require an Iceberg name mapping",
          )
        }
        let label = @utf8.decode(name) catch {
          _ =>
            raise Invalid(
              "INVALID_PARQUET", "schema", "Invalid UTF-8 column name",
            )
        }
        match aliases.get(label) {
          Some(id) if !resolved.contains(id) => Some(id)
          _ => None
        }
      }
      None => None
    }
    if id is Some(id) {
      if seen.contains(id) {
        raise Invalid(
          "DUPLICATE_FIELD", "schema", "Two physical fields resolve to the same ID",
        )
      }
      seen[id] = true
      if wanted.contains(id) {
        guard depth == 1 &&
          physical is Some(physical) &&
          footer_num(field, 3) is Some(0L | 1L) else {
          raise Invalid(
            "UNSUPPORTED_NESTED", "schema", "Selected field must be a top-level scalar",
          )
        }
        chosen.push({ ordinal, id, name, physical, schema_record: encoded, })
      }
    }
    if physical is Some(_) {
      ordinal += 1
    } else {
      for _ in 0..<children.to_int() {
        visit(depth + 1)
      }
    }
  }
  visit(0)
  guard cursor == elements.length() else {
    raise Invalid(
      "INVALID_PARQUET", "schema", "Unexpected trailing schema elements",
    )
  }
  (ordinal, chosen)
}

///|
fn compact_unsigned(out : @buffer.Buffer, number : UInt64) -> Unit {
  let mut n = number
  while n >= 128UL {
    out.write_byte((n.to_int() | 128).to_byte())
    n = n >> 7
  }
  out.write_byte(n.to_int().to_byte())
}

///|
fn compact_number(out : @buffer.Buffer, value : Int64) -> Unit {
  compact_unsigned(out, ((value << 1) ^ (value >> 63)).reinterpret_as_uint64())
}

///|
fn compact_list(out : @buffer.Buffer, kind : Int32, count : Int32) -> Unit {
  out.write_byte(((Int32::min(count, 15) << 4) | kind).to_byte())
  if count >= 15 {
    compact_unsigned(out, count.to_uint64())
  }
}

///|
// Keep the selected compressed page streams unchanged. Build the compact
// metadata consumed by mizchi/parquet with their new offsets; optional indexes
// and statistics from the source file do not apply to this in-memory view.
fn write_selected_chunk(
  body : @buffer.Buffer,
  footer : @buffer.Buffer,
  bytes : Bytes,
  column : FooterValue,
  leaf : ProjectedLeaf,
) -> Int64 raise IceError {
  guard column is Obj(chunk, _) &&
    chunk.get(3) is Some(Obj(meta, _)) &&
    footer_num(meta, 1) == Some(leaf.physical) &&
    meta.get(2) is Some(Seq(encodings)) &&
    meta.get(3) is Some(Seq([Blob(path)])) &&
    path == leaf.name else {
    raise Invalid(
      "PARQUET_SHAPE", "footer", "Selected chunk type or path disagrees with schema",
    )
  }
  // All sizes and ranges have passed validate_parquet_layout.
  let data_offset = footer_num(meta, 9).unwrap()
  let dictionary = footer_num(meta, 11)
  let start = dictionary.unwrap_or(data_offset)
  let length = footer_num(meta, 7).unwrap()
  let expanded = footer_num(meta, 6).unwrap()
  if chunk.contains(8) || chunk.contains(9) {
    raise Invalid(
      "UNSUPPORTED_ENCRYPTION", "footer", "Encrypted columns cannot be decoded",
    )
  }
  if data_offset > start + length {
    raise Invalid(
      "INVALID_PARQUET", "footer", "Data page offset lies outside its column",
    )
  }
  let destination = body.length().to_int64()
  body.write_bytes(bytes[start.to_int():(start + length).to_int()])
  footer.write_byte(0x26) // ColumnChunk.file_offset
  compact_number(footer, 0L)
  footer.write_byte(0x1c) // ColumnChunk.meta_data
  footer.write_byte(0x15)
  compact_number(footer, leaf.physical)
  footer.write_byte(0x19)
  compact_list(footer, 5, encodings.length())
  for encoding in encodings {
    guard encoding is Num(n) && n >= 0L && n <= 2147483647L else {
      raise Invalid("INVALID_PARQUET", "footer", "Invalid encoding identifier")
    }
    compact_number(footer, n)
  }
  footer.write_byte(0x19)
  compact_list(footer, 8, 1)
  compact_unsigned(footer, path.length().to_uint64())
  footer.write_bytes(path)
  footer.write_byte(0x15)
  compact_number(footer, footer_num(meta, 4).unwrap())
  for id in [5, 6, 7] {
    footer.write_byte(0x16)
    compact_number(footer, footer_num(meta, id).unwrap())
  }
  footer.write_byte(0x26)
  compact_number(
    footer,
    if data_offset == 0L {
      0L
    } else {
      destination + data_offset - start
    },
  )
  if dictionary is Some(_) {
    footer.write_byte(0x26)
    compact_number(footer, destination)
  }
  footer.write_byte(0)
  footer.write_byte(0)
  expanded
}

///|
fn projected_parquet(
  bytes : Bytes,
  file : DataFile,
  wanted : Map[Int32, Bool],
  aliases : Map[String, Int32],
  identity_ids : Map[Int32, Bool],
) -> (Bytes?, Array[Int32]) raise IceError {
  let (fields, footer_start) = parquet_footer(bytes)
  let rows = bounded_footer_num(fields, 3, 100000L)
  guard rows == file.record_count &&
    fields.get(2) is Some(Seq(elements)) &&
    fields.get(4) is Some(Seq(groups)) else {
    raise Invalid(
      "PARQUET_SHAPE",
      file.path,
      "Missing schema or group, or record count mismatch",
    )
  }
  let (leaf_count, chosen) = projection_leaves(
    elements, wanted, aliases, identity_ids,
  )
  let selected_groups = []
  let mut total = 0L
  for group in groups {
    guard group is Obj(g, _) &&
      g.get(1) is Some(Seq(chunks)) &&
      chunks.length() == leaf_count else {
      raise Invalid(
        "PARQUET_SHAPE",
        file.path,
        "Row group columns disagree with schema",
      )
    }
    total += bounded_footer_num(g, 3, rows - total)
    g[1] = Seq(chosen.map(leaf => chunks[leaf.ordinal]))
    selected_groups.push(group)
  }
  guard total == rows else {
    raise Invalid(
      "PARQUET_SHAPE",
      file.path,
      "Row groups disagree with file row count",
    )
  }
  if chosen.is_empty() {
    return (None, [])
  }
  fields[4] = Seq(selected_groups)
  validate_parquet_layout(fields, bytes, footer_start, chosen.length())
  let body = @buffer.Buffer()
  let footer = @buffer.Buffer()
  body.write_bytes(b"PAR1")
  footer.write_byte(0x15) // FileMetaData.version
  compact_number(footer, bounded_footer_num(fields, 1, 2147483647L))
  footer.write_byte(0x19) // FileMetaData.schema
  compact_list(footer, 12, chosen.length() + 1)
  footer.write_bytes(b"\x48\x06schema\x15") // root name and num_children
  compact_number(footer, chosen.length().to_int64())
  footer.write_byte(0)
  for leaf in chosen {
    footer.write_bytes(leaf.schema_record)
  }
  footer.write_byte(0x16)
  compact_number(footer, rows)
  footer.write_byte(0x19)
  compact_list(footer, 12, groups.length())
  for group in selected_groups {
    guard group is Obj(g, _) && g.get(1) is Some(Seq(columns)) else {
      raise Invalid("INVALID_PARQUET", "footer", "Missing columns")
    }
    footer.write_byte(0x19)
    compact_list(footer, 12, columns.length())
    let mut expanded = 0L
    for i, column in columns {
      expanded += write_selected_chunk(body, footer, bytes, column, chosen[i])
    }
    footer.write_byte(0x16)
    compact_number(footer, expanded)
    footer.write_byte(0x16)
    compact_number(footer, footer_num(g, 3).unwrap())
    footer.write_byte(0)
  }
  footer.write_byte(0)
  body.write_bytes(footer.to_bytes())
  body.write_uint_le(footer.length().reinterpret_as_uint())
  body.write_bytes(b"PAR1")
  (Some(body.to_bytes()), chosen.map(leaf => leaf.id))
}
