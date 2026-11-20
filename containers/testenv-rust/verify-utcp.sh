#!/bin/bash
# Verify a staged utcp image: binary, version, no libssl, SKILL.md, systemd unit.
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
match = re.fullmatch(r"utcp-(\d+\.\d+\.\d+)(?:-r\d+)?", package)
require(match, f"Cannot determine the expected version from {image.parent}")
version = match.group(1)

binary = image / "usr/bin/utcp"
require(binary.is_file() and os.access(binary, os.X_OK),
        f"Staged executable missing: {binary}")

ver_out = run([str(binary), "--version"]).strip()
require(ver_out == f"utcp {version}",
        f"Unexpected utcp --version output: {ver_out!r} (expected 'utcp {version}')")

ldd_out = run(["ldd", str(binary)])
require("libssl" not in ldd_out and "libcrypto" not in ldd_out,
        f"Unexpected OpenSSL linkage in utcp:\n{ldd_out}")

skill = image / "usr/share/utcp/SKILL.md"
require(skill.is_file(), f"Missing rendered skill: {skill}")
skill_lines = skill.read_text().splitlines()
require(len(skill_lines) >= 2 and skill_lines[0] == "---"
        and any("name: utcp-tools" in line for line in skill_lines[:10]),
        f"Unexpected SKILL.md header:\n{skill_lines[:5]}")

unit = image / "usr/lib/systemd/user/utcp-daemon.service"
require(unit.is_file(), f"Missing systemd user unit: {unit}")

print(f"utcp {version} verification passed")
PY
