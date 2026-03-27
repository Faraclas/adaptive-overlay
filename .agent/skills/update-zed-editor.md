# Skill: Updating the Zed Editor Ebuild

This document describes the canonical procedure for updating the
`app-editors/zed` ebuild to the latest upstream release.

> **Safety rules**: Refer to `.agent/instructions/general.md` before
> making any changes.

**Package directory**: `app-editors/zed/`
**Package metadata**: `.agent/packages.json` (entry for `app-editors/zed`)
**Upstream repo**: `zed-industries/zed` on GitHub

---

## Overview: Script + Agent Division of Labor

The upgrade process uses `scripts/upgrade-ebuild.sh` as the primary
tool. The script handles mechanical detection and safe replacements.
The agent handles decisions that require understanding code structure.

| Responsibility | Owner |
|---|---|
| Detect new upstream version | Script |
| Check source availability | Script |
| Copy ebuild to new version | Script |
| Diff upstream `Cargo.toml` | Script |
| Update existing commit hashes (global sed) | Script (`--apply`) |
| Update `WEBRTC_COMMIT` | Script (`--apply`) |
| Update `src_prepare()` commit variables | Script (side effect of global sed) |
| **Insert new `GIT_CRATES` entries** | **Agent** |
| **Remove old `GIT_CRATES` entries** | **Agent** |
| **Determine subpath for new crates** | **Agent** |
| **Update `RUST_MIN_VER`** | **Agent** (has container/toolchain implications — see below) |
| **Review and validate final ebuild** | **Agent** |
| Generate Manifest | Script (`scripts/manifest.sh`) |
| Lint | Script (`scripts/lint.sh`) |

---

## Step-by-Step Update Process

### 1. Run the Upgrade Script

From the overlay root, run:

```bash
scripts/upgrade-ebuild.sh app-editors/zed --apply --json
```

This will:
- Auto-detect the latest upstream version (or use `--version X.Y.Z`)
- Verify source tarballs are available
- Copy the current ebuild to the new version
- Fetch and diff `Cargo.toml` between old and new versions
- Apply all safe mechanical changes (commit hash updates, `RUST_MIN_VER`,
  `WEBRTC_COMMIT`)
- Output structured JSON with everything detected

If sources are not yet available (especially the crates tarball from
`gentoo-crate-dist`), the script will error. Wait a few hours and retry.

### 2. Read the JSON Output

The script outputs structured JSON. Key fields to act on:

```json
{
  "status": "upgrade-prepared",
  "ebuild_path": "path/to/new/ebuild",
  "git_crates": {
    "updated": [{"crate": "...", "old_rev": "...", "new_rev": "...", "url": "..."}],
    "added":   [{"crate": "...", "url": "...", "rev": "..."}],
    "removed": ["crate-name"]
  },
  "new_workspace_members": ["crates/new_member"],
  "rust_min_ver": "1.85.0 or null",
  "webrtc_commit": "new-value or null"
}
```

- **`git_crates.updated`**: Already handled by `--apply`. No action needed.
- **`git_crates.added`**: You must insert these. See step 3.
- **`git_crates.removed`**: You must remove these. See step 4.
- **`new_workspace_members`**: Check their `Cargo.toml` for git deps. See step 5.
- **`rust_min_ver`**: **Not auto-applied.** Requires agent handling. See step 5a.
- **`webrtc_commit`**: Already handled by `--apply` if non-null.

If `git_crates.added`, `git_crates.removed`, `new_workspace_members`
are all empty and `rust_min_ver` is null, skip to step 6.

### 3. Insert New GIT_CRATES Entries

For each entry in `git_crates.added`, you need to:

