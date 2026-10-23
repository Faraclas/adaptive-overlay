#!/bin/bash
# Verify a staged D2 image and its retained, unstripped source-build binary.
set -euo pipefail

if [[ $# -ne 1 || ! -d $1 ]]; then
    echo "Usage: ${0##*/} <build-image-dir>" >&2
    exit 1
fi

exec python3 - "$1" <<'PY'
import hashlib
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


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
match = re.fullmatch(r"d2-(\d+\.\d+\.\d+)(?:-r\d+)?", package)
require(match, f"Cannot determine the expected version from {image.parent}")
version = match.group(1)
binary = image / "usr/bin/d2"
require(binary.is_file() and os.access(binary, os.X_OK),
        f"Staged executable missing: {binary}")
require(run([str(binary), "--version"]).strip() == f"v{version}",
        "Staged D2 version does not match the ebuild")
require(list((image / "usr/share/man/man1").glob("d2.1*")), "D2 man page missing")

notices = image / f"usr/share/doc/{package}/licenses"
for name in (f"d2-{version}-bundled-notices.txt",
             f"d2-{version}-runtime-notices.txt",
             f"d2-{version}-module-sources.txt", "d2/LICENSE.txt",
             "d2/THIRD_PARTY_NOTICES.txt",
             "d2/d2renderers/d2fonts/NOTICE.txt",
             "d2/d2renderers/d2fonts/NotoColorEmoji-OFL.txt",
             "d2/d2layouts/d2elklayout/NOTICE.txt"):
    require((notices / name).is_file(), f"Required notice missing: {name}")
require(list(notices.glob("go-mod/github.com/d2lang/mathjax-go@*/LICENSES/MIT-Luo-Studio.txt")),
        "Nested MathJax MIT notice missing")
require(list(notices.glob("go-mod/github.com/alecthomas/chroma/v2@*/COPYING")),
        "Chroma's complete code/font notice missing")
require(not (notices / "go-mod/cache").exists(), "Proxy cache installed as docs")

# Portage may strip the staged image. Inspect the actual pre-strip build,
# requiring positive Go-pdf symbol evidence so a stripped binary cannot pass.
unstripped = image.parent / f"work/d2-{version}/d2"
require(unstripped.is_file(), f"Retain the source-build binary: {unstripped}")
symbols = run(["go", "tool", "nm", str(unstripped)])
require("codeberg.org/go-pdf/fpdf." in symbols, "Go-pdf symbols unavailable")
for line in symbols.splitlines():
    require(not re.search(
        r"codeberg\.org/go-pdf/fpdf\..*"
        r"(?:Tickmarks|TickmarkPrecision|niceNum|GridType|linearTickmark|NewGrid)", line),
        f"Graphics Gems/Grid code survives linking; license review required: {line}")
info = run(["go", "version", "-m", str(unstripped)])
require("CGO_ENABLED=0" in info, "Build did not explicitly disable CGO")
print(f"==> Staged D2 v{version}: {binary}", flush=True)
print("==> Unstripped Go-pdf symbol check passed; no Graphics Gems/Grid routines", flush=True)

with tempfile.TemporaryDirectory(prefix="verify-d2-") as directory:
    work = Path(directory)
    env = {key: value for key, value in os.environ.items()
           if not key.startswith("D2_")}
    env.update(HOME=directory, PATH="/usr/bin:/bin")
    layouts = run([str(binary), "layout"], env=env, cwd=work)
    bundled = sorted(set(re.findall(r"^([\w-]+) \(bundled\) -", layouts, re.M)))
    require({"dagre", "elk"}.issubset(bundled),
            f"Required bundled layouts missing:\n{layouts}")
    print(f"==> Bundled layouts: {', '.join(bundled)}", flush=True)
    source = work / "smoke.d2"
    source.write_text("direction: right\nclient: Client\nserver: Server\n"
                      "client -> server: request\n", encoding="utf-8")
    for layout in bundled:
        for extension in ("svg", "png", "pdf"):
            output = work / f"{layout}.{extension}"
            run([str(binary), "--layout", layout, str(source), str(output)],
                env=env, cwd=work)
            data = output.read_bytes()
            require(len(data) > 100, f"Empty/truncated output: {output.name}")
            if extension == "svg":
                root = ET.fromstring(data)
                require(root.tag == "{http://www.w3.org/2000/svg}svg",
                        f"Invalid SVG root: {output.name}")
            elif extension == "png":
                require(data.startswith(b"\x89PNG\r\n\x1a\n")
                        and data[12:16] == b"IHDR", "Invalid PNG header")
                width, height = struct.unpack(">II", data[16:24])
                require(width > 0 and height > 0, "Invalid PNG dimensions")
            else:
                require(data.startswith(b"%PDF-") and b"%%EOF" in data[-1024:],
                        f"Invalid PDF: {output.name}")
            print(f"PASS {layout}/{extension}: {len(data)} bytes "
                  f"sha256={hashlib.sha256(data).hexdigest()}", flush=True)

print("D2 staged-image verification passed", flush=True)
PY
