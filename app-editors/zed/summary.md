# Comprehensive install comparison: Gentoo ebuild vs upstream install script

## Scope
This document is a **comprehensive, end-to-end comparison** of what the Gentoo ebuild does versus what the upstream `zed_install.sh` script does, including **inputs, build steps, install layout, runtime behavior, permissions, updates, and system integration**. It also calls out **likely runtime implications**, especially for config/data persistence.

---

## 1) Acquisition & artifact provenance
**Ebuild**
- **Source-based**: downloads upstream source tarball plus a crate dist tarball.
- **Rebuilds binaries** locally via Cargo, from tagged release source.
- **WebRTC bundle**: downloads architecture-specific prebuilt WebRTC for LiveKit SDK.
- **Checksums** and integrity are handled via Portage.

**Install script**
- **Binary-based**: downloads a prebuilt Zed application bundle tarball.
- No compilation on the target system.
- Integrity relies on the upstream delivery; no Portage checks.

**Implication:** The ebuild is reproducible and tied to system toolchain; the script is fast and matches upstream’s exact packaging.

---

## 2) Build environment & toolchain
**Ebuild**
- Uses system toolchain (Rust, LLVM/Clang, cmake, etc.).
- Honors Gentoo build flags (CFLAGS/RUSTFLAGS, LTO, etc.).
- Applies portage-specific build configuration.

**Install script**
- Uses no toolchain locally.
- No influence from system build flags or ABI constraints.

**Implication:** The ebuild is sensitive to your system toolchain and flags; the script is not.

---

## 3) Dependency model
**Ebuild**
- Declares **runtime dependencies** (Wayland/X11, OpenSSL, libgit2, etc.).
- Declares **build-time dependencies** (Rust, LLVM, cmake, etc.).
- Dependencies are tracked and managed by Portage.

**Install script**
- No dependency management.
- Assumes system libraries present at runtime.
- If a dependency is missing, runtime failures can occur without clear package mapping.

**Implication:** Ebuild gives explicit system dependency guarantees; script relies on environment.

---

## 4) Architecture & platform handling
**Ebuild**
- Builds per-arch with Gentoo keywords (e.g., `~amd64`, `~arm64`).
- Uses the correct WebRTC bundle for arch.
- No macOS support in Gentoo ebuild.

**Install script**
- Supports macOS and Linux.
- Determines arch at runtime (`x86_64`/`aarch64`).
- Uses a single upstream binary channel with arch-specific bundles.

**Implication:** Script has broader OS support; ebuild is Linux-only and tied to Gentoo arch policy.

---

## 5) Install location & filesystem layout
**Ebuild**
- **System-wide install**:
  - `zedit` CLI installed in `/usr/bin/`.
  - Main editor binary installed in `/usr/libexec/zed-editor`.
  - Icons installed into system icon directories.
  - Desktop file installed into system menu locations.
- No app bundle directory structure in `/usr`.

**Install script**
- **User-local install**:
  - Extracts bundle to `~/.local/zed*.app`.
  - Symlinks `~/.local/bin/zed`.
  - Desktop file in `~/.local/share/applications`.
  - Icons remain inside the bundle; desktop file points to user path.

**Implication:** Ebuild integrates with system paths; script mirrors upstream bundle structure in the user’s home.

---

## 6) File ownership & permissions
**Ebuild**
- Files installed as root, owned by root.
- Read-only system files by design.
- Runtime config/data lives in user directories (not created in install).

**Install script**
- All files owned by the user.
- Bundle files are writable by the user.

**Implication:** Script avoids permission issues for bundled files; ebuild relies on user directories for writable state.

---

## 7) Binary names & entry points
**Ebuild**
- CLI installed as `zedit`.
- GUI/editor binary installed as `/usr/libexec/zed-editor`.
- Desktop file references `zedit` or configured entry points.

**Install script**
- CLI entry is `~/.local/bin/zed` (symlink to bundle binary).
- Uses upstream layout and naming inside the bundle.

**Implication:** Ebuild may differ from upstream expected binary names, which can affect desktop file assumptions or internal paths.

---

## 8) Desktop integration
**Ebuild**
- Generates `.desktop` from upstream template via `envsubst`.
- Installs to system applications menu.
- Installs icons to system icon directories.

