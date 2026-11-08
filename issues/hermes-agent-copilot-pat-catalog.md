# hermes-agent: Copilot PAT model catalog fails; scoped token not found

- Package: `app-ai/hermes-agent`
- Patch: `files/hermes-agent-copilot-plugin-pat-integration-id.patch`
  (against the github-copilot plugin, used by 0.22.7 and 0.23.0 with
  USE=copilot). The core patch (`hermes-agent-copilot-pat-discovery.patch`)
  went with the 0.22.5 ebuild (removed 2026-11-08).
- Upstream: PRs https://github.com/NousResearch/hermes-agent/pull/51411
  and https://github.com/NousResearch/hermes-agent/pull/32723 (both closed
  unmerged 2026-10-26); bug 1:
  https://github.com/NousResearch/hermes-labs-plugins/issues/63, fix PR
  https://github.com/NousResearch/hermes-labs-plugins/pull/69 (opened
  2026-11-08 by a third party)
- Status: open (checked 2026-11-08: #63 and #69 open; v0.23.0's
  `plugin-catalog/github-copilot.yaml` still pins `346cfe9`, plugin `main`
  has one newer `github-copilot/` commit, `2ce59cf`, raw pool tokens for
  the catalog)
- Drop when: the plugin sha core's `plugin-catalog/github-copilot.yaml`
  pins sends a PAT-compatible integration id.

## Problem

Two bugs with a fine-grained Copilot PAT (`github_pat_*`):

1. The model catalog request (`fetch_github_model_catalog`) sends
   `Copilot-Integration-Id: vscode-chat`, which GitHub rejects with HTTP
   400 for PATs, so new models are reported as unknown.
2. `resolve_copilot_token()` reads the token with `os.getenv` instead of
   the profile-scoped secret store (`get_secret`), and a routed profile
   can fall back to the host's `gh auth token` (the wrong account).

## Upstream

- #51411 (catalog and inference identity, PAT transport) and #32723
  (secret-store token discovery) were closed unmerged on 2026-10-26.
  Copilot left core in
  https://github.com/NousResearch/hermes-agent/pull/144788 (merge
  `0591b66`, after v0.22.5) and is now the `github-copilot` plugin in
  https://github.com/NousResearch/hermes-labs-plugins ("built by Nous, not
  supported"). The maintainer invited #51411's author to send the identity
  work there.
- Plugin state at `346cfe9`:
  - Bug 2 fixed: `credentials.resolve_copilot_token` reads `get_secret`.
  - Bug 1 still present: `copilot_request_headers()` hardcodes
    `vscode-chat`; `catalog.py` `fetch_github_model_catalog` uses it.
- Fix idea for the plugin: pick `copilot-developer-cli` when the token
  starts with `github_pat_`, in `fetch_github_model_catalog` and in the
  `client_headers(api_key=..., has_images=...)` hook. Covers
  `hermes-agent-copilot-image-headers.md` too. That the raw PAT reaches
  `client_headers` is inferred, not verified.
- Plan (2026-10-26): do not file yet. The bug 1 finding comes from
  reading plugin source, not from running it. Re-test with the first
  packaged Hermes release that includes #144788 and the plugin; file on
  hermes-labs-plugins only if a PAT catalog or image request still fails.
  Re-tested 2026-11-05: it still fails (see "0.22.7: plugin patch");
  filed as hermes-labs-plugins#63 (covers the image-headers bug too).
  Related, not the same: #43 (exchange 404 on Individual plans), #48
  (classic `ghp_` picked from the credential pool).
- Kanban card: `hermes_upstream` / t_0d86805f.

## Observed on 0.22.5 (panther, 2026-10-28)

- At gateway startup `agent.credential_pool` warns: "Copilot token
  exchange degraded to RAW token ... enterprise-only models may 400 with
  model_not_available_for_integrator".
