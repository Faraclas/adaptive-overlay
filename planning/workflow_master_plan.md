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
| Container images | `testenv` (base) + `testenv-rust` (Zed) on GHCR |
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
| **Scheduled** | Cron (twice weekly) version-check across tracked packages. |
| **Upstream release** | Webhook or watcher polling GitHub Releases/Tags API. |

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
    "auto_upgrade": false,
    "notes": "Requires GIT_CRATES and WEBRTC_COMMIT checks..."
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

Two container images are maintained, both published to GHCR:

**Base image — `testenv`**
(`ghcr.io/faraclas/adaptive-overlay/testenv:latest`)

Built from `gentoo/stage3:latest`. Installs `pkgcheck` and
`pkgdev`, copies overlay metadata/profiles, and configures
the overlay in `repos.conf`. Published weekly (Mondays at
04:00 UTC) via `publish-testenv.yml`. Used for linting and
building most packages.

**Rust image — `testenv-rust`**
(`ghcr.io/faraclas/adaptive-overlay/testenv-rust:latest`)

Extends `testenv` with everything needed to build
`app-editors/zed`: LLVM 21, Rust 1.93, Wayland/X11 libs,
and ~60+ build dependencies pre-installed. Published
automatically after `testenv` via `publish-testenv-rust.yml`.

Containerfiles live in `containers/testenv/` and
`containers/testenv-rust/` respectively.

At workflow runtime, the repo contents are bind-mounted into
the container so that the latest ebuild changes are visible.

### 6.3 Caching

* The portage tree is synced at image build time and baked
  into the container layer.
* The `testenv-rust` image pre-installs ~60+ build
  dependencies so Zed builds don't start from scratch.
* Both images are published to GHCR and rebuilt weekly.
* Explicit distfiles/portage tree caching in CI workflows
  is not yet implemented (Phase 2.4, partial).

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
3. Run `pkgcheck scan --exit error` — fail on errors, warn
   on warnings.

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

**Callers:** `ci-version-check.yml` (scheduled Wed/Sat at
06:00 UTC + manual dispatch, with `create_issues: true`).

**Not yet implemented (Phase 4.6):**

* Auto-dispatch of upgrade/repackage workflows.

### 7.5 `upgrade-ebuild` (Workflow) 🔶

**Status:** Being created — `upgrade-ebuild.yml`

**Local script:** `scripts/upgrade-ebuild.sh` (✅) handles
version detection, ebuild copy, Cargo.toml dependency
diffing, and auto-apply. Supports `--apply`, `--json`, and
`--manifest` flags.

**Planned workflow inputs:** `package` (e.g.
`app-editors/zed`), `new_version`, `auto_merge` (boolean)

**Steps (planned):**

1. Run `scripts/upgrade-ebuild.sh` with `--apply --json`.
2. Run lint checks on the new ebuild.
3. Optionally run build test (informational).
4. Create PR via `peter-evans/create-pull-request` with
   appropriate labels.

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
| `scripts/test-build.sh <pkg> <ebuild> [--no-clean]` | ✅ | `ebuild clean compile` in container. Auto-selects `testenv-rust` for Zed. `--no-clean` for fast retry. |
| `scripts/check-updates.sh [--json]` | ✅ | Check tracked packages for upstream updates. `--json` for machine output. |
| `scripts/upgrade-ebuild.sh` | ✅ | Detect upstream updates, copy ebuild, diff Cargo.toml deps, apply changes. `--apply`, `--json`, `--manifest`. |
| `scripts/new-ebuild.sh <cat> <name> <ver>` | ❌ | Scaffold new ebuild skeleton + metadata.xml. (Phase 5) |

### 9.2 Container Runtime

Scripts prefer Podman and fall back to Docker. Image
resolution: local image first (e.g.
`localhost/adaptive-overlay-testenv:local`), then GHCR
(`ghcr.io/faraclas/adaptive-overlay/testenv:latest`).
`test-build.sh` auto-selects `testenv-rust` for
`app-editors/zed`. Override overlay root via
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
| 1.1 | ✅ | `containers/testenv/Containerfile` + bonus `testenv-rust/` for Zed. |
| 1.2 | ✅ | `publish-testenv.yml` (weekly) + chained `publish-testenv-rust.yml`. |
| 1.3 | ✅ | `lint-ebuild.yml` — reusable `pkgcheck scan`. |
| 1.4 | ✅ | `scripts/lint.sh` — local Podman/Docker. |
| 1.5 | ✅ | `ci-lint.yml` — lints changed ebuilds on PR/push. |

