# Skill: Updating the Carla Ebuild

This document describes the procedure for updating the
`media-sound/carla` ebuild to the latest upstream release.

> **Safety rules**: Refer to `.agent/instructions/general.md` before
> making any changes.

**Package directory**: `media-sound/carla/`
**Package metadata**: `.agent/packages.json` (entry for `media-sound/carla`)
**Upstream repo**: `falkTX/Carla` on GitHub
**Upstream type**: `github-release` (tags like `v2.5.10`)
**Build system**: GNU Make (custom) — not CMake, Meson, or Cargo

---

## Overview: Script + Agent Division of Labor

Carla is a C/C++ project with a Python (PyQt5) GUI. There are no
Cargo-specific complexities — no `GIT_CRATES`, no `WEBRTC_COMMIT`,
no `RUST_MIN_VER`. The upgrade script handles the mechanical parts;
the agent's main job is checking patches and reviewing release notes.

| Responsibility | Owner |
|---|---|
| Detect new upstream version | Script |
| Check source tarball availability | Script |
| Copy ebuild to new version | Script |
| **Check if patches still apply** | **Agent** |
| **Rebase or remove stale patches** | **Agent** |
| **Extend `PYTHON_COMPAT` if needed** | **Agent** |
| **Review release notes for dep/USE changes** | **Agent** |
| Generate Manifest | Script (`scripts/manifest.sh`) |
| Lint | Script (`scripts/lint.sh`) |

---

## Step-by-Step Update Process

### 1. Run the Upgrade Script

```bash
scripts/upgrade-ebuild.sh media-sound/carla --apply --json
```

Auto-detects the latest version (or pass `--version X.Y.Z`), verifies
the tarball exists, and copies the ebuild. No commit-hash replacements
or Cargo diffs — output is minimal compared to Rust packages.

### 2. Check Patches

This is the most important agent task. Two patches live in `files/`:

1. **`carla-2.5.9-gtk.patch`** — Wraps GTK2/GTK3 LV2 UI bridge
   targets in `HAVE_GTK2`/`HAVE_GTK3` guards in
   `source/bridges-ui/Makefile`. Always applied via `PATCHES=()`.

2. **`carla-2.5.10-no-lssp.patch`** — Removes `-lssp` from MinGW
   linker flags in `source/bridges-plugin/Makefile` (Gentoo's
   `mingw64-toolchain` doesn't ship `libssp`). Applied conditionally
   only when `wine` or `wine32` USE flags are enabled.

For each patch, fetch the relevant Makefile from the new tag and check:

- **Fixed upstream?** Remove the patch and its ebuild reference.
- **Context shifted?** Rebase the patch, rename with the new version
  (e.g. `carla-2.6.0-gtk.patch`), and update the ebuild reference.
- **Applies cleanly?** Keep as-is.

### 3. Check PYTHON_COMPAT

Currently `PYTHON_COMPAT=( python3_{10..14} )`. If a new Python
version has landed in Gentoo, extend the range after confirming
upstream compatibility.

### 4. Review Upstream Release Notes

Check `https://github.com/falkTX/Carla/releases` for:

- New system dependencies → update `DEPEND`/`RDEPEND`/`BDEPEND`
- Removed features → drop USE flags if needed
- Build system changes → adjust `src_compile()` `HAVE_*` flags
- MinGW/Wine bridge changes → may affect the no-lssp patch

### 5. Generate Manifest, Lint, Build Test

```bash
scripts/manifest.sh media-sound/carla
scripts/lint.sh media-sound/carla
scripts/test-build.sh media-sound/carla carla-X.Y.Z.ebuild
```

If manifest fails, the tarball URL is likely wrong or the release
hasn't been published yet. Fix any QA issues from `pkgcheck`.

### 6. Report

Summarize: version bump, patch status (kept / rebased / removed),
`PYTHON_COMPAT` changes, dependency changes, and manifest/lint/build
results.

---

## Patch Format Reference

Both patches use unified diff format against the source tree root:

**GTK patch** (`carla-2.5.9-gtk.patch`) targets
`source/bridges-ui/Makefile` — wraps the unconditional
`TARGETS += ui_lv2-gtk2` / `ui_lv2-gtk3` lines with
`ifeq ($(HAVE_GTK2),true)` / `ifeq ($(HAVE_GTK3),true)` guards.

**No-lssp patch** (`carla-2.5.10-no-lssp.patch`) targets
`source/bridges-plugin/Makefile` — removes `-lssp` from the
`EXTRA_LINK_FLAGS` line under the `ifeq ($(WINDOWS),true)` block.

When rebasing, preserve the `--- a/` / `+++ b/` path style and
update surrounding context lines to match the new source.

---

## Key Facts

- Carla is **not in the main Gentoo overlay** — this is the only
  Gentoo ebuild for the project
- Releases are infrequent (months apart), so patches may need
  rebasing across larger version jumps
- The ebuild uses `MY_PN="Carla"` / `MY_P="${MY_PN}-${PV}"` for
  GitHub's case-sensitive tarball naming (`Carla-X.Y.Z/`)
- Wine bridge builds unset `LDFLAGS` to avoid MinGW-incompatible
  Gentoo hardening flags — this is intentional, not a bug
- Never hardcode the version inside the ebuild; use `${PV}`

---

## Available Tools

| Tool | Purpose |
|---|---|
| `scripts/upgrade-ebuild.sh media-sound/carla --apply --json` | Detect changes, copy ebuild, output structured JSON |
| `scripts/upgrade-ebuild.sh media-sound/carla` | Same but human-readable output, no auto-apply |
| `scripts/manifest.sh media-sound/carla` | Generate Manifest in container |
| `scripts/lint.sh media-sound/carla` | Run `pkgcheck` QA scan in container |
| `scripts/test-build.sh media-sound/carla carla-X.Y.Z.ebuild` | Build-test in container |
| `scripts/check-updates.sh --json` | Check all packages for upstream updates |