- Cause: the token is a fine-grained PAT from `COPILOT_GITHUB_TOKEN`.
  `GET https://api.github.com/copilot_internal/v2/token` returns HTTP 404
  for it. That endpoint only exchanges OAuth app tokens (`gho_`/`ghu_`),
  so the warning is expected with a PAT and is not a separate bug.
- Impact: none in practice. The raw PAT is sent as the bearer token.
  The business host is not learned from the exchange, but `base_url` is
  set explicitly. Chat turns send `copilot-developer-cli` because the
  user config sets `model.default_headers.Copilot-Integration-Id`, which
  `_apply_user_default_headers` merges with user-wins precedence.
- Cost: a 404 counts as permanent, so there is one request with no
  retries, then a 30-minute negative cache. The warning is logged once
  per process.

## Notes: first Hermes release with #144788

- Copilot becomes a plugin installed at runtime (`hermes plugins install
  github-copilot` into `~/.hermes`). Decide how Portage ships it instead
  (USE flag in this ebuild, or a separate package).
- Core drops the `gh auth token` fallback; it reads only env/secret
  tokens and `hermes auth add copilot` logins. `left_core_migration.py`
  prints a re-login notice for old setups.
- Rework this patch and the image-headers patch against the plugin.
  Done for 0.22.7; see the next section.

## 0.22.7: plugin patch (2026-11-05)

Live check on panther, read-only `GET /models` with the real PAT (only
status codes recorded):

| Host | `vscode-chat` | `copilot-developer-cli` |
| --- | --- | --- |
| `api.githubcopilot.com` | 400 | 200 (34 models) |
| `api.business.githubcopilot.com` | 400 | 200 (34 models) |

The 400 body: "Personal Access Tokens are not supported for this
endpoint". So bug 1 is real on the plugin, for the catalog and for the
image client (core 0.22.7 merges `{**default_headers, **image_headers}`,
and the plugin's image headers carry `vscode-chat`, which beat a
configured `model.default_headers` id).

The patch adds `copilot_integration_id(api_key)` in
`copilot/credentials.py` (`copilot-developer-cli` for `github_pat_*`,
else `vscode-chat`), and passes the key through
`copilot_request_headers`, `copilot_default_headers` (catalog fetch) and
`editor_headers` / the `client_headers` hook. Every core caller of
`client_headers` that builds the main or image client passes `api_key`
(`agent_init`, `client_lifecycle`, `agent_runtime_helpers`); the
auxiliary client does not, but it applies `model.default_headers` after.

Tests: `tests/test_copilot_pat_integration_id.py` in the plugin (client
headers with and without images, catalog request, a real offline chat
turn). In the lab on v0.22.7: the 4 PAT cases fail on the unpatched
plugin and pass with the patch; the plugin's whole suite passes (155).

## 0.23.0 (2026-11-08)

Same plugin pin (`346cfe9`), so the patch is carried unchanged; CI
build-test applied it and `verify-hermes-agent.sh` passed the PAT
integration id checks.

hermes-labs-plugins#69 (head `dfa9f1e`, 5 additions, 1 file) changes only
`copilot_request_headers()`: it sends `copilot-developer-cli` when
`resolve_copilot_token()` returns a `github_pat_` token. The catalog
fetch (`catalog.py`) and the image headers (`wire.py` `editor_headers`)
both build their headers through that function, so #69 likely covers
both paths (read from source, not run). It decides from the env/secret
token, not from the key actually sent, so a mixed setup (PAT in env, a
different credential sent, or the reverse) could get the wrong id; a
single PAT in `COPILOT_GITHUB_TOKEN`, as on panther, is fine.

Decision (2026-11-08): do not test or comment on #69 now. It is
unmerged, so no plugin sha we could pin contains it; keep our patch.
When a fix lands in plugin `main` and core's catalog pins a sha with it,
run `tests/test_copilot_pat_integration_id.py` against that sha without
our patch, then drop the patch.
