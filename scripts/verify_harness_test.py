# Adapted from Ridge-Lab/moonstretch (MIT); see licenses/moonstretch-MIT.
"""Failure-contract regressions for the verification entry point (no MoonBit build)."""
import argparse
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import verify
import verify_release


class VerificationFailureTests(unittest.TestCase):
    def setUp(self):
        work = verify.ROOT / "work"
        work.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="harness-regression-", dir=work)
        self.directory = pathlib.Path(self.temporary.name)
        args = argparse.Namespace(node="node", moon="moon", profile="quick", targets=["js"], timeout=10)
        self.verification = verify.Verification(args, self.directory)

    def tearDown(self):
        self.temporary.cleanup()

    def test_child_failure_blocks_dependents_and_fails_summary(self):
        marker = self.directory / "must-not-exist"
        self.verification.task("failing-child", [sys.executable, "-c", "raise SystemExit(23)"])
        self.verification.task("dependent", [sys.executable, "-c",
                               "import pathlib,sys; pathlib.Path(sys.argv[1]).touch()", str(marker)],
                               requires=("failing-child",))
        self.assertEqual(self.verification.tasks[0]["exit_code"], 23)
        self.assertEqual(self.verification.tasks[1]["status"], "skipped")
        self.assertFalse(marker.exists())
        self.assertEqual(self.verification.finish(), 1)

    def test_exit_zero_without_fresh_report_is_failure(self):
        (self.directory / "old-success.json").write_text('{"passed":true}')
        fresh = self.directory / "this-run-report.json"
        self.verification.task("missing-report", [sys.executable, "-c", "pass"], artifacts=(fresh,))
        self.assertEqual(self.verification.tasks[0]["status"], "failed")
        self.assertIn("Expected artifact missing", self.verification.tasks[0]["reason"])
        self.assertEqual(self.verification.finish(), 1)

    def test_missing_executable_is_failure_not_empty_success(self):
        self.verification.task("missing-tool", ["moonice-nonexistent-test-tool", "--version"])
        self.assertEqual(self.verification.tasks[0]["status"], "failed")
        self.assertIsNone(self.verification.tasks[0]["exit_code"])
        self.assertEqual(self.verification.finish(), 1)
        summary = self.directory / "summary.json"
        report = json.loads(summary.read_text(encoding="utf-8"))
        self.assertEqual(report["status"], "failed")
        self.assertEqual(report["counts"]["failed"], 1)
        self.assertEqual(report["counts"]["passed"], 0)

    def test_release_requires_explicit_version(self):
        run = subprocess.run([sys.executable, str(verify.ROOT / "scripts/verify.py"), "--profile", "release"],
                             cwd=verify.ROOT, capture_output=True, text=True)
        self.assertEqual(run.returncode, 2)
        self.assertIn("explicit --version", run.stderr)

    def test_release_rejects_wrong_checkout_or_installed_identity(self):
        for label in ("Checkout", "Installed package"):
            for identity in ({"name": "other/package", "version": "0.3.0"},
                             {"name": verify_release.PACKAGE, "version": "0.2.1"}):
                with self.assertRaisesRegex(ValueError, "identity mismatch"):
                    verify_release.require_identity(identity, "0.3.0", label)
        verify_release.require_identity({"name": verify_release.PACKAGE, "version": "0.3.0"}, "0.3.0", "Installed package")

    def test_release_tag_must_match_requested_version(self):
        for tag in ("v0.2.1", "main", "0.3.0"):
            with self.assertRaisesRegex(ValueError, "does not match"):
                verify_release.require_release_tag(tag, "0.3.0")
        verify_release.require_release_tag("v0.3.0", "0.3.0")

    def test_release_tag_must_identify_checkout_commit(self):
        version = verify_release.module_identity(verify.ROOT / "moon.mod")["version"]
        with patch.dict("os.environ", {"RELEASE_TAG": "v" + version}), \
             patch.object(verify_release.subprocess, "check_output", side_effect=["head-commit\n", "other-commit\n"]):
            with self.assertRaisesRegex(ValueError, "checked-out commit"):
                verify_release.checkout_identity(version)

    def test_installed_manifest_identity_is_read_not_inferred(self):
        manifest = self.directory / "moon.mod"
        manifest.write_text('name = "Ridge-Lab/moonice"\nversion = "0.2.1"\n')
        actual = verify_release.module_identity(manifest)
        self.assertEqual(actual["version"], "0.2.1")
        with self.assertRaises(ValueError):
            verify_release.require_identity(actual, "0.3.0", "Installed package")
        manifest.write_text('name = "Ridge-Lab/moonice"\nversion = "0.3.0"\nversion = "0.2.1"\n')
        with self.assertRaises(ValueError):
            verify_release.module_identity(manifest)


if __name__ == "__main__":
    unittest.main()