1. **Determine the subpath.** Fetch the repo's root `Cargo.toml` at the
   given commit to check if it's a workspace:

   ```bash
   curl -s "https://raw.githubusercontent.com/OWNER/REPO/COMMIT/Cargo.toml"
   ```

   - If the root `Cargo.toml` has `[package]` with `name = "crate-name"`,
     the crate is at the repo root. Use: `repo-name-%commit%`
   - If it has `[workspace]` with `members = [...]`, find which member
     contains the crate. Check `SUBDIR/Cargo.toml` for the matching
     `[package] name`. Use: `repo-name-%commit%/SUBDIR`

2. **Format the entry** using the GIT_CRATES format:

   ```
   [crate-name]='https://github.com/owner/repo;FULL_COMMIT_HASH;repo-name-%commit%/optional/subpath'
   ```

3. **Insert alphabetically** into the `declare -A GIT_CRATES=(...)` block
   in the ebuild.

4. **Check if `src_prepare()` needs a corresponding patch entry.** If the
   new crate's repo also appears in the `src_prepare()` sed substitutions
   (e.g., livekit, calloop, notify), add the corresponding variable and
   sed line. Most new crates do NOT need this — it's only for repos that
   have special Cargo workspace path overrides.

### 4. Remove Old GIT_CRATES Entries

For each crate name in `git_crates.removed`:

1. Delete the corresponding line from `declare -A GIT_CRATES=(...)`.
2. Check `src_prepare()` — if the removed crate's repo is no longer
   referenced by any remaining GIT_CRATES entry, remove the associated
   sed substitution and commit variable too.

### 5. Check New Workspace Members

For each path in `new_workspace_members`, fetch its `Cargo.toml`:

```bash
curl -s "https://raw.githubusercontent.com/zed-industries/zed/v${VERSION}/${MEMBER}/Cargo.toml"
```

Scan for `{ git = "...", rev = "..." }` dependencies. Any git deps found
here that are NOT already in `GIT_CRATES` (either existing or just added
in step 3) must be added using the same procedure as step 3.

Note: Most new workspace members only use `workspace = true` deps and
introduce no new git dependencies. But always check.

### 5a. Handle RUST_MIN_VER Change (if reported)

If the JSON output has a non-null `rust_min_ver`, this requires careful
handling because it has cascading implications:

1. **Check the current container.** The `testenv-rust` container has a
   specific Rust version baked in (see
   `containers/testenv-rust/Containerfile`). If the new `RUST_MIN_VER`
   exceeds the container's Rust version, builds will fail or trigger a
   massive in-container recompile.

2. **Update the ebuild.** Change `RUST_MIN_VER="X.Y.Z"` to the new value.

3. **Update the Containerfile** if needed:
   - Bump the `dev-lang/rust-bin` version and its `~amd64` keyword accept
   - Check whether the LLVM version also needs bumping (`LLVM_COMPAT`
     in the ebuild, `llvm-core/clang` slot in the Containerfile)
   - Check for any other toolchain changes needed

4. **Flag for human review.** A `RUST_MIN_VER` change should always be
   reviewed by a human because:
   - The container image must be rebuilt and published before build tests
     can run
   - Other packages in the overlay may be affected by toolchain changes
   - The `publish-testenv-rust.yml` workflow must complete before
     `ci-build.yml` can succeed

5. **Communicate clearly** in the PR description that this upgrade
   requires a container rebuild, and list the Containerfile changes needed.

### 6. Generate the Manifest

```bash
scripts/manifest.sh app-editors/zed
```

This runs `pkgdev manifest` inside the testenv container, fetching all
distfiles and recording their checksums. The `Manifest` file is written
back to the overlay via a read-write bind mount.

If this fails, the most likely causes are:
- Wrong commit hash in `GIT_CRATES` (download 404)
- `WEBRTC_COMMIT` doesn't match a release tag at `livekit/rust-sdks`
- Force-pushed upstream repo (hash no longer exists)

### 7. Lint

```bash
scripts/lint.sh app-editors/zed
```

Fix any QA issues reported by `pkgcheck`.

### 8. Report

