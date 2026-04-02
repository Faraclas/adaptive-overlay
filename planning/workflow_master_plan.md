# Workflow Master Plan — adaptive-overlay

## 1. Purpose & Goals

This document defines the automation strategy for the
**adaptive-overlay** Gentoo overlay repository. The overlay
provides ebuilds that are missing from other repos, track
upstream more closely, or expose additional build features.

Two primary workflows must be supported:

| Workflow | Autonomy Level | Trigger |
|---|---|---|
| **New ebuild creation** | Collaborative (agent + human) | On-demand |
| **Ebuild upgrades** | Mostly/fully autonomous | On-demand, scheduled, upstream |

Cross-cutting concerns that apply to both workflows:

* Ebuild quality checks (pkgcheck linting,
  `ebuild manifest` verification)
* Build testing via `ebuild` command inside a Gentoo
  container
* Runnable in GitHub Actions **and** locally
* Pull-request-based review for every change

---

## 2. Repository Conventions

Current repo facts that inform workflow design:

| Item | Value |
|---|---|
| EAPI | 8 |
| Masters | gentoo |
| Manifests | thin-manifests, unsigned |
| Package categories | `app-editors`, `media-sound`, `net-vpn` |
| Container images | `testenv` (base) + `testenv-rust` (Zed) + `testenv-audio` (media-sound) on GHCR |
| CI — lint | `ci-lint.yml` — pkgcheck on changed ebuilds |
| CI — build | `ci-build.yml` — opt-in build test |
| CI — versions | `ci-version-check.yml` — scheduled check |
| CI — containers | `publish-testenv{,-rust}.yml` — weekly |
| CI — repackage | `repackage-surge.yml` — Surge XT tarball |
| CI — project | `add-issues-to-project.yml` |
| Reusable | `lint-ebuild`, `test-ebuild`, `check-upstream-versions` |

---

### 2.1 File Organization — Agent vs Human Files

A Gentoo overlay has a well-defined directory structure
that humans and tools like `pkgcheck` expect. Automation
and agent-facing files should live separately from the
standard overlay tree to avoid confusion.

**Standard overlay directories** (human / Gentoo tooling):

| Path | Contents |
|---|---|
| `<category>/<package>/` | Ebuilds, Manifest, metadata.xml |
| `metadata/` | Overlay-level metadata (`layout.conf`, etc.) |
| `profiles/` | Profile configuration |
| `licenses/` | Custom license files |
| `.github/workflows/` | CI/CD workflow definitions |
| `scripts/` | Helper scripts for local development (lint, test-build, etc.) |
| `planning/` | Human-readable planning documents (this file, roadmaps, etc.) |

**Agent-facing directory** (`.agent/`):

Files that agents reference during automated tasks —
structured metadata, skills, and per-package
instructions — live in `.agent/` at the repo root:

| Path | Purpose |
|---|---|
| `.agent/packages.json` | Package registry with upstream metadata (§5.2) |
| `.agent/skills/` | Reusable agent skill documents |
| `.agent/skills/update-zed-editor.md` | Zed-specific update procedure for agents |
| `.agent/instructions/general.md` | Agent safety rules and repo conventions |
| `.agent/instructions/<cat>/<pkg>/` | Per-package upgrade/creation notes |
| `.agent/ebuild_guidelines.md` | Overlay-specific conventions for agents |

This separation keeps the overlay directory clean for human
contributors and Gentoo tooling, while giving agents a
well-known location to find structured context. The
`.agent/` prefix signals that these files are
machine-consumed and may be auto-generated or auto-updated.

> **Note:** The `.agent/` directory is committed to the
> repo so agents can access it. It is not hidden from
> humans — anyone can read and edit these files — but its
> primary audience is automated tooling.

---

## 3. Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Trigger Layer                                 │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
│  │  Manual /   │  │  Scheduled   │  │  Upstream    │  │  Issue /  │ │
│  │  Dispatch   │  │  Cron        │  │  Release     │  │  Agent    │ │
│  └─────┬──────┘  └──────┬───────┘  └──────┬───────┘  └─────┬─────┘ │
└────────┼────────────────┼────────────────┼──────────────────┼───────┘
         │                │                │                  │
         ▼                ▼                ▼                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     Orchestration Layer                               │
│                                                                      │
│  ┌─────────────────────┐      ┌──────────────────────────────────┐  │
│  │  upgrade-ebuild.yml │      │  new-ebuild.yml                  │  │
│  │  (autonomous)       │      │  (collaborative: agent + human)  │  │
│  └────────┬────────────┘      └──────────────┬───────────────────┘  │
└───────────┼──────────────────────────────────┼──────────────────────┘
            │                                  │
            ▼                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     Reusable Workflows / Actions                     │
│                                                                      │
│  ┌────────────────┐ ┌──────────────────┐ ┌────────────────────────┐ │
│  │ lint-ebuild    │ │ test-ebuild      │ │ repackage-source       │ │
│  │ (pkgcheck)     │ │ (container build │ │ (tarball creation for  │ │
│  │                │ │  + verify script)│ │  submodule projects)   │ │
│  └────────────────┘ └──────────────────┘ └────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ check-upstream-versions (version checking + issue creation)   │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
            │                  │
            ▼                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     Container / Environment Layer                    │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Gentoo Stage3 Container Image                               │   │
│  │  • Pre-synced portage tree                                   │   │
│  │  • Overlay mounted / synced                                  │   │
│  │  • Supports: ebuild, pkgdev, pkgcheck                        │   │
│  │  • Variants: testenv (base), testenv-rust (Zed/LLVM)        │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 4. Workflow 1 — New Ebuild Creation

### 4.1 Trigger

* A GitHub Issue is filed (manually or by an agent)
  requesting a new ebuild.
* The `new-ebuild.yml` workflow can also be dispatched
  manually with inputs: `category`, `package_name`,
  `version`, and `upstream_url`.

### 4.2 Steps

| # | Step | Actor | Details |
|---|---|---|---|
| 1 | **Gather metadata** | Agent | Clone/inspect upstream. Determine homepage, license, build system, deps, SRC_URI. |
| 2 | **Draft ebuild** | Agent | Generate skeleton `.ebuild` (EAPI 8) + `metadata.xml`. |
| 3 | **Lint** | CI | `pkgcheck scan` + `ebuild manifest` in container. |
| 4 | **Review** | Human | Agent opens PR, requests review, posts questions. |
| 5 | **Build test** | CI | `ebuild clean compile` in container. Agent fixes failures. `emerge` integration test in container only. |
| 6 | **Iterate** | Both | Address feedback. Repeat 3–5. Safety constraints (§8.4). |
| 7 | **Merge** | Human | Final approval and merge. |

### 4.3 Human-in-the-Loop Mechanisms

* **PR comments**: The agent posts questions as PR
  comments and labels the PR `waiting-for-human`.
* **Issue threads**: For broader design decisions,
  discussion happens in the originating issue.
* **Workflow dispatch inputs**: Humans can supply
  overrides (USE flags, patches, SRC_URI) via workflow
  dispatch inputs or PR comments that the agent parses.

---

## 5. Workflow 2 — Ebuild Upgrades

### 5.1 Triggers

