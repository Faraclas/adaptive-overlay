#!/bin/bash
# Verify a staged gitleaks image: binary, version output, git scan, and licenses.
set -euo pipefail

if [[ $# -ne 1 || ! -d $1 ]]; then
    echo "Usage: ${0##*/} <build-image-dir>" >&2
    exit 1
fi

exec python3 - "$1" <<'PY'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True,
                            timeout=60, **kwargs)
    require(result.returncode == 0,
            f"Command failed: {args}\n{result.stdout}\n{result.stderr}")
    return result.stdout


image = Path(sys.argv[1]).resolve(strict=True)
package = image.parent.name
match = re.fullmatch(r"gitleaks-(\d+\.\d+\.\d+)(?:-r\d+)?", package)
require(match, f"Cannot determine the expected version from {image.parent}")
version = match.group(1)

binary = image / "usr/bin/gitleaks"
require(binary.is_file() and os.access(binary, os.X_OK),
        f"Staged executable missing: {binary}")

ver_out = run([str(binary), "version"]).strip()
require(ver_out == version or ver_out == f"v{version}",
        f"Unexpected gitleaks version output: {ver_out!r} (expected {version!r})")

notices = image / f"usr/share/doc/{package}/licenses"
require((notices / "gitleaks/LICENSE").is_file(), "gitleaks LICENSE missing")
require(any((notices / "go-mod").rglob("*")), "go-mod license notices missing")
require(not (notices / "go-mod/cache").exists(), "Proxy cache installed as docs")

with tempfile.TemporaryDirectory() as tmp:
    repo = Path(tmp) / "repo"
    repo.mkdir()
    run(["git", "-C", str(repo), "init", "-q"])
    run(["git", "-C", str(repo), "config", "user.name", "Test"])
    run(["git", "-C", str(repo), "config", "user.email", "test@example.com"])
    (repo / "README.md").write_text("hello world\n")
    run(["git", "-C", str(repo), "add", "README.md"])
    run(["git", "-C", str(repo), "commit", "-q", "-m", "init"])
    run([str(binary), "git", "--no-banner", str(repo)])

print(f"gitleaks {ver_out} verification passed")
PY
