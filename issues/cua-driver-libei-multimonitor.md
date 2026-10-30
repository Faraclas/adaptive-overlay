# cua-driver: libei pointer input never reaches a second monitor

- Package: `x11-misc/cua-driver`
- Patch: `files/cua-driver-0.38.0-libei-multimonitor.patch` (used by
  0.38.0-r1)
- Upstream: issue https://github.com/trycua/cua/issues/5808 (ours, filed
  2026-10-24); PR https://github.com/trycua/cua/pull/5853
- Status: fixed upstream, not yet released. #5853 merged 2026-10-30 as
  `1e0da1a`; #5808 closed. Newest cua-driver-rs build then: 0.38.1
  nightlies from before the merge (checked 2026-10-30).
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

- Merged 2026-10-30 17:14 UTC as `1e0da1a` (11 commits, squashed; no
  review comments). The final diff still matches the comparison below.
  The merge adds tests showing that a positioned scroll to a point
  outside every region sends no scroll. CI now runs the whole
  `platform-linux --features portal-input --lib` test binary. Live
  multi-monitor GNOME/KDE testing was still not run upstream.
- #5853 "onigiri: issue-5808-auto-1" is upstream automation
  (`Closes #5808`). State on 2026-10-26: open, merge blocked, head
  `5ae80d3`, review requested. CI not fully green (one flaky updater
  test, Linux verification-skill job timed out). The PR body says live
  multi-monitor testing on GNOME/KDE was not run.
- Compared with our patch (2026-10-26), same behaviour:
  - removes the single-`wl_output` clamp in `libei_click`,
    `libei_move_absolute` and `libei_drag`;
  - sends absolute points unchanged, the region only selects the device;
  - errors when regions were announced but none contains the point;
  - falls back to the first absolute-pointer device only when no regions
    were announced;
  - `click(0,0)` still means the output centre; `move`/`drag` take (0,0)
    literally.
- Where #5853 differs:
  - Drag end outside the start device's regions fails before any input
    is sent. Ours sends the raw point, EIS discards it and the drag stops
    early. The PR is better here.
  - Routing moves to a new `wayland/region_route.rs` (`route_absolute`,
    `RegionRect`); `libei_click_with` takes an injectable dimensions
    function.
  - Adds unit tests (with a local EIS test server) and a CI step
    `cargo test -p platform-linux --features portal-input --lib wayland::`.
  - Our error message is richer (lists the announced regions).
- Conclusion: functionally equivalent, slightly better on drags. Drop our
  patch for the first release containing #5853, after a live
  right-monitor test without it.
- Origin: #5853 came from our report. Issue filed 2026-10-24 02:22 UTC;
  the PR's first commit is 04:37 UTC, PR opened 06:48 UTC, branch
  `onigiri/issue-5808` (looks like upstream's issue-to-PR automation).
  Its design matches the issue's "Proposed fix" item by item; the code is
  their own refactor, not a copy of our patch.

## Backlog

- On the first cua-driver-rs release after `1e0da1a`: bump the ebuild
  without our patch and repeat the live checks on the two-monitor GNOME
  setup: right-monitor click, scroll and drag; left-monitor Nautilus
  click; a drag across the monitor edge. Mutter puts both monitors'
  regions on one device, so that drag should work (upstream test
  `drag_across_regions_of_one_device...`); it fails cleanly only when
  the end lies outside the start device's regions. If all pass, drop
  the patch and this file. Optionally report the live result on #5808.
  Ask before posting upstream.