| Trigger | Mechanism |
|---|---|
| **On-demand** | `workflow_dispatch` with inputs `package` and `version`. |
| **Scheduled** | Cron (twice weekly, Thu/Sun 06:00 UTC) — version-check detects updates, filters by `auto_upgrade: true`, then fans out to `upgrade-ebuild.yml` per package. Thursday is used instead of Wednesday because Zed typically releases on Wednesdays. |
| **Upstream release** | Evaluated `repository_dispatch` vs. polling. Cross-repo webhooks require a GitHub App installed on the upstream repo — not viable for third-party projects. Polling is the correct approach. |

### 5.2 Package Registry

The overlay's directory structure is the canonical source
of truth for package data — categories, names, and
versions are all derivable from the ebuild file tree.
However, some automation-specific metadata has no natural
home in standard Gentoo overlay files:

* **Upstream repo location** (`zed-industries/zed`) —
  needed to poll for new releases
* **Version tag pattern** (`v(.*)`, `release_xt_(.*)`) —
  needed to extract versions from upstream tags
* **Upstream type** (`github-release`, `github-tag`,
  `manual`, etc.) — determines which API to poll
* **Repackage flag** — whether the package needs source
  repackaging before build
* **Auto-upgrade eligibility** — whether a version bump
  can be auto-merged without human review

This metadata lives in `.agent/packages.json` (see §2.1
for the `.agent/` directory rationale):

```jsonc
[
  {
    "category": "app-editors",
    "name": "zed",
    "upstream_repo": "zed-industries/zed",
    "upstream_type": "github-release",
    "version_pattern": "v(.*)",
    "repackage": false,
    "auto_upgrade": true,
    "notes": "Requires GIT_CRATES and WEBRTC_COMMIT checks. Upgrade workflow proven end-to-end."
  },
  {
    "category": "media-sound",
    "name": "surgext",
    "upstream_repo": "surge-synthesizer/surge",
    "upstream_type": "github-tag",
    "version_pattern": "release_xt_(.*)",
    "repackage": true,
    "auto_upgrade": false,
    "notes": "Stable releases are tags only (no GitHub Release objects)..."
  }
]
```

**Upstream types:**

| `upstream_type` | API Used | Notes |
|---|---|---|
| `github-release` | GitHub Releases API | For projects that create GitHub Release objects for stable versions. Tags that don't match `version_pattern` (e.g. "Nightly") are skipped. |
| `github-tag` | GitHub Tags API | For projects that publish stable versions as tags only, without creating Release objects (e.g. Surge XT uses `release_xt_*` tags). |
| `manual` | None | No public release API. Updates must be checked manually. |

**Fields:**

* `auto_upgrade` — gate for the automated upgrade pipeline.
  When `true`, a detected upstream update will automatically
  trigger `upgrade-ebuild.yml` (via the scheduled
  `ci-version-check.yml`), which runs the upgrade script,
  creates a detailed GitHub issue, and assigns the Copilot
  coding agent to finalize the ebuild and open a PR.
  When `false`, version-check will still detect the update
  but will take no automated action — a human must trigger
  `upgrade-ebuild.yml` manually via `workflow_dispatch`.
  Set to `true` only after the upgrade workflow has been
  proven end-to-end for that package.
  **Currently `true`:** `app-editors/zed`, `media-sound/carla`.
* `notes` — free-text field for human and agent context
  (upgrade caveats, special handling, etc.)

Note: `current_versions` is intentionally omitted — the
overlay tree itself is the source of truth for what versions
exist. The version-check workflow derives current versions by
scanning ebuild filenames at runtime.

### 5.3 Steps (Autonomous Upgrade)

| # | Step | Details |
|---|---|---|
| 1 | **Detect new version** | Query upstream using `.agent/packages.json`. Compare to ebuild filenames in overlay. |
| 2 | **Verify sources** | Confirm upstream tarball (and supplementary archives) are downloadable. |
| 3 | **Create branch** | `upgrade/<category>/<name>-<new_version>` |
| 4 | **Copy ebuild** | Copy latest existing ebuild to `<name>-<new_version>.ebuild`. |
| 5 | **Check deps** | Diff upstream build manifests (§5.5). Update ebuild as needed. |
| 6 | **Regen Manifest** | `ebuild manifest` — fetches sources, updates checksums. Fallback: `pkgdev manifest`. |
| 7 | **Lint** | `pkgcheck scan` on the package directory. |
| 8 | **Build test** | `ebuild clean compile` in container. Agent fixes failures and re-runs (§5.4). |
| 9 | **Verify build** | Check expected binaries, version strings, `ldd` linkage. |
| 10 | **Integration test** | `emerge` in disposable container. Never on host (§5.4). |
| 11 | **Open PR** | If checks pass and `auto_upgrade` is true, auto-merge. |
| 12 | **Notify** | Email / issue comment on failure. |

### 5.4 Build & Test Tooling: `ebuild` for Iteration, `emerge` for Final Testing

The build/test process uses a **two-tier approach**:

**Tier 1 — `ebuild` (primary, development iteration):**

The `ebuild` command is the primary tool for building
and testing ebuilds during development, both in CI and
locally. Unlike `emerge` (Portage), `ebuild` operates
directly on a single `.ebuild` file from the overlay
source tree without interacting with the system package
database. This provides:

* **Isolation** — Clear separation between the
  development overlay and the installed system.
* **Consistency** — The same
  `ebuild ./pkg-1.0.ebuild clean compile` command works
  identically in CI containers and locally.
* **Granular control** — Individual phases (`clean`,
  `fetch`, `unpack`, `prepare`, `compile`, `install`)
  can be run and retried independently.
* **Speed on retry** — Re-running without `clean` reuses
  the already-unpacked source tree, skipping the slow
  unpack/patch phase.

All iterative development — fixing dependency issues,
adjusting USE flags, debugging compile failures — should
use `ebuild`. This is the tool agents use for the vast
majority of build/test cycles.

**Tier 2 — `emerge` (final integration test, container
only):**

Once an ebuild compiles successfully with `ebuild`, a
final `emerge` test inside a Gentoo container confirms
Portage integration (dependency resolution, slot
handling, post-install actions). This step is **never
run on the host system** — it executes exclusively
inside a disposable container.

**Important:** The existing toolchain, both locally and
in the container, is assumed to be sufficient. Agents
must follow the safety constraints in §8.4.

The workflow uses `ebuild ./<file>.ebuild manifest` as
the primary tool for Manifest generation. If `ebuild
manifest` is unavailable, `pkgdev manifest` (from
`dev-util/pkgdev`) serves as a fallback.

### 5.5 Dependency Change Detection (Upgrade Sub-Process)

When upgrading an ebuild, always check for upstream
dependency changes before considering the update complete.
The exact checks depend on the build system:

#### Cargo / Rust packages (e.g. `app-editors/zed`)

Diff the upstream `Cargo.toml` between old and new
versions and look for:

| Change detected | Action |
|---|---|
| A git dep's `rev =` changed | Update commit hash in `GIT_CRATES` |
| A new git dep appeared | Add new entry to `GIT_CRATES` |
| A git dep was removed | Remove its `GIT_CRATES` entry |
| New workspace members added | Fetch their `Cargo.toml`, scan for git deps |
| `rust-version` changed | Update `RUST_MIN_VER` in ebuild |
| Crates.io version bumps | No action — handled by crates tarball |

Also check release notes for mentions of new system-level
libraries that would affect `DEPEND`/`BDEPEND`.

#### CMake / Meson packages

Diff `CMakeLists.txt` or `meson.build` for changed
`find_package()`, `dependency()`, or version
requirements. Update `DEPEND`/`BDEPEND` accordingly.

