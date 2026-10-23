# Skill: Updating D2

Read `.agent/instructions/general.md` first. D2 is `media-gfx/d2`,
upstream `d2lang/d2`, registry build system `go`. Build the tagged Go
source, not an upstream binary release. Use the existing headless
`testenv-rust` image with Go, never the desktop image or a new image family.
Do not install Go or download modules/toolchains on the host.

## Release and archive contract

The initial source baseline is `v0.9.0`, whose tagged `go.mod` declares
module `github.com/d2lang/d2` and Go `1.27.0`. Recheck the exact target
release, its `go.mod`/`go.sum`, and release notes on every upgrade. Do not
assume future Go requirements, source features, licenses, or flags match it.

For version `X.Y.Z`, the immutable overlay release contract is:

- Release tag: `d2-deps-X.Y.Z`
- Dependency asset: `d2-X.Y.Z-go-deps.tar.xz`
- Provenance asset: `d2-X.Y.Z-go-deps.json`
- Ebuild download URL, under this overlay's GitHub repository:
  `releases/download/d2-deps-X.Y.Z/d2-X.Y.Z-go-deps.tar.xz`

The archive contains a module cache rooted at `go-mod/`, matching
`go-module.eclass`'s `GOMODCACHE=${WORKDIR}/go-mod`. It contains dependency
sources and metadata, not a D2 binary, vendor tree, or replacement Go
compiler. Do not add `EGO_SUM` or fetch Go modules during Portage compilation.

A published archive from one source release **cannot be substituted
silently**, even if upstream moves its tag or Go accepts equivalent module
zip contents. Existing matching archive/provenance bytes may be reused.
Different bytes require an explicitly versioned new packaging asset and
reviewed `SRC_URI`/Manifest changes. Never delete/reupload or use `--clobber`
to repair a mismatch. The focused generator does not automate that exception.

## Prepare before Manifest or agent handoff

The same script is used locally and by `prepare-go-deps.yml`:

```bash
scripts/prepare-go-deps.sh media-gfx/d2 --version X.Y.Z \
    --output /home/elias/tmp/d2-deps-X.Y.Z
```

`--output` is a directory, inside this repository or `/home/elias/tmp`.
It receives the archive and JSON sidecar. Prefer the scratch location above;
never stage generated archives/caches in Git or put helpers in package trees.
An optional `--image IMAGE` selects a specific headless Rust image. Otherwise
Podman (preferred) or Docker uses the local image if present, then
`ghcr.io/faraclas/adaptive-overlay/testenv-rust:latest`.
`GO_DEPS_RUNTIME=podman|docker` explicitly selects the runtime; hosted runs
select Docker so registry authentication, image inspection, and execution
use the same image store.

The wrapper mounts the repository read-only and the output directory writable,
using the invoking user's UID/GID. Generation/network downloads happen only
inside that disposable container. The private `--in-container` entry point
is not a local execution mode. There is no host Go or host `gh` requirement.

The generator fetches the exact `refs/tags/vX.Y.Z`, sets
`GOTOOLCHAIN=local`, uses a fresh cache, and follows the eclass's documented
`go mod download -modcacherw` scope with checksum verification. Do not append
`all`: that expands downloads beyond root build/test needs and adds 26
`go.sum` entries for D2 `v0.9.0`. The generator runs `go mod verify` and
resolves the root module's packages/tests with readonly mode and `GOPROXY=off`.
It refuses changes to `go.mod`/`go.sum`, reporting the diff and failing stage.
It removes download-time sumdb/lock state, sorts proxy version lists, and
uses sorted GNU tar entries, epoch zero, numeric UID/GID zero, normalized
permissions, and single-threaded xz compression. The sidecar
records the source commit, module-file hashes, and archive SHA256.

If the image's Go is too old, stop and arrange an image rebuild. Do not enable
automatic toolchain download or install packages ad hoc. If dependency
resolution fails, investigate the pinned graph, required build/test scope,
and upstream changes rather than publishing an incomplete cache.

