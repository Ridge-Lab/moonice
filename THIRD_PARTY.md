# Third-party components

The compiled MoonIce browser distribution includes code from these MoonBit
components. Each is distributed under Apache-2.0; the license text is provided
in the accompanying `LICENSE` file. The dependencies retain their own authorship.

| Component | Version | Purpose and source |
|---|---|---|
| MoonBit core | 0.10.8+8606a5800 | Standard library, [moonbitlang/core](https://github.com/moonbitlang/core) |
| moonbitlang/x | 0.4.40 | Filesystem support used by the Parquet package and CLI, [moonbitlang/x](https://github.com/moonbitlang/x) |
| yugonlian/moon-avro | 0.3.0 | Avro container decoding, [moon-avro](https://github.com/yugonlian/moon-avro) |
| Milky2018/moon_yazi | 0.1.3 | DEFLATE support for Avro, [moon_yazi](https://github.com/moonbit-community/moon_yazi) |
| mizchi/parquet | 0.2.1 | Parquet data-page decoding, [mizchi/parquet](https://github.com/mizchi/parquet) |

The dependency resolver also downloads `f4ah6o/duckdb@0.6.0` and
`moonbitlang/quickcheck@0.9.9` (Apache-2.0) for dependency package examples/tests.
MoonIce does not run a DuckDB engine in its browser or use it for scan execution.

Synthetic fixtures were produced with Apache PyIceberg/PyArrow (Apache-2.0)
and fastavro (MIT). These Python programs are reference tooling; Python and those
libraries are not included in the browser executable. See the source repository's
`docs/PROVENANCE.md` for implementation and reference-data provenance.