#### Binary repackage packages

Typically no dependency changes, but verify runtime
library requirements by checking `ldd` output after
build.

### 5.6 Source Repackaging

Some packages (e.g. Surge XT) require source repackaging
because upstream tarballs do not include git submodules.
The existing `repackage-surge.yml` handles this for
Surge XT.

This pattern should be generalized into a **reusable
workflow** (`.github/workflows/repackage-source.yml`)
that accepts:

* `upstream_repo`
* `version`
* `tag_pattern`
* `tarball_name_pattern`
* `release_tag_pattern`

The upgrade workflow will call the repackage workflow
first when the package registry has `"repackage": true`.

---

## 6. Gentoo Container Environment

### 6.1 Why a Container?

* Provides a reproducible Gentoo stage3 environment with a synced portage tree.
* Avoids polluting the developer's host system.
* Runs identically in GitHub Actions and locally.

### 6.2 Container Images

Three container images are maintained, all published to
GHCR. Images are built and pushed **locally** (not in
CI). Publish workflows exist only for weekly scheduled
rebuilds (fresh portage tree) and manual dispatch —
there are no push triggers on Containerfile changes.

**Base image — `testenv`**
(`ghcr.io/faraclas/adaptive-overlay/testenv:latest`)

Built from `gentoo/stage3:amd64-desktop-systemd` — the
official Gentoo desktop stage3 with systemd and the
`default/linux/amd64/23.0/desktop/systemd` profile
pre-configured. This avoids the painful openrc→systemd
migration that the generic `stage3:latest` required.
Installs `pkgcheck` and `pkgdev`, copies overlay
metadata/profiles, configures repos.conf, and disables
sandbox features for rootless containers. Published
weekly (Mondays at 04:00 UTC) via `publish-testenv.yml`.
Used for linting and building most packages.

**Rust image — `testenv-rust`**
(`ghcr.io/faraclas/adaptive-overlay/testenv-rust:latest`)

Extends `testenv` with everything needed to build
`app-editors/zed`: LLVM 21, Rust 1.93, Wayland/X11 libs,
and ~76 build dependencies pre-installed. Includes
circular dep breakers for tiff/glib/pillow/w3m.
Published automatically after `testenv` via
`publish-testenv-rust.yml` (workflow_run chain).

**Audio image — `testenv-audio`**
(`ghcr.io/faraclas/adaptive-overlay/testenv-audio:latest`)

Extends `testenv` with everything needed to build
`media-sound/*` packages: Wine (with `abi_x86_32`,
not `wow64` — see note below), MinGW cross-toolchain,
JACK, ALSA, PulseAudio, PipeWire, FluidSynth, multilib
X11/XCB libraries, LV2/LADSPA, GTK3, Qt6, PyQt5, Rust,
and Meson. Includes circular dep breakers for
tiff/glib/pillow/w3m/ncurses. ~271 packages installed.
Covers build deps for Carla, yabridge, Surge XT, Bitwig
Studio, amp-locker, and drum-locker. Published
automatically after `testenv` via
`publish-testenv-audio.yml` (workflow_run chain).

> **wow64 vs abi_x86_32:** Carla's `wine32` build
> target uses `winegcc -m32` to produce a 32-bit
> `.dll.so`. This requires Wine's 32-bit import
> libraries, which are only installed with
> `abi_x86_32`. On x86_64, `wow64` and `abi_x86_32`
> are mutually exclusive (`REQUIRED_USE`), so the
> image uses `abi_x86_32 -wow64`.

Containerfiles live in `containers/testenv/`,
`containers/testenv-rust/`, and
`containers/testenv-audio/` respectively.

At workflow runtime, the repo contents are bind-mounted
into the container so that the latest ebuild changes are
visible.

### 6.3 Caching

* The portage tree is synced at image build time and
  baked into the container layer.
* The `testenv-rust` image pre-installs ~76 build
  dependencies so Zed builds don't start from scratch.
* The `testenv-audio` image pre-installs Wine (with
  full multilib dep chain), JACK, and all audio build
  dependencies (~271 packages).
* All three images are published to GHCR. Weekly
  scheduled rebuilds keep the portage tree fresh.
  Containers are also maintained locally and pushed
  to GHCR manually when Containerfiles change.
* Publish workflows have no push triggers — only
  schedule, manual dispatch, and workflow_run chain.
* Explicit distfiles/portage tree caching in CI
  workflows is not yet implemented (Phase 2.4,
  partial).

### 6.4 Local Usage

Developers run the same containers locally via the helper
scripts:

```bash
# Quick lint check
scripts/lint.sh media-sound/carla

# Full build test
scripts/test-build.sh media-sound/carla carla-2.5.10.ebuild

# Retry without clean (reuse unpacked source)
scripts/test-build.sh media-sound/carla carla-2.5.10.ebuild \
    --no-clean

# Check for upstream updates
scripts/check-updates.sh
scripts/check-updates.sh --json
```

These scripts invoke `podman run` (or `docker run` as
fallback) with the correct bind mounts and arguments,
mirroring the CI workflows exactly.

---

## 7. Reusable Workflows & Actions

### 7.1 `lint-ebuild` (Reusable Workflow) ✅

**Status:** Implemented — `lint-ebuild.yml`

**Inputs:** `package_dir` (e.g. `media-sound/carla`)

**Steps:**

