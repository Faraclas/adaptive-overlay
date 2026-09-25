#!/bin/bash
# verify-hermes-agent.sh: check the app-ai/hermes-agent build image.
# Called by scripts/test-build.sh with the portage image directory, e.g.
#   /var/tmp/portage/app-ai/hermes-agent-2026.9.24-r3/image
set -u
IMAGE="${1:?usage: verify-hermes-agent.sh <build-image-dir>}"
PASS=0 FAIL=0
pass() { echo "  ok   $*"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL $*" >&2; FAIL=$((FAIL + 1)); }

SITE=$(find "$IMAGE/usr/lib" -maxdepth 3 -type d -name site-packages | head -1)
echo "==> Verifying hermes-agent image: $IMAGE"
echo "    site-packages: ${SITE:-<not found>}"
[ -n "$SITE" ] || { echo "no site-packages in image" >&2; exit 1; }
CU="$SITE/tools/computer_use"

echo "--- Patched sources ---"
check() { # file, fixed-string, label
    if grep -qF -- "$2" "$1" 2>/dev/null; then pass "$3"; else fail "$3"; fi
}
check "$SITE/tools/lazy_deps.py" "allow_lazy_installs" \
    "lazy_deps: pins-as-floors patch"
check "$CU/cua_backend_session.py" 'name == "MCPError"' \
    "computer_use: MCPError(CONNECTION_CLOSED) reconnect"
check "$CU/tool.py" 'if action == "release":' \
    "computer_use: release action handler"
check "$CU/schema.py" '"release",' \
    "computer_use: release in the tool schema"

echo "--- Imports (image on sys.path) ---"
if PYTHONPATH="$SITE" python3 -c '
import tools.computer_use.schema as s
assert "release" in s.COMPUTER_USE_SCHEMA["parameters"]["properties"]["action"]["enum"]
from tools.computer_use.cua_backend_session import _CuaDriverSession as S
from mcp.shared.exceptions import MCPError
from mcp.types import CONNECTION_CLOSED
assert S._is_closed_session_error(MCPError(code=CONNECTION_CLOSED, message="x"))
assert not S._is_closed_session_error(MCPError(code=-32602, message="x"))
' 2>&1; then
    pass "schema has release; CONNECTION_CLOSED is treated as closed"
else
    fail "import-level checks"
fi

echo ""
echo "==> $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
