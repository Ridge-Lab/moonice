# Compatibility and boundaries

MoonIce 0.1.0 is a bounded Iceberg v2 reader/inspector, not a complete standards certification.

| Surface | Current behavior |
|---|---|
| Table metadata | v2 only; schemas, partition specs, snapshots, current snapshot, branches/tags, retained ancestry checks |
| v1 upgraded tables | v1 manifests are not supported, even inside a v2 table |
| v3/v4 | Rejected, including deletion vectors, row lineage and newer types |
| Avro containers | Existing `yugonlian/moon-avro` decoder; null/deflate codecs; header version/spec/content checked |
| Manifest entries | Existing/added/deleted status; null sequence inheritance only for added entries; deleted entries excluded |
| File statistics | Integer/date/time/timestamp, string, boolean, binary and double bounds; float/unsupported bounds retain files |
| Null / NaN | Null counts used conservatively; float/double bounds do not prune when NaN counts are unknown/nonzero; no NaN literal filters |
| Predicates | Typed ID-bound comparisons, null checks, AND/OR; no SQL, NOT, IN or transforms in expressions |
| Partition pruning | Identity only; unknown transforms retained; spec IDs and partition values used for deletes |
| Position deletes | Reserved field IDs for path/position, exact path match, zero-based positions; data sequence ≤ delete sequence |
| Equality deletes | Flat supported scalar keys including null; data sequence < delete sequence; same partition or global unpartitioned spec |
| Parquet | Existing `mizchi/parquet` decoder plus MoonIce field-ID footer inspection; flat primitive schema, explicit positive IDs |
| Projection | Stable IDs survive rename; absent optional fields null-fill; required missing fields fail; int→long values supported |
| Nested/decimal/UUID/defaults | Not supported for row execution; unsupported projected types fail. No name mapping fallback for absent Parquet IDs |
| Other data formats | Metadata can be inspected; ORC/Avro data-row execution fails explicitly |
| Snapshot difference | Physical file additions/removals and schema changes; not logical row CDC |
| Diagnostics | Bundle reference existence/size, incomplete traversal, unsupported format hints; not a complete file-integrity or table-consistency validator |
| Storage | Caller-provided byte reader or explicit offline object map; no REST catalog, S3 client, remote auth or range reads |
| Mutations | No table writes, transactions, snapshot expiration or object deletion |

The pinned Parquet decoder supports a subset of codecs and encodings. The frozen interoperability fixtures use uncompressed Parquet. Other codecs are delegated to that dependency and may return `PARQUET_DECODE`; they have not all been independently certified here.

## Resource limits

- Offline bundle: at most 10,000 objects, 64 MiB per decoded object, 128 MiB decoded in total; JSON length also bounded.
- Manifest OCF: 64 MiB input, 1 MiB header metadata, 8 MiB block bytes, 100,000 records per block, one million resulting entries.
- Parquet: 64 MiB input, 8 MiB footer, 100,000 rows per file; compact footer depth 32 / nodes 100,000.
- Scan: one million data rows and 100,000 distinct delete rows; output limit 0–100,000, default 1,000.
- Predicate depth: 64.

These guards limit ordinary oversized inputs; they are not a complete hostile-input sandbox. Underlying codecs allocate decoded structures, and compressed data can expand. Use trusted, bounded diagnostic samples; a production service needs stronger streaming, allocation and decompression budgets.

The current scanner materializes files. It is intended for diagnostic samples and reference verification rather than warehouse-scale queries. Displayed skipped bytes are manifest file sizes, not measured network traffic or a claim of query speedup.

## Source references

- [Apache Iceberg spec](https://iceberg.apache.org/spec/): sequence inheritance, scan planning, stable IDs, equality/position deletes and binary bounds.
- [Parquet schema definition](https://github.com/apache/parquet-format/blob/master/src/main/thrift/parquet.thrift): footer schema field IDs.
- [Thrift compact protocol](https://github.com/apache/thrift/blob/master/doc/specs/thrift-compact-protocol.md): footer wire encoding.

Reference URLs describe evolving upstream specifications. MoonIce's declared scope remains the table above until implementation and tests expand it.