1. Start `testenv` container from GHCR.
2. Symlink checkout into the portage repo location.
3. Run `pkgcheck scan` with:
   * `--profiles default/linux/amd64/23.0/desktop` —
     restricts checks to multilib desktop profiles
     (overlay doesn't target no-multilib or musl).
   * `--exit error,-DeprecatedDep` — fail on errors,
     but allow deprecated deps (upstream Qt5/PyQt5).
   * Warnings are surfaced in the log but do not
     block the PR.

**Callers:** `ci-lint.yml` (PR/push to main, auto-detects
changed packages).

### 7.2 `test-ebuild` (Reusable Workflow) ✅

**Status:** Implemented — `test-ebuild.yml`

**Inputs:** `package_dir`, `ebuild_file`, `container_image`
(defaults to `testenv`, auto-selects `testenv-rust` for Zed)

**Steps:**

1. Start the appropriate container from GHCR.
2. `ebuild ./<ebuild_file> clean compile` — full build from
   source.
3. Upload build log as GitHub Actions artifact.
4. If a verify script exists
   (`containers/<image>/verify-<pkg>.sh`), run it against
   the build image directory.
5. Report pass/fail.

**Callers:** `ci-build.yml` (opt-in via `build-test` label,
auto-detects changed packages).

**Not yet implemented (Phase 4):**

* `emerge` integration test step (Tier 2 testing)

### 7.3 `repackage-source` (Reusable Workflow) 🔶

**Status:** Surge-specific version exists
(`repackage-surge.yml`). Generalized reusable version
planned for Phase 4.5.

**Current implementation** (`repackage-surge.yml`):

* Weekly cron checks for new Surge XT releases (via Tags
  API) and sends email notification on new version.
* Manual dispatch clones at tag with
  `--recurse-submodules`, creates tarball excluding
  `.git`, publishes as a GitHub Release on this repo.

**Planned inputs (generalized):** `upstream_repo`, `version`,
`tag_pattern`, `tarball_prefix`, `release_tag_prefix`

### 7.4 `check-upstream-versions` (Reusable Workflow) ✅

**Status:** Implemented —
`check-upstream-versions.yml`

**Inputs:** `create_issues` (boolean, default false)

**Outputs:** `results` (JSON array), `updates_available`
(boolean)

**Steps:**

1. For each package in `.agent/packages.json`:
   a. Derive current versions by scanning ebuild filenames
      in `<category>/<name>/`.
   b. Query the upstream source for the latest version
      (GitHub Releases API for `github-release`, GitHub
      Tags API for `github-tag`, skip for `manual`).
   c. Compare to the versions found on disk using
      `sort -V`.
2. Output a JSON array of results with per-package status.
3. If `create_issues` is true, create GitHub issues for
   packages with available updates (deduplicated by title).
4. Write a formatted summary table to
   `$GITHUB_STEP_SUMMARY`.

**Callers:** `ci-version-check.yml` (scheduled Thu/Sun at
06:00 UTC + manual dispatch, with `create_issues: false` —
issue creation is delegated to `upgrade-ebuild.yml` which
produces the authoritative detailed issue).

**Auto-dispatch (Phase 4.6 — ✅ implemented):**

The `ci-version-check.yml` workflow now fans out to
`upgrade-ebuild.yml` for every package where the version
check returns `update-available` **and** `auto_upgrade:
true` in `.agent/packages.json`.  A `prepare-upgrades`
job does a sparse checkout of `packages.json`, joins it
against the version-check results via `jq`, and emits a
matrix of `category/name` strings.  The `upgrade` matrix
job then calls `upgrade-ebuild.yml` once per package with
`secrets: inherit` so `GH_PAT` is available for the
Copilot agent assignment step.

### 7.5 `upgrade-ebuild` (Workflow) ✅

**Status:** Created — `upgrade-ebuild.yml` +
`scripts/upgrade-ebuild.sh` + `scripts/manifest.sh`

**Architecture: Script + Agent division of labor.**

The upgrade process splits work between a bash script
(mechanical detection and safe replacements) and an AI
agent (decisions requiring code structure understanding):

| Responsibility | Owner |
|---|---|
| Detect version, check sources, copy ebuild | Script |
| Diff `Cargo.toml`, extract all changes | Script |
| Update existing commit hashes (global sed) | Script (`--apply`) |
| Update `WEBRTC_COMMIT` | Script (`--apply`) |
| Update `src_prepare()` commit variables | Script (side effect of global sed) |
| **Insert new `GIT_CRATES` entries** | **Agent** |
| **Remove old `GIT_CRATES` entries** | **Agent** |
| **Determine subpath for new crates** | **Agent** |
| **Update `RUST_MIN_VER`** | **Agent** (cascading impact: container rebuild, LLVM version, keyword accepts) |
| **Review and validate final ebuild** | **Agent** |
| Generate Manifest | Script (`scripts/manifest.sh`) |
| Lint | Script (`scripts/lint.sh`) |

The script outputs structured JSON so the agent can
programmatically act on each change. See
`.agent/skills/update-zed-editor.md` for the full
agent procedure.

**Local scripts:**

* `scripts/upgrade-ebuild.sh` — version detection, source
  checking, ebuild copy, Cargo.toml dep diffing, auto-apply.
  Flags: `--apply`, `--json`, `--manifest`, `--version`.
* `scripts/manifest.sh` — runs `pkgdev manifest` inside
  the testenv container with a read-write overlay mount.

**Workflow triggers:** `workflow_dispatch` (manual) and
`workflow_call` (for chaining from version-check).

**Workflow inputs:** `package` (required, e.g.
`app-editors/zed`), `version` (optional — auto-detected
if empty).

**Steps:**

1. Run `scripts/upgrade-ebuild.sh` with `--apply --json`.
2. Parse JSON output into step outputs.
3. AI agent finalizes ebuild (insert/remove `GIT_CRATES`,
   validate changes). *(Planned — currently manual.)*
4. Run `scripts/manifest.sh` in container.
5. Create PR via `peter-evans/create-pull-request@v7`
   with `upgrade` + `automated` labels.
6. Run lint via reusable `lint-ebuild.yml`.
7. Build testing is deferred — reviewer adds `build-test`
   label to trigger `ci-build.yml`.

**Third-party dependency:**
[`peter-evans/create-pull-request`](https://github.com/peter-evans/create-pull-request)
(v7) — widely-used action (5k+ stars) for committing
working-directory changes to a branch and opening a PR.
Requires only the default `GITHUB_TOKEN`.

---

## 8. Agent Collaboration Model

### 8.1 Agent Capabilities

The AI coding agent (e.g. GitHub Copilot) should be
able to:

* Read `.agent/packages.json` and per-package
  instructions in `.agent/instructions/`.
* Generate new ebuilds by inspecting upstream build
  systems.
* Copy and modify existing ebuilds for version bumps.
* Run lint and build workflows and interpret their
  output.
* Open PRs and interact via PR comments.

Agents must always operate within the safety constraints
defined in §8.4 — no system tool installation or system
file modification without explicit approval.

### 8.2 Agent Entrypoints

| Task | Entry point |
|---|---|
| Create new ebuild | Issue → branch → draft ebuild → PR |
| Upgrade ebuild | Workflow dispatch → version bump |
| Fix lint/build failure | Read CI logs → fix → push |

### 8.3 Providing Context to Agents

To help agents produce high-quality ebuilds:

* Maintain `.agent/ebuild_guidelines.md` describing
  overlay-specific conventions (preferred USE flags,
  licensing practices, Manifest handling, etc.).
* Provide per-package upgrade instructions in
  `.agent/instructions/<category>/<package>/`, mirroring
  the overlay's directory structure (e.g. Zed update
  process as
  `.agent/instructions/app-editors/zed/upgrade.md`).
* Store reusable agent skill documents in
  `.agent/skills/` (e.g. "how to upgrade a Cargo-based
  ebuild", "how to handle GIT_CRATES").
* Include example ebuilds in the overlay that demonstrate
  common patterns (cmake, cargo, binary repackage, etc.).
* `.agent/packages.json` provides structured upstream
  metadata the agent can consume for version checking and
  upgrade automation.

### 8.5 Agent Backends — Dual Architecture (CI + Local)

The upgrade workflow uses AI agents in two environments
with different backends but identical logic and context:

#### CI Path — GitHub Copilot Coding Agent

In GitHub Actions, the agent step uses the **Copilot
coding agent** (`copilot-swe-agent[bot]`), which is
included in the GitHub Copilot Business plan. The
workflow assigns a GitHub Issue to Copilot via the REST
API:

```bash
gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/OWNER/REPO/issues/ISSUE_NUMBER/assignees \
  --input - <<< '{
  "assignees": ["copilot-swe-agent[bot]"],
  "agent_assignment": {
    "base_branch": "upgrade/PACKAGE-VERSION",
    "custom_instructions": "...(structured prompt)...",
    "model": "claude-sonnet-4.6"
  }
}'
```

Key details:

* Copilot coding agent works on **Issues**, not mid-
  workflow steps. It reads the issue, edits files, and
  opens/updates a PR.
* `custom_instructions` contains the structured JSON
  from `upgrade-ebuild.sh` plus a reference to
  `.agent/skills/update-zed-editor.md`.
* `model: claude-sonnet-4.6` specifies Claude Sonnet as
  the backing model (selectable on Business/Pro+ plans).
* Copilot reads `.github/copilot-instructions.md` for
  repo-level context (should point at
  `.agent/instructions/general.md`).
* A `.devcontainer/devcontainer.json` is required so
  Copilot can run shell commands (`curl`, `jq`, `diff`,
  `sed` — our scripts handle container operations).

Prerequisites to create:

| File | Purpose |
|---|---|
| `.devcontainer/devcontainer.json` | Lightweight dev environment for Copilot (needs `curl`, `jq`, `diff`, `sed`, `bash`) |
| `.github/copilot-instructions.md` | Repo-level instructions pointing at `.agent/instructions/general.md` and `.agent/skills/` |

#### Local Path — GitHub Copilot CLI

On a developer's machine, the agent step uses the
**GitHub Copilot CLI** (`copilot`), a standalone binary
that exposes the same models as Copilot Chat. It is
included in the Copilot subscription with no separate
API key required.

The CLI is invoked programmatically by piping a prompt
via stdin (the `-p` flag has command-line length limits
and must NOT be used for large prompts):

```bash
echo "${PROMPT}" \
  | copilot -s --no-ask-user --model claude-sonnet-4.6
```

Required flags for non-interactive use:

| Flag | Purpose |
|---|---|
| `-s` | Silent — suppress UI chrome, response text only |
| `--no-ask-user` | Never prompt for clarification (critical for scripted use) |
| `--model <name>` | Model selection (e.g. `claude-sonnet-4.6`) |

**Do NOT use `-p`** — omit it entirely and pipe via
stdin. This bypasses all command-line length limits.

The local agent script (`scripts/agent-finalize-ebuild.sh`,
to be created) will:

1. Read the JSON output from `upgrade-ebuild.sh`.
2. Read the current ebuild content and the skills doc.
3. Construct a prompt: skills doc + JSON change report +
   ebuild content + instructions to output the edited
   ebuild.
4. Pipe the prompt to `copilot -s --no-ask-user --model
   claude-sonnet-4.6`.
5. Parse the response (strip markdown code fences if
   present, sanitize control characters).
6. Write the edited ebuild back to disk.

Response post-processing (from production experience):

* **Strip markdown code fences:** The CLI wraps output
  in `` ```lang ... ``` `` blocks. Strip with regex.
* **Remove invalid JSON control characters:** LLMs
  occasionally emit raw C0 control chars (`0x00`–`0x1F`
  except tab/newline/CR). Strip before JSON parsing.

Available models (as of 2026):

| Model | Premium Multiplier | Recommended Use |
|---|---|---|
| `claude-sonnet-4.6` | 1x | **Default.** Strong structured output, good reasoning |
| `claude-opus-4.6` | 4x | Escalation for hard problems |
| `gpt-5.4` | 1x | Good all-around |
| `gemini-3-pro-preview` | 1x | Fastest response time |

Verified working on this repo's development machine:

```
$ which copilot
/home/elias/.local/bin/copilot
$ copilot --version
GitHub Copilot CLI 1.0.11.
$ echo "Reply with only the word WORKING" \
    | copilot -s --no-ask-user --model claude-sonnet-4.6
WORKING
```

#### Unified Flow — Both Paths

Both paths use the same scripts, skills docs, and
detection logic:

```
┌─────────────────────────────────────────────────┐
│  upgrade-ebuild.sh --apply --json               │
│  (version detect, source check, copy, diff,     │
│   commit hash updates, structured JSON output)   │
└──────────────────────┬──────────────────────────┘
                       │
              ┌────────┴────────┐
              │                 │
     ┌────────▼──────┐  ┌──────▼────────┐
     │  CI Path      │  │  Local Path   │
     │               │  │               │
     │  Issue →      │  │  copilot CLI  │
     │  Copilot      │  │  via stdin    │
     │  coding agent │  │               │
     └────────┬──────┘  └──────┬────────┘
              │                 │
              └────────┬────────┘
                       │
              ┌────────▼────────┐
              │  Agent edits:   │
              │  • Insert new   │
              │    GIT_CRATES   │
              │  • Remove old   │
              │    GIT_CRATES   │
              │  • RUST_MIN_VER │
              │  • Validate     │
              └────────┬────────┘
                       │
              ┌────────▼────────┐
              │  manifest.sh    │
              │  lint.sh        │
              │  (human review) │
              └─────────────────┘
```

### 8.4 Agent Safety Constraints

Agents operate under strict safety rules that protect the
developer's system while still allowing full automation in
controlled environments. The installed toolchain — both
locally and in containers — is assumed to be sufficient
for all workflow tasks.

#### System tool installation

| Environment | Rule |
|---|---|
| **Local system** | **Never** install system tools (`emerge`, `apt`, etc.). |
| **CI container** | Only if defined in workflow. No ad-hoc installs. |

If an agent encounters a missing tool, it must **pause
and request human guidance** — post a PR comment
describing the missing tool, apply the
`waiting-for-human` label, and stop work on that step
until the human responds.

#### System file modification

| Environment | Rule |
|---|---|
| **Local system** | **Never** modify system files without explicit permission. Confine work to overlay dir. |
| **CI container** | Only if defined in workflow. Seek approval for unanticipated changes. |

#### Rationale

These constraints allow:

* **Full automation in CI/cloud** — Containers are
  disposable; workflow-defined system changes are safe
  and reproducible.
* **Protection for local systems** — A developer's
  workstation is never used as an experimental testbed.
  `ebuild` (§5.4) provides build/test capability without
  touching the system; containers handle `emerge`.
* **Flexibility with guardrails** — New tools or system
  changes are added to the workflow definition
  (Containerfile, workflow YAML) with human review, not
  installed ad-hoc by agents.

---

## 9. Local Development Experience

### 9.1 Scripts

The `scripts/` directory contains local convenience helpers
that mirror CI behavior:

| Script | Status | Purpose |
|---|---|---|
| `scripts/lint.sh <pkg_dir>` | ✅ | `pkgcheck` in `testenv` container. Local image → GHCR fallback. |
| `scripts/test-build.sh <pkg> <ebuild> [--no-clean]` | ✅ | `ebuild clean compile` in container. Auto-selects `testenv-rust` for Zed, `testenv-audio` for `media-sound/*`. `--no-clean` for fast retry. |
| `scripts/check-updates.sh [--json]` | ✅ | Check tracked packages for upstream updates. `--json` for machine output. |
| `scripts/upgrade-ebuild.sh` | ✅ | Detect upstream updates, copy ebuild, diff Cargo.toml deps, apply safe changes. `--apply`, `--json`, `--manifest`. Outputs structured JSON for agent consumption. |
| `scripts/manifest.sh <pkg_dir>` | ✅ | Run `pkgdev manifest` in `testenv` container with read-write overlay mount. Fetches distfiles and updates `Manifest`. |
| `scripts/new-ebuild.sh <cat> <name> <ver>` | ❌ | Scaffold new ebuild skeleton + metadata.xml. (Phase 5) |

### 9.2 Container Runtime

Scripts prefer Podman and fall back to Docker. Image
resolution: local image first (e.g.
`localhost/adaptive-overlay-testenv:local`), then GHCR
(`ghcr.io/faraclas/adaptive-overlay/testenv:latest`).
`test-build.sh` auto-selects `testenv-rust` for
`app-editors/zed` and `testenv-audio` for all
`media-sound/*` packages. Override overlay root via
`OVERLAY_DIR`.

### 9.3 Makefile / Taskfile (Optional)

A top-level `Makefile` or `Taskfile.yml` can provide convenient aliases:

```makefile
lint:
    ./scripts/lint.sh $(PKG)

test:
    ./scripts/test-build.sh $(PKG) $(EBUILD)

check-updates:
    ./scripts/check-updates.sh
```

---

## 10. Implementation Phases

The work is broken into sequential phases. Each phase
produces usable, testable deliverables.

### Phase 1 — Foundation (Container & Lint) ✅

> Goal: Establish the container environment and basic lint
> CI.

| Item | Status | Description |
|---|---|---|
| 1.1 | ✅ | `containers/testenv/Containerfile` (base, `stage3:amd64-desktop-systemd`) + `testenv-rust/` for Zed + `testenv-audio/` for media-sound. |
| 1.2 | ✅ | `publish-testenv.yml` (weekly + manual) + chained `publish-testenv-rust.yml` + `publish-testenv-audio.yml`. No push triggers — containers maintained locally. |
| 1.3 | ✅ | `lint-ebuild.yml` — reusable `pkgcheck scan`, restricted to desktop profiles. |
| 1.4 | ✅ | `scripts/lint.sh` — local Podman/Docker. |
| 1.5 | ✅ | `ci-lint.yml` — lints changed ebuilds on PR/push. Filters non-package dirs (`.agent/`, `.github/`, `containers/`, etc.). |

### Phase 2 — Build Testing ✅

> Goal: Enable full build testing in CI and locally.

| Item | Status | Description |
|---|---|---|
| 2.1 | ✅ | `test-ebuild.yml` — reusable, verify-script support. |
| 2.2 | ✅ | `scripts/test-build.sh` — local, `--no-clean`, Rust auto-select. |
| 2.3 | ✅ | `ci-build.yml` — opt-in via `build-test` label. Routes `media-sound/*` to `testenv-audio`, `app-editors/zed` to `testenv-rust`. |
| 2.4 | ⚠️ | Partial — images pre-bake deps. No distfiles cache yet. |

### Phase 3 — Package Registry & Version Checking ✅

> Goal: Track packages and detect upstream updates.

| Item | Status | Description |
|---|---|---|
| 3.1 | ✅ | `.agent/packages.json` — all 8 packages. Types: `github-release`, `github-tag`, `manual`. |
| 3.2 | ✅ | `check-upstream-versions.yml` — JSON output, issue creation, summary. |
| 3.3 | ✅ | `scripts/check-updates.sh` — `--json`, `GITHUB_TOKEN`. |
| 3.4 | ✅ | `ci-version-check.yml` — Thu/Sun 06:00 UTC + manual. |

### Phase 4 — Automated Ebuild Upgrades ✅

> Goal: End-to-end autonomous version bumps.

| Item | Status | Description |
|---|---|---|
| 4.1 | ✅ | `upgrade-ebuild.sh` — version detection, source checking, ebuild copy, Cargo.toml dep diffing, auto-apply, JSON output. `upgrade-ebuild.yml` — workflow with `workflow_dispatch`/`workflow_call`, PR creation via `peter-evans/create-pull-request@v7`, lint integration. |
| 4.2 | ✅ | Copy-and-update logic + dep change detection for Cargo/Rust implemented in `upgrade-ebuild.sh` (§5.5). |
| 4.3 | ✅ | Lint runs automatically in the upgrade workflow. Build test deferred to reviewer via `build-test` label (handled by existing `ci-build.yml`). |
| 4.4 | ✅ | `upgrade-ebuild.yml` creates PRs with `upgrade` + `automated` labels, change summary table, manifest instructions. |
| 4.5 | ❌ | Generalize `repackage-surge.yml` → `repackage-source.yml`. |
| 4.6 | ✅ | Wire version-check → upgrade triggers. `ci-version-check.yml` now fans out to `upgrade-ebuild.yml` for every package with `update-available` status and `auto_upgrade: true` in `.agent/packages.json`. A `prepare-upgrades` job does a sparse checkout + `jq` join; an `upgrade` matrix job calls `upgrade-ebuild.yml` per package with `secrets: inherit`. |
| 4.7 | ✅ | **Agent finalization — CI path:** Created `.devcontainer/devcontainer.json` (lightweight Ubuntu base + gh CLI for Copilot coding agent). Created `.github/copilot-instructions.md` (repo-level Copilot context pointing at `.agent/instructions/general.md`, `.agent/skills/`, `scripts/`, and `.agent/packages.json`). Rewrote `upgrade-ebuild.yml` to use Approach B (issue-first): detect job runs `upgrade-ebuild.sh --apply --json`, delegate job creates a GitHub Issue with structured JSON + ebuild content + skills reference + step-by-step instructions, then assigns to `copilot-swe-agent[bot]` via REST API. Copilot owns the entire finalization (edits, manifest, lint, PR). |
| 4.8 | ✅ | **Agent finalization — local path:** Created `scripts/agent-finalize-ebuild.sh`. Reads JSON from `upgrade-ebuild.sh`, resolves the skills doc, constructs a prompt (skills + JSON report + ebuild content), pipes to `copilot -s --no-ask-user --model claude-sonnet-4.6` via stdin, strips code fences and control chars from response, validates output looks like an ebuild, writes back, then runs `manifest.sh` and `lint.sh` automatically. Supports `--dry-run`, `--model`, `--skip-manifest`, `--skip-lint`. |
| 4.9 | ✅ | **Manifest in CI:** Manifest generation is now the agent's responsibility (Approach B). The agent runs `scripts/manifest.sh` after making edits, ensuring manifest reflects final ebuild content. The workflow no longer generates manifest itself. |
| 4.10 | ✅ | **Issue-first flow (Approach B chosen):** Decided that every upgrade goes through the agent — no branching logic for "trivial" vs "complex" bumps. The agent validates even simple bumps, keeping the workflow simple and ensuring intelligent review on every upgrade. The workflow is now a "detect and delegate" pipeline: it gathers structured data, creates an Issue, and hands off to Copilot. |
| 4.11 | ✅ | **End-to-end test:** Zed 0.229.0 upgrade verified locally and pushed to `main`. CI lint and build tests pass. |

### Phase 5 — New Ebuild Creation Workflow

> Goal: Agent-assisted new ebuild creation with human collaboration.

| Item | Description |
|---|---|
| 5.1 | `.agent/ebuild_guidelines.md` — conventions for agents. |
| 5.2 | `scripts/new-ebuild.sh` — scaffold ebuild skeleton. |
| 5.3 | `new-ebuild.yml` with issue/dispatch triggers. |
| 5.4 | Human-in-the-loop (labels, PR comments, reviews). |
| 5.5 | Populate `.agent/skills/` and `.agent/instructions/`. |

### Phase 6 — Upstream Release Triggers ✅ (evaluated & closed)

> Goal: React to upstream GitHub releases in near-real-time.

| Item | Status | Description |
|---|---|---|
| 6.1 | ✅ | Evaluated `repository_dispatch` vs. polling. Cross-repo webhooks require a GitHub App installed on the upstream repo — not viable for third-party projects we don't control. Polling is the correct and sufficient approach. |
| 6.2 | ✅ | Polling implemented via `check-upstream-versions.yml` (GitHub Releases + Tags APIs). Schedule shifted to Thu/Sun to align with Zed's typical Wednesday release cadence. |
| 6.3 | ✅ | Release detection is now connected to `upgrade-ebuild.yml` via the `ci-version-check.yml` fan-out (Phase 4.6). |

### Phase 7 — Polish & Documentation

> Goal: Comprehensive documentation and developer experience.

| Item | Description |
|---|---|
| 7.1 | Update `README.md` with contributing/CI docs. |
| 7.2 | Add `CONTRIBUTING.md` for human + agent contributors. |
| 7.3 | Create optional `Makefile` or `Taskfile.yml`. |
| 7.4 | Harden all workflows (permissions, secrets, errors). |

---

## 11. Dependency Graph

```
Phase 1 ──► Phase 2 ──► Phase 4
   │                       ▲
   │                       │
   └──► Phase 3 ──────────┘
                           │
                           ▼
                       Phase 6

Phase 1 ──► Phase 5

Phase 4 + Phase 5 ──► Phase 7
```

Phases 1–2 (container + testing) are prerequisites for
everything else. Phase 3 (version checking) and Phase 5
(new ebuilds) can proceed in parallel once Phase 1 is
done. Phase 4 (upgrades) depends on Phases 2 and 3.
Phase 6 (release triggers) extends Phase 4. Phase 7
wraps up after the core workflows are functional.

---

## 12. Secrets, Permissions & Third-Party Actions

| Secret / Permission | Used By | Purpose |
|---|---|---|
| `GITHUB_TOKEN` (default) | All workflows | PRs, releases, branches, issue assignment |
| `MAIL_USERNAME` | Version check, notifications | SMTP authentication for email alerts |
| `MAIL_PASSWORD` | Version check, notifications | SMTP auth (GitHub encrypted secret — never commit) |
| `MAIL_TO` | Version check, notifications | Recipient |
| GHCR write access | Container image workflow | Push the test environment image |

**Third-party GitHub Actions:**

| Action | Version | Used By | Purpose |
|---|---|---|---|
| `peter-evans/create-pull-request` | v7 | `upgrade-ebuild.yml` | Commit changes to a branch and open a PR automatically. Uses only `GITHUB_TOKEN`. |
| `softprops/action-gh-release` | v2 | `repackage-surge.yml` | Publish repackaged source tarballs as GitHub Releases. |
| `dawidd6/action-send-mail` | v3 | `repackage-surge.yml` | Send email notifications for new upstream versions. |
| `docker/build-push-action` | v6 | `publish-testenv*.yml` | Build and push container images to GHCR. |
| `docker/login-action` | v3 | `publish-testenv*.yml` | Authenticate with GHCR for image push. |
| `docker/metadata-action` | v5 | `publish-testenv*.yml` | Generate image tags (`latest` + date). |
| `docker/setup-buildx-action` | v3 | `publish-testenv*.yml` | Set up Docker Buildx for layer caching. |

**GitHub Copilot Integration:**

| Component | Used By | Purpose |
|---|---|---|
| Copilot coding agent (`copilot-swe-agent[bot]`) | `upgrade-ebuild.yml` (CI) | Assigned to issues via REST API to finalize ebuilds (insert/remove GIT_CRATES, handle RUST_MIN_VER). Requires Copilot Business plan. No API key — uses `GITHUB_TOKEN`. |
| Copilot CLI (`copilot`) | `agent-finalize-ebuild.sh` (local) | Programmatic LLM inference for local agent workflow. Installed via `npm install -g @github/copilot`. Auth via `gh auth` (no separate key). |
| Model: `claude-sonnet-4.6` | Both CI and local | Default model for agent tasks. 1x premium multiplier. Strong structured output and reasoning. |

> **Note on notifications:** Email is used for out-of-band
> alerts (matching `repackage-surge.yml`). For tighter
> GitHub integration, consider supplementing with Issue
> comments or Discussions posts. Workflows can create
> issue comments using `GITHUB_TOKEN` without extra
> secrets.

---

## 13. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Gentoo container builds are slow | Long CI times | Cache portage tree, distfiles, binpkgs. Build only package under test. |
| Upstream API rate limits | Version checks fail | Cache responses. Conditional requests. Limit frequency. |
| Ebuild complexity varies | Incorrect ebuilds | Guidelines + examples. Human review for new ebuilds. Auto-merge only for `auto_upgrade: true`. |
| Supply-chain attacks | Malicious code in bump | Build-test as first gate. Checksum/signature verification. Hold period before auto-merge. |
| Container staleness | Outdated portage tree | Weekly rebuild + manual dispatch. |
| Flaky upstream sources | Transient download errors | Retry logic. Cache distfiles. Use mirrors. |

---

## 14. Success Criteria

The workflow system is considered complete when:

1. Every PR automatically receives lint and build-test
   results.
2. Version bumps for `auto_upgrade` packages happen
   without human intervention, from detection through
   merge.
3. An agent can be assigned a "create new ebuild" issue
   and produce a working, tested PR with minimal human
   guidance.
4. All CI workflows can be replicated locally using the
   provided scripts and container image.
5. The package registry accurately reflects the overlay
   contents and is kept up to date by automation.

---

## 15. Next Steps (Session Resume Point)

> **Last updated:** After bitwig-studio 6.0 upgrade
> session. First successful end-to-end agent-driven
> upgrade completed (PR #46 merged). GHCR publish
> workflows fixed. Container build optimization.
> All GitHub Actions updated to Node.js 24.

### What Was Done (Bitwig 6.0 / CI Fix Session)

**GHCR publish workflow fixes:**

* Fixed `permission_denied: write_package` error on
  all three `publish-testenv` workflows. Root cause:
  GHCR package-level "Manage Actions access" did not
  list the repository. Fix: added `adaptive-overlay`
  with Write role under each package's settings.
* Enabled "Inherit access from source repository"
  on all three GHCR packages (testenv, testenv-audio,
  testenv-rust).

**Node.js 20 → 24 action version bumps:**

* Updated all 10 workflow files to latest major
  versions with Node.js 24 support:
  * `actions/checkout` v4 → v6
  * `docker/login-action` v3 → v4
  * `docker/metadata-action` v5 → v6
  * `docker/setup-buildx-action` v3 → v4
  * `docker/build-push-action` v6 → v7
  * `actions/upload-artifact` v4 → v7

**testenv-audio container optimization:**

* Split single monolithic `RUN emerge` (270
  packages, >6 hr timeout) into 4 cached layers:
  1. Core libs, X11, audio stack, light tools
  2. FFmpeg + multimedia codecs
  3. PyQt5 + WebKit-GTK + Python tools
  4. Wine + MinGW cross-toolchain
* Added parallel build settings:
  `MAKEOPTS="-j3"`,
  `EMERGE_DEFAULT_OPTS="--jobs=2 --load-average=3"`
* Configured Gentoo official binary package host
  (`getbinpkg`, `binpkg-request-signature`,
  `PORTAGE_BINHOST` for 23.0/x86-64). Packages
  with matching USE flags download as binaries;
  mismatched (e.g. `abi_x86_32`) compile from
  source automatically.
* Built locally and pushed to GHCR to seed the
  layer cache. Subsequent CI rebuilds now only
  recompile changed layers.

**Bitwig Studio upgrade infrastructure:**

* Created `.agent/skills/update-bitwig-studio.md` —
  skills doc covering version numbering quirks
  (2-component `6.0` vs 3-component `5.3.13`),
  download URL verification (HTTP 302 check),
  `.deb` structural checks for major bumps, and
  USE flag review.
* Updated `.agent/packages.json` — added
  `build_system: "binary"` for bitwig-studio,
  updated notes with version format guidance.
* Updated `scripts/upgrade-ebuild.sh`:
  * Allows `manual` upstream type when `--version`
    is provided (no longer requires `upstream_repo`)
  * Adds Bitwig download URL verification (HTTP 302)
  * Skips GitHub tarball check for non-GitHub pkgs
  * Added explicit `manual` case to auto-detection
    with helpful error message
* Added bitwig-studio to skills mapping in
  `upgrade-ebuild.yml` delegate job.

**Upgrade workflow bug fixes:**

* Fixed artifact name containing `/` (invalid char)
  — added sanitization step replacing `/` with `-`.
* Fixed shell escaping bug in issue body: ebuild
  content containing `${PV}`, `${DEPEND}`, etc. was
  interpreted by the shell. Fix: pass dangerous
  content via `env:` block (safe from shell
  expansion), write body to temp file, use
  `gh issue create --body-file` instead of `--body`.
* Fixed Copilot agent assignment 403 Forbidden:
  `GITHUB_TOKEN` lacks permission to assign
  `copilot-swe-agent[bot]`. Fix: use `secrets.GH_PAT`
  (Personal Access Token with `repo` scope) for the
  assignment step.

**First successful end-to-end agent upgrade:**

* Triggered `upgrade-ebuild.yml` via workflow
  dispatch for `media-sound/bitwig-studio` v6.0.
* Workflow detected version, verified download URL,
  created issue #45 with structured report, assigned
  to Copilot coding agent.
* Agent read the skills doc, copied the ebuild,
  removed the old version, ran `manifest.sh` and
  `lint.sh`, opened PR #46.
* PR #46 merged — bitwig-studio 5.3.13 → 6.0.

### Context for Resuming

**Working packages:**

* `app-editors/zed` — builds in `testenv-rust`
  container, lint passes, CI working.
* `media-sound/carla` — builds in `testenv-audio`
  container, lint passes, CI working.
* `media-sound/bitwig-studio` — binary repackage,
  agent-driven upgrade proven (PR #46).

**Agent integration (Phase 4.7–4.10):**

* **CI path (Approach B — issue-first):**
  `upgrade-ebuild.yml` runs the upgrade script to
  gather structured change data, creates a GitHub
  Issue with the JSON report + ebuild content +
  skills reference + step-by-step instructions,
  then assigns it to `copilot-swe-agent[bot]` via
  REST API (using `GH_PAT` secret). The agent owns
  the entire finalization flow: edits, manifest,
  lint, and PR creation. **Proven end-to-end** with
  bitwig-studio 6.0 upgrade (PR #46).

* **Local path:** `scripts/agent-finalize-ebuild.sh`
  reads JSON from `upgrade-ebuild.sh`, constructs a
  prompt (skills doc + JSON report + ebuild content),
  pipes it to the Copilot CLI, post-processes the
  response (strips code fences, validates EAPI),
  writes the edited ebuild back, then runs
  `manifest.sh` and `lint.sh` automatically.

**Key design decision (Approach B):** Every upgrade
goes through the agent — no branching logic for
"trivial" vs "complex" bumps. The agent validates
even simple bumps, keeping the workflow simple and
ensuring intelligent review on every upgrade.

### Remaining Items

#### 1. Generalize Repackage (Phase 4 item 4.5) ❌

Generalize `repackage-surge.yml` into a reusable
`repackage-source.yml` workflow.

#### 2. Wire Version-Check → Upgrade (Phase 4.6) ✅

`ci-version-check.yml` now fans out to `upgrade-ebuild.yml`
for every package with `update-available` status and
`auto_upgrade: true` in `.agent/packages.json`.
Schedule shifted to Thu/Sun (was Wed/Sat).
`app-editors/zed` and `media-sound/carla` are the first
two packages with `auto_upgrade: true`.

#### 3. Automated Version Detection for Bitwig ❌

Add `bitwig-web` upstream type to
`check-updates.sh` that scrapes the download page
at `https://www.bitwig.com/download/` for the
current version. Currently using `manual` type
with explicit `--version` on workflow dispatch.

#### 4. Remaining Phases (5–7)

* **Phase 5** — New ebuild creation workflow
  (agent-assisted scaffolding).
* **Phase 6** — Upstream release triggers
  (near-real-time via `repository_dispatch` or
  polling).
* **Phase 7** — Polish and documentation (README,
  CONTRIBUTING, Makefile/Taskfile, workflow
  hardening).

### Suggested Next Step

Phase 4 is now complete. Remaining items before Phase 5:

1. Add `bitwig-web` scraping to `check-updates.sh` for
   Bitwig version detection (manual → automated detection).
2. Generalize `repackage-surge.yml` → `repackage-source.yml`
   (Phase 4.5) when Surge XT needs its next upgrade.

After those, move to Phase 5 (new ebuild creation workflow).

### Files Summary

| File | Status | Description |
|---|---|---|
| `ci-version-check.yml` | ✅ | Scheduled Thu/Sun 06:00 UTC + manual dispatch. Fans out to `upgrade-ebuild.yml` for packages with `update-available` + `auto_upgrade: true`. |
| `scripts/upgrade-ebuild.sh` | ✅ | Mechanical detection + safe apply (supports `manual` upstream type) |
| `scripts/manifest.sh` | ✅ | Manifest generation in container |
| `scripts/lint.sh` | ✅ | pkgcheck in container |
| `scripts/test-build.sh` | ✅ | Build test in container |
| `scripts/agent-finalize-ebuild.sh` | ✅ | Local Copilot CLI wrapper |
| `.agent/instructions/general.md` | ✅ | Agent safety rules |
| `.agent/skills/update-zed-editor.md` | ✅ | Zed upgrade procedure |
| `.agent/skills/update-carla.md` | ✅ | Carla upgrade procedure |
| `.agent/skills/update-bitwig-studio.md` | ✅ | Bitwig upgrade procedure |
| `.agent/packages.json` | ✅ | Package registry (incl. `build_system` field) |
| `.github/workflows/upgrade-ebuild.yml` | ✅ | CI detect + delegate workflow (uses `GH_PAT` for agent assignment) |
| `.github/workflows/ci-lint.yml` | ✅ | Lint CI (desktop profiles only) |
| `.github/workflows/ci-build.yml` | ✅ | Build CI (routes to correct container) |
| `.github/workflows/publish-testenv.yml` | ✅ | Base container publish (Node.js 24 actions) |
| `.github/workflows/publish-testenv-audio.yml` | ✅ | Audio container publish (Node.js 24 actions) |
| `.github/workflows/publish-testenv-rust.yml` | ✅ | Rust container publish (Node.js 24 actions) |
| `.github/copilot-instructions.md` | ✅ | Repo-level Copilot context |
| `.devcontainer/devcontainer.json` | ✅ | Devcontainer for Copilot agent |
| `containers/testenv/Containerfile` | ✅ | Base env (`stage3:amd64-desktop-systemd`) |
| `containers/testenv-rust/Containerfile` | ✅ | Rust/Zed build env |
| `containers/testenv-audio/Containerfile` | ✅ | Audio build env (4-layer cached, binpkg, parallel emerge) |
| `media-sound/carla/carla-2.5.10-r1.ebuild` | ✅ | Wine32 build dep fix (merged) |
| `media-sound/bitwig-studio/bitwig-studio-6.0.ebuild` | ✅ | Agent-driven upgrade (PR #46 merged) |
