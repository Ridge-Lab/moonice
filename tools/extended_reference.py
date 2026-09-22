"""Independent PyIceberg/PyArrow interoperability fixtures, not MoonIce logic.

Synthetic data only. Generates partition-transform answers using PyIceberg,
an actual table with evolving day/month specs, and compressed Parquet samples.
Run with requirements-reference.txt; output goes to the supplied fixture folder.
"""
from pathlib import Path
import base64
import datetime as dt
import json
import sys

import fsspec
import pyarrow as pa
import pyarrow.parquet as pq
import pyiceberg
from pyiceberg.catalog import load_in_memory
from pyiceberg.expressions import GreaterThanOrEqual, EqualTo
from pyiceberg.io.fsspec import SCHEME_TO_FS
from pyiceberg.partitioning import PartitionSpec, PartitionField
from pyiceberg.transforms import parse_transform, DayTransform
from pyiceberg.types import LongType, IntegerType, StringType, DateType, TimestampType, BinaryType, NestedField
from pyiceberg.schema import Schema


def literal_file(path, name, value):
    text = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    path.write_text("// Generated independent reference data; see tools/extended_reference.py.\n///|\nlet "
                    + name + " : String =\n  #|" + text + "\n", encoding="utf-8")


def generate(out):
    out.mkdir(parents=True, exist_ok=True)
    vectors = []
    groups = [
        ("int", IntegerType(), [-2147483648, -1001, -11, -1, 0, 1, 34, 1001, 2147483647], ["bucket[1]", "bucket[16]", "bucket[97]"]),
        ("long", LongType(), [-9223372036854775808, -9007199254740993, -11, -1, 0, 1, 34, 9007199254740993, 9223372036854775807], ["bucket[16]", "bucket[97]"]),
        ("long", LongType(), [-1001, -11, -1, 0, 1, 34, 1001], ["truncate[1]", "truncate[10]", "truncate[97]"]),
        ("string", StringType(), ["", "a", "ab", "abc", "abcd", "iceberg", "北京😀abc", "😀甲乙", "é\u0301"], ["bucket[16]", "bucket[97]", "truncate[1]", "truncate[3]"]),
        ("date", DateType(), [-25568, -1, 0, 1, 10957, 11016, 47541], ["year", "month", "day", "bucket[16]"]),
        ("timestamp", TimestampType(), [-2208988800000000, -86400000001, -86400000000, -3600000001, -1, 0, 1, 3600000000, 951782400000000, 4107542400000000], ["year", "month", "day", "hour", "bucket[16]"]),
    ]
    for label, typ, values, transforms in groups:
        for value in values + [None]:
            for transform in transforms:
                result = parse_transform(transform).transform(typ)(value)
                vectors.append({"type": label, "transform": transform,
                    "input": str(value) if isinstance(value, int) else value,
                    "expected": str(result) if isinstance(result, int) else result})
    literal_file(out.parent / "partition_fixture_test.mbt", "partition_reference", vectors)
    (out / "partition-reference.json").write_text(json.dumps(vectors, ensure_ascii=False, indent=2), encoding="utf-8")

    codecs = []
    arrow_schema = pa.schema([
        pa.field("id", pa.int64(), nullable=False, metadata={b"PARQUET:field_id": b"1"}),
        pa.field("label", pa.string(), metadata={b"PARQUET:field_id": b"2"}),
    ])
    table = pa.Table.from_pylist([{"id": -1, "label": "北京"}, {"id": 9007199254740993, "label": "repeat"},
        {"id": 3, "label": None}, {"id": 4, "label": "repeat"}], schema=arrow_schema)
    for codec in ["NONE", "snappy", "gzip", "zstd"]:
        sink = pa.BufferOutputStream()
        pq.write_table(table, sink, compression=codec, row_group_size=2, use_dictionary=True, data_page_version="1.0")
        data = sink.getvalue().to_pybytes()
        codecs.append({"codec": codec, "bytes": base64.b64encode(data).decode(), "length": len(data)})
    literal_file(out.parent / "codec_fixture_test.mbt", "codec_reference", codecs)

    SCHEME_TO_FS["memory"] = lambda properties: fsspec.filesystem("memory")
    catalog = load_in_memory("extended", {"warehouse": "memory://moonice-partitioned",
        "py-io-impl": "pyiceberg.io.fsspec.FsspecFileIO"})
    catalog.create_namespace("demo")
    schema = Schema(NestedField(1, "id", LongType(), required=True),
        NestedField(2, "ts", TimestampType(), required=False), NestedField(3, "label", StringType(), required=False))
    spec = PartitionSpec(PartitionField(source_id=2, field_id=1000, transform=DayTransform(), name="ts_day"))
    table = catalog.create_table("demo.partitioned", schema, partition_spec=spec,
        properties={"format-version": "2", "write.parquet.compression-codec": "snappy"})
    arrow_schema = pa.schema([pa.field("id", pa.int64(), nullable=False), pa.field("ts", pa.timestamp("us")), pa.field("label", pa.string())])
    table.append(pa.Table.from_pylist([
        {"id": 1, "ts": dt.datetime(1969, 12, 31, 23, 59, 59), "label": "before epoch"},
        {"id": 2, "ts": dt.datetime(1970, 1, 1), "label": "epoch"},
        {"id": 3, "ts": dt.datetime(2024, 2, 29, 12), "label": "leap"},
        {"id": 4, "ts": None, "label": "null"},
    ], schema=arrow_schema))
    with table.update_spec() as update:
        update.remove_field("ts_day")
        update.add_field("ts", "month", "ts_month")
    table.append(pa.Table.from_pylist([
        {"id": 10, "ts": dt.datetime(2024, 3, 1), "label": "month"},
        {"id": 11, "ts": dt.datetime(2025, 1, 1), "label": "next year"},
    ], schema=arrow_schema))
    cases = []
    for label, expression, predicate in [
        ("all", None, None),
        ("epoch", GreaterThanOrEqual("ts", 0), {"field": "ts", "op": ">=", "value": "0"}),
        ("march", GreaterThanOrEqual("ts", 1709251200000000), {"field": "ts", "op": ">=", "value": "1709251200000000"}),
        ("leap", EqualTo("ts", 1709208000000000), {"field": "ts", "op": "=", "value": "1709208000000000"}),
    ]:
        scan = table.scan() if expression is None else table.scan(row_filter=expression)
        cases.append({"label": label, "predicate": predicate, "files": sorted(t.file.file_path for t in scan.plan_files()),
            "ids": sorted(scan.to_arrow().column("id").to_pylist())})
    fs = fsspec.filesystem("memory")
    files = {"memory://" + p.lstrip("/"): base64.b64encode(fs.cat(p)).decode()
        for p in fs.find("/moonice-partitioned") if p.endswith((".avro", ".parquet"))}
    bundle = {"moonice_bundle_version": 1, "metadata": table.metadata.model_dump_json(by_alias=True, exclude_none=True),
        "files": files, "reference": {"engine": "PyIceberg", "version": pyiceberg.__version__, "cases": cases}}
    (out / "partitioned.icebundle.json").write_text(json.dumps(bundle, ensure_ascii=False, indent=2), encoding="utf-8")
    literal_file(out.parent / "partitioned_fixture_test.mbt", "partitioned_bundle", bundle)
    print(json.dumps({"transform_vectors": len(vectors), "parquet_codecs": len(codecs), "partition_specs": len(table.metadata.partition_specs), "scan_cases": len(cases)}))


if __name__ == "__main__":
    generate(Path(sys.argv[1] if len(sys.argv) > 1 else "fixtures"))
