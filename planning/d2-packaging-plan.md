# D2 and D2 MCP packaging plan

## Purpose and status

Capture the decisions, research, and remaining work from the D2 packaging
conversation so another session or workstation can resume after a reboot.
Implementation and local container validation are complete. Publication and
hosted execution remain pending, as detailed below.

- Planning date: 2026-10-23.
- Working branch: `add/d2-and-d2-mcp`, created from local `main` at
  `985394f` (also `origin/main` at the time).
- The unrelated Hermes work is safely committed and pushed on
  `update/hermes-agent-0.22.2`, commit `d7f1015`. Do not merge that checkpoint
  into this branch or modify it as part of this project.
- Implemented `media-gfx/d2/d2-0.9.0.ebuild` and
  `media-gfx/d2-mcp/d2-mcp-0.1.0.ebuild`, metadata, Manifests, and notices.
- Both packages are registered for automatic upgrades. Local and CI routing,
  package skills, Go archive generation, and hosted preparation are wired.
- Source builds, source tests, full Portage installation, and real CLI/MCP
  rendering passed locally. See the validation record below.
- The initial plan was committed and pushed as `012e091`. Implementation
  changes remain local until explicitly committed/pushed.
- **External-use blocker:** the initial dependency asset and Go-enabled GHCR
  image have not been published. Normal fresh remote builds need that asset;
  successful local builds used preseeded distfiles. Hosted execution and
  real-workstation installation have not been tested.

## User requirements and agreed direction

This is our personal Gentoo overlay, maintained for our own computers.
Use normal Gentoo source packaging and installation practices, while keeping
maintenance proportional to that purpose. The practical goal is successful
source builds and correctly installed, efficient, current executables that
will also build on the user's real Gentoo workstations.

Do not turn this work into a general-purpose packaging framework, elaborate
security-testing project, or one-container-per-ebuild design. Add focused
checks that give confidence in builds, installation, and integration.

The user previously built/installed D2 outside Portage under `~/.local/bin`
on another machine and reported that it worked. That was an experiment, not
the installation layout for these packages. The exact tested version and
commands were not established. Pasted background mentioned both the upstream
installer and `go install`; do not infer which produced that binary.

### Maintainer notes

The user's normal home for nontrivial package-maintenance notes is
`/home/elias/Documents/Notes/gentoo/ebuilds/`. Use one combined D2/D2 MCP note
for integration details, unusual packaging/upgrade requirements, and roadmap
items; do not fill it with trivial standard Gentoo instructions.

The user added `Notes/` as a workspace root and requested writing these notes
there. The combined note is `Notes/gentoo/ebuilds/d2-and-d2-mcp.md`; the former
in-repository draft has been moved there. Follow the Notes root's `AGENTS.md`
when editing it. Preserve unrelated Notes changes and do not commit them.

### Package locations

Both packages belong under `media-gfx/`:

- `media-gfx/d2`, upstream `https://github.com/d2lang/d2`, installs
  `/usr/bin/d2`.
- `media-gfx/d2-mcp`, upstream `https://github.com/Stranmor/d2-mcp-rs`,
  installs `/usr/bin/d2-mcp`.

`d2-mcp-rs` is the upstream repository name; its Cargo package/executable is
`d2-mcp`. Confirm this when implementing the selected tagged release.
The earlier suggestion of `dev-util/` is superseded by the agreed shared
`media-gfx/` location.

### Source builds and installation

- Use EAPI 8 and the existing `gentoo` master repository.
- Build both application executables from source, not upstream binary assets.
- Inherit `go-module` for D2 and use the established Cargo ebuild conventions
  for D2 MCP. Initially target the overlay's tested `~amd64` environment.
- Declare all build/runtime dependencies even when container images already
  contain them. Image contents are an optimization, not dependency metadata.
- Stage files with standard ebuild helpers; let Portage own installation,
  collision handling, stripping/debug information, upgrades, and removal.
- Install the D2 manpage and relevant documentation/notices. Do not run the
  upstream host installer or install into any user's home directory.
- Do not blindly copy upstream release flags that pre-strip debug information
  or unnecessarily restrict normal Portage behavior. Respect applicable
  Gentoo Go/Rust settings; avoid speculative optimization changes.
