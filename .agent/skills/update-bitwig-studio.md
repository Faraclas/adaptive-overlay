# Skill: Updating the Bitwig Studio Ebuild

This document describes the procedure for updating the
`media-sound/bitwig-studio` ebuild to the latest upstream
release.

> **Safety rules**: Refer to `.agent/instructions/general.md`
> before making any changes.

**Package directory**: `media-sound/bitwig-studio/`
**Package metadata**: `.agent/packages.json`
  (entry for `media-sound/bitwig-studio`)
**Upstream**: Bitwig GmbH — <https://www.bitwig.com/>
**Upstream type**: `bitwig-web` (version scraped from
  download page)
**Build system**: Binary repackage (`.deb` → Gentoo)

---

## Overview: Script + Agent Division of Labor

Bitwig Studio is a proprietary binary package. There is no
source compilation — the ebuild unpacks a `.deb` downloaded
from Bitwig's servers. This makes upgrades straightforward,
but there are still things to verify on major version bumps.

| Responsibility | Owner |
|---|---|
| Detect new upstream version | Script (`check-updates.sh`) |
| Copy ebuild to new version | Script (`upgrade-ebuild.sh`) |
| **Verify download URL works** | **Agent** |
| **Check .deb contents for structural changes** | **Agent** |
| **Review USE flag compatibility** | **Agent** |
| **Update RDEPEND if deps changed** | **Agent** |
| Generate Manifest | Script (`scripts/manifest.sh`) |
| Lint | Script (`scripts/lint.sh`) |

---

## Step-by-Step Update Process

### 1. Run the Upgrade Script

```bash
scripts/upgrade-ebuild.sh media-sound/bitwig-studio \
    --apply --json
```

Auto-detects the latest version from the Bitwig download
page (or pass `--version X.Y.Z`), verifies the download URL
returns HTTP 302, and copies the ebuild. Output is minimal
since there are no Cargo/Rust complexities.

### 2. Verify the Download URL

The SRC_URI pattern is:

```text
https://www.bitwig.com/dl/Bitwig%20Studio/${PV}/installer_linux/
```

This should return HTTP 302 redirecting to:

```text
https://downloads-secure.bitwig.com/${PV}/bitwig-studio-${PV}.deb
```

Test with:

```bash
curl -sI -o /dev/null -w "%{http_code}" \
    "https://www.bitwig.com/dl/Bitwig%20Studio/${VERSION}/installer_linux/"
```

A `302` means the version exists. A `404` means the version
string is wrong — check the download page manually.

**Version numbering note**: Bitwig uses variable-length
version strings. Major releases may use 2 components (e.g.,
`6.0`) while point releases use 3 (e.g., `5.3.13`). Always
use the exact string from the download page — do not
zero-pad (e.g., `6.0` not `6.0.0`).

### 3. Check for Structural Changes (Major Bumps Only)

On major version bumps (e.g., 5.x → 6.x), the `.deb`
contents may have changed. Download the `.deb` and inspect:

```bash
mkdir -p /home/elias/tmp/bitwig-check
cd /home/elias/tmp/bitwig-check
curl -L -o bitwig.deb \
    "https://www.bitwig.com/dl/Bitwig%20Studio/${VERSION}/installer_linux/"
ar x bitwig.deb
tar tf data.tar.* | head -50
```

Verify:
- The application still installs to `opt/bitwig-studio/`
- The launch binary is still `opt/bitwig-studio/bitwig-studio`
- The desktop file is still at
  `usr/share/applications/com.bitwig.BitwigStudio.desktop`
- Icons are still under `usr/share/icons/hicolor/`
- MIME types are still under `usr/share/mime/packages/`
- The 32-bit plugin host is still named
  `opt/bitwig-studio/bin/BitwigPluginHost-X86-SSE41`
- Bundled ffmpeg binaries are still at
  `opt/bitwig-studio/bin/ffmpeg` and
  `opt/bitwig-studio/bin/ffprobe`

