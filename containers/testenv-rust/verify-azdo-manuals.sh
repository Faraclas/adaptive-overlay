#!/bin/bash
# Verify a staged azdo-manuals image: binary, version, no libssl, docs.
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
match = re.fullmatch(r"azdo-manuals-(\d+\.\d+\.\d+)(?:-r\d+)?", package)
require(match, f"Cannot determine the expected version from {image.parent}")
version = match.group(1)

binary = image / "usr/bin/azdo-manuals"
require(binary.is_file() and os.access(binary, os.X_OK),
        f"Staged executable missing: {binary}")

ver_out = run([str(binary), "--version"]).strip()
require(ver_out == f"azdo-manuals {version}",
        f"Unexpected azdo-manuals --version output: {ver_out!r} (expected 'azdo-manuals {version}')")

ldd_out = run(["ldd", str(binary)])
require("libssl" not in ldd_out and "libcrypto" not in ldd_out,
        f"Unexpected OpenSSL linkage in azdo-manuals:\n{ldd_out}")

doc_dir = image / f"usr/share/doc/{package}"
require(any(doc_dir.glob("README.md*")), f"Missing README.md in {doc_dir}")

print(f"azdo-manuals {version} verification passed")
PY
