# hermes-agent: lazy-dep pins block computer_use on Portage

- Package: `app-ai/hermes-agent`
- Patch: `files/hermes-agent-lazydeps-pins-as-floors.patch` (used by
  2026.9.24-r9 only)
- Upstream: none filed
- Status: local (checked 2026-10-26)
- Drop when: `hermes-agent-2026.9.24-r9.ebuild` is removed (after the
  laptop `gentoo` moves to the semver releases). Not carried in 0.22.5.

## Problem

`tools/lazy_deps.py` `_is_satisfied()` requires the installed version to
match each exact `==X` pin. With `security.allow_lazy_installs: false`,
Hermes cannot install anything itself, so a newer Portage-installed
release counted as missing and blocked computer_use. The patch treats an
exact pin as a floor (`>=X`) when lazy installs are disabled; older
versions still fail.

## Notes

When deleting the r9 ebuild, also delete this patch and
`files/hermes-agent-computer-use-release-reconnect.patch`, then remove
this file. The `>=app-ai/hermes-agent-2000` mask in
`profiles/package.mask` stays until no system has a date version
installed.
