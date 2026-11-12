# Compatibility and boundaries

MoonIce 0.3.3 is a bounded Iceberg v2 reader/inspector, not a complete standards certification.

| Surface | Current behavior |
|---|---|
| Table metadata | v2 only; schemas, partition specs, snapshots, current snapshot, branches/tags, retained ancestry checks |
| v1 upgraded tables | v1 manifests are not supported, even inside a v2 table |
| v3/v4 | Rejected, including deletion vectors, row lineage and newer types |
| Avro containers | `yugonlian/moon-avro` schema/header and datum decoding, null/deflate blocks, bounded output via MoonBit core flate, manifest version/spec/content checks |
| Manifest entries | Existing/added/deleted status; null sequence inheritance only for added entries; deleted entries excluded |
| File statistics | Integer/date/time/timestamp, string, boolean, binary and double bounds; float/unsupported bounds retain files |
| Null / NaN | Null counts used conservatively; float/double bounds do not prune when NaN counts are unknown/nonzero; no NaN literal filters |
| Predicates | Typed ID-bound comparisons, null checks, AND/OR; no SQL, NOT, IN or transforms in expressions |
| Partition pruning | identity, bucket[N] equality, truncate[W], year/month/day/hour; per-manifest spec IDs support partition evolution; void and unknown transforms retain files |
| Transform types | int/long/string/binary bucket and truncate; date/time/timestamp bucket; date year/month/day, timestamp year/month/day/hour; decimal/UUID transforms unsupported; overflow retains files |
| Position deletes | Reserved field IDs for path/position, exact path match, zero-based positions; data sequence ≤ delete sequence |
| Equality deletes | Flat supported scalar keys including null; data sequence < delete sequence; same partition or global unpartitioned spec |
| Parquet | Existing `mizchi/parquet` decoder plus MoonIce field-ID footer inspection; flat primitive schema, explicit positive IDs |
| Projection | Stable IDs survive renames. For a missing physical column, scans use the data file's own identity partition value when available, including null. Other missing optional fields read as null. Required nulls fail. Supports int→long. |
| Nested/decimal/UUID/defaults | Not supported for row execution; unsupported projected types fail. No name mapping fallback for absent Parquet IDs |
| Other data formats | Metadata can be inspected; ORC/Avro data-row execution fails explicitly |
| Snapshot difference | Physical file additions/removals and schema changes; not logical row CDC |
| Diagnostics | Bundle reference existence/size, incomplete traversal, unsupported format hints; not a complete file-integrity or table-consistency validator |
| Storage | Caller-provided byte reader or explicit offline object map; no REST catalog, S3 client, remote auth or range reads |
| Batch delivery | `scan_batches` emits visible filtered rows, 1–100,000 per callback; arrays are owned and not reused; shared delete indexes; whole-file decoding remains |
| Mutations | No table writes, transactions, snapshot expiration or object deletion |

The core and optional MoonFrame consumer use the same pinned toolchain and
dependency versions. Their JS/Wasm/Wasm GC/native jobs are defined in CI; actual
results are recorded in [validation](ACCEPTANCE.md). The current dependency graph is resolved from published versions without cache patches.
MoonIce 0.3.3 uses compiler/core 0.10.20 and the optional MoonFrame 0.8.1 example.
For compiler/core 0.10.16, use the v0.3.0 tag or Mooncakes package 0.3.0.

Independent PyArrow fixtures verify NONE and Snappy compression with dictionary
encoding, multiple row groups, nulls and exact Int64. Gzip and Zstd fixtures return
`PARQUET_DECODE` with the offending path and an unsupported-codec explanation.
Other codecs/encodings are not certified; support is constrained by the pinned
`mizchi/parquet@0.2.2` dependency. Snappy is also exercised by a real PyIceberg
partition-evolution table.

Time transforms use epoch microseconds (dates use epoch days), including negative
values. String truncate counts Unicode code points, not UTF-16 code units.
Inclusive transform projection retains the boundary partition and applies the
original row predicate after decoding; missing metrics are not proof of exclusion.

## Resource limits

- Offline bundle: at most 10,000 objects, 64 MiB per decoded object, 128 MiB decoded in total; JSON length also bounded.
- Raw metadata: at most 8 MiB of string code units.
- Manifest OCF: 64 MiB input, 1 MiB header metadata, 8 MiB encoded and decoded bytes per block, 64 MiB decoded bytes across the container, 100,000 records per block and one million records per container. Check all block envelopes and sync markers first. For DEFLATE, count output against the remaining byte budget before allocating an output buffer. A size overrun returns `RESOURCE_LIMIT`. Up to one million live entries may be retained across a snapshot.
- Parquet: 64 MiB input, 8 MiB footer, 100,000 rows and five million materialized cells per file; compact footer and page-header depth 32 / nodes 100,000 each. Before page decoding, validate row-group/column/page counts, byte ranges, overlaps and a cumulative 64 MiB declared uncompressed-page/header budget. Cross-file column chunks and unknown page types fail explicitly.
- Scan: one million data rows and 100,000 distinct delete rows; output limit 0–100,000, default 1,000.
- Predicate depth: 64.

The Avro specification uses raw RFC 1951 DEFLATE blocks. MoonIce also accepts the three trailing Adler-32 bytes emitted by fastavro 1.12.2 when they match the decoded payload. Truncated streams and other trailing data return `INVALID_AVRO`. See the [Avro specification](https://avro.apache.org/docs/1.12.0/specification/#deflate) and [fastavro writer](https://github.com/fastavro/fastavro/blob/1.12.2/fastavro/_write_py.py).

These format budgets apply to the encoded and decoded data, while schemas, datum objects, output rows and compiler runtime have their own overhead. Process RSS and CPU time need separate limits. Use trusted diagnostic samples, and isolate a service that processes untrusted input.

The current scanner materializes files. Batch callbacks avoid a single combined
result array but do not impose a decoder allocation budget. A callback error stops
further scanning; batches already delivered remain visible if a later I/O error
occurs. Consumers needing atomic output must stage it themselves. This reader is
intended for bounded samples rather than warehouse-scale queries. Displayed skipped
bytes are manifest file sizes, not measured traffic or a claim of speedup.

## Source references

- [Apache Iceberg spec](https://iceberg.apache.org/spec/): sequence inheritance, scan planning, stable IDs, equality/position deletes and binary bounds.
- [Parquet schema definition](https://github.com/apache/parquet-format/blob/master/src/main/thrift/parquet.thrift): footer schema field IDs.
- [Thrift compact protocol](https://github.com/apache/thrift/blob/master/doc/specs/thrift-compact-protocol.md): footer wire encoding.

Reference URLs describe evolving upstream specifications. MoonIce's declared scope remains the table above until implementation and tests expand it.
