# Skill: Finalizing an overlay upgrade

Read `.agent/instructions/general.md` first. This is the shared procedure
for agents receiving an upgrade issue, not a new executable finalizer.

## Select the package procedure

Read the issue's package-specific skill before changing files:

| Package | Procedure |
| --- | --- |
| `media-gfx/d2` | `.agent/skills/update-d2.md` |
| `media-gfx/d2-mcp` | `.agent/skills/update-d2-mcp.md` |

For other packages, use the skill referenced by the issue. Do not interpret
empty Cargo fields or `rust_min_ver: null` as proof that a Go upgrade needs
no work. Go archive preparation and Rust crate inspection are different
lifecycles, and neither automatically audits statically linked licenses.

## Hosted handoff

1. Read the issue report and check out the target repository revision.
   Mechanical edits from the detection job are not committed. Rerun the
   exact package/version command in the issue to reproduce them.
2. For D2, check `go_deps.ready`, source commit, module-file hashes, archive
   SHA256, and the published versioned asset URL. The workflow prepares the
   archive before handoff; normal upgrade preparation refuses missing or
   source-mismatched assets before copying an ebuild. Do not replace an
   existing asset or bypass checks to make Manifest generation succeed.
3. Follow the package skill for intelligent changes across the ebuild,
   patches, metadata, dependency licenses/notices, and verification inputs.
   For D2 inspect `go_min_ver` and `go_modules_changed`; for MCP review the
   selected `Cargo.lock`, crates, minimum Rust version, and patch status.
4. Generate Manifest only after all required source assets are available.
   Use `scripts/manifest.sh`, `scripts/lint.sh`, and `scripts/test-build.sh`
   as specified by the package procedure. Do not run Gentoo tools on the
   host, install tools ad hoc, or treat mock tests as source-build validation.
5. Report exact commands/results and unresolved blockers. Follow the task's
   authorization for publishing, commits, pushes, and PR creation. An
   upgrade issue does not authorize auto-merging or silent asset replacement.

## Image publication is a prerequisite, not a hidden side effect

Go preparation uses the existing headless Rust image. The hosted workflow
pulls it, pins its digest, and compares its recorded source Containerfile
against the checkout before generating anything. Go must already be in the
image and satisfy the selected release with `GOTOOLCHAIN=local`.

If that gate fails, arrange an authorized completion of the existing
`publish-testenv.yml` -> `publish-testenv-rust.yml` chain, or the existing
Rust-image manual rebuild. Do not add another image family, dispatch builds
without authorization, install Go in the runner, or download a toolchain.
Retry archive preparation only after the correct image is available.

## Local CLI guard and supported maintenance path

The actual local finalizer is `scripts/agent-finalize-ebuild.sh`, not this
Markdown file. Its agent prompt expects one edited ebuild and uses
Cargo-specific no-change criteria. D2/MCP require archive readiness and
multi-file license/patch review, which cannot safely fit that response.

The CLI therefore rejects `media-gfx/d2` and `media-gfx/d2-mcp` before calling
upgrade preparation or Copilot. This includes `--dry-run` and reports passed
with `--json`; the latter are checked before ebuild-path resolution or edits.
It prints the appropriate package skill and, for D2, the shared container
archive generator. This is an intentional safety guard, not an automated
multi-file finalizer. The existing Zed path is unchanged.

For D2/MCP, follow the package procedure and normal agent-driven multi-file
review using the same `scripts/manifest.sh`, `scripts/lint.sh`, and
`scripts/test-build.sh` container helpers as other packages. Prepare D2's
archive with `scripts/prepare-go-deps.sh` in the existing headless Rust image.
Local generation does not publish, and the finalizer guard does not make an
unpublished asset ready. Do not bypass the guard with a misleading package
name or an edited report, and do not silently replace published assets.
