# Changelog

## 0.4.0 — 2026-11-12

- Scan selected top-level scalar columns by Iceberg ID, with explicit top-level name-mapping support for migrated Parquet tables. Unselected page payloads are skipped, including nested siblings. Residual filters and equality deletes can access hidden columns without exposing them in results.
- Reproduce a DuckDB table scan with map, list and struct siblings and compare the scalar results against PyArrow. The CLI, batch API and registry-only consumer exercise the projection path.

## 0.3.3 — 2026-11-12

- Recover an identity-partitioned field from the file's partition tuple when Parquet omits its physical column. Scans use the recovered value for projection, row filters and equality deletes. A physically stored null stays null.

## 0.3.2 — 2026-11-11

- Validate compressed manifest payloads with a bounded first pass. Enforce both the per-block 8 MiB decoded limit and a cumulative 64 MiB limit before allocating the block's output. Reject malformed trailing bytes while reading fastavro 1.12.2 files.
- Decode each Avro header once and project each datum as it is read. Compare manifest fields, 64-bit IDs and failure codes against independently generated fastavro/zlib files.
- Measure data-file calls and bytes through the public batch-reader callback for full and partition-pruned scans of the same snapshot.

## 0.3.1 — 2026-11-11

- Adopt MoonBit compiler/core 0.10.20 and its `#derive` syntax. The v0.3.0 tag retains the 0.10.16 source and package.
- Exercise MoonFrame 0.8.1 with typed Int64 and null transfer on the current SDK.
- Ship the updated core NOTICE from the SDK used to compile the CLI and browser assets.

## 0.3.0 — 2026-11-10

- Upgrade the compiler/core floor to 0.10.16 and resolve compatible public dependencies without modifying caches.
- Reject compact field-ID overflow and out-of-range int/date row projections.
- Preflight Parquet row-group, column and page allocation dimensions, cumulative expanded bytes and materialized cells; preflight total OCF block counts before allocating records.
- Add a repeatable quick/full/release verification entry, fail-closed runner tests, seeded live PyIceberg/PyArrow comparisons, CLI and distribution checks.
- Pin MoonFrame 0.8.0 and use its public scalar constructor; retain exact Int64/null transfer.
- Preserve the matching core NOTICE and third-party licenses in web and CLI outputs.
- Add Linux four-backend and Windows JS/native verification workflows. Successful local and published CI evidence are recorded separately.

## 0.2.1 — 2026-09-30

- Raised the supported toolchain floor to moonc 0.10.14 and pinned CI/compiler
  core to `0.10.14+7d59c7ec9`.
- Imported the Avro OCF package directly; the unused Avro JSON facade calls an
  API removed from the new standard library. No dependency source is patched.
- Explicitly exposed derived trait methods under the new compiler rules,
  preserving the previous public method-call API without suppressing warnings.
- Upgraded Parquet to 0.2.2 and x to 0.5.5; expanded the MoonFrame integration
  CI to JS, Wasm, Wasm GC and native after resolving the old dependency conflict.
- Added clone/install instructions and refreshed release verification records.

The supported Iceberg feature set is unchanged from 0.2.0.

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
