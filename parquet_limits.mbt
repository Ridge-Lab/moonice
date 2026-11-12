///|
fn bounded_footer_num(
  fields : Map[Int32, FooterValue],
  id : Int32,
  maximum : Int64,
) -> Int64 raise IceError {
  guard footer_num(fields, id) is Some(n) && n >= 0L && n <= maximum else {
    raise Invalid(
      "RESOURCE_LIMIT",
      "footer",
      "Missing, negative or excessive numeric field \{id}",
    )
  }
  n
}

///|
// Validate allocation dimensions before entering the Parquet decoder. Flat
// schemas have exactly one value (including nulls) per row and column.
fn validate_parquet_layout(
  fields : Map[Int32, FooterValue],
  bytes : Bytes,
  footer_start : Int32,
  leaves : Int32,
) -> Unit raise IceError {
  let rows = bounded_footer_num(fields, 3, 100000L)
  let budget = 64L * 1024L * 1024L
  if leaves <= 0 || (rows > 0L && leaves.to_int64() > 5000000L / rows) {
    raise Invalid(
      "RESOURCE_LIMIT", "footer", "Parquet materialization exceeds five million cells",
    )
  }
  guard fields.get(4) is Some(Seq(groups)) else {
    raise Invalid("INVALID_PARQUET", "footer", "Row groups are absent")
  }
  let mut counted_rows = 0L
  let mut declared_bytes = 0L
  let mut decoded_bytes = 0L
  let ranges : Array[(Int32, Int32)] = []
  let reader = FooterReader::{ bytes, offset: 0, nodes: 0, }
  for group in groups {
    guard group is Obj(group, _) &&
      group.get(1) is Some(Seq(columns)) &&
      columns.length() == leaves else {
      raise Invalid(
        "PARQUET_SHAPE", "footer", "Row group column count differs from schema",
      )
    }
    let group_rows = bounded_footer_num(group, 3, rows - counted_rows)
    counted_rows += group_rows
    for column in columns {
      guard column is Obj(chunk, _) && chunk.get(3) is Some(Obj(meta, _)) else {
        raise Invalid("INVALID_PARQUET", "footer", "Column metadata is absent")
      }
      if chunk.contains(1) {
        raise Invalid(
          "UNSUPPORTED_EXTERNAL_COLUMN", "footer", "Cross-file column chunks are unsupported",
        )
      }
      let values = bounded_footer_num(meta, 5, 100000L)
      if values != group_rows {
        raise Invalid(
          "PARQUET_SHAPE", "footer", "Flat column value count differs from row group",
        )
      }
      let declared = bounded_footer_num(meta, 6, budget - declared_bytes)
      declared_bytes += declared
      let compressed = bounded_footer_num(meta, 7, footer_start.to_int64())
      let data_offset = bounded_footer_num(meta, 9, footer_start.to_int64())
      let start = if meta.contains(11) {
        // Empty PyArrow columns have a dictionary but data_page_offset = 0.
        bounded_footer_num(
          meta,
          11,
          if values == 0L {
            footer_start.to_int64()
          } else {
            data_offset
          },
        )
      } else {
        data_offset
      }
      if start < 4L || compressed > footer_start.to_int64() - start {
        raise Invalid(
          "INVALID_PARQUET", "footer", "Column range is outside the file body",
        )
      }
      let finish = (start + compressed).to_int()
      ranges.push((start.to_int(), finish))
      let codec = bounded_footer_num(meta, 4, 100L)
      reader.offset = start.to_int()
      let mut page_values = 0L
      let mut column_bytes = 0L
      let mut dictionary_seen = false
      while reader.offset < finish {
        let before = reader.offset
        guard reader.value(12, 0) is Obj(page, _) else {
          raise Invalid("INVALID_PARQUET", "page", "Expected page header")
        }
        let header_bytes = (reader.offset - before).to_int64()
        let size = bounded_footer_num(
          page,
          3,
          (finish - reader.offset).to_int64(),
        )
        let expanded = bounded_footer_num(page, 2, budget - decoded_bytes)
        if header_bytes > budget - decoded_bytes - expanded {
          raise Invalid("RESOURCE_LIMIT", "page", "Decoded pages exceed 64 MiB")
        }
        decoded_bytes += expanded + header_bytes
        column_bytes += expanded + header_bytes
        if codec == 0L && size != expanded {
          raise Invalid(
            "INVALID_PARQUET", "page", "Uncompressed page size disagrees with payload",
          )
        }
        match footer_num(page, 1) {
          Some(0L) => {
            guard page.get(5) is Some(Obj(data, _)) else {
              raise Invalid(
                "INVALID_PARQUET", "page", "Missing data page header",
              )
            }
            page_values += bounded_footer_num(data, 1, values - page_values)
          }
          Some(2L) => {
            guard !dictionary_seen &&
              page_values == 0L &&
              page.get(7) is Some(Obj(dictionary, _)) else {
              raise Invalid(
                "INVALID_PARQUET", "page", "Invalid dictionary page order",
              )
            }
            dictionary_seen = true
            ignore(bounded_footer_num(dictionary, 1, 100000L))
          }
          Some(3L) => {
            guard page.get(8) is Some(Obj(data, _)) else {
              raise Invalid(
                "INVALID_PARQUET", "page", "Missing v2 data page header",
              )
            }
            let count = bounded_footer_num(data, 1, values - page_values)
            ignore(bounded_footer_num(data, 2, count))
            if bounded_footer_num(data, 3, count) != count ||
              bounded_footer_num(data, 6, 0L) != 0L {
              raise Invalid(
                "PARQUET_SHAPE", "page", "V2 page is not a flat row sequence",
              )
            }
            ignore(bounded_footer_num(data, 5, Int64::min(size, expanded)))
            page_values += count
          }
          _ =>
            raise Invalid(
              "UNSUPPORTED_PARQUET_PAGE", "page", "Only data and dictionary pages are supported",
            )
        }
        reader.offset += size.to_int()
      }
      if reader.offset != finish ||
        page_values != values ||
        column_bytes != declared {
        raise Invalid(
          "PARQUET_SHAPE", "page", "Column pages disagree with footer counts or sizes",
        )
      }
    }
  }
  if counted_rows != rows {
    raise Invalid(
      "PARQUET_SHAPE", "footer", "Row group total differs from file row count",
    )
  }
  ranges.sort_by((a, b) => a.0.compare(b.0))
  for i in 1..<ranges.length() {
    if ranges[i].0 < ranges[i - 1].1 {
      raise Invalid("INVALID_PARQUET", "footer", "Column byte ranges overlap")
    }
  }
}
