"""Create or validate the exact local-source integration workspace; never overwrite it."""
from pathlib import Path
import subprocess
import tomllib

ROOT = Path(__file__).resolve().parent.parent
integration = ROOT / "integrations/moonframe"
workspace = integration / "moon.work"
if not workspace.exists():
    subprocess.run(["moon", "work", "init", ".", "../.."], cwd=integration, check=True)
members = tomllib.loads(workspace.read_text(encoding="utf-8"))["members"]
actual = {(integration / member).resolve() for member in members}
expected = {ROOT.resolve(), integration.resolve()}
if actual != expected:
    raise SystemExit(f"Unexpected workspace members: {actual}; inspect {workspace} before replacing it")
print("MoonFrame workspace selects exactly this MoonIce source and the integration")