- An old `~/.local/bin/d2` can shadow `/usr/bin/d2`; mention checking
  `command -v d2` when validating on the user's workstation.

## D2 release, capabilities, and dependency handling

### Research baseline

The latest release observed during research was D2 `v0.9.0`:
`https://github.com/d2lang/d2/releases/tag/v0.9.0`.
Recheck upstream before implementation if time has passed.

The inspected tag:

- Declares module path `github.com/d2lang/d2` and Go `1.27.0` in `go.mod`.
- Uses version injection at `github.com/d2lang/d2/lib/version.Version`.
  Match upstream's expected version representation when implementing.
- Builds its official CLI with CGO disabled.
- Contains a manpage under `ci/release/template/man/`.
- Has developer/release orchestration that initializes a Git submodule;
  build the CLI directly rather than invoking that orchestration unnecessarily.
- Bundles Dagre, ELK, and now open-source TALA layout engines.
- Provides native SVG, PNG, GIF, PDF, and PPTX export; its documented module
  graph does not require browser/Node/Java runtime tooling for these features.

Dagre is the general-purpose directed-graph layout, ELK provides additional
layout capabilities for complex/nested/port-oriented diagrams, and TALA is
oriented toward software architecture diagrams. Layout controls placement;
SVG/PNG/PDF controls the output representation. These are runtime choices.

Retain the bundled layouts and exporters. The user agreed that `mcp` is the
only additional feature USE flag needed. Do not introduce layout or format
flags without a real supported build/dependency distinction. Optional test
metadata should follow normal eclass conventions where applicable.

### Go dependency archives: decision and rationale

The user approved adopting dependency tarballs now, following the current
Gentoo `go-module` direction.

Go does have source dependencies even though a direct `go install` downloads
them automatically. Examples in the selected release include layout modules,
`fsnotify`, `pflag`, `fpdf`, text shaping, and image-processing libraries.
They generally compile into the executable; they do not need individual
Gentoo ebuilds or separate runtime installations.

Fetching individual modules through Portage is technically possible and is
analogous to Rust crate fetching. The `EGO_SUM` mechanism implements this,
but the inspected `go-module.eclass` explicitly warns that it is deprecated,
asks for migration to a dependency tarball, and warns of a future fatal error.
A tarball is a current Gentoo eclass recommendation, not a Go language
requirement. Do not revive the earlier claim that individual fetching is
technically impossible.

Planned release process:

1. Fetch/check out the exact D2 source release in a disposable Gentoo container.
2. Use the required Go toolchain to prepare the pinned dependency sources and
   module metadata, including what the selected build/tests actually need.
3. Produce a `go-module`-compatible dependency archive. The documented eclass
   pattern uses a module cache rooted at `go-mod/` and `go mod download
   -modcacherw`, then archives that cache. Verify the exact eclass behavior
   available in the test environment rather than guessing the layout.
4. Publish the archive as a versioned GitHub release asset in this overlay
   repository, following its existing archive-hosting pattern.
5. Have the ebuild fetch upstream tagged source plus that dependency archive
   through `SRC_URI`; generate Manifest hashes for both.
6. Compile from prepared sources without downloading additional modules or a
   replacement Go toolchain.

Do not commit vendor/module trees or archives into Git. Choose and document
an asset/tag naming convention during implementation. Keep published assets
immutable: reuse a verified matching asset, or explicitly version a changed
archive rather than silently replacing an asset and invalidating hashes.
Use the same archive-generation implementation locally and in automation.

## MCP implementation and integration

### Selected implementation

The user selected `Stranmor/d2-mcp-rs`, not `i2y/d2mcp`.
The latest release observed was `v0.1.0`:
`https://github.com/Stranmor/d2-mcp-rs/releases/tag/v0.1.0`.

Source inspection of that tag found:

- MIT project license and a Cargo lockfile; no embedded D2 dependency.
- A Rust 2024 crate. A toolchain file pins Rust `1.93.1`, but Cargo does not
  declare `rust-version`; the pin is not proof of the actual minimum Rust.
- Subprocess execution of `d2` from `PATH`, overridable with
  `D2_MCP_D2_BIN`. Document `/usr/bin/d2` for deterministic local configuration.
- MCP stdio transport, with rendering, validation, formatting, status, and
  layout/theme discovery. Layout selection is forwarded to D2.
