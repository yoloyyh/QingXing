#!/usr/bin/env python3
"""Prove that a changed local build still satisfies the previous code identity."""
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1]).resolve()


def run(*arguments):
    result = subprocess.run(arguments, text=True, capture_output=True, check=True)
    return result.stdout + result.stderr


def identity(bundle):
    output = run("codesign", "-d", "-r-", "--verbose=4", str(bundle))
    requirement = re.search(r"^designated => (.+)$", output, re.M)
    digest = re.search(r"^CDHash=(.+)$", output, re.M)
    assert requirement and digest, "Expected a certificate-backed designated requirement"
    assert 'certificate leaf = H"' in requirement.group(1)
    assert "cdhash" not in requirement.group(1)
    return requirement.group(1), digest.group(1)


before, old_hash = identity(app)
with tempfile.TemporaryDirectory(prefix="signature-update-", dir=ROOT / ".build") as folder:
    updated = Path(folder) / "QingXing.app"
    shutil.copytree(app, updated)
    info_path = updated / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["CFBundleVersion"] = str(int(info["CFBundleVersion"]) + 1)
    info_path.write_bytes(plistlib.dumps(info))
    print(run(sys.executable, str(ROOT / "scripts/sign-app.py"), str(updated)).strip())
    after, new_hash = identity(updated)
    assert new_hash != old_hash, "The update must change its code hash"
    assert after == before, "An update must retain the same designated requirement"
    run("codesign", "--verify", "--strict", "-R", "=" + before, str(updated))
print("PASS: changed build hash, identical certificate identity, previous requirement accepts the update")
