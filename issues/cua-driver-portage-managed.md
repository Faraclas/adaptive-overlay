# cua-driver: self-updater must defer to Portage

- Package: `x11-misc/cua-driver`
- Patch: `files/cua-driver-0.51.5-portage-managed.patch` (0.51.5, 0.54.0)
- Upstream: none filed
- Status: local (checked 2026-11-19)
- Drop when: upstream offers a generic "managed by the system package
  manager" switch we can set at build time.

## Problem

`cua-driver update --apply` replaces the binary in place, which would
fight Portage over `/usr/bin/cua-driver`. The patches recognize Portage
installs in `crates/cua-driver/src/updater.rs`, so the updater refuses and
points at the package manager. The 0.51.5 patch uses a separate owner after
upstream refactored its update ownership handling.

## Notes

Possible upstream ask: replace pacman-only detection with a build-time
option or marker file any distro can use.