**Install script**
- Copies `.desktop` from the bundle.
- Patches `Icon` and `Exec` to user-local paths.
- Installs into user applications menu.

**Implication:** Ebuild integrates globally; script integrates per-user.

---

## 9) Update behavior
**Ebuild**
- Portage-managed updates.
- Explicitly sets `ZED_UPDATE_EXPLANATION` to tell the app updates are handled by Portage.

**Install script**
- Updates by re-running script (or by upstream self-update mechanisms if any).
- Supports channels (`stable`, `nightly`, `preview`, `dev`) via env vars.

**Implication:** Ebuild suppresses self-update expectations; script aligns with upstream channels.

---

## 10) Runtime config, cache, and data paths
**Ebuild**
- Does **not** create `~/.config/zed` or `~/.local/share/zed`.
- Assumes Zed will create user config/cache at runtime.

**Install script**
- Does not explicitly create config/cache either, but uses upstream layout.

**Potential issue:** If Zed expects bundle-relative writable paths, root-owned bundle locations could cause write failures. The script’s per-user bundle is writable.

---

## 11) Permissions-related failure modes
**Ebuild**
- If Zed tries to write into its install directory (`/usr/libexec/...`), it will fail.
- If it expects to write to `AppImage`-like bundle resources, root ownership could block it.

**Install script**
- Bundle lives in user home, so any internal writes generally succeed.

**Implication:** A startup loop where settings never persist could be caused by **write attempts in root-owned paths** when installed system-wide.

---

## 12) Logging & diagnostics
**Ebuild**
- No explicit logging configuration in install.
- Tests create `~/.config/zed` and `~/.local/share/zed/logs` during test phase only.

**Install script**
- No logging configuration.
- Relies on runtime defaults.

**Implication:** For debugging, ensure writable `~/.config/zed` and `~/.local/share/zed/logs`.

---

## 13) Sandboxing & isolation
**Ebuild**
- Fully integrated into system runtime environment.
- No containerized or per-user sandbox assumptions.

**Install script**
- Per-user install is effectively isolated from system package manager.

---

## 14) Removal/uninstall
**Ebuild**
- Portage clean uninstall; removes system files and tracks state.
- Orphaned user config remains unless manually removed.

**Install script**
- Manual: remove `~/.local/zed*.app`, `~/.local/bin/zed`, and desktop entries.

---

## 15) Security & trust model
**Ebuild**
- Builds from source, auditable through ebuild and Gentoo patches.
- Trusts your toolchain and system libraries.

**Install script**
- Trusts upstream binary distribution as-is.

---

## 16) Compatibility & ABI stability
**Ebuild**
- Built against system libraries; ABI mismatches are managed via Portage.
- More likely to be consistent with Gentoo’s system policies.

**Install script**
- Bundled binary may assume specific library versions.
- If the system lacks expected libraries, runtime errors may occur.

---

## 17) Startup behavior differences (potentially relevant)
**Ebuild**
- If the app expects bundle-relative data (icons, resources, etc.), the system layout may not match upstream assumptions.
- `zedit` wrapper vs `zed` may cause unexpected internal path resolution.

**Install script**
- Uses upstream bundle layout, which is likely what Zed expects.

**Implication:** Some runtime issues can be rooted in **path expectations** from upstream bundle structure.

---

## 18) Summary: key differences that matter for runtime issues
- **Writable paths**: Script installs into user-writable bundle; ebuild installs into root-owned system paths.
- **Bundle layout**: Script uses upstream bundle layout; ebuild installs binaries into system locations without a bundle.
- **Binary naming**: Script uses `zed`; ebuild uses `zedit` and `zed-editor`, which may affect internal path logic.
- **Dependencies**: Ebuild declares and enforces system dependencies; script assumes them.

---

## One-line summary
- **Ebuild** = source build, system-wide, root-owned, Portage-managed, non-bundle layout.
- **Script** = upstream prebuilt bundle, per-user, writable bundle layout, manually updated.

---

## Next steps if you want to debug “settings never persist”
1. Check if Zed is trying to write into a **root-owned install path**.
2. Confirm Zed’s config/data directories are writable: `~/.config/zed`, `~/.local/share/zed`.
3. Compare runtime logs between the ebuild version and the script version.