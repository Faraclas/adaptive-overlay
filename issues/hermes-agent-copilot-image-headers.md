# hermes-agent: Copilot image requests drop configured headers

- Package: `app-ai/hermes-agent`
- Patch: `files/hermes-agent-copilot-image-headers.patch` (used by 0.22.5,
  2026.9.24-r9); test `files/test_copilot_image_headers.py`
- Upstream: none filed (reported in a comment on #51411, 2026-10-04, now
  closed)
- Status: unfiled (checked 2026-10-26)
- Drop when: the `github-copilot` plugin sends a PAT-compatible
  integration ID on image requests. The core-side patch is obsolete after
  #144788 either way.

## Problem

For a Copilot request containing images, `agent/client_lifecycle.py`
replaces the effective headers with `copilot_request_headers(is_vision=
True)`. That discards configured integration/custom headers, so a PAT
setup (which needs a non-`vscode-chat` integration ID) gets HTTP 400 on
image turns. Only the vision flag should be forced; the patch merges
instead of replacing.

## Upstream

- Core `main` after #144788 merges as `{**effective,
  **route_image_headers}`, so custom headers are no longer dropped
  wholesale. But the plugin's image headers carry
  `Copilot-Integration-Id: vscode-chat` and win the merge, so PAT image
  requests still fail.
- Plan (2026-10-26): not filed yet. Re-test on the first packaged release
  that includes #144788 and the plugin; if PAT image requests still fail,
  report to hermes-labs-plugins together with the PAT catalog bug. See
  `hermes-agent-copilot-pat-catalog.md`.
