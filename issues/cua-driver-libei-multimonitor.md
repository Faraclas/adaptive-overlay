# cua-driver: libei pointer input never reaches a second monitor

- Package: `x11-misc/cua-driver`
- Patch: `files/cua-driver-0.38.0-libei-multimonitor.patch` (used by
  0.38.0-r1)
- Upstream: issue https://github.com/trycua/cua/issues/5808 (ours, filed
  2026-10-24); PR https://github.com/trycua/cua/pull/5853
- Status: open (checked 2026-10-25)
- Drop when: a release contains #5853 or an equivalent fix, and a
  foreground pixel click on the right monitor works without the patch.

## Problem

GNOME/KDE Wayland, portal (libei) input, two monitors side by side.
Foreground pixel click/scroll/drag work on the left monitor and do nothing
on the right one; AT-SPI `element_token` clicks work on both. The real
pointer stops at the right edge of the left monitor (x=3839 on a 3840+3840
layout).

Two bugs in `libs/cua-driver/rust/crates/platform-linux/src/wayland/`:

1. `mod.rs`: `libei_click` (via `normalize_click_xy`),
   `libei_move_absolute` and `libei_drag` clamp x/y to
   `output_dimensions()`, the mode of one `wl_output`, not the desktop.
2. `libei.rs`: `pointer_device_for` / `region_local_on` subtract the
   region offset before `motion_absolute`. Absolute coordinates are
   desktop-layout positions that must lie inside a region (ei protocol,
   libei `ei_region_contains`, libeis `eis_device_in_region`, Mutter 49
   `meta-remote-desktop-session.c`). Hidden by bug 1 today.

The patch removes the clamp, sends absolute points unchanged (the region
only selects the device), and errors when regions were announced but none
contains the point. The full analysis is in the filed issue.

Verified with the patch (2026-10-24): triple-click in a terminal and a
10-tick scroll on the right monitor; Nautilus click on the left monitor
still works.

## Upstream

- #5853 "onigiri: issue-5808-auto-1" is upstream automation
  (`Closes #5808`). Open, review requested on 2026-10-25.
- TODO: compare #5853 with our patch before dropping ours.