- The packaged pair passed actual stdio integration using installed D2 0.9.0:
  initialize, tool discovery, renderer status, and SVG/PNG renders. Keep testing
  our exact pair on upgrades rather than relying on upstream's older D2 CI.

Desired architecture:

```text
Editor / AI agent -> /usr/bin/d2-mcp -> /usr/bin/d2
```

D2 MCP must depend on the installed D2 CLI, not build a second D2 renderer.
The user explicitly rejected the older embedded-library mismatch.

### Package relationship and USE flag

- Add a default-enabled `mcp` flag (`IUSE="+mcp"`) to `media-gfx/d2`, as
  explicitly requested by the user. Also validate the `-mcp` configuration.
- `media-gfx/d2-mcp` has an appropriate runtime dependency on `media-gfx/d2`.
- Use D2's conditional `PDEPEND` for the optional MCP package to avoid a
  normal dependency cycle. Validate actual Portage resolution/install order.
- Each ebuild owns/builds its own executable; D2's ebuild must not install the
  MCP package's files itself.
- Use stdio for the local editor/agent integration. Do not automatically start
  a network daemon or alter users' editor configuration.
- The inspected upstream `v0.1.0` entry point serves stdio. No daemon, OpenRC
  script, or systemd unit is required. Do not track additional transports as
  a roadmap item; the user does not need them.

### PDF gap: deferred roadmap item, not a first-version requirement

The user explicitly chose to get the initial packages working without a PDF
patch. Package the upstream MCP server unchanged: it exposes SVG and PNG.
D2 itself retains its native PDF exporter, usable through the CLI. Do not
remove existing SVG or PNG support and do not make MCP PDF support a blocker.

A future focused MCP PDF-file extension may be considered if needed. No patch
has been written or tested. A recheck found that current upstream main still
accepts only Svg/Png, the latest observed release remains v0.1.0, and scoped
GitHub searches found no PDF-related PR, issue, or commit. Do not claim this
proves no fork contains such a change. Recheck upstream before writing one.

For the future roadmap, the source-reviewed minimal extension would:

- Add `Pdf` to `D2OutputFormat` and its extension mapping in `src/lib.rs`.
- Include it in status-advertised formats; Serde/Schemars derives update the
  relevant schemas.
- Pass `--stdout-format pdf` through the existing invocation structure.
- Reuse format-independent file reading, size checks, hashes, and reporting.
- Update the tool description in `src/mcp.rs`, documentation, and tests.

The existing rendering result is JSON containing an output file path and
metadata, optionally inline SVG text. It does not transmit PNG image bytes
or expose a resource-reading service. A minimal PDF extension would likewise
return a server-local file path, not automatically deliver PDF bytes to a
remote client. Local use is the intended initial scope. Do not expand this
into an artifact-delivery protocol unless requested.

The wrapper's timeouts/path checks are not a filesystem/network sandbox.
Do not market them as one or expand packaging into a security-hardening
project. Normal local stdio usage runs with the invoking user's permissions.

### Rejected alternatives

- `i2y/d2mcp v0.5.0` embeds `oss.terrastruct.com/d2 v0.7.0`, hardcodes Dagre
  rendering, and uses external `rsvg-convert`/ImageMagick for PNG/PDF.
  Installing D2 0.9.0 would not upgrade its internal renderer.
- `kasey-purvor/mcp-d2-diagrams` invokes the CLI but hardcodes
  `~/.local/bin/d2`, limits layout selection, and had no license found.
- A Typst/D2 MCP alternative was substantially broader than this requirement.

## Licensing

Audit both binaries' statically linked dependencies and embedded assets,
not only the projects' MPL-2.0/MIT licenses.

Existing overlay conventions:

- `licenses/` exists, and `metadata/layout.conf` declares `masters = gentoo`.
- Standard license texts inherited from Gentoo do not need duplicating here.
- Existing Rust packages declare dependency licenses alongside the project
  license; see `app-editors/zed/zed-1.24.2.ebuild` and the agent-browser package.
- Add an overlay license file only when a required text is not supplied by
  the master repository.
- Correct `LICENSE` metadata and installation of required license/copyright
  notices are distinct responsibilities.

