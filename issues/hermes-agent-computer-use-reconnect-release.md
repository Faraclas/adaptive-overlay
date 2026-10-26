# hermes-agent: computer_use breaks after cua-driver dies; no way to end sharing

- Package: `app-ai/hermes-agent`
- Patch: `files/hermes-agent-0.22.2-computer-use-release-reconnect.patch`
  (used by 0.22.5); unversioned predecessor
  `files/hermes-agent-computer-use-release-reconnect.patch` (used by
  2026.9.24-r9)
- Upstream: issue https://github.com/NousResearch/hermes-agent/issues/108215;
  PRs #108222, #115064, #118979
- Status: open (checked 2026-10-25)
- Drop when: a release contains #108222 (drops parts 1 and 2) and a
  release action is upstream (drops part 3). Split the patch if only part
  of it lands.

## Problem

Three changes in `tools/computer_use/`:

1. Reconnect after mcp 2.x `MCPError(CONNECTION_CLOSED)`. Without it a
   dead cua-driver breaks every later call with "Connection closed" until
   the gateway restarts; the reconnect check only knew the old error.
2. Revive a dead private (yolo/bounded) cua-driver daemon on reconnect
   (`ensure_alive`).
3. `action="release"`: end this session's desktop connection, closing the
   GNOME RemoteDesktop/ScreenCast sessions (orange bar off). The next call
   reconnects without a consent prompt.

## Upstream

- https://github.com/NousResearch/hermes-agent/pull/108222 covers 1 and 2;
  the Hermes kanban notes say our embedded-daemon revive was cherry-picked
  into it.
- https://github.com/NousResearch/hermes-agent/pull/115064: alternate PR
  for 1.
- https://github.com/NousResearch/hermes-agent/pull/118979: session
  labels after reconnect; replaces #127219 (closed unmerged).
- Part 3 (release action): no upstream PR; local work.
- Kanban card: `hermes_upstream` / t_6f79b7e4.

## Notes

Delete the unversioned predecessor patch together with
`hermes-agent-2026.9.24-r9.ebuild`.
