# cua-driver: libei pointer input never reaches a second monitor

- Package: `x11-misc/cua-driver`
- Patch: none (removed with the last affected ebuild, 0.38.0-r1;
  0.43.2 and 0.47.19 have the upstream fix)
- Upstream: issue https://github.com/trycua/cua/issues/5808 (ours, filed
  2026-10-24); PR https://github.com/trycua/cua/pull/5853
- Status: resolved (0.43.2; checked 2026-11-12)
- Drop when: no retained ebuild references the patch; 0.43.2 includes the
  upstream fix.

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
  (`Closes #5808`). It merged 2026-10-30 as `1e0da1a`; the live GitHub
  API reports both the PR and #5808 closed (checked 2026-11-12).
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
- Conclusion: 0.43.2 contains the upstream fix (`wayland/region_route.rs`
  and `route_absolute`) and no longer applies the local patch. The fix
  remains present in 0.47.19. The local patch was removed with 0.38.0-r1.
  A live multi-monitor test was not available during this upgrade.
- Origin: #5853 came from our report. Issue filed 2026-10-24 02:22 UTC;
  the PR's first commit is 04:37 UTC, PR opened 06:48 UTC, branch
  `onigiri/issue-5808` (looks like upstream's issue-to-PR automation).
  Its design matches the issue's "Proposed fix" item by item; the code is
  their own refactor, not a copy of our patch.

## Backlog

- 0.43.2 is the first checked release containing `1e0da1a`'s fix. The
  retained ebuilds no longer need the patch, which has been removed.
  A live right-monitor check remains useful; ask before posting results
  upstream.
