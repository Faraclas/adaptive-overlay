# cua-driver: self-updater must defer to Portage

- Package: `x11-misc/cua-driver`
- Patch: `files/cua-driver-0.28.3-portage-managed.patch` (used by
  0.43.2); `files/cua-driver-0.47.19-portage-managed.patch` (used by
  0.47.19)
- Upstream: none filed
- Status: local (checked 2026-11-12)
- Drop when: upstream offers a generic "managed by the system package
  manager" switch we can set at build time.

## Problem

`cua-driver update --apply` replaces the binary in place, which would
fight Portage over `/usr/bin/cua-driver`. The patch routes Portage
installs through upstream's ownership check in
`crates/cua-driver/src/updater.rs`, so the updater refuses and points at
the package manager. In 0.47.19 upstream replaced the pacman-only check
with `UpdateOwner`; the rebased patch adds a Portage owner and extends
the installer-refusal regression test. Channel switching uses the same
ownership check.

## Notes

Possible upstream ask: replace pacman-only detection with a build-time
option or marker file any distro can use.