If any paths changed, update the ebuild's `src_install()`,
`QA_PREBUILT`, or `src_prepare()` accordingly.

For minor/patch bumps (e.g., 5.3.12 → 5.3.13), structural
changes are extremely unlikely — skip this step.

### 4. Review USE Flags and Dependencies

The ebuild has these USE flags:

- `+abi_x86_32` — 32-bit plugin bridging
- `+ffmpeg` — use system ffmpeg instead of bundled
- `+jack-sdk` — PipeWire with JACK SDK (default)
- `jack-client` — traditional JACK2

On major bumps, check:
- Are there new runtime libraries bundled or required?
- Has the minimum glibc or kernel version changed?
- Are there new audio backend options?
- Has the desktop file `Categories` or `Version` field
  changed?

### 5. Generate Manifest and Lint

```bash
scripts/manifest.sh media-sound/bitwig-studio
scripts/lint.sh media-sound/bitwig-studio
```

If manifest fails, the download URL is likely wrong or
Bitwig's CDN is temporarily unavailable. Retry after a
few minutes.

### 6. Clean Up Old Ebuilds

After the new version is confirmed working, remove the old
ebuild file. Keep only the latest version unless there is a
specific reason to maintain multiple (e.g., a beta
alongside stable).

### 7. Report

Summarize:
- Version bumped from X to Y
- Download URL verified (HTTP 302)
- Structural changes (if major bump): list any or "none"
- Dependency changes: list any or "none"
- Manifest generation result
- Lint result

---

## Version Detection

Bitwig has no public release API. Version detection uses
the `bitwig-web` upstream type in `check-updates.sh`,
which scrapes the download page at:

```text
https://www.bitwig.com/download/
```

The page contains a string like
`Bitwig Studio X.Y` or `Bitwig Studio X.Y.Z`
in the download button/heading area. The script extracts
the version with a regex.

As a fallback, you can probe the download URL directly
with a HEAD request — a `302` confirms the version exists.

---

## Key Facts

- Bitwig Studio is **proprietary** — `LICENSE="Bitwig"`
- It is a **binary repackage** — no compilation, no
  patches, no build system
- Releases are moderate frequency (every few weeks for
  point releases, a few times per year for major)
- The `.deb` is ~400 MB; manifest generation downloads
  the full file
- The ebuild uses `${PV}` throughout — never hardcode
  the version
- Version strings can be 2-component (`6.0`) or
  3-component (`5.3.13`) — use exactly what upstream
  publishes
- The `src_prepare()` function modifies the desktop file
  to fix categories — verify this sed still applies on
  major bumps
- `QA_PREBUILT` suppresses QA warnings for all binaries
  under `opt/bitwig-studio/`

---

## Common Issues

| Issue | Cause / Fix |
|---|---|
| Manifest download fails | Bitwig CDN issue or wrong version string. Verify URL with curl HEAD request. |
| 404 on download URL | Wrong version format. Check if major release uses 2-component version (e.g., `6.0` not `6.0.0`). |
| Desktop file sed fails | Upstream changed the desktop file format. Inspect the new `.deb` and update the sed command. |
| Missing 32-bit plugin host | Binary was renamed or removed upstream. Check `.deb` contents and update `src_install()`. |
| New bundled libraries | Major version added new deps. Check `ldd` output against `RDEPEND`. |

---

## Available Tools

| Tool | Purpose |
|---|---|
| `scripts/upgrade-ebuild.sh media-sound/bitwig-studio --apply --json` | Detect changes, copy ebuild, output structured JSON |
| `scripts/upgrade-ebuild.sh media-sound/bitwig-studio` | Same but human-readable output, no auto-apply |
| `scripts/manifest.sh media-sound/bitwig-studio` | Generate Manifest in container |
| `scripts/lint.sh media-sound/bitwig-studio` | Run `pkgcheck` QA scan in container |
| `scripts/check-updates.sh --json` | Check all packages for upstream updates |