# Changelog

## 0.2.0 — 2026-09-22

- Added per-spec partition projection for bucket, truncate, year, month, day and
  hour, with conservative boundary handling and exact Int64/Unicode behavior.
- Added `transform_partition`, `scan_batches`, `Bundle::scan_batches` and
  `ScanSummary`. Existing row-returning APIs remain compatible.
- Reused position/equality delete indexes across applicable data files.
- Rejected ambiguous partition metadata and unexpected filter fields; bounded
  raw metadata and the total loaded live-entry count.
- Added a PyIceberg day-to-month evolution fixture, 201 transform vectors and
  independently generated codec/row-group cases. Test count: 45.
- Added batch-reading and typed MoonFrame consumer examples; expanded the web
  workbench with a partition-evolution demo and accurate transform explanations.
- Documented supported NONE/Snappy codecs and explicit Gzip/Zstd rejection.

Scope remains bounded Iceberg v2 reading/inspection. No table writes, catalog,
S3 client, range reads, nested/decimal/UUID row execution or warehouse-scale
performance claims are introduced.

## 0.1.0 — 2026-09-14

Initial snapshot metadata, Avro manifest interpretation, conservative metrics,
position/equality deletes, stable-ID Parquet projection, diagnostics, CLI and
browser workbench. Independent format fixtures and 31 regression tests.
