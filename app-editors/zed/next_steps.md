# Next steps: Zed diagnostics + ebuild follow-ups

## Goal
Track the packaging/runtime differences between the Gentoo source build and the upstream prebuilt bundle, with emphasis on the new `0.221.5` anomalies:
- `GPUI was compiled in test mode`
- references to `/home/zed/...` paths
- `zed` binary not found (CLI name mismatch)

---

## Findings recap (from the last comparison)
- Archive contents match between `0.218.5` and `0.221.5`; only logs differ.
- `commands.log` still shows `command -v zed` missing in both; only `zedit` exists.
- `0.221.5` adds:
  - `GPUI was compiled in test mode`
  - `Failed to watch /home/zed/.config/github-copilot`
  - `lmstudio` connection refused
  - `window not found` (GPUI)

---

## Hypothesis A: `--all-features` enables GPUI test mode
The ebuild uses:
- `cargo_src_configure --all-features`

If the `gpui` crate exposes a test-mode feature, `--all-features` could be enabling it unintentionally.

### Action items
1. **Completed: remove `--all-features` from `src_configure`**
   - Done in the ebuild.

2. **Rebuild without `--all-features`**
   - Rebuild and compare logs:
     - Check if `GPUI was compiled in test mode` disappears.
     - Check if `/home/zed/...` warnings disappear.

---

## Hypothesis B: Missing `zed` entrypoint changes runtime behavior
The upstream install provides `zed` in PATH. The ebuild provides `zedit`, so:
- `command -v zed` fails (confirmed in diagnostics)

### Action items
1. **Completed: add `zed` symlink in `src_install`**
   - Implemented as `dosym zedit /usr/bin/zed`.
2. Re-run diagnostics and confirm whether any path resolution or config location changes.

---

## Hypothesis C: `/home/zed` path is a baked-in default
Since `commands.log` shows `HOME=/home/elias`, `/home/zed` is likely:
- an internal fallback path (possibly in test mode),
- or a baked default in a dependency (Copilot tooling or GPUI).

### Action items
1. Search in source for `"/home/zed"` or `github-copilot` default path handling.
2. Confirm whether the path only appears with test-mode builds.
3. If not test-mode related, trace where `copilot` config paths are resolved.

---

## Dependency audit (system libraries)
- **Completed audit on 0.218.5 binaries** using `scanelf`.
- **Result:** added `media-libs/freetype` to `DEPEND`.
- **Next:** repeat the `scanelf` audit on the freshly built **0.221.5** binaries and update `DEPEND`/`RDEPEND` if any new libraries appear.

### Repeatable audit checklist
Run these after installing the new build:

```
/dev/null/zed-dep-audit.txt#L1-7
scanelf -n /usr/libexec/zed-editor
scanelf -n /usr/bin/zed
scanelf -n /usr/bin/zedit
```

Notes for interpreting output:
- Ignore `ld-linux-*.so.*`, `libc.so.*`, `libm.so.*`, `libgcc_s.so.*`, and `libstdc++.so.*` (toolchain/glibc-provided).
- Focus on non-toolchain libs like `libxkbcommon`, `libxcb`, `libX11`, `libasound`, `libgit2`, `libfreetype`, etc.
- If `libX11-xcb.so.1` appears, it is covered by `x11-libs/libX11`.

If any new `NEEDED` libraries show up, map them to packages with:

```
/dev/null/zed-dep-audit.txt#L9-10
equery b /lib64/libNAME.so
equery b /usr/lib64/libNAME.so
```

## Diagnostic rerun checklist
When testing changes:
- Capture new `zed-diagnostics` bundle
- Compare:
  - `files/Zed.log`
  - `commands.log`
  - `summary.txt`
- Explicitly verify:
  - `GPUI was compiled in test mode` log line
  - `/home/zed/...` warnings
  - `command -v zed` and `zedit --version`

---

## Safety note
The `commands.log` includes sensitive environment variables (API keys, tokens, etc.).  
Always redact before sharing publicly and rotate any leaked credentials.

---

## Upstream Linux build + packaging notes (from zed.dev docs)
Key points to align with upstream guidance:

- Build from source with Cargo:
  - Debug: `cargo run`
  - Tests: `cargo test --workspace`
  - Release UI via CLI: `cargo run -p cli`
  - Install dev build: `./script/install-linux` (puts `zed` in `~/.local/bin` and installs desktop files)

- Packaging requirements:
  - Build `crates/cli` and provide it on `PATH` as **`zed`**
  - Build `crates/zed` and install it as **`libexec/zed-editor`** (or `lib/zed/zed-editor`)
  - Use `crates/zed/resources/zed.desktop.in` + `envsubst`, rename to `$APP_ID.desktop`, and `chmod 755`
  - Set `ZED_UPDATE_EXPLANATION` to explain distro-managed updates
  - Update `crates/zed/RELEASE_CHANNEL` to `stable`/`preview`/`nightly` (no newline)

Notes:
- The docs **do not mention** “test mode,” which reinforces the suspicion that test mode is being enabled by build flags rather than by upstream defaults.

---

## Proposed minimal changes (for next iteration)
1. **Completed:** remove `--all-features` from `src_configure`
2. **Completed:** add `zed` symlink in `src_install`
3. **Completed:** add `media-libs/freetype` to `DEPEND` after audit
4. Rebuild 0.221.5 and capture diagnostics for comparison
5. Re-run `scanelf` on the 0.221.5 binaries and confirm no additional dependencies are missing