Image publication must precede hosted archive preparation. The workflow
pulls the existing headless Rust image, pins its digest, and checks that its
OCI source revision has the same Rust Containerfile as the checkout. A stale
or unlabelled image blocks preparation, even when a mutable `latest` exists.
The generator separately enforces the tagged source's actual Go minimum.
Arrange an authorized completion of `publish-testenv.yml` followed by
`publish-testenv-rust.yml`, or the existing Rust-image manual rebuild, then
retry. No preparation step installs Go or dispatches an image build.

Local generation does **not** publish. Once publication is authorized, the
`prepare-go-deps.yml` manual/reusable workflow generates the same files and
publishes them using `contents: write`. It verifies both existing assets
byte-for-byte and refuses mismatches. New releases are drafted, populated,
then published; interrupted drafts can be retried. Published releases missing
one of the pair require manual review, not implicit repair.

`upgrade-ebuild.yml` resolves the target without mutation, invokes the reusable
preparation workflow **only for Go upgrades**, then runs strict upgrade
preparation and creates the agent issue. Its scheduled caller must grant
`contents: write` and `packages: read` to permit publication and GHCR access.
A failed preparation must block agent handoff and Manifest generation. Do not
enable automatic upgrades in the registry until generation, upgrade ordering,
and source builds have actually passed validation. There is no automatic merge.

The hosted handoff requires `.agent/skills/finalize-upgrade.md` and this
package skill. Read both. The actual local finalizer is
`scripts/agent-finalize-ebuild.sh`; its Zed-only skill lookup and Cargo-oriented
single-ebuild prompt do not implement the D2/MCP lifecycle. Use normal
agent-driven multi-file review for these packages, not that wrapper.

## Review and finish the upgrade

1. Read the issue's report and this skill before rerunning preparation:

   ```bash
   scripts/upgrade-ebuild.sh media-gfx/d2 --version X.Y.Z --apply --json
   ```

   `--check --json` only resolves/compares versions and explicitly does not
   check sources or prepare an ebuild. Normal execution refuses a missing
   archive or provenance mismatch before copying the ebuild. Report fields
   `go_min_ver`, `go_modules_changed`, and `go_deps` describe what needs review;
   the script does not mechanically change Go dependencies or ebuild flags.
2. Verify source-tag/archive pairing and immutable release provenance. Review
   `go.mod` and `go.sum`, the selected CLI/test dependencies, bundled notices,
   and **all statically linked dependency licenses**. Update the ebuild's
   `LICENSE` and any required notices; archive generation is not a license
   audit. Review changes in patches or embedded/generated assets explicitly.
3. Match the Go minimum in declared `BDEPEND` and the headless Rust image.
   Confirm the container's actual `go version` meets it. Preserve source-only
   CLI compilation, normal Portage flags, and offline operation with
   `GOPROXY=off` and `GOTOOLCHAIN=local`. Check the test environment's actual
   `go-module.eclass`, not just an assumed extraction layout.
4. Recheck version injection at
   `github.com/d2lang/d2/lib/version.Version` and upstream's expected version
   representation. Build directly, not through the upstream host installer
   or unnecessary release/submodule orchestration. Retain bundled layouts
   and exporters, the manpage, docs/notices, and the existing `mcp`
   relationship.
5. Only after the exact source and dependency archive are published, run:

   ```bash
   scripts/manifest.sh media-gfx/d2
   scripts/lint.sh media-gfx/d2
   scripts/test-build.sh media-gfx/d2 d2-X.Y.Z.ebuild
   ```

   Test offline source compilation and focused CLI SVG/PNG/PDF output through
   the bundled layouts. Exercise package dependency resolution with and without
   `mcp`, and coordinate MCP integration using `update-d2-mcp.md`. Do not add
   browser/Node/Java dependencies without evidence from the selected release.
6. Keep the normal two most recent releases, with `9999` if present. Summarize
   source/archive versions and hashes, compiler and license changes, and exact
   validation results. Do not claim successful generation/builds from mock
   tests alone. Obtain authorization before publishing, dispatching workflows,
   committing, pushing, or opening a PR when not already authorized by the task.