D2 supplies `THIRD_PARTY_NOTICES.txt`; include the relevant notices and account
for embedded fonts as well as Go modules. Regenerate/review the Rust crate
license list for MCP upgrades. Do not guess a complete license expression
from project-level license names alone.

## Containers: final agreed design

**Extend `containers/testenv-rust/Containerfile` with Go. Do not add a new
container family and do not use the Rust desktop image for these packages.**

The existing headless Rust image has AI/CUDA/NVIDIA dependencies. It is
heavier than D2 needs, but already maintained. The user prioritizes reuse and
a small number of environments over optimizing image size for each package.
The earlier dedicated `testenv-diagrams` recommendation is superseded.

- Add Go as a layer in the existing Rust Containerfile, using Portage.
- Follow existing Rust toolchain conventions; using a Portage-managed binary
  compiler in the test image does not change the requirement to build the two
  application executables from source.
- Update comments/descriptions to reflect Go and headless Rust use; do not
  rename/refactor existing environments unnecessarily.
- Do not bake D2/MCP executables into the image: build the selected overlay
  versions during testing, including D2 when testing the MCP runtime dependency.
- Reuse the existing image publishing workflow/chain.
- Route both packages to the same image in local and CI selection logic.
- Use that image for dependency-archive generation as well.

The base `containers/testenv/Containerfile` currently disables network, IPC,
PID, and user sandbox features because of container namespace limitations.
The user permits enabling features if needed, but the goal is practical
confidence that source builds succeed on real Gentoo systems, not an
elaborate sandbox test program. Do not disable sandboxing in the ebuilds.
Where available, test with normal protections; where unavailable, be honest
about that limitation. In any case, enforce prepared/offline Go compilation
and use the declared toolchain (for example `GOPROXY=off` and
`GOTOOLCHAIN=local` during compilation, as appropriate for the eclass).

## Existing self-maintenance architecture and required integration

The actual system is registry-driven detection -> mechanical preparation ->
agent issue handoff -> agent PR -> container lint/build -> review. It is not
an unattended deterministic upgrade-and-merge pipeline.

### Upstream detection and upgrade handoff

- `.agent/packages.json`: upstream repository, version pattern, build system,
  `auto_upgrade`, and maintenance notes.
- `.github/workflows/ci-version-check.yml`: Thursday/Sunday 06:00 UTC checks
  and manual dispatch; calls `check-upstream-versions.yml`.
- Only `update-available` packages with `auto_upgrade: true` enter its upgrade
  matrix. New-package detection does not scaffold a first ebuild.
- `.github/workflows/upgrade-ebuild.yml`: runs `scripts/upgrade-ebuild.sh`,
  creates an upgrade issue with structured output/ebuild contents, and assigns
  Copilot. Mechanical output is not committed by that workflow; the agent
  reruns preparation, finishes changes, and opens the PR.
- `scripts/upgrade-ebuild.sh`: has Cargo-specific inspection and a generic
  version-copy path for other build systems. A new Go registry value alone
  will not generate an archive or review dependencies.
- Cargo inspection does not regenerate `CRATES` from Cargo.lock or audit all
  dependency licenses automatically. The MCP procedure must cover those tasks.
- `repackage: true` is not currently a generic executable hook.
- `.github/workflows/repackage-surge.yml` demonstrates overlay GitHub release
  asset hosting, but is package-specific; its manual publication path is not
  an existing generic Go dependency-archive lifecycle.
- The generalized repackaging described in `planning/workflow_master_plan.md`
  is planned functionality, not something to assume already exists.

Add focused D2 archive-generation/publication integration to this flow, with
explicit ordering before Manifest generation. Add package-specific upgrade
procedures and wire them into the actual agent handoff/skill lookup, which
currently recognizes only selected existing packages. Include Go minimum,
module/archive regeneration, licenses, and MCP patch maintenance. Reuse the
same generation script from local and hosted entry points.

Register both GitHub-release packages and enable `auto_upgrade: true` once
both have been built/tested and their upgrade paths validated, as explicitly
requested by the user. Temporary `auto_upgrade: false` during bring-up still
allows release detection/manual handoff; it is not the intended final state.
No user decision authorizes auto-merging. Keep shared automation changes
narrowly scoped.

### CI verification

- `.github/workflows/ci-lint.yml` -> `lint-ebuild.yml`: QA on package-changing
  PRs and pushes to main, in the base Gentoo test image.
