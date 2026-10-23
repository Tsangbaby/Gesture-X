"""Build-policy contracts. Workflow uses JSON syntax, which is valid YAML."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class CloudBuildContracts(unittest.TestCase):
    def workflow(self):
        path = ROOT / ".github/workflows/build.yml"
        self.assertTrue(path.is_file(), "Missing cloud build workflow")
        return json.loads(path.read_text())

    def test_one_standard_mac_job_for_roothide_only(self):
        workflow = self.workflow()
        self.assertEqual(workflow["on"]["push"]["branches"], ["main"])
        self.assertIn("workflow_dispatch", workflow["on"])
        self.assertEqual(workflow["permissions"], {"contents": "read"})
        self.assertEqual(set(workflow["jobs"]), {"roothide"})
        job = workflow["jobs"]["roothide"]
        self.assertEqual(job["runs-on"], "macos-15")
        self.assertEqual(job["env"]["THEOS_PACKAGE_SCHEME"], "roothide")
        self.assertNotIn("matrix", job.get("strategy", {}))
        self.assertLessEqual(job["timeout-minutes"], 35)
        for value in job["env"].values():
            self.assertNotIn("${{ runner.", value)

    def test_dependencies_are_pinned_and_artifact_has_exact_sha_name(self):
        job = self.workflow()["jobs"]["roothide"]
        for key in ("THEOS_REF", "SDK_REF"):
            self.assertRegex(job["env"][key], r"^[a-f0-9]{40}$")
        actions = [step for step in job["steps"] if "uses" in step]
        for action in actions:
            self.assertRegex(action["uses"], r"@[a-f0-9]{40}$")
        upload = [s for s in actions if s["uses"].startswith("actions/upload-artifact@")]
        self.assertEqual(len(upload), 1)
        self.assertEqual(upload[0]["with"]["name"], "taplock-roothide-${{ github.sha }}")
        self.assertEqual(upload[0]["with"]["if-no-files-found"], "error")
        self.assertIn("roothide/theos.git", json.dumps(job["steps"]))

    def test_actual_swift_runtime_gate_precedes_target_build_and_package(self):
        job = self.workflow()["jobs"]["roothide"]
        steps = job["steps"]
        names = [step["name"] for step in steps if "name" in step]
        self.assertLess(names.index("Source and real Swift runtime tests"),
                        names.index("Compile and package RootHide"))
        runtime = next(s["run"] for s in steps if s.get("name") == "Source and real Swift runtime tests")
        self.assertIn("Sources/PrivateAPI.swift", runtime)
        self.assertIn("Tests/PrivateAPIRuntimeTests.swift", runtime)
        self.assertIn('"$RUNNER_TEMP/private-api-tests"', runtime)
        path = ROOT / "ci/build.sh"
        self.assertTrue(path.is_file(), "Missing actual build script")
        script = path.read_text()
        self.assertLess(script.index("make all"), script.index("make package"))
        self.assertIn("THEOS_PACKAGE_SCHEME=roothide", script)
        self.assertIn("ARCHS=arm64 arm64e", script)
        self.assertIn("FINALPACKAGE=1", script)
        self.assertIn("verify_package.py", script)
        self.assertIn("SOURCE_COMMIT.txt", script)
        self.assertIn("SOURCE_REPOSITORY.txt", script)
        self.assertNotRegex(script, r"make\s+install|TARGET_CODESIGN=|gh\s+release")

    def test_package_verifier_covers_settings_and_minimum_os(self):
        path = ROOT / "ci/verify_package.py"
        self.assertTrue(path.is_file(), "Missing package verifier")
        text = path.read_text()
        for token in ("iphoneos-arm64e", "TapLock.dylib", "TapLockPrefs.bundle",
                      "PreferenceLoader/Preferences/TapLock.plist", "NSPrincipalClass",
                      "CFBundleIdentifier", "0x32", "0x25", "0x000F0000",
                      "0x1D", "0xFADE0CC0", "plistlib.loads", "SHA256SUMS.txt"):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
