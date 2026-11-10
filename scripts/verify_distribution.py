"""Check executable staging and byte-identical license/NOTICE inclusion."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--output", type=Path, required=True)
p.add_argument("--node", default="node")
a = p.parse_args()
version = re.search(r'^version = "([^"]+)"', (ROOT / "moon.mod").read_text(), re.M)[1]
cli = ROOT / "_build/distribution" / version / "cli"
core = Path(os.environ["MOON_HOME"]) / "lib/core"
for name in ("LICENSE", "NOTICE"):
    assert (core / name).read_bytes() == (ROOT / "licenses" / ("moonbit-core-" + name)).read_bytes(), "SDK notice drift"
hashes = {}
for source in sorted((ROOT / "licenses").iterdir()):
    if source.is_file():
        for target in (ROOT / "web/licenses" / source.name, cli / "licenses" / source.name):
            assert target.read_bytes() == source.read_bytes(), f"Missing/stale notice: {target}"
        hashes[source.name] = hashlib.sha256(source.read_bytes()).hexdigest()
for root in (ROOT / "web", cli):
    for name in ("LICENSE", "THIRD_PARTY.md"):
        assert (root / name).read_bytes() == (ROOT / name).read_bytes()
assert (ROOT / "web/moonice.js").stat().st_size > 0
result = subprocess.run([a.node, str(cli / "moonice.mjs"), "scan", "fixtures/deletes.icebundle.json"], cwd=cli,
                        check=True, capture_output=True, text=True, encoding="utf-8", timeout=120)
response = json.loads(result.stdout)
assert response["ok"] and response["result"]["scan"]["matched_rows"] == 2
a.output.write_text(json.dumps({"status": "passed", "version": version, "notice_sha256": hashes,
                               "cli_sha256": hashlib.sha256((cli / "moonice.mjs").read_bytes()).hexdigest()}, indent=2) + "\n")
print(f"Distribution {version}: notices and staged CLI passed")