- `.github/workflows/ci-build.yml`: changed-package builds gated by PR label
  `build-test`, with automatic labeling for Copilot-authored ebuild PRs; also
  supports manual package/image/verify selection.
- `.github/workflows/test-ebuild.yml`: installs declared dependencies, runs
  `ebuild clean compile install`, uploads build logs, and invokes the supplied
  verification script against the staged installation image.
- That build path does not automatically execute all upstream tests or prove
  a full target-package merge. Add only the focused checks we need.
- CI image/verify routing is explicit. Merely adding a verification file will
  not make CI discover it.

### Local maintenance and shared images

- `scripts/check-updates.sh`: local release detection.
- `scripts/upgrade-ebuild.sh`: mechanical preparation.
- `scripts/agent-finalize-ebuild.sh`: separate local agent-assisted finalizer;
  not the hosted workflow. Review its limitations before using for multi-file
  or archive-publication tasks.
- `scripts/manifest.sh`: `pkgdev manifest` in the base Gentoo container, with
  the repository mounted writable so Manifest changes persist.
- `scripts/lint.sh`: pkgcheck in the base Gentoo container.
- `scripts/test-build.sh <category/package> <ebuild-file> [--no-clean]`:
  declared dependency installation, compile/staged install, optional verify.
  It accepts `USE` from the environment.
- Wrappers prefer Podman, fall back to Docker, and prefer locally built images
  over the corresponding GHCR image. Gentoo tools are not needed on the host.
- Local and CI package/image/verify routing are duplicated and must both be
  updated for these packages. They are similar, not a single shared executor.
- The base image is published weekly; derived-image workflows run afterward.
- `.devcontainer` is Ubuntu tooling for agents, not the Gentoo build target.

Known nearby issues observed during research, not authorization for a broad
cleanup:

- The local lint wrapper failed while checkpointing Hermes because pkgcheck
  rejected the negative `--profiles` argument as missing a value. CI's lint
  arguments differ. Address the blocker if encountered during this work,
  rather than assuming lint passed or refactoring unrelated infrastructure.
- Local Zed verify routing differs from CI; do not fix unrelated packages as
  part of the D2 task.
- Scheduled hosted detection and local detection have some support differences;
  the selected packages use ordinary GitHub release tags, so avoid unrelated
  detector rewrites.

## Implementation checklist

1. [x] Read instructions, preserve the Hermes branch and unrelated Notes work.
2. [x] Verify tagged sources, compiler requirements, binary names, and licenses.
3. [x] Build the appended Go layer on the existing headless Rust image.
       Full CUDA-heavy rebuild and GHCR publication remain pending.
4. [x] Implement shared containerized Go generation and immutable publication
       workflow. Real generation passed; publication contract tested with mocks.
5. [x] Add D2 ebuild/metadata/Manifest and register `media-gfx` category.
6. [x] Add source-built MCP, 94 crates, notices, metadata, and Manifest.
7. [x] Add default `+mcp`, conditional `PDEPEND`, and MCP runtime D2 dependency.
8. [x] Wire local and CI Rust/Go image routing and both verification scripts.
9. [x] Build both sources offline, with normal sandboxes enabled.
10. [x] Validate full `emerge`, default `+mcp`, `-mcp`, and installed ownership.
11. [x] Pass Dagre/ELK/TALA SVG/PNG/PDF and installed MCP SVG/PNG rendering.
12. [x] Register automatic upgrades, package skills/handoff, and README entries.
        Local lifecycle tests passed; live hosted handoff is still untested.
13. [x] Record results and maintenance caveats here and in the Notes document.
14. [ ] Commit/push implementation after authorization.
15. [ ] Publish Go-enabled GHCR image and initial dependency assets.
16. [ ] Verify public distfile bytes, fresh remote fetch, and hosted workflows.
17. [ ] Install on an actual Gentoo workstation when the maintainer is ready.

## Local validation and release handoff

Validation date: 2026-10-23. Toolchains: Go 1.27.1 and Rust/Cargo 1.98.1.

- Built the exact appended Go layer with Portage on the existing Rust image.
  `localhost/adaptive-overlay-testenv-rust:local` now points to that tested
  toolchain-only image, also tagged `:d2`. It contains no D2/MCP applications.