Summarize what was done:
- Version bumped from X to Y
- `GIT_CRATES` changes: list each updated, added, or removed crate
- `WEBRTC_COMMIT` change (if any)
- `RUST_MIN_VER` change (if any)
- `DEPEND`/`BDEPEND` changes (if any)
- Manifest generation result
- Lint result

---

## GIT_CRATES Format Reference

```bash
declare -A GIT_CRATES=(
    # Crate at repo root:
    [crate-name]='https://github.com/owner/repo;FULL40CHARHASH;repo-name-%commit%'

    # Crate in a subdirectory:
    [sub-crate]='https://github.com/owner/repo;FULL40CHARHASH;repo-name-%commit%/path/to/sub-crate'

    # Multiple crates from same repo (same hash, one entry per crate):
    [crate-a]='https://github.com/owner/monorepo;FULL40CHARHASH;monorepo-%commit%/crates/crate-a'
    [crate-b]='https://github.com/owner/monorepo;FULL40CHARHASH;monorepo-%commit%/crates/crate-b'
)
```

The cargo eclasses use this to:
1. Download `https://github.com/owner/repo/archive/HASH.tar.gz`
2. Unpack as `repo-name-HASH/` (with `%commit%` substituted)
3. Make the crate available to the offline build

When a repo is renamed or hash changes, update **ALL** entries from that repo.

---

## WEBRTC_COMMIT Reference

The `WEBRTC_COMMIT` value corresponds to a release tag at
`https://github.com/livekit/rust-sdks/releases` with the form `webrtc-XXXX-N`.

If the livekit-rust-sdks commit changed in `GIT_CRATES`, verify whether
`WEBRTC_COMMIT` also needs updating by checking that releases page.

---

## src_prepare() Commit Variables

The ebuild's `src_prepare()` function contains sed substitutions that
rewrite git dependencies to local paths for offline builds. Each
substitution has a corresponding `*_COMMIT` variable, e.g.:

```
local CALLOOP_COMMIT="eb6b4fd..."
local LIVEKIT_COMMIT="37835f8..."
local WGPU_COMMIT="6e0c254..."
```

When `--apply` does its global sed replacement of old→new commit hashes,
these variables are updated automatically (because they contain the same
hash string). No separate action is needed for existing repos.

For **new** repos that need `src_prepare()` handling: this is rare. It
only applies when the upstream `Cargo.toml` uses workspace-level path
overrides that conflict with the git checkout layout. Most git deps
work fine with just a `GIT_CRATES` entry.

---

## Common Issues

| Issue | Cause / Fix |
|---|---|
| Crates tarball 404 | Normal for brand-new releases. `gentoo-crate-dist` generates it asynchronously. Wait a few hours. |
| WebRTC prebuilt not found | `WEBRTC_COMMIT` doesn't match a release tag. Check `livekit/rust-sdks/releases`. |
| `pkgdev manifest` fails | Wrong commit hash in `GIT_CRATES`, or force-pushed repo. Verify hashes. |
| `pkgdev manifest` re-downloads | Expected when hashes changed — it fetches new archives. |

## Key Facts

- Zed releases frequently (often multiple times per week)
- Most releases change at least a few git dependency revisions
- The ebuild uses `${PV}` — never hardcode the version inside the ebuild
- Crates.io version bumps require no ebuild changes (handled by crates tarball)

## Available Tools

| Tool | Purpose |
|---|---|
| `scripts/upgrade-ebuild.sh app-editors/zed --apply --json` | Detect changes, apply mechanical updates, output structured JSON |
| `scripts/upgrade-ebuild.sh app-editors/zed` | Same but human-readable output, no auto-apply |
| `scripts/manifest.sh app-editors/zed` | Generate Manifest in container |
| `scripts/lint.sh app-editors/zed` | Run `pkgcheck` QA scan in container |
| `scripts/test-build.sh app-editors/zed zed-X.Y.Z.ebuild` | Build-test in `testenv-rust` container |
| `scripts/check-updates.sh --json` | Check all packages for upstream updates |