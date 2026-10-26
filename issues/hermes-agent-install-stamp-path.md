# hermes-agent: install stamp not found in a wheel install

- Package: `app-ai/hermes-agent`
- Patch: `files/hermes-agent-0.22.5-install-stamp-path.patch` (used by
  0.22.5)
- Upstream: none filed
- Status: local (checked 2026-10-26)
- Drop when: upstream finds a stamp inside the installed package for
  wheel installs.

## Problem

`pm/paths.py:install_stamp_path()` looks for `install-stamp.json` at the
install root, which for a wheel install is `site-packages/`. A top-level
file in site-packages is a Gentoo QA violation, so the ebuild installs the
stamp in `hermes_cli/` and the patch falls back to it.

The stamp matters: `updateMechanism: external` and `distribution:
portage` make `hermes update` defer to Portage, and it supplies the
version/commit Hermes shows.

## Notes

- Not using `HERMES_INSTALL_ROOT` (upstream's Nix mechanism): it also
  moves the gateway runtime check, update locks, the MCP catalog and
  launchers.
- Before 0.22.5 the ebuild made this edit with inline `python3 -c` in
  `src_prepare`.
- Possible upstream ask: look for the stamp inside the package for wheel
  installs. Would likely be accepted as a packaging fix.
