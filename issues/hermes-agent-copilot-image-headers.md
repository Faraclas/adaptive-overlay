# hermes-agent: Copilot image requests drop configured headers

- Package: `app-ai/hermes-agent`
- Patch: none. The core patch and its test went with the 0.22.5 ebuild
  (removed 2026-11-08). 0.22.7 and 0.23.0: covered by
  `files/hermes-agent-copilot-plugin-pat-integration-id.patch`, tracked in
  `hermes-agent-copilot-pat-catalog.md`
- Upstream: reported in a comment on #51411 (2026-10-04, now closed);
  plugin side filed with the PAT catalog bug as
  https://github.com/NousResearch/hermes-labs-plugins/issues/63
- Status: resolved (v0.22.7 core; checked 2026-11-08). The plugin side is
  open in `hermes-agent-copilot-pat-catalog.md`
- Drop when: delete this file when the PAT catalog issue is resolved.

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
- 2026-11-05: confirmed on v0.22.7 by reading `agent/client_lifecycle.py`:
  image requests get `{**default_headers, **image_headers}` from the
  route's `client_headers(..., api_key=..., has_images=True)`. The plugin
  patch makes that answer carry `copilot-developer-cli` for a PAT, so one
  plugin fix covers both bugs; one upstream report for both
  (hermes-labs-plugins#63).
