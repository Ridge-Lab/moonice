# Validation record

Environment: Windows, 2026-09-14, `moon 0.1.20260814`, `moonc v0.10.8+8606a5800`, Node.js. The repository includes runnable checks; this document separates observed results from configured future checks.

## Observed locally

- All 31 tests passed independently on Wasm, Wasm GC and JavaScript, including two executable documentation examples. Each run used `--deny-warn`.
- `moon check --target all` passed (type checking is distinct from running native binaries).
- Windows native execution could not start because no supported system C compiler was available. The bundled `tcc` was not accepted through the attempted `CC` environment override. Native execution is not claimed as locally validated.
- Six frozen PyIceberg scan cases compare exact file sets and row values across three snapshots, including append, rewrite/delete and schema rename/addition.
- Independently written standard delete fixtures have five physical rows, three deleted rows, and two surviving rows. Equal-sequence newly added data survives equality deletes; nullable equality keys and physical positions are covered.
- Exhaustive small integer intervals test that any file-pruning proof excludes every value in that interval; boundary comparisons use all five comparison operators.
- Sequence test matrix covers equality strict inequality versus position non-strict inequality, plus global equality deletes and partition mismatches.
- Browser manual integration: default `id >= 10` yields two rows, one retained file and one pruned file; changing to all records yields four rows; delete demo yields two survivors; missing-manifest demo yields a path-specific failure and clears stale data.

## Commands

```sh
moon check --target all --deny-warn
moon test --target wasm
moon test --target wasm-gc
moon test --target js
npm run build
moon run --target js cmd/main -- check fixtures/events.icebundle.json
moon run --target js cmd/main -- scan fixtures/deletes.icebundle.json --limit 1
```

`.github/workflows/ci.yml` configures Linux checks for Wasm, Wasm GC, JS and native, plus a downloadable web build. A configured workflow is not evidence of a successful remote run. See the actual repository Actions results after publication.

## Reproducibility and evidence limits

`tools/reference.py` executes PyIceberg/PyArrow, with pinned packages in `requirements-reference.txt`. It regenerates the same semantic sequence with newly assigned IDs. `tools/delete_reference.py` uses Avro schemas from that fixture and independent fastavro/PyArrow writers. Its expected deletion results are specification-derived; no PyIceberg equality-delete execution is claimed.

The generated `_fixture_test.mbt` files contain data literals for cross-backend tests, not implementation code. They should not be counted as authored implementation complexity. Small fixtures establish correctness examples, not performance leadership, production readiness or adoption. No fabricated external usage or benchmark multiplier is included.
