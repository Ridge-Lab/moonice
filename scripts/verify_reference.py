"""Live PyIceberg oracle: seeded transforms and a newly generated evolving table.

Uses only synthetic data. Never rewrites the frozen repository fixtures.
"""
from __future__ import annotations
import argparse
import base64
import hashlib
from io import BytesIO
import json
from pathlib import Path
import random
import subprocess
import sys
import zlib

ROOT = Path(__file__).resolve().parent.parent


def run_json(command):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", timeout=120)
    if result.returncode:
        raise RuntimeError(f"Reference driver exited {result.returncode}: {result.stdout}\n{result.stderr}")
    return json.loads(result.stdout)


def manifest_cases():
    """Cross-check real OCF producers and distinguish bad streams from resource limits."""
    import fastavro
    from fastavro import _write_py
    sync = b"moonice-reference"[:16]
    fields = [("manifest_path", "string"), ("manifest_length", "long"), ("partition_spec_id", "int"),
              ("content", "int"), ("sequence_number", "long"), ("min_sequence_number", "long"),
              ("added_snapshot_id", "long"), ("extension", "bytes")]
    schema = {"type": "record", "name": "manifest_file", "fields": [{"name": k, "type": t} for k, t in fields]}
    rows = [dict(zip((k for k, _ in fields), [f"memory://m{i}", 18+i, i, i, 9, 7, 2**53+1+i, b""])) for i in range(2)]

    def file(writer, codec, records):
        out = BytesIO()
        writer(out, schema, records, codec=codec, sync_interval=1, sync_marker=sync)
        return out.getvalue()

    def avro(typ, value):
        out = BytesIO()
        fastavro.schemaless_writer(out, typ, value)
        return out.getvalue()

    def raw_deflate(payload):
        encoder = zlib.compressobj(wbits=-15)
        return encoder.compress(payload) + encoder.flush()

    header = file(fastavro.writer, "deflate", [])
    def frame(block):
        return header + avro("long", 1) + avro("long", len(block)) + block + sync

    def projection(data):
        return [{"path": r["manifest_path"], "length": str(r["manifest_length"]), "spec_id": r["partition_spec_id"],
                 "content": r["content"], "sequence_number": str(r["sequence_number"]),
                 "min_sequence_number": str(r["min_sequence_number"]), "added_snapshot_id": str(r["added_snapshot_id"])}
                for r in fastavro.reader(BytesIO(data))]

    block = raw_deflate(avro(schema, rows[0]))
    valid = [file(fastavro.writer, codec, rows) for codec in ("null", "deflate")]
    valid += [file(_write_py.writer, "deflate", rows), frame(block)]
    limit = 8 * 1024 * 1024
    padded = rows[0].copy()
    padded["extension"] = bytes(limit)
    overhead = len(avro(schema, padded)) - limit
    padded["extension"] = bytes(limit - overhead)
    exact = avro(schema, padded)
    assert len(exact) == limit
    valid.append(frame(raw_deflate(exact)))
    padded["extension"] += b"\0"
    over = avro(schema, padded)
    assert len(over) == limit + 1
    cases = [(data, projection(data)) for data in valid]
    cases += [(frame(raw_deflate(over)), "RESOURCE_LIMIT"), (frame(block[:-1]), "INVALID_AVRO"),
              (frame(block + b"bad"), "INVALID_AVRO"), (frame(raw_deflate(avro(schema, rows[0]) + b"x")), "INVALID_AVRO"),
              (valid[0][:-1] + b"!", "INVALID_AVRO")]
    return cases


