# Skill: Updating D2 MCP

Read `.agent/instructions/general.md` first. Never install host tools, run
sudo, or publish/commit anything without authorization.

- Package: `media-gfx/d2-mcp`, executable `/usr/bin/d2-mcp`.
- Upstream: `Stranmor/d2-mcp-rs`, Cargo package/binary `d2-mcp`.
- Initial release: `v0.1.0`, commit
  `87186697cc9fedc6e84b09ace443c039fa16de79`.
- Source-build with EAPI 8 and `cargo.eclass`; initially `~amd64`.
- Runtime: `>=media-gfx/d2-0.9.0`. D2 is not embedded in this server.
- Integration: local stdio only, vanilla upstream SVG and PNG. No PDF
  patch, daemon, service unit, editor configuration, or automatic startup.
- D2's default-enabled `mcp` USE flag and conditional `PDEPEND` belong to
  `media-gfx/d2`, not this ebuild. Keep D2 out of MCP's build dependencies.

## Upgrade procedure

1. Recheck the latest upstream release and inspect its exact tagged source,
   including `Cargo.toml`, `Cargo.lock`, `rust-toolchain.toml`, upstream CI,
   `src/main.rs`, `src/mcp.rs`, and `tests/mcp_smoke.rs`.
2. If the shared upgrade script has prepared a version bump, read its JSON
   and inspect the resulting changes. It does not regenerate `CRATES` or
   audit all licenses. Do not assume a version-copy is ready to build.
3. Fetch the source archive with existing download tools into
   `/home/elias/tmp/`. Never run upstream installers. Preserve the tagged
   lockfile; do not run an unconstrained `cargo update`.
4. Derive `CRATES` from **every registry package** in that lockfile, including
   development and non-Linux target dependencies. Omit only the local root
   package. Fail on unexpected sources; if Git dependencies appear, inspect
   them and use the overlay's `GIT_CRATES` conventions explicitly.

   Python 3.11+ can generate the list without installing anything:

   ```python
   import pathlib
   import tomllib

   lock = tomllib.loads(pathlib.Path("Cargo.lock").read_text())
   crates = []
   for package in lock["package"]:
       source = package.get("source")
       if source is None:
           assert package["name"] == "d2-mcp"
           continue
       assert source == "registry+https://github.com/rust-lang/crates.io-index"
       crates.append((package["name"], package["version"]))
   for name, version in sorted(crates):
       print(f"\t{name}@{version}")
   ```

5. Fetch the exact registry archives. Verify each archive's SHA256 against
   its lockfile `checksum` **before** unpacking/auditing or using its bytes
   for Manifest generation. Inspect normalized `Cargo.toml` license and
   `rust-version` fields, license files, notices, and copied code/assets.
6. Review compiler requirements. Upstream 0.1.0 uses Rust 2024, declares no
   `rust-version`, and pins 1.93.1 in its toolchain file and CI. The ebuild
   conservatively uses `RUST_MIN_VER="1.93.1"`; that is an upstream CI support
   baseline, **not a verified minimum compiler**. The lockfile's highest
   declared crate MSRV is 1.88.0 (`darling` and its helpers); that alone does
   not prove the server or undeclared-MSRV dependencies compile on 1.88.
   Coordinate any test-image/toolchain changes with the shared-image owner.
7. Re-audit `LICENSE` and the installed notices as described below. Update
   versioned files and remove obsolete ones only after reviewing all ebuilds
   that reference them. Do not copy a stale notices file into a new version.
8. Generate the package Manifest, lint, and build using the established
   container wrappers after their D2/MCP routing is present:

   ```sh
   scripts/manifest.sh media-gfx/d2-mcp
   scripts/lint.sh media-gfx/d2-mcp
   scripts/test-build.sh media-gfx/d2-mcp d2-mcp-0.1.0.ebuild
   ```

   Substitute the actual new ebuild filename. The Rust test image must have
   the declared compiler and installed runtime D2. Do not work around a
   missing toolchain with ad-hoc package installs. If the shared manifest
   wrapper is unavailable, a thin Manifest can be generated from verified
   downloaded bytes with their exact distfile names, sizes, BLAKE2B and
   SHA512 hashes. Report that fallback and independently check coverage.
