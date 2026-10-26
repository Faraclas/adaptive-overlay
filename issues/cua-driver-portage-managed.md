# cua-driver: self-updater must defer to Portage

- Package: `x11-misc/cua-driver`
- Patch: `files/cua-driver-0.28.3-portage-managed.patch` (used by
  0.28.3-r1, 0.38.0-r1)
- Upstream: none filed
- Status: local (checked 2026-10-25)
- Drop when: upstream offers a generic "managed by the system package
  manager" switch we can set at build time.

## Problem

`cua-driver update --apply` replaces the binary in place, which would
fight Portage over `/usr/bin/cua-driver`. The patch routes Portage
installs through upstream's existing pacman-managed path in
`crates/cua-driver/src/updater.rs`, so the updater refuses and points at
the package manager.

## Notes

Possible upstream ask: replace pacman-only detection with a build-time
option or marker file any distro can use.
