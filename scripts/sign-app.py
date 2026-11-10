#!/usr/bin/env python3
"""Sign local builds with one persistent project certificate, without root trust."""
import hashlib
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / ".signing"
os.umask(0o077)
STORE.mkdir(mode=0o700, exist_ok=True)
KEYCHAIN = STORE / "QingXing.keychain-db"
PASSWORD = STORE / "keychain-password"
FINGERPRINT = STORE / "identity-sha1"
secret = PASSWORD.read_text() if PASSWORD.exists() else secrets.token_urlsafe(32)


def run(*arguments):
    result = subprocess.run(arguments, capture_output=True)
    if result.returncode:
        message = result.stderr.decode(errors="replace").replace(secret, "[redacted]")
        raise RuntimeError(f"{Path(arguments[0]).name}: {message.strip()}")
    return result.stdout


def search_list():
    return shlex.split(run("security", "list-keychains", "-d", "user").decode())


def unregister():
    current = search_list()
    retained = [path for path in current if Path(path) != KEYCHAIN]
    if retained != current:
        run("security", "list-keychains", "-d", "user", "-s", *retained)


try:
    if not FINGERPRINT.exists():
        if KEYCHAIN.exists():
            raise RuntimeError("Incomplete .signing initialization; inspect before retrying.")
        PASSWORD.write_text(secret)
        config = STORE / "certificate.cnf"
        config.write_text("""[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = QingXing Local Development
O = QingXing Local
[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
""")
        key, certificate, archive = (STORE / name for name in ("private-key.pem", "certificate.pem", "identity.p12"))
        run("/usr/bin/openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes", "-x509", "-days", "3650",
            "-sha256", "-config", str(config), "-keyout", str(key), "-out", str(certificate))
        run("/usr/bin/openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(certificate),
            "-out", str(archive), "-passout", "file:" + str(PASSWORD))
        run("security", "create-keychain", "-p", secret, str(KEYCHAIN))
        run("security", "unlock-keychain", "-p", secret, str(KEYCHAIN))
        run("security", "import", str(archive), "-k", str(KEYCHAIN), "-P", secret, "-T", "/usr/bin/codesign")
        run("security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", secret, str(KEYCHAIN))
        der = run("/usr/bin/openssl", "x509", "-in", str(certificate), "-outform", "DER")
        FINGERPRINT.write_text(hashlib.sha1(der).hexdigest().upper())

    current = search_list()
    if str(KEYCHAIN) not in current:
        run("security", "list-keychains", "-d", "user", "-s", *current, str(KEYCHAIN))
    fingerprint = FINGERPRINT.read_text().strip()
    if len(fingerprint) != 40 or any(char not in "0123456789ABCDEF" for char in fingerprint):
        raise RuntimeError("Invalid signing fingerprint")
    requirement = f'=designated => identifier "local.qingxing.Heathy" and certificate leaf = H"{fingerprint}"'
    run("security", "unlock-keychain", "-p", secret, str(KEYCHAIN))
    run("codesign", "--force", "--sign", fingerprint, "--keychain", str(KEYCHAIN), "--timestamp=none",
        "--requirements", requirement, "--entitlements", str(ROOT / "Resources/Heathy.entitlements"), sys.argv[1])
    run("codesign", "--verify", "--strict", sys.argv[1])
    print("PASS: signed with the persistent project certificate; no system trust or TCC changes")
except (OSError, RuntimeError, IndexError) as error:
    print(str(error).replace(secret, "[redacted]"), file=sys.stderr)
    sys.exit(1)
finally:
    try:
        for name in ("private-key.pem", "identity.p12"):
            (STORE / name).unlink(missing_ok=True)
    finally:
        unregister()
