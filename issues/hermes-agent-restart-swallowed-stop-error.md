# hermes-agent: gateway restart hangs in `draining` when `stop()` raises

- Package: `app-ai/hermes-agent`
- Patch: none
- Upstream: https://github.com/NousResearch/hermes-agent/issues/159067
- Status: watching (checked 2026-11-22)
- Drop when: a release logs a failed `stop()` on the restart path and
  keeps the shutdown watchdog armed; then the install message can go
  back to recommending `hermes gateway restart`.

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

How we hit it: after a Portage upgrade, the old gateway is still running
while the new version's files are on disk. The stop path imports modules
lazily. On Panther (2026-11-22, 0.23.2 -> 0.23.3), the 0.23.2 gateway
needed `hermes_state_runtime`, which 0.23.3 moved into `persistence/`.
It stopped after `Shutdown phase: drain done` with no error anywhere. A
`SIGUSR2` faulthandler dump showed no watchdog thread. The exact
exception was lost, so the missing module is an inference.

## Workaround

After every upgrade, restart through the service manager instead of
`hermes gateway restart`:

- systemd: `systemctl --user restart hermes-gateway`. The `SIGTERM` stop
  can wedge the same way. systemd then kills it at `TimeoutStopSec`
  (70 s in the unit `hermes gateway install` writes) and starts the new
  version. Expect up to about a minute of waiting.
- OpenRC: `rc-service hermesagent restart`. `files/hermesagent.initd`
  sets no `retry`, so it is not verified that a wedged stop gets killed.
  If it hangs, stop the service and kill the leftover process.

The `pkg_postinst` message of 0.23.2 and 0.23.3 says this.

## Upstream

- 2026-11-22: filed #159067 with the faulthandler dump. Unchanged on
  `main` at 0f602c5f the same day.

## Notes

- Recovery leaves a `Previous gateway life ... exited UNCLEANLY` warning
  on the next start. That is the kill, not an OOM.
- Diagnose a stuck gateway with `kill -USR2 <pid>`. It writes stacks to
  `~/.hermes/logs/gateway_faulthandler.log` and does not stop the
  process.
