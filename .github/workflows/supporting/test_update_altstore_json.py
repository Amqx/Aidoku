import copy
import hashlib
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import update_altstore_json as publisher


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.run = {
            "id": 42, "run_attempt": 1, "head_branch": "main",
            "head_repository": {"full_name": publisher.REPO},
            "head_sha": "a" * 40, "status": "completed", "conclusion": "success",
            "html_url": "https://github.com/Amqx/Aidoku/actions/runs/42",
        }

    def test_only_latest_success_is_eligible(self):
        self.assertTrue(publisher.eligible(self.run, {}))
        for status, conclusion in [("completed", "failure"), ("completed", "cancelled"),
                                   ("in_progress", None), ("queued", None)]:
            with self.subTest(status=status, conclusion=conclusion):
                self.assertFalse(publisher.eligible(dict(self.run, status=status, conclusion=conclusion), {}))
        self.assertFalse(publisher.eligible(None, {}))
        self.assertFalse(publisher.eligible(dict(self.run, head_branch="feature"), {}))
        self.assertFalse(publisher.eligible(
            dict(self.run, head_repository={"full_name": "Aidoku/Aidoku"}), {}))

    def test_stale_event_and_rerun_are_skipped(self):
        for changes in [{"id": 41}, {"run_attempt": 2}]:
            self.assertFalse(publisher.eligible(self.run, {"workflow_run": dict(self.run, **changes)}))
        self.assertTrue(publisher.eligible(self.run, {"workflow_run": self.run}))

    def test_latest_query_does_not_filter_out_failed_runs(self):
        with patch.object(publisher, "api", return_value={"workflow_runs": [self.run]}) as api:
            self.assertEqual(publisher.latest_run(), self.run)
            self.assertEqual(api.call_args.args[0], "actions/workflows/build.yaml/runs?branch=main&per_page=1")

    def test_release_must_match_successful_commit(self):
        with patch.object(publisher, "api", return_value={"object": {"type": "commit", "sha": "b" * 40}}):
            with self.assertRaisesRegex(ValueError, "does not match"):
                publisher.release_asset(self.run)

    def test_manifest_uses_ipa_metadata_and_rejects_bad_downloads(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / "test.ipa"
            info = {
                "CFBundleIdentifier": publisher.BUNDLE_ID,
                "CFBundleShortVersionString": "0.9", "CFBundleVersion": "42.1",
                "MinimumOSVersion": "15.0", "NSFaceIDUsageDescription": "Use Face ID",
            }
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/Aidoku.app/Info.plist", plistlib.dumps(info))
                archive.writestr("Payload/Aidoku.app/Frameworks/Other.framework/Info.plist", b"ignored")
            asset = {
                "size": ipa.stat().st_size,
                "digest": "sha256:" + hashlib.sha256(ipa.read_bytes()).hexdigest(),
                "updated_at": "2026-09-14T01:00:00Z",
                "browser_download_url": "https://github.com/Amqx/Aidoku/releases/download/nightly/Aidoku-nightly.ipa",
            }
            app = publisher.make_manifest(ipa, self.run, asset)["apps"][0]
            self.assertEqual(len(app["versions"]), 1)
            version = app["versions"][0]
            self.assertEqual((version["version"], version["buildVersion"]), ("0.9", "42.1"))
            self.assertEqual(version["size"], ipa.stat().st_size)
            self.assertEqual(version["date"], asset["updated_at"])
            self.assertEqual(app["appPermissions"]["privacy"], {"NSFaceIDUsageDescription": "Use Face ID"})
            with self.assertRaisesRegex(ValueError, "size"):
                publisher.make_manifest(ipa, self.run, dict(asset, size=0))
            with self.assertRaisesRegex(ValueError, "digest"):
                publisher.make_manifest(ipa, self.run, dict(asset, digest="sha256:bad"))
            with patch.object(publisher, "BUNDLE_ID", "wrong.bundle"):
                with self.assertRaisesRegex(ValueError, "bundle identifier"):
                    publisher.make_manifest(ipa, self.run, asset)

    def test_publication_rechecks_latest_run_and_asset(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "altstore").mkdir()
            manifest = root / "altstore/apps.json"
            manifest.write_text("original")
            event = root / "event.json"
            event.write_text("{}")
            output = root / "output"
            asset = {"name": "Aidoku-nightly.ipa"}
            for scenario in ["success", "newer", "failed", "changed_asset"]:
                with self.subTest(scenario=scenario):
                    manifest.write_text("original")
                    output.write_text("")
                    current = copy.deepcopy(self.run)
                    if scenario == "newer":
                        current["id"] += 1
                    if scenario == "failed":
                        current["conclusion"] = "failure"
                    assets = [asset, dict(asset, size=1) if scenario == "changed_asset" else asset]
                    with patch.dict(os.environ, GITHUB_EVENT_PATH=str(event), GITHUB_OUTPUT=str(output)), \
                            patch.object(publisher, "ROOT", root), \
                            patch.object(publisher, "latest_run", side_effect=[self.run, current]), \
                            patch.object(publisher, "release_asset", side_effect=assets), \
                            patch.object(publisher.subprocess, "run"), \
                            patch.object(publisher, "make_manifest", return_value={"apps": []}):
                        if scenario == "changed_asset":
                            with self.assertRaisesRegex(ValueError, "changed"):
                                publisher.main()
                        else:
                            publisher.main()
                    if scenario == "success":
                        self.assertEqual(json.loads(manifest.read_text()), {"apps": []})
                        self.assertEqual(output.read_text(), "publish=true\n")
                    else:
                        self.assertEqual(manifest.read_text(), "original")
                        self.assertEqual(output.read_text(), "")


if __name__ == "__main__":
    unittest.main()
