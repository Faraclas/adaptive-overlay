# Skill: Updating cua-driver

Read `.agent/instructions/general.md` first. Never install host tools, run
sudo, or publish/commit anything without authorization.

- Package: `x11-misc/cua-driver`, executables `/usr/bin/cua-driver` and its
  sidecar `/usr/bin/cua-cursor-theme`.
- Upstream: `trycua/cua` monorepo. The Rust driver is one component stream,
  tagged `cua-driver-rs-vX.Y.Z`. **Every release is a GitHub prerelease**, so
  `packages.json` uses `upstream_type: "github-prerelease"`; the strict
  `version_pattern` keeps `nightly-*` and other components' tags out.
- Cargo workspace: `libs/cua-driver/rust` (`cargo_subdir` in
  `packages.json`; the ebuild's `S`). Upstream's root `Cargo.toml` is not
  this workspace.
- Consumers: Hermes `computer_use` and the Zed MCP server entry. Both start
  it with `CUA_DRIVER_RS_ENABLE_WAYLAND=1` (Hermes:
  `computer_use.native_wayland: true`).

## What the upgrade script does and does not do

`scripts/upgrade-ebuild.sh x11-misc/cua-driver --apply --json` resolves the
latest prerelease, checks the `cua-driver-rs-v<ver>` tarball, copies the
ebuild, and diffs the workspace `Cargo.toml` (git deps, `rust-version`, new
members). It does **not** regenerate `CRATES`. A copied ebuild is never
ready to build as-is.

## Upgrade procedure

1. Fetch the old and new tag tarballs into `~/tmp` (scratch only):
   `https://github.com/trycua/cua/archive/refs/tags/cua-driver-rs-v<ver>.tar.gz`.
   Extracting only `*/libs/cua-driver/*` keeps it small.
2. Regenerate `CRATES` from `libs/cua-driver/rust/Cargo.lock`. Take every
   registry package (including non-Linux targets; Cargo needs them to
   resolve offline). Skip only local workspace members (no `source`). Fail on
   any other source; if git sources appear, add `GIT_CRATES` explicitly.

   ```python
   import pathlib, tomllib

   lock = tomllib.loads(pathlib.Path("Cargo.lock").read_text())
   crates = []
   for package in lock["package"]:
       source = package.get("source")
       if source is None:
           continue  # workspace member (cua-driver, platform-linux, ...)
       assert source == "registry+https://github.com/rust-lang/crates.io-index", package
       crates.append(f'{package["name"]}@{package["version"]}')
   for crate in sorted(crates):
       print(f"\t{crate}")
   ```

   Diff old vs new as `name@version` sets. Look up licenses for **new**
   entries (crates.io API `/api/v1/crates/<name>/<ver>`, field `license`)
   and extend `LICENSE` if one is not already listed.
3. `RUST_MIN_VER`: compare `rust-toolchain.toml` and any `rust-version`
   (workspace and `crates/cua-driver`, `crates/cursor-theme-cli`). Raising it
   past the `testenv-rust-desktop` image's Rust needs an image rebuild first.
4. Patches in `files/`: check each with `patch -p1 --dry-run` in the new
   workspace. Keep the file name while it applies unchanged; rename/rebase
   only when it does not. First read `issues/cua-driver-*.md` and re-check
   their upstream refs (see "On every upgrade" in `issues/README.md`):
   drop `cua-driver-*-libei-multimonitor.patch` once a release contains
   trycua/cua#5853 (or an equivalent fix), and update the issue file
   either way. `cua-driver-*-portage-managed.patch` (targets
   `crates/cua-driver/src/updater.rs`) is local-only and always stays.
5. Features and binaries: the ebuild builds
   `-p cua-driver -p cursor-theme-cli` with `cua-driver/portal-input` for
   `USE=portal`. Confirm those names still exist in
   `crates/cua-driver/Cargo.toml` and `crates/platform-linux/Cargo.toml`.
   Do **not** enable `portal-capture`/`portal-libei`: they pull PipeWire
   via pipewire-rs, which did not build against PipeWire 1.6 (0.28.3).
   Re-test that before changing it.
6. WinRects (`USE=gnome`): list
   `libs/cua-driver/wayland-helper/winrects@cua/` (the ebuild installs
   `metadata.json` and `extension.js`; add new files) and read
   `metadata.json`: `version` and `shell-version`. A version bump means users
   must log out and back in after installing. If the current GNOME major
   (`best_version gnome-base/gnome-shell`) is missing from
   `shell-version`, say so prominently in the PR: GNOME will not load it.
7. `scripts/manifest.sh x11-misc/cua-driver`, `scripts/lint.sh
   x11-misc/cua-driver`, then
   `scripts/test-build.sh x11-misc/cua-driver cua-driver-<ver>.ebuild`.
   The build runs `containers/testenv-rust-desktop/verify-cua-driver.sh`
   (binaries, `--version`, libraries, update refusal). Expect a
   `RedundantVersion` lint note while the previous ebuild is kept.
8. Keep the previous ebuild unless asked to drop it. The regenerated
   `metadata/md5-cache` entries are committed with the change.

## History

- 0.28.3 (2026-09-25): new package. `-r1`: WinRects GNOME version check.
- 0.38.0 (2026-10-23): first bump; CI had silently skipped this package
  (`unsupported:github-prerelease`) until the version-check workflow was
  switched to `scripts/check-updates.sh`. Lockfile diff: +`rquickjs*`
  (default `script` feature of `cua-driver-core`, bundled QuickJS built
  with `cc`, MIT), +`arbitrary`, +`relative-path`, and bumps of `rustls`,
  `rustls-webpki`, `webpki-roots`. No new licenses, toolchain still 1.97.1,
  patch applied unchanged. WinRects v8 → v10; `shell-version` now 45–49
  (GNOME 50 dropped upstream, #5565).
