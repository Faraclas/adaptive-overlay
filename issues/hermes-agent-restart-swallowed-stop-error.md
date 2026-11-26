# hermes-agent: gateway restart hangs in `draining` when `stop()` raises

- Package: `app-ai/hermes-agent`
- Patch: none
- Upstream: https://github.com/NousResearch/hermes-agent/issues/158360
  (ours: #159067, a duplicate), fix PR
  https://github.com/NousResearch/hermes-agent/pull/158399
- Status: fixed upstream, not yet released (checked 2026-11-25: #158399
  merged on `main` at `fa4ed19da3`, not in `v0.23.4`)
- Drop when: a release contains #158399 (`fa4ed19da3`) or an equivalent
  fix and running gateways have cycled onto it; until then, an already
  running `0.23.2`/`0.23.3`/`0.23.4` gateway keeps the old stop code in
  memory, so keep recommending service-manager restarts in `pkg_postinst`.

## Problem

`hermes gateway restart` (and `systemctl --user reload`) sends `SIGUSR1`.
The gateway runs `stop()` in a task started by
`gateway/restart_when_idle.py:request_restart()` and keeps only a
reference in `runner._restart_task`. Nothing reads the task's exception.
`stop()` (`gateway/run_shutdown.py`) sets `_watchdog_done` in a
`finally`, so a failed stop also disarms the shutdown watchdog.

Result: an exception in `stop()` is never logged, the gateway stays
alive with its adapters connected in `gateway_state: draining`, and
`hermes gateway restart` waits its whole budget (about 31 minutes).

A later `SIGTERM` does not help: `stop()` keeps the failed task in
`self._stop_task` and only awaits it again, so teardown never re-runs and
no new watchdog is armed. Only the supervisor's kill ends the process.

How we hit it: after a Portage upgrade, the old gateway is still running
while the new version's files are on disk, and the stop path imports
modules lazily. On Panther (2026-11-22, 0.23.2 -> 0.23.3) the restart
stopped after `Shutdown phase: drain done` with nothing logged; a
`SIGUSR2` faulthandler dump showed no watchdog thread. The `SIGTERM`
from `systemctl --user restart` then surfaced the lost exception:

```text
ERROR asyncio: Task exception was never retrieved ... GatewayShutdownMixin.stop() ...
ImportError: cannot import name 'authority_persistence' from 'gateway.session_persistence'
```

The 0.23.2 process had its own `gateway.session_persistence` loaded
(0.23.2 has no `authority_persistence`), and a module first imported
during `stop()` came from the 0.23.3 files and imports the new name. Any
in-place upgrade under a running gateway can mix versions like this.

## Workaround

After every upgrade, restart through the service manager instead of
`hermes gateway restart`:

- systemd: `systemctl --user restart hermes-gateway`. If the stop fails
  the same way, systemd kills it at `TimeoutStopSec`
  (70 s in the unit `hermes gateway install` writes) and starts the new
  version. Expect up to about a minute of waiting.
- OpenRC: `rc-service hermesagent restart`. `files/hermesagent.initd`
  sets no `retry`, so it is not verified that a wedged stop gets killed.
  If it hangs, stop the service and kill the leftover process.

The `pkg_postinst` message of 0.23.2 and 0.23.3 says this.

## Upstream

- 2026-11-20: #158360 filed by someone else (same root cause, not
  upgrade-specific); fix PR #158399 opened the same day.
- 2026-11-22: we filed #159067 with the faulthandler dump. Unchanged on
  `main` at 0f602c5f the same day.
- 2026-11-23: on #159067, a contributor traced the `SIGTERM` path and
  reproduced it; another reported the same pattern on macOS after
  in-place `git rebase` upgrades. Triage labelled it P2 and pointed to
  #158360 / #158399. We commented with the confirmed `ImportError` and
  agreed to close ours as a duplicate. #158399 is open, not reviewed.
- 2026-11-25: #158399 merged into `main` (`fa4ed19da3468434d00d4bbc216f0790d57ea40c`),
  and both #158360 and #159067 were closed as fixed. It replaces
  `try/finally: _watchdog_done.set()` with `disarm_after_teardown()` (logs
  a failed or cancelled stop and keeps the watchdog armed to exit `1` on
  its ~60 s leash) and moves `session_acp_lifecycle` import inside
  `settle_gateway_runtime`'s `try/except` so the mixed-version
  `ImportError` logs a warning without aborting `stop()`. `v0.23.4` was
  published before the merge, so the fix awaits a later release; pre-fix
  gateways still need a service-manager restart to move onto it.

## Notes

- Recovery leaves a `Previous gateway life ... exited UNCLEANLY` warning
  on the next start. That is the kill, not an OOM.
- The lost exception only reaches the logs once the stop task is
  dropped: look for `Task exception was never retrieved` in
  `~/.hermes/logs/errors.log` or the journal after the `SIGTERM`.
  Traceback frames are read from the replaced files, so they can point at
  the wrong code.
- Diagnose a stuck gateway with `kill -USR2 <pid>`. It writes stacks to
  `~/.hermes/logs/gateway_faulthandler.log` and does not stop the
  process.