9. Exercise upstream unit tests with the ebuild `test` phase. The ebuild runs
   `cargo_src_test --lib`: six pure unit tests in 0.1.0. The upstream MCP
   integration test silently skips without D2, so its success alone is not
   proof of runtime integration.
10. Run `containers/testenv-rust/verify-d2-mcp.sh <staged-image-directory>` in
    the test container. It invokes the **staged** MCP executable directly
    and the **installed** `/usr/bin/d2`, never a staged or PATH-shadowed D2.
    Missing runtime D2 is a failure, not a successful skip. The script uses
    Python 3 from the base image; Python is not an MCP runtime dependency.
    It checks initialize/version, initialized notification, six tools,
    renderer status, then real SVG and PNG renders and artifact hashes.
    Requests, renderer execution, and process shutdown have bounded waits.
    Keep this a small smoke test, not a broad testing framework.
11. Have the integration owner validate D2's `+mcp`/`-mcp` dependency
    resolution and actual package installation. Report exact commands and
    results, distinguishing source/staging validation, installed runtime
    validation, upstream compiler policy, and tested compiler versions.

## Initial license audit

All 94 registry archives in 0.1.0's Cargo.lock were fetched and SHA256-checked
against the lockfile. MIT is chosen wherever offered, including alternatives
in `rustix`, `linux-raw-sys`, `r-efi`, and `memchr`. The resulting code/data
license set is `MIT Apache-2.0 BSD-2 CC0-1.0 Unicode-3.0`.

Important exceptions to crate-level metadata:

- `rmcp` and `rmcp-macros` 1.8.0 declare Apache-2.0 but omit their repository
  LICENSE. Both `.cargo_vcs_info.json` files identify rust-sdk commit
  `25220361d5540715294c501c289d79de4bec2bfc`. The verbatim root LICENSE is
  preserved in `files/rmcp-1.8.0-LICENSE`, including its MIT/Apache transition
  notice. SDK documentation under CC-BY-4.0 is not installed as package docs.
- `rmcp/src/model/extension.rs` identifies copied MIT code from
  `hyperium/http`. Its notice is supplied in
  `files/rmcp-1.8.0-http-LICENSE-MIT`, copied from upstream tag `v1.3.1`.
- `futures-channel/src/mpsc/queue.rs` has a BSD-2 header, despite the crate's
  MIT/Apache metadata. `rustix/src/backend/linux_raw/vdso.rs` identifies CC0
  code. `schemars/src/_private/regex_syntax.rs` contains a copied MIT notice.
  These source-header notices and provenance are retained in
  `files/d2-mcp-0.1.0-embedded-notices.txt`.
- `unicode-ident` additionally requires Unicode-3.0. Its `LICENSE-UNICODE`
  must be retained even when choosing MIT for its other code.
- The installation phase preserves crate license/copyright/notice files
  recursively under the package's documentation `licenses/` directory,
  including `tracing-core/src/spin/LICENSE`. Do not flatten these files or
  silently omit nested licenses. All fetched target/build/dev crate notices
  are retained conservatively, rather than guessing which files survive LTO.

Standard license definitions are inherited from Gentoo; no overlay-global
license files are needed. Declaring `LICENSE` does not replace installing
required notices with binary packages.

## MCP framing and local configuration

The locked `rmcp` async-rw stdio codec uses one JSON-RPC message per newline,
not LSP `Content-Length` framing. Send `initialize`, wait for its response,
then `notifications/initialized` before `tools/list` or `tools/call`.
The renderer returns metadata and a server-local output path, optionally
inline SVG, not PNG image bytes or a file-reading service.

For deterministic editor configuration, use command `/usr/bin/d2-mcp`,
`D2_MCP_D2_BIN=/usr/bin/d2`, and a writable `D2_MCP_WORKDIR`. No network daemon
is needed. These path checks and timeouts are not a filesystem/network
sandbox; the subprocess runs with the invoking user's permissions.
