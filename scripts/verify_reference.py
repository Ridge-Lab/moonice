"""Live PyIceberg oracle: seeded transforms and a newly generated evolving table.

Uses only synthetic data. Never rewrites the frozen repository fixtures.
"""
from __future__ import annotations
import argparse
import base64
import hashlib
import json
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def run_json(command):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", timeout=120)
    if result.returncode:
        raise RuntimeError(f"Reference driver exited {result.returncode}: {result.stdout}\n{result.stderr}")
    return json.loads(result.stdout)


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
    corpus = args.output.parent / "transform-cases.json"
    corpus.write_text(json.dumps(cases, ensure_ascii=False), encoding="utf-8")
    actual = run_json([args.node, str(ROOT / "_build/js/release/build/cmd/reference/reference.js"), str(corpus)])
    if actual != expected:
        failures = [{"case": case, "expected": want, "actual": got} for case, want, got in zip(cases, expected, actual) if want != got]
        raise AssertionError(f"Transform oracle mismatch: {failures[:5]}; lengths={len(expected)}/{len(actual)}")

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
              "transform_cases": transform_count, "parquet_preflight_cases": len(cases)-transform_count,
              "corpus_sha256": hashlib.sha256(corpus.read_bytes()).hexdigest(), "scans": scans,
              "limits": "Synthetic bounded samples; live PyIceberg plan/row oracle. Does not certify all Iceberg versions or equality-delete execution."}
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