def verify_column_projection(node, directory):
    """Compare against PyArrow and prove that pages outside the selection are skipped."""
    import pyarrow.parquet as pq
    bundle_path = ROOT / "fixtures/duckdb/column-mapping.icebundle.json"
    bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
    file = next(name for name in bundle["files"] if name.endswith(".parquet"))
    payload = bytearray(base64.b64decode(bundle["files"][file], validate=True))
    parquet = pq.ParquetFile(BytesIO(payload))
    expected = [{"name": row["name"]} for row in parquet.read(columns=["age", "name"]).to_pylist()
                if row["age"] >= 30]
    cli = [node, str(ROOT / "_build/js/release/build/cmd/main/main.js"), "scan"]

    def check(path, column="name"):
        response = run_json(cli + [str(path), "--column", column, "--filter",
                                   json.dumps({"field": "age", "op": ">=", "value": "30"})])
        return [row["values"] for row in response["result"]["scan"]["rows"]]

    if check(bundle_path) != expected:
        raise AssertionError("Mixed-schema projection differs from PyArrow")
    # The compressed page containing id becomes unreadable. A projection that
    # accidentally opens every column fails here even if it drops id afterwards.
    chunks = [parquet.metadata.row_group(0).column(i) for i in range(parquet.metadata.num_columns)]
    id_chunk = next(c for c in chunks if c.path_in_schema == "id")
    start = id_chunk.dictionary_page_offset if id_chunk.has_dictionary_page else id_chunk.data_page_offset
    payload[start] = 0  # prematurely terminate this Thrift page header
    bundle["files"][file] = base64.b64encode(payload).decode("ascii")
    corrupted = directory / "invalid-unselected-page.icebundle.json"
    corrupted.write_text(json.dumps(bundle), encoding="utf-8")
    if check(corrupted) != expected:
        raise AssertionError("Skipped column affected a successful projection")
    rejected = subprocess.run(cli + [str(corrupted), "--column", "id"], cwd=ROOT,
                              capture_output=True, text=True, encoding="utf-8", timeout=30)
    if rejected.returncode != 1 or json.loads(rejected.stdout).get("ok") is not False:
        raise AssertionError("Corrupted selected column was accepted")
    return {"rows": expected, "total_leaf_chunks": len(chunks), "selected_chunks": 2,
            "selected_compressed_bytes": sum(c.total_compressed_size for c in chunks
                                             if c.path_in_schema in ("age", "name")),
            "total_compressed_bytes": sum(c.total_compressed_size for c in chunks),
            "corrupt_unselected_column_skipped": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--node", default="node")
    parser.add_argument("--seed", type=int, default=20261110)
    args = parser.parse_args()
    import pyiceberg
    import pyarrow
    from pyiceberg.transforms import parse_transform
    from pyiceberg.types import IntegerType, LongType, StringType, BinaryType, DateType, TimestampType
    sys.path.insert(0, str(ROOT / "tools"))
    from extended_reference import generate

    args.output.parent.mkdir(parents=True, exist_ok=True)
    rng = random.Random(args.seed)
    cases, expected = [], []
    groups = [
        ("int", IntegerType(), [rng.randint(-(2**31), 2**31-1) for _ in range(80)], ["bucket[97]", "truncate[17]"]),
        ("long", LongType(), [rng.randint(-(2**63)+100, 2**63-1) for _ in range(80)], ["bucket[97]", "truncate[17]"]),
        ("string", StringType(), ["".join(rng.choices("abc北京😀é\u0301\ue000\U0010ffff", k=rng.randrange(20))) for _ in range(80)], ["bucket[97]", "truncate[3]"]),
        ("binary", BinaryType(), [bytes(rng.randrange(256) for _ in range(rng.randrange(30))) for _ in range(80)], ["bucket[97]", "truncate[7]"]),
        ("date", DateType(), [rng.randint(-100000, 100000) for _ in range(80)], ["year", "month", "day", "bucket[97]"]),
        ("timestamp", TimestampType(), [rng.randint(-2208988800000000, 4102444800000000) for _ in range(80)], ["year", "month", "day", "hour", "bucket[97]"]),
    ]
    def wire(value):
        if isinstance(value, bytes):
            return base64.b64encode(value).decode()
        return str(value) if isinstance(value, int) else value
    for kind, typ, values, transforms in groups:
        for value in values + [None]:
            for transform in transforms:
                cases.append({"type": kind, "transform": transform, "input": wire(value)})
                expected.append(wire(parse_transform(transform).transform(typ)(value)))
    transform_count = len(cases)
    # Exercise allocation preflight against independently written empty tables,
    # multiple row groups, nulls, dictionary pages, and both data-page versions.
    import pyarrow.parquet as pq
    schema = pyarrow.schema([
        pyarrow.field("id", pyarrow.int64(), metadata={b"PARQUET:field_id": b"1"}),
        pyarrow.field("label", pyarrow.string(), metadata={b"PARQUET:field_id": b"2"})])
    for rows in ([], [{"id": 1, "label": "a"}, {"id": None, "label": None}, {"id": 3, "label": "a"}]):
        for codec in ("NONE", "snappy"):
            for page_version in ("1.0", "2.0"):
                sink = pyarrow.BufferOutputStream()
                pq.write_table(pyarrow.Table.from_pylist(rows, schema=schema), sink, compression=codec,
                               data_page_version=page_version, row_group_size=2)
                cases.append({"type": "binary", "transform": "parquet-fields", "input": wire(sink.getvalue().to_pybytes())})
                expected.append([1, 2])
                cases.append({"type": "binary", "transform": "parquet-select", "rows": len(rows),
                              "input": wire(sink.getvalue().to_pybytes())})
                expected.append([r["label"] for r in rows])
    parquet_count = sum(case["transform"] == "parquet-fields" for case in cases)
    projection_count = sum(case["transform"] == "parquet-select" for case in cases)
    manifests = manifest_cases()
    for data, result in manifests:
        cases.append({"type": "binary", "transform": "manifest-list", "input": wire(data)})
        expected.append(result)
    corpus = args.output.parent / "transform-cases.json"
    corpus.write_text(json.dumps(cases, ensure_ascii=False), encoding="utf-8")
    actual = run_json([args.node, str(ROOT / "_build/js/release/build/cmd/reference/reference.js"), str(corpus)])
    if actual != expected:
        failures = [{"index": i, "transform": case["transform"], "expected": want, "actual": got}
                    for i, (case, want, got) in enumerate(zip(cases, expected, actual)) if want != got]
        raise AssertionError(f"Reference mismatch: {failures[:5]}; lengths={len(expected)}/{len(actual)}")

    fixtures = args.output.parent / "live-fixtures"
    generate(fixtures)
    bundle_path = fixtures / "partitioned.icebundle.json"
    bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
    scans = []
    for case in bundle["reference"]["cases"]:
        command = [args.node, str(ROOT / "_build/js/release/build/cmd/main/main.js"), "scan", str(bundle_path)]
        if case["predicate"] is not None:
            command += ["--filter", json.dumps(case["predicate"])]
        response = run_json(command)
        if not response.get("ok"):
            raise AssertionError(response)
        result = response["result"]
        ids = sorted(int(row["values"]["id"]) for row in result["scan"]["rows"])
        files = sorted(decision["entry"]["file"]["path"] for decision in result["plan"]["decisions"] if decision["kept"])
        if ids != case["ids"] or files != case["files"]:
            raise AssertionError({"case": case, "actual_ids": ids, "actual_files": files})
        scans.append({"case": case["label"], "rows": len(ids), "files": len(files)})
    report = {"status": "passed", "seed": args.seed, "pyiceberg": pyiceberg.__version__, "pyarrow": pyarrow.__version__,
              "transform_cases": transform_count, "parquet_preflight_cases": parquet_count,
              "parquet_projection_cases": projection_count, "avro_container_cases": len(manifests),
              "corpus_sha256": hashlib.sha256(corpus.read_bytes()).hexdigest(), "scans": scans,
              "duckdb_projection": verify_column_projection(args.node, args.output.parent),
              "limits": "Synthetic PyIceberg tables and a fixed DuckDB test table. These checks cover the reported cases."}
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
