"""Verify the tagged release in a fresh registry-only consumer, with asserted semantics."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = "Ridge-Lab/moonice"
CONSUMER = r'''///|
fn verify_identity_projection() -> Unit raise {
  let bundle = @moonice.open_bundle(@fs.read_file_to_string("fixtures/duckdb/identity-source.icebundle.json"))
  let read = path => bundle.read_file(path)
  let state = @moonice.load_snapshot(bundle.metadata, read)
  let visible = @moonice.scan_rows(bundle.metadata, state, All, read)
  let ids : Array[Int64] = []
  for row in visible.rows {
    let values = row.project(visible.schema)
    assert_eq(values.get("region"), Some(@moonice.Text("eu")))
    match values.get("id") {
      Some(@moonice.Integer(id)) => ids.push(id)
      _ => fail("Expected an integer id from the DuckDB fixture")
    }
  }
  ids.sort()
  assert_eq(ids, [1L, 2L])
  let predicate = @moonice.parse_predicate("{\"field\":\"region\",\"op\":\"=\",\"value\":\"eu\"}", state.schema)
  let selected = @moonice.scan_rows(bundle.metadata, state, predicate, read)
  assert_eq(selected.matched_rows, 2)
}

///|
fn demonstrate() -> Unit raise {
  let bundle = @moonice.open_bundle(@fs.read_file_to_string("fixtures/deletes.icebundle.json"))
  let read = path => bundle.read_file(path)
  let state = @moonice.load_snapshot(bundle.metadata, read)
  let mut physical_rows = 0
  for entry in state.entries {
    if entry.file.content == 0 {
      physical_rows += @moonice.read_data_rows(read(entry.file.path), entry.file).length()
    }
  }
  let visible = @moonice.scan_rows(bundle.metadata, state, All, read)
  assert_eq(physical_rows, 5)
  assert_eq(visible.read_rows, 5)
  assert_eq(visible.deleted_rows, 3)
  assert_eq(visible.matched_rows, 2)
  assert_eq(visible.rows.length(), 2)
  assert_false(visible.truncated)
  let predicate = @moonice.parse_predicate("{\"field\":\"id\",\"op\":\"=\",\"value\":\"2\"}", state.schema)
  let selected = @moonice.scan_rows(bundle.metadata, state, predicate, read)
  assert_eq(selected.matched_rows, 1)
  assert_eq(selected.rows.length(), 1)
  assert_eq(selected.rows[0].values.get(1), Some(@moonice.Integer(2L)))
  assert_eq(selected.rows[0].project(selected.schema).get("category"), Some(@moonice.Text("new")))
  // Version 0.3.0 regression: illegal narrowing must not return a projected row.
  let schema : @moonice.Schema = {
    id: 0,
    fields: [{ id: 1, name: "value", required: true, field_type: Json("int") }],
  }
  let row : @moonice.DataRow = {
    file_path: "memory://consumer-limit", position: 0L,
    values: Map([(1, @moonice.Integer(2147483648L))]),
  }
  try row.project(schema) catch {
    @moonice.Invalid(code, _, _) => assert_eq(code, "UNSUPPORTED_TYPE")
  } noraise { _ => fail("Published package accepted an out-of-range int") }
  // A complete raw stream for Avro long 7 followed by an invalid producer suffix.
  let sync = b"0123456789abcdef"
  let header = b"Obj\x01\x04\x14avro.codec\x0edeflate\x16avro.schema\x0c\"long\"\x00"
  let bad_block = b"\x02\x0c\xe3\x03\x00bad"
  try @moonice.decode_manifest_list(header + sync + bad_block + sync) catch {
    @moonice.Invalid(code, _, _) => assert_eq(code, "INVALID_AVRO")
  } noraise { _ => fail("Published package accepted trailing DEFLATE data") }
  verify_identity_projection()
  let (mixed, names) = @moonice.open_mapped_bundle(@fs.read_file_to_string("fixtures/duckdb/column-mapping.icebundle.json"))
  let people = mixed.scan(Compare(3, Ge, Integer(30L)), columns=["name"], name_mapping=names)
  assert_eq(people.rows.map(r => r.values.get(2)), [Some(Text("Bob")), Some(Text("Charlie"))])
  assert_true(people.rows.iter().all(r => r.values.length() == 1))
  println("MOONICE_CONSUMER_OK physical=5 deleted=3 visible=2 selected_id=2 int_range=rejected deflate_tail=rejected identity_eu=2 projected_names=2")
}

///|
fn main {
  demonstrate() catch {
    error => {
      println("Consumer assertion failed: \{error}")
      @sys.exit(1)
    }
  }
}
'''


def module_identity(path: Path) -> dict[str, str]:
    source = path.read_text(encoding="utf-8")
    result = {}
    for key in ("name", "version"):
        matches = re.findall(r'^\s*' + key + r'\s*=\s*"([^"\n]+)"', source, re.M)
        if len(matches) != 1:
            raise ValueError(f"Expected one {key} in {path}")
        result[key] = matches[0]
    return result


def require_identity(actual: dict[str, str], version: str, label: str) -> None:
    expected = {"name": PACKAGE, "version": version}
    if actual != expected:
        raise ValueError(f"{label} identity mismatch: expected {expected}, found {actual}")


def require_release_tag(tag: str, version: str) -> None:
    if tag != "v" + version:
        raise ValueError(f"Release tag {tag!r} does not match requested version {version}")


def checkout_identity(version: str) -> dict:
    identity = module_identity(ROOT / "moon.mod")
    require_identity(identity, version, "Checkout")
    git = ["git", f"--git-dir={ROOT / '.git'}", f"--work-tree={ROOT}"] if (ROOT / ".git").is_dir() else ["git", "-C", str(ROOT)]
    def read(*args):
        return subprocess.check_output(git + list(args), cwd=ROOT, text=True, stderr=subprocess.PIPE).strip()
    tag = os.environ.get("RELEASE_TAG") or read("describe", "--exact-match", "--tags", "HEAD")
    require_release_tag(tag, version)
    head = read("rev-parse", "HEAD")
    tag_commit = read("rev-parse", f"refs/tags/{tag}^{{commit}}")
    if head != tag_commit:
        raise ValueError("Release tag does not identify the checked-out commit")
    return {**identity, "release_tag": tag, "head": head, "tag_commit": tag_commit}


def write_consumer(directory: Path, version: str) -> None:
    directory.mkdir(parents=True, exist_ok=False)
    (directory / "moon.mod").write_text(f'name = "verify/moonice_consumer"\nversion = "0.0.0"\nimport {{ "{PACKAGE}@{version}", "moonbitlang/x@0.5.7" }}\n', encoding="utf-8")
    shutil.copyfile(ROOT / "examples/library_read/moon.pkg", directory / "moon.pkg")
    (directory / "main.mbt").write_text(CONSUMER, encoding="utf-8")
    (directory / "fixtures/duckdb").mkdir(parents=True)
    for fixture in ("deletes.icebundle.json", "duckdb/identity-source.icebundle.json", "duckdb/column-mapping.icebundle.json", "duckdb/LICENSE"):
        shutil.copyfile(ROOT / "fixtures" / fixture, directory / "fixtures" / fixture)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--targets", nargs="+", choices=("js", "wasm", "wasm-gc", "native"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("version must be an explicit numeric release")
    checkout = checkout_identity(args.version)
    directory = args.output.resolve()
    write_consumer(directory, args.version)
    for command in (["moon", "update"], ["moon", "fmt"]):
        subprocess.run(command, cwd=directory, check=True)
    # Resolve before claiming which package was actually consumed.
    subprocess.run(["moon", "check", "--target", args.targets[0], "--deny-warn"], cwd=directory, check=True)
    installed_mod = directory / ".mooncakes" / "Ridge-Lab" / "moonice" / "moon.mod"
    installed = module_identity(installed_mod)
    require_identity(installed, args.version, "Installed package")
    for name in ("column-mapping.icebundle.json", "identity-source.icebundle.json", "LICENSE"):
        fixture = Path("fixtures/duckdb") / name
        if (installed_mod.parent / fixture).read_bytes() != (ROOT / fixture).read_bytes():
            raise ValueError(f"Installed DuckDB fixture or license differs: {name}")
    results = []
    for target in args.targets:
        subprocess.run(["moon", "check", "--target", target, "--deny-warn"], cwd=directory, check=True)
        run = subprocess.run(["moon", "run", "--target", target, "."], cwd=directory, check=True,
                             capture_output=True, text=True, encoding="utf-8", timeout=300)
        print(run.stdout, end="")
        if "MOONICE_CONSUMER_OK physical=5 deleted=3 visible=2 selected_id=2 int_range=rejected deflate_tail=rejected identity_eu=2 projected_names=2" not in run.stdout:
            raise ValueError(f"{target}: successful exit without consumer assertions marker")
        results.append({"target": target, "exit_code": run.returncode, "stdout": run.stdout})
    require_identity(module_identity(installed_mod), args.version, "Installed package after execution")
    report = {"status": "passed", "mode": "registry-only", "requested_version": args.version,
              "checkout": checkout, "installed": installed,
              "installed_manifest_sha256": hashlib.sha256(installed_mod.read_bytes()).hexdigest(), "results": results}
    (directory / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Registry-only {installed['name']}@{installed['version']} passed: {args.targets}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
