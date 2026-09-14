"""Publish only the newest main-branch Build Nightly run, after it succeeds."""

import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile


ROOT = Path(__file__).parent
REPO = "Amqx/Aidoku"
BUNDLE_ID = "org.ry-st.Aidoku"


def api(path):
    return json.loads(subprocess.check_output(
        ["gh", "api", f"repos/{REPO}/{path}"], text=True
    ))


def latest_run():
    # Do not filter by success: a newer failed or running build must block updates.
    runs = api("actions/workflows/build.yaml/runs?branch=main&per_page=1")["workflow_runs"]
    return runs[0] if runs else None


def eligible(run, event):
    if not run or run["status"] != "completed" or run["conclusion"] != "success":
        return False
    if run["head_branch"] != "main" or run["head_repository"]["full_name"] != REPO:
        return False
    trigger = event.get("workflow_run")
    return trigger is None or (run["id"], run["run_attempt"]) == (
        trigger["id"], trigger["run_attempt"]
    )


def release_asset(run):
    tag = api("git/ref/tags/nightly")["object"]
    if tag["type"] != "commit" or tag["sha"] != run["head_sha"]:
        raise ValueError("Nightly tag does not match the successful build")
    release = api("releases/tags/nightly")
    if release["draft"]:
        raise ValueError("Nightly release is a draft")
    assets = [asset for asset in release["assets"] if asset["name"] == "Aidoku-nightly.ipa"]
    if len(assets) != 1 or assets[0]["state"] != "uploaded":
        raise ValueError("Expected one uploaded nightly IPA")
    return assets[0]


def make_manifest(ipa_path, run, asset):
    if ipa_path.stat().st_size != asset["size"]:
        raise ValueError("Downloaded IPA size does not match the release asset")
    digest = asset.get("digest")
    if digest and digest != "sha256:" + hashlib.sha256(ipa_path.read_bytes()).hexdigest():
        raise ValueError("Downloaded IPA digest does not match the release asset")
    with zipfile.ZipFile(ipa_path) as ipa:
        paths = [name for name in ipa.namelist() if name.startswith("Payload/")
                 and name.count("/") == 2 and name.endswith(".app/Info.plist")]
        if len(paths) != 1:
            raise ValueError("Expected one app Info.plist in the IPA")
        info = plistlib.loads(ipa.read(paths[0]))
    if info["CFBundleIdentifier"] != BUNDLE_ID:
        raise ValueError("IPA is not the fork's bundle identifier")

    data = json.loads((ROOT / "altstore/apps.json").read_text())
    app = data["apps"][0]
    app["appPermissions"]["privacy"] = {
        key: value for key, value in info.items() if key.startswith("NS") and key.endswith("UsageDescription")
    }
    # The nightly URL is replaced on every build, so retain only the current version.
    app["versions"] = [{
        "version": info["CFBundleShortVersionString"],
        "buildVersion": info["CFBundleVersion"],
        "date": asset["updated_at"],
        "localizedDescription": f"Nightly build from commit {run['head_sha'][:7]}.\n{run['html_url']}",
        "downloadURL": asset["browser_download_url"],
        "size": asset["size"],
        "minOSVersion": info["MinimumOSVersion"],
    }]
    return data


def main():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    run = latest_run()
    if not eligible(run, event):
        print("Skipping: the latest nightly has not succeeded, or this event is stale.")
        return
    asset = release_asset(run)
    with tempfile.TemporaryDirectory() as directory:
        subprocess.run([
            "gh", "release", "download", "nightly", "--repo", REPO,
            "--pattern", asset["name"], "--dir", directory,
        ], check=True)
        data = make_manifest(Path(directory) / asset["name"], run, asset)

    # Recheck after downloading so a superseding build cannot publish stale metadata.
    current = latest_run()
    if not eligible(current, {"workflow_run": run}):
        print("Skipping: a newer nightly build started during generation.")
        return
    if release_asset(current) != asset:
        raise ValueError("Nightly release changed during generation")
    (ROOT / "altstore/apps.json").write_text(json.dumps(data, indent=2) + "\n")
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write("publish=true\n")


if __name__ == "__main__":
    main()
