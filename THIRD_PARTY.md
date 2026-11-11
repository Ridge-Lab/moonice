# Third-party components

The MoonIce browser and CLI distributions retain notices for these direct and
transitive MoonBit components. Their package-level license is Apache-2.0; the license text
is provided in the accompanying `LICENSE` file. The dependencies retain their
own authorship. MoonBit core also carries upstream notices and licenses for
adapted components: its unchanged [LICENSE](licenses/moonbit-core-LICENSE) and
[NOTICE](licenses/moonbit-core-NOTICE) are included with these distributions.
The NOTICE must be retained alongside the package-level license, including the
attribution and license terms reproduced there.

| Component | Version | Purpose and source |
|---|---|---|
| MoonBit core | 0.10.20+65efd5b93 | Standard library and bounded raw DEFLATE decoding, [moonbitlang/core](https://github.com/moonbitlang/core) |
| moonbitlang/x | 0.5.7 | Filesystem support used by the Parquet package and CLI, [moonbitlang/x](https://github.com/moonbitlang/x) |
| yugonlian/moon-avro | 0.3.0 | Avro container decoding, [moon-avro](https://github.com/yugonlian/moon-avro) |
| Milky2018/moon_yazi | 0.1.3 | Transitive codec dependency of moon-avro, [moon_yazi](https://github.com/moonbit-community/moon_yazi) |
| mizchi/parquet | 0.2.2 | Parquet data-page decoding, [mizchi/parquet](https://github.com/mizchi/parquet) |

The dependency resolver also downloads `mizchi/duckdb@0.6.6` and
`moonbitlang/quickcheck@0.15.1` (Apache-2.0) for dependency package examples/tests.
MoonIce does not run a DuckDB engine in its browser or use it for scan execution.

Synthetic fixtures were produced with Apache PyIceberg/PyArrow (Apache-2.0)
and fastavro (MIT). These Python programs are reference tooling; Python and those
libraries are not included in the browser executable. See the source repository's
`docs/PROVENANCE.md` for implementation and reference-data provenance.

The core license and notice files are copied byte-for-byte from the pinned
`0.10.20+65efd5b93` SDK's `lib/core/`. When changing the toolchain, refresh both
files from the matching SDK and retain them in browser and CLI archives.

`scripts/verify.py` and its harness-contract tests adapt the maintainer's
[Ridge-Lab/moonstretch](https://github.com/Ridge-Lab/moonstretch) verification
runner (MIT). Its original license is retained as `licenses/moonstretch-MIT`.
This is shared engineering infrastructure, not a new MoonIce algorithm or a
separate contest contribution. Original Avro, Yazi and Parquet license texts
are also preserved in `licenses/` and copied into both distributions.
The published x 0.5.7 package declares Apache-2.0 and retains IDEA source
copyright headers; it does not contain a root LICENSE file. The Apache-2.0
text is distributed as `LICENSE`, without inventing a copied x license file.
