"""Standard Avro/Parquet delete fixtures; expected survivors are explicit.

Uses PyIceberg-generated manifest schemas and independent fastavro/PyArrow
writers. This is not a claim that PyIceberg executes equality deletes.
"""
import base64
import copy
import io
import json
from pathlib import Path
import fastavro
import pyarrow as pa
import pyarrow.parquet as pq


def generate(root: Path):
    original = json.loads((root / "events.icebundle.json").read_text(encoding="utf-8"))
    templates = {}
    for path, value in original["files"].items():
        if path.endswith(".avro"):
            reader = fastavro.reader(io.BytesIO(base64.b64decode(value)))
            records = list(reader)
            if records:
                templates["manifest" if "data_file" in records[0] else "list"] = (
                    reader.writer_schema, records[0], reader.metadata)
    files = {}
    prefix = "memory://moonice-deletes/"

    def parquet(name, rows, fields):
        schema = pa.schema([pa.field(n, t, nullable=nullable,
            metadata={b"PARQUET:field_id": str(fid).encode()}) for n, t, fid, nullable in fields])
        sink = io.BytesIO()
        pq.write_table(pa.Table.from_pylist(rows, schema=schema), sink, compression="NONE")
        files[prefix + name] = sink.getvalue()
        return prefix + name

    fields = [("id", pa.int64(), 1, False), ("category", pa.string(), 2, True)]
    old = parquet("old.parquet", [{"id": 1, "category": "a"}, {"id": 2, "category": "b"},
        {"id": 3, "category": None}, {"id": 4, "category": "c"}], fields)
    new = parquet("new.parquet", [{"id": 2, "category": "new"}], fields)
    eq = parquet("equality.parquet", [{"category": "b"}, {"category": None}], [fields[1]])
    pos = parquet("positions.parquet", [{"file_path": old, "pos": 0}], [
        ("file_path", pa.string(), 2147483546, False), ("pos", pa.int64(), 2147483545, False)])

    def entry(path, content, count, sequence):
        result = copy.deepcopy(templates["manifest"][1])
        result.update(status=1, snapshot_id=101, sequence_number=sequence, file_sequence_number=sequence)
        data = result["data_file"]
        for key in data:
            if key not in ("content", "file_path", "file_format", "partition", "record_count", "file_size_in_bytes"):
                data[key] = None
        data.update(content=content, file_path=path, file_format="PARQUET", partition={},
                    record_count=count, file_size_in_bytes=len(files[path]), equality_ids=[2] if content == 2 else None)
        return result

    def avro(name, which, records, extra=None):
        schema, _, metadata = templates[which]
        metadata = {k: v for k, v in metadata.items() if not k.startswith("avro.")}
        metadata.update(extra or {})
        sink = io.BytesIO()
        fastavro.writer(sink, schema, records, metadata=metadata, codec="null", sync_marker=b"MoonIceFixture01")
        files[prefix + name] = sink.getvalue()
        return prefix + name

    data_manifest = avro("data.avro", "manifest", [entry(old, 0, 4, 1), entry(new, 0, 1, 2)], {"content": "data"})
    delete_manifest = avro("deletes.avro", "manifest", [entry(eq, 2, 2, 2), entry(pos, 1, 1, 2)], {"content": "deletes"})
    manifests = []
    for path, content in [(data_manifest, 0), (delete_manifest, 1)]:
        record = copy.deepcopy(templates["list"][1])
        record.update(manifest_path=path, manifest_length=len(files[path]), partition_spec_id=0,
            content=content, sequence_number=2, min_sequence_number=1 if content == 0 else 2, added_snapshot_id=101,
            added_files_count=2, existing_files_count=0, deleted_files_count=0,
            added_rows_count=5 if content == 0 else 3, existing_rows_count=0, deleted_rows_count=0, partitions=[])
        manifests.append(record)
    manifest_list = avro("list.avro", "list", manifests, {"snapshot-id": "101", "parent-snapshot-id": "null", "sequence-number": "2"})
    metadata = json.loads(original["metadata"])
    metadata.update({"table-uuid": "b5ee55b7-7340-4032-9668-ab29b55c6e51", "location": prefix,
        "last-sequence-number": 2, "current-schema-id": 0, "last-column-id": 2,
        "schemas": [{"type": "struct", "schema-id": 0, "fields": [
            {"id": 1, "name": "id", "required": True, "type": "long"},
            {"id": 2, "name": "category", "required": False, "type": "string"}]}],
        "current-snapshot-id": 101, "snapshots": [{"snapshot-id": 101, "sequence-number": 2,
            "timestamp-ms": 1789344000000, "manifest-list": manifest_list, "schema-id": 0, "summary": {"operation": "overwrite"}}],
        "refs": {"main": {"snapshot-id": 101, "type": "branch"}}, "snapshot-log": [], "metadata-log": []})
    bundle = {"moonice_bundle_version": 1, "metadata": json.dumps(metadata),
        "files": {p: base64.b64encode(b).decode() for p, b in files.items()},
        "reference": {"method": "explicit spec-derived expected rows", "expected_ids": [2, 4],
            "explanation": "Old id=1 removed by position, id=2 and null category removed by equality; same-sequence new id=2 survives."}}
    source = json.dumps(bundle, ensure_ascii=False, indent=2)
    (root / "deletes.icebundle.json").write_text(source, encoding="utf-8")
    (root.parent / "delete_fixture_test.mbt").write_text(
        "// Generated data by tools/delete_reference.py.\n///|\nlet delete_bundle : String =\n" +
        "\n".join("  #|" + line for line in source.splitlines()) + "\n", encoding="utf-8")
    print(json.dumps({"files": len(files), "expected_survivors": [2, 4]}))


if __name__ == "__main__":
    generate(Path("fixtures"))
