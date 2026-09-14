"""Independent PyIceberg oracle and synthetic fixtures; no MoonIce implementation.

Run with the pinned packages in tools/requirements-reference.txt. Uses an isolated
in-memory warehouse and writes only the supplied output directory.
"""
from pathlib import Path
import base64
import json
import sys

import fsspec
import pyarrow as pa
import pyiceberg
from pyiceberg.catalog import load_in_memory
from pyiceberg.schema import Schema
from pyiceberg.types import NestedField, LongType, StringType
from pyiceberg.expressions import GreaterThanOrEqual
from pyiceberg.io.fsspec import SCHEME_TO_FS


def generate(output: Path):
    output.mkdir(parents=True, exist_ok=True)
    SCHEME_TO_FS["memory"] = lambda properties: fsspec.filesystem("memory")
    catalog = load_in_memory("reference", {
        "warehouse": "memory://moonice-reference",
        "py-io-impl": "pyiceberg.io.fsspec.FsspecFileIO",
    })
    catalog.create_namespace("demo")
    schema = Schema(
        NestedField(1, "id", LongType(), required=True),
        NestedField(2, "city", StringType(), required=False),
        NestedField(3, "amount", LongType(), required=False),
    )
    table = catalog.create_table("demo.events", schema, properties={
        "format-version": "2",
        "write.parquet.compression-codec": "uncompressed",
    })
    arrow_schema = pa.schema([
        pa.field("id", pa.int64(), nullable=False),
        pa.field("city", pa.string()), pa.field("amount", pa.int64()),
    ])
    table.append(pa.Table.from_pylist([
        {"id": 1, "city": "北京", "amount": 10},
        {"id": 2, "city": "深圳", "amount": 20},
        {"id": 3, "city": None, "amount": None},
    ], schema=arrow_schema))
    table.append(pa.Table.from_pylist([
        {"id": 10, "city": "杭州", "amount": 100},
        {"id": 11, "city": "上海", "amount": 200},
    ], schema=arrow_schema))
    table.delete("id == 2")
    with table.update_schema() as update:
        update.rename_column("city", "region")
        update.add_column("note", StringType())
    references = []
    for snapshot in table.snapshots():
        for label, predicate in [("all", None), ("id_ge_10", GreaterThanOrEqual("id", 10))]:
            kwargs = {"snapshot_id": snapshot.snapshot_id}
            if predicate is not None:
                kwargs["row_filter"] = predicate
            scan = table.scan(**kwargs)
            references.append({
                "snapshot_id": str(snapshot.snapshot_id), "filter": label,
                "files": sorted(task.file.file_path for task in scan.plan_files()),
                "rows": sorted(scan.to_arrow().to_pylist(), key=lambda r: r["id"]),
            })
    fs = fsspec.filesystem("memory")
    files = {}
    for path in fs.find("/moonice-reference"):
        if path.endswith((".avro", ".parquet")):
            files["memory://" + path.lstrip("/")] = base64.b64encode(fs.cat(path)).decode("ascii")
    bundle = {
        "moonice_bundle_version": 1,
        "metadata": table.metadata.model_dump_json(by_alias=True, exclude_none=True),
        "files": files,
        "reference": {"engine": "PyIceberg", "version": pyiceberg.__version__, "cases": references},
    }
    (output / "events.icebundle.json").write_text(json.dumps(bundle, ensure_ascii=False, indent=2), encoding="utf-8")
    (output / "reference.json").write_text(json.dumps(references, ensure_ascii=False, indent=2), encoding="utf-8")
    # A data literal keeps the frozen reference usable on all MoonBit backends.
    source = "// Generated test data by tools/reference.py; not implementation code.\n///|\nlet reference_bundle : String =\n"
    source += "\n".join("  #|" + line for line in json.dumps(bundle, ensure_ascii=False, indent=2).splitlines()) + "\n"
    (output.parent / "reference_fixture_test.mbt").write_text(source, encoding="utf-8")
    print(json.dumps({"snapshots": len(table.snapshots()), "files": len(files), "reference_cases": len(references)}))


if __name__ == "__main__":
    generate(Path(sys.argv[1] if len(sys.argv) > 1 else "fixtures"))
