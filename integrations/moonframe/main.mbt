///|
// This is a schema-specific integration example, not a general type adapter.
// Preserve integer values through typed Series rather than lossy JSON numbers.
fn demonstrate() -> Unit raise {
  let bundle = @moonice.open_bundle(
    @fs.read_file_to_string("../../fixtures/deletes.icebundle.json"),
  )
  let ids : Array[Int64?] = []
  let categories : Array[String?] = []
  let summary = bundle.scan_batches(
    All,
    rows => {
      for row in rows {
        ids.push(
          match row.values.get(1) {
            Some(@moonice.Integer(n)) => Some(n)
            Some(@moonice.Missing) | None => None
            _ => raise @moonice.Invalid("ADAPTER_TYPE", "id", "Expected Int64")
          },
        )
        categories.push(
          match row.values.get(2) {
            Some(@moonice.Text(s)) => Some(s)
            Some(@moonice.Missing) | None => None
            _ =>
              raise @moonice.Invalid(
                "ADAPTER_TYPE", "category", "Expected String",
              )
          },
        )
      }
    },
    batch_size=1,
  )
  let df = @frame.DataFrame([
    @series.Series::from_int_options("id", ids),
    @series.Series::from_string_options("category", categories),
  ])
  let sum = df.get_column("id").sum().as_int()
  println(
    "physical_rows=\{summary.read_rows} deleted_rows=\{summary.deleted_rows}",
  )
  println(df.to_markdown())
  println("moonframe_rows=\{df.nrows()} id_sum=\{sum}")
  if df.nrows() != 2 || sum != 6L {
    @sys.exit(1)
  }
  // A separate precision check guards this conversion's central contract.
  let wide = @series.Series::from_int_options("id", [
    Some(9007199254740993L),
    None,
  ])
  if wide.get(0) != @types.Int(9007199254740993L) || wide.get(1) != @types.Null {
    @sys.exit(1)
  }
}

///|
fn main {
  demonstrate() catch {
    error => {
      println("MoonFrame integration failed: \{error}")
      @sys.exit(1)
    }
  }
}
