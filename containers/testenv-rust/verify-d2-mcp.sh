#!/bin/bash
# Verify a staged media-gfx/d2-mcp image against the installed runtime D2.
# Run in the test container with the Portage image directory as argument.
set -euo pipefail

if [[ $# -ne 1 || ! -d $1 ]]; then
    echo "Usage: ${0##*/} <build-image-dir>" >&2
    exit 1
fi

exec python3 - "$1" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


image = Path(sys.argv[1]).resolve(strict=True)
binary = image / "usr/bin/d2-mcp"
d2 = Path("/usr/bin/d2")
require(binary.is_file() and os.access(binary, os.X_OK),
        f"Staged executable missing: {binary}")
require(d2.is_file() and os.access(d2, os.X_OK),
        "Install the runtime media-gfx/d2 first; /usr/bin/d2 is required")
version = subprocess.run([str(d2), "--version"], check=True,
                         capture_output=True, text=True, timeout=10).stdout.strip()
require(version, "Installed D2 returned no version")
print(f"==> Staged MCP: {binary}\n==> Installed D2: {d2} ({version})", flush=True)
expected = re.fullmatch(r"d2-mcp-(\d+\.\d+\.\d+)(?:-r\d+)?", image.parent.name)

with tempfile.TemporaryDirectory(prefix="verify-d2-mcp-") as workdir, \
        tempfile.TemporaryFile() as errors, selectors.DefaultSelector() as selector:
    # Do not let caller overrides select a different renderer or output tree.
    env = {key: value for key, value in os.environ.items()
           if not key.startswith("D2_MCP_")}
    env.update(D2_MCP_D2_BIN=str(d2), D2_MCP_WORKDIR=workdir)
    proc = subprocess.Popen([str(binary)], cwd=workdir, env=env,
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=errors, bufsize=0, start_new_session=True)
    selector.register(proc.stdout, selectors.EVENT_READ)
    pending = bytearray()
    request_id = 0

    def send(message):
        proc.stdin.write((json.dumps(message) + "\n").encode())
        proc.stdin.flush()

    def request(method, params=None, timeout=15):
        global request_id
        request_id += 1
        message = {"jsonrpc": "2.0", "id": request_id, "method": method}
        if params is not None:
            message["params"] = params
        send(message)
        deadline = time.monotonic() + timeout
        # rmcp's async-rw stdio codec uses newline-delimited JSON, not LSP
        # Content-Length headers. Read bytes to avoid buffered-reader stalls.
        while True:
            require(time.monotonic() < deadline, f"Timed out: {method}")
            if b"\n" not in pending:
                require(selector.select(max(0, deadline - time.monotonic())),
                        f"Timed out: {method}")
                data = os.read(proc.stdout.fileno(), 65536)
                require(data, f"MCP closed stdout during {method}")
                pending.extend(data)
                require(len(pending) <= 1024 * 1024, "Oversized MCP message")
                continue
            line, _, rest = pending.partition(b"\n")
            pending[:] = rest
            reply = json.loads(line)
            require(reply.get("jsonrpc") == "2.0", f"Invalid JSON-RPC: {reply}")
            if "id" not in reply:
                continue
            require(reply["id"] == request_id, f"Unexpected response: {reply}")
            require("error" not in reply, f"{method}: {reply.get('error')}")
            return reply["result"]

    def tool(name, arguments=None, timeout=15):
        result = request("tools/call", {"name": name, "arguments": arguments or {}},
                         timeout=timeout)
        require(not result.get("isError", False), f"{name}: {result}")
        require(isinstance(result.get("structuredContent"), dict),
                f"{name} returned no structuredContent")
        return result["structuredContent"]

    try:
        info = request("initialize", {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "adaptive-overlay-verify", "version": "1"},
        })
        server = info["serverInfo"]
        require(server["name"] == "d2-mcp" and server.get("version"),
                f"Unexpected server: {server}")
        if expected:
            require(server["version"] == expected[1], f"Wrong MCP version: {server}")
        require(info.get("protocolVersion"), "Missing negotiated protocol version")
        require("tools" in info.get("capabilities", {}), "Missing tools capability")
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        print(f"  ok initialize: d2-mcp {server['version']}", flush=True)

        tools = request("tools/list")["tools"]
        names = {entry["name"] for entry in tools}
        require(names == {"d2_status", "d2_layouts", "d2_themes", "d2_validate",
                          "d2_format", "d2_render"}, f"Unexpected tools: {names}")
        print("  ok tools/list: six upstream tools", flush=True)

        status = tool("d2_status")
        require(status["status"] == "ready" and status["d2_binary"] == str(d2),
                f"Installed D2 not ready: {status}")
        require(status["d2_version"] == version, f"D2 version mismatch: {status}")
        require(set(status["supported_output_formats"]) == {"svg", "png"},
                f"Unexpected output formats: {status}")
        print("  ok d2_status: installed renderer, SVG and PNG", flush=True)

        for fmt in ("svg", "png"):
            filename = f"smoke.{fmt}"
            report = tool("d2_render", {
                "source": "client -> mcp -> d2", "format": fmt,
                "output_path": filename, "layout": "dagre",
                "inline_svg": fmt == "svg", "timeout_seconds": 20,
            }, timeout=45)
            require(report["status"] == "rendered" and report["format"] == fmt
                    and report["output_path"] == filename,
                    f"Unexpected render report: {report}")
            artifact = (Path(workdir) / filename).read_bytes()
            require(artifact and len(artifact) == report["output_bytes"],
                    f"Empty or truncated {fmt} artifact")
            require(hashlib.sha256(artifact).hexdigest() == report["output_sha256"],
                    f"{fmt} hash mismatch")
            if fmt == "svg":
                require(ET.fromstring(artifact).tag == "{http://www.w3.org/2000/svg}svg",
                        "Invalid SVG document")
                require(report.get("inline_svg") == artifact.decode(),
                        "Inline SVG differs from the output file")
            else:
                require(artifact.startswith(b"\x89PNG\r\n\x1a\n"), "Invalid PNG signature")
            print(f"  ok d2_render: {fmt.upper()} ({len(artifact)} bytes)", flush=True)

        proc.stdin.close()
        require(proc.wait(timeout=5) == 0, "MCP exited unsuccessfully")
    except Exception:
        errors.seek(0)
        print(errors.read(32768).decode(errors="replace"), file=sys.stderr)
        raise
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=5)

print("==> d2-mcp stdio SVG/PNG smoke test passed")
PY
