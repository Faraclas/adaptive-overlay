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
check "$CU/cua_backend_daemon.py" 'def ensure_alive' \
    "computer_use: private daemon revive on reconnect"

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

echo "--- Copilot PAT discovery (synthetic credentials, no network) ---"
if PYTHONPATH="$SITE" python3 -c '
from unittest.mock import patch
from hermes_cli import models, copilot_auth
from hermes_cli.models_validate import validate_requested_model
from agent.secret_scope import set_secret_scope, reset_secret_scope

for key, integration in [("github_pat_fixture", "copilot-developer-cli"),
                         ("exchanged_oauth_fixture", "vscode-chat")]:
    seen = []
    def endpoint(url, *, timeout, headers):
        assert headers["Authorization"] == "Bearer " + key
        assert headers["Copilot-Integration-Id"] == integration
        seen.append(True)
        return {"data": [{"id": "fixture-new-model"}]}
    with patch.object(models, "_github_model_catalog_cache", None), \
         patch.object(models, "_get_json", endpoint), \
         patch.object(models, "provider_model_ids", return_value=[]):
        result = validate_requested_model("fixture-new-model", "copilot",
            api_key=key, base_url=models.COPILOT_BASE_URL)
        assert result["recognized"] and not result["message"]
        assert len(seen) == 1

for name in ("a", "b", "a"):
    token = "github_pat_profile_" + name
    bound = set_secret_scope({"COPILOT_GITHUB_TOKEN": token},
                             profile_home="/nonexistent-fixture/" + name)
    try:
        assert copilot_auth.resolve_copilot_token() == (token, "COPILOT_GITHUB_TOKEN")
    finally:
        reset_secret_scope(bound)
bound = set_secret_scope({}, profile_home="/nonexistent-fixture/missing")
try:
    with patch.object(copilot_auth, "_try_gh_cli_token") as host_login:
        assert copilot_auth.resolve_copilot_token() == ("", "")
        host_login.assert_not_called()
finally:
    reset_secret_scope(bound)
' 2>&1; then
    pass "PAT/OAuth catalogs validate; profile tokens isolated; host fallback blocked"
else
    fail "Copilot PAT discovery behavioral checks"
fi

echo "--- Copilot image request headers (synthetic credentials, no network) ---"
REGRESSION="$(dirname "${BASH_SOURCE[0]}")/../../app-ai/hermes-agent/files/test_copilot_image_headers.py"
if env -i PATH="$PATH" PYTHONPATH="$SITE" HOME=/nonexistent-fixture/images \
    HERMES_HOME=/nonexistent-fixture/images python3 -c '
import runpy
import sys
from pathlib import Path
import agent.client_lifecycle as lifecycle
# Reject accidentally testing host/source modules instead of the built image.
assert Path(lifecycle.__file__).resolve().is_relative_to(Path(sys.argv[1]).resolve())
test = sys.argv[2]
sys.argv = [test, "-v"]
runpy.run_path(test, run_name="__main__")
' "$SITE" "$REGRESSION" 2>&1; then
    pass "image headers: Chat/Responses, casing, mandatory vision, OAuth, isolation, cache reuse"
else
    fail "Copilot image header behavioral checks"
fi

echo ""
echo "==> $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