- Refreshed `localhost/adaptive-overlay-testenv:local` from the already-pulled
  GHCR base snapshot. The previous local tree was stale and could not resolve
  the Go minimum during lint. Both normal package lint wrappers now pass.
- Two real fresh-cache Go archive generations produced identical bytes:
  `fa6262731f1f94f1ae3e992262beba0ae22edc26a7eaf347d24a694f7325190d`.
  Archive/provenance are under `/home/elias/tmp/d2-work/distfiles/`.
- Local Manifest generation used the verified source/archive cache, not an
  already-published URL. The committed `SRC_URI` remains the intended public URL.
- D2 source `ebuild clean compile test install` passed, including 16 selected
  offline Go packages, 133 top-level tests, and 5,014 passing test/subtest
  invocations. One upstream sequence-diagram case skips intentionally.
  Module files and all 3,276 shipped testdata files remained unchanged.
- MCP source compilation and all six library unit tests passed. Its separate
  integration verifier requires actual installed D2 rather than silently
  skipping like upstream's test can.
- Full source `emerge` installed `/usr/bin/d2` then `/usr/bin/d2-mcp`, with VDB
  ownership verified. Clean `-mcp` resolution selected D2 alone.
- All nine CLI layout/format combinations passed, staged and installed;
  MCP initialize/status/discovery and actual SVG/PNG artifacts passed too.
- The unstripped D2 binary retained Go-pdf symbols but no checked Graphics
  Gems/Grid routines. Supplemental font, Unicode, layout, and module notices
  were installed. No new global license definitions were necessary.
- All five Portage sandboxes were enabled, with `userpriv` and `strict`, while
  container networking was disabled. Namespace setup needed `SYS_ADMIN` and
  `seccomp=unconfined`; loopback-configuration warnings did not fail builds.
  These local permissions are not encoded as ebuild sandbox restrictions.
- Initial global D2 testing exposed upstream Makefile helper requirements.
  The final ebuild's explicit offline `src_test` avoids that target and passes;
  its standard `test` flag declares Git for the fixture diff helper.
- 27 offline lifecycle regressions passed, including mocked release publication,
  source/provenance mismatches, handoff ordering, and local finalizer guards.
  Live read-only checks report both packages up to date. Hosted execution,
  token permissions, publication, and real-workstation behavior remain untested.

The legacy local ebuild-only finalizer intentionally rejects D2/MCP before
mutation and points to the package procedures. It cannot safely review the
multiple source/license files needed here. Hosted handoff loads the shared
and package-specific procedures instead; failed Go readiness blocks handoff.

Useful retained local integration artifacts:

- `/home/elias/tmp/d2-work/ebuild-test-validation/`: D2 test/build/render logs
  and retained Portage work/staging tree.
- `/home/elias/tmp/d2-mcp-work/integration/`: exact invocation in `HANDOFF.md`,
  `results/report.json`, resolver/build/render logs, and preseeded distfiles.
- `d2-mcp-emerge-integration`: exited-successfully integration container.
- `localhost/adaptive-overlay-testenv-rust:d2-mcp-integrated`: scratch-only
  integration image with installed applications, **not** the normal toolchain
  image and not an image to publish as the maintained test environment.

After authorized commit/push, publish the normal Rust/Go image through the
existing workflow, then run `prepare-go-deps.yml` for `0.9.0`. Its gate checks
published image source provenance. Verify resulting archive bytes against
this Manifest before fresh-fetch/hosted tests. Never replace differing bytes
silently or claim the currently unpublished package is remotely fetchable.

## Safety and scope reminders

- Never install packages/toolchains on the host; run Gentoo operations and Go
  module preparation in the prescribed disposable containers.
- Never run sudo or modify host system files. Follow repository safety rules.
- Stay inside the repository, using `/home/elias/tmp/` only for allowed scratch.
- Keep only normal overlay content in package directories: ebuilds, Manifest,
  metadata.xml, and necessary `files/` contents. Plans belong in `planning/`.
- Preserve unrelated user work. Do not commit, push, publish assets/images,
  dispatch workflows, or open a PR without the applicable user authorization.
- The user subsequently authorized implementation, but not an automatic
  commit, push, publication, workflow dispatch, PR, or merge.