### Phase 2 — Build Testing ✅

> Goal: Enable full build testing in CI and locally.

| Item | Status | Description |
|---|---|---|
| 2.1 | ✅ | `test-ebuild.yml` — reusable, verify-script support. |
| 2.2 | ✅ | `scripts/test-build.sh` — local, `--no-clean`, Rust auto-select. |
| 2.3 | ✅ | `ci-build.yml` — opt-in via `build-test` label. |
| 2.4 | ⚠️ | Partial — images pre-bake deps. No distfiles cache yet. |

### Phase 3 — Package Registry & Version Checking ✅

> Goal: Track packages and detect upstream updates.

| Item | Status | Description |
|---|---|---|
| 3.1 | ✅ | `.agent/packages.json` — all 8 packages. Types: `github-release`, `github-tag`, `manual`. |
| 3.2 | ✅ | `check-upstream-versions.yml` — JSON output, issue creation, summary. |
| 3.3 | ✅ | `scripts/check-updates.sh` — `--json`, `GITHUB_TOKEN`. |
| 3.4 | ✅ | `ci-version-check.yml` — Wed/Sat 06:00 UTC + manual. |

### Phase 4 — Automated Ebuild Upgrades 🔶

> Goal: End-to-end autonomous version bumps.

| Item | Status | Description |
|---|---|---|
| 4.1 | 🔶 | `upgrade-ebuild.sh` script exists with version detection, source checking, ebuild copy, Cargo.toml dep diffing, auto-apply, and JSON output. `upgrade-ebuild.yml` workflow being created. |
| 4.2 | ✅ | Copy-and-update logic + dep change detection for Cargo/Rust implemented in `upgrade-ebuild.sh` (§5.5). |
| 4.3 | 🔶 | Lint integration done (script prints next steps). Build test integration is informational only (CI workflow being created). |
| 4.4 | 🔶 | `upgrade-ebuild.yml` being created with PR creation via `peter-evans/create-pull-request`. |
| 4.5 | ❌ | Generalize `repackage-surge.yml` → `repackage-source.yml`. |
| 4.6 | ❌ | Wire version-check → upgrade triggers. |

### Phase 5 — New Ebuild Creation Workflow

> Goal: Agent-assisted new ebuild creation with human collaboration.

| Item | Description |
|---|---|
| 5.1 | `.agent/ebuild_guidelines.md` — conventions for agents. |
| 5.2 | `scripts/new-ebuild.sh` — scaffold ebuild skeleton. |
| 5.3 | `new-ebuild.yml` with issue/dispatch triggers. |
| 5.4 | Human-in-the-loop (labels, PR comments, reviews). |
| 5.5 | Populate `.agent/skills/` and `.agent/instructions/`. |

### Phase 6 — Upstream Release Triggers

> Goal: React to upstream GitHub releases in near-real-time.

| Item | Description |
|---|---|
| 6.1 | Evaluate `repository_dispatch` vs. polling workflow. |
| 6.2 | Implement trigger for GitHub-hosted upstreams. |
| 6.3 | Connect release triggers to the upgrade workflow. |

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

## 12. Secrets & Permissions Required

| Secret / Permission | Used By | Purpose |
|---|---|---|
| `GITHUB_TOKEN` (default) | All workflows | PRs, releases, branches |
| `MAIL_USERNAME` | Version check, notifications | SMTP authentication for email alerts |
| `MAIL_PASSWORD` | Version check, notifications | SMTP auth (GitHub encrypted secret — never commit) |
| `MAIL_TO` | Version check, notifications | Recipient |

> **Note on notifications:** Email is used for out-of-band
> alerts (matching `repackage-surge.yml`). For tighter
> GitHub integration, consider supplementing with Issue
> comments or Discussions posts. Workflows can create
> issue comments using `GITHUB_TOKEN` without extra
> secrets.
| GHCR write access | Container image workflow | Push the test environment image |

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
