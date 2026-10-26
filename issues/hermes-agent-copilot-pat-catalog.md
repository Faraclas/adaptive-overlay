# hermes-agent: Copilot PAT model catalog fails; scoped token not found

- Package: `app-ai/hermes-agent`
- Patch: `files/hermes-agent-copilot-pat-discovery.patch` (used by
  0.22.5, 2026.9.24-r9)
- Upstream: PRs https://github.com/NousResearch/hermes-agent/pull/51411
  and https://github.com/NousResearch/hermes-agent/pull/32723 (both closed
  unmerged 2026-10-26); the remaining bug is unfiled against
  hermes-labs-plugins
- Status: unfiled (checked 2026-10-26)
- Drop when: 0.22.x keeps it. From the first release containing #144788
  the patch cannot apply (`hermes_cli/copilot_auth.py` is gone); carry the
  PAT header fix against the plugin until the plugin ships it.

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
- Kanban card: `hermes_upstream` / t_0d86805f.

## Notes: first Hermes release with #144788

- Copilot becomes a plugin installed at runtime (`hermes plugins install
  github-copilot` into `~/.hermes`). Decide how Portage ships it instead
  (USE flag in this ebuild, or a separate package).
- Core drops the `gh auth token` fallback; it reads only env/secret
  tokens and `hermes auth add copilot` logins. `left_core_migration.py`
  prints a re-login notice for old setups.
- Rework this patch and the image-headers patch against the plugin.
