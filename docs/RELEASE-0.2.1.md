# MoonIce 0.2.1

MoonIce now builds with **moonc 0.10.14+7d59c7ec9** and the matching core.
The release preserves the 0.2.0 Iceberg v2 reading feature set while repairing
compiler and dependency compatibility.

- Direct Avro OCF imports avoid the unused, incompatible JSON facade.
- Explicit trait-method exposure preserves public method calls.
- Parquet 0.2.2 and x 0.5.5 resolve the MoonFrame Wasm dependency conflict.
- CI covers check/test/release build on JS, Wasm, Wasm GC and Linux native,
  and exercises the MoonFrame consumer on the same four targets.
- README includes versioned clone, library installation and reproducible samples.

All four core targets passed 45 tests each, and all four MoonFrame integration
jobs passed [CI](https://github.com/Ridge-Lab/moonice/actions/runs/36724785284).
The published Mooncakes package also passed a registry-only consumer check on
JS, Wasm and Wasm GC. The deployed workbench's four sample flows were exercised.

Install with `moon add Ridge-Lab/moonice@0.2.1`. See
[verification](ACCEPTANCE.md), [compatibility](COMPATIBILITY.md) and
[provenance](PROVENANCE.md) for actual results and supported scope.

Distribution assets include the CLI (Node.js), static web workbench, source
and Mooncakes module archives, plus `SHA256SUMS-0.2.1.txt`.
The reader remains bounded and read-only; no full Iceberg conformance or
production-scale performance is claimed. Apache-2.0.
