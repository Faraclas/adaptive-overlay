# Workflow Master Plan — adaptive-overlay

## 1. Purpose & Goals

This document defines the automation strategy for the **adaptive-overlay** Gentoo overlay repository. The overlay provides ebuilds that are missing from other repos, track upstream more closely, or expose additional build features.

Two primary workflows must be supported:

| Workflow | Autonomy Level | Trigger |
|---|---|---|
| **New ebuild creation** | Collaborative (agent + human) | On-demand |
| **Ebuild upgrades** | Mostly/fully autonomous | On-demand, scheduled, or upstream-release |

Cross-cutting concerns that apply to both workflows:

* Ebuild quality checks (pkgcheck linting, `pkgdev manifest` verification)
* Build testing via `ebuild` command inside a Gentoo container
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
| Existing CI | `repackage-surge.yml` — weekly check + manual dispatch for Surge XT tarball repackaging |
| Package categories | `app-editors`, `media-sound`, `net-vpn` |

---

### 2.1 File Organization — Agent vs Human Files

A Gentoo overlay has a well-defined directory structure that humans and tools like `pkgcheck` expect. Automation and agent-facing files should live separately from the standard overlay tree to avoid confusion.

**Standard overlay directories** (human / Gentoo tooling):

| Path | Contents |
|---|---|
| `<category>/<package>/` | Ebuilds, Manifest, metadata.xml — the overlay itself |
| `metadata/` | Overlay-level metadata (`layout.conf`, etc.) |
| `profiles/` | Profile configuration |
| `licenses/` | Custom license files |
| `.github/workflows/` | CI/CD workflow definitions |
| `scripts/` | Helper scripts for local development (lint, test-build, etc.) |
| `planning/` | Human-readable planning documents (this file, roadmaps, etc.) |

**Agent-facing directory** (`.agent/`):

Files that agents reference during automated tasks — structured metadata, skills, and per-package instructions — live in `.agent/` at the repo root:

| Path | Purpose |
|---|---|
| `.agent/packages.json` | Package registry with upstream tracking metadata (§5.2) |
| `.agent/skills/` | Reusable agent skill documents (e.g. "how to upgrade a Cargo-based ebuild") |
| `.agent/instructions/` | Per-package upgrade/creation instructions (e.g. the Zed update process) |
| `.agent/ebuild_guidelines.md` | Overlay-specific conventions for agents (USE flags, licensing, Manifest handling) |

This separation keeps the overlay directory clean for human contributors and Gentoo tooling, while giving agents a well-known location to find structured context. The `.agent/` prefix signals that these files are machine-consumed and may be auto-generated or auto-updated.

> **Note:** The `.agent/` directory is committed to the repo so agents can access it. It is not hidden from humans — anyone can read and edit these files — but its primary audience is automated tooling.

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
│  │ (pkgcheck /    │ │ (container build │ │ (tarball creation for  │ │
│  │  repoman)      │ │  & install)      │ │  submodule projects)   │ │
│  └────────────────┘ └──────────────────┘ └────────────────────────┘ │
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
│  │  • Supports: ebuild, pkgdev, pkgcheck, repoman               │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 4. Workflow 1 — New Ebuild Creation

### 4.1 Trigger

* A GitHub Issue is filed (manually or by an agent) requesting a new ebuild.
* The `new-ebuild.yml` workflow can also be dispatched manually with inputs: `category`, `package_name`, `version`, and `upstream_url`.

### 4.2 Steps

| # | Step | Actor | Details |
|---|---|---|---|
| 1 | **Gather upstream metadata** | Agent | Clone/inspect upstream repo. Determine: homepage, license, build system (cmake, meson, cargo, etc.), dependencies, SRC_URI pattern. |
| 2 | **Draft ebuild** | Agent | Generate a skeleton `.ebuild` following EAPI 8 conventions. Place it in `<category>/<package>/`. Generate `metadata.xml`. |
| 3 | **Lint** | CI | Run `pkgcheck scan` and `pkgdev manifest` inside the Gentoo container. |
| 4 | **Human review checkpoint** | Human | Agent opens a PR and requests review. If there are open questions (USE flags, optional deps, patches), the agent comments on the PR asking for input. |
| 5 | **Build test** | CI | Inside a Gentoo container: `ebuild ./<name>-<version>.ebuild clean compile`. If build fails, the agent fixes the ebuild and pushes a new commit to repeat steps 3–5 (see §5.4 for retry strategy). Final integration test with `emerge` runs only in the container. Record build log as artifact. |
| 6 | **Iterate** | Agent + Human | Address review feedback and test failures across commits. Repeat steps 3–5. Agent must follow safety constraints (§8.4). |
| 7 | **Merge** | Human | Final approval and merge. |

### 4.3 Human-in-the-Loop Mechanisms

* **PR comments**: The agent posts questions as PR comments and labels the PR `waiting-for-human`.
* **Issue threads**: For broader design decisions, discussion happens in the originating issue.
* **Workflow dispatch inputs**: Humans can supply overrides (USE flags, patches, SRC_URI) via workflow dispatch inputs or PR comments that the agent parses.

---

## 5. Workflow 2 — Ebuild Upgrades

### 5.1 Triggers

| Trigger | Mechanism |
|---|---|
| **On-demand** | `workflow_dispatch` with inputs `package` (e.g. `media-sound/carla`) and `version` (e.g. `2.6.0` or `latest`). |
| **Scheduled** | Cron job (e.g. twice weekly) runs a version-check job across all tracked packages. |
| **Upstream release** | GitHub webhook via `repository_dispatch` or a watcher workflow that polls GitHub Releases API (extending the pattern already used in `repackage-surge.yml`). |

### 5.2 Package Registry

The overlay's directory structure is the canonical source of truth for package data — categories, names, and versions are all derivable from the ebuild file tree. However, some automation-specific metadata has no natural home in standard Gentoo overlay files:

* **Upstream repo location** (`zed-industries/zed`) — needed to poll for new releases
* **Version tag pattern** (`v(.*)`, `release_xt_(.*)`) — needed to extract versions from upstream tags
* **Upstream type** (GitHub release, PyPI, crate, etc.) — determines which API to poll
* **Repackage flag** — whether the package needs source repackaging before build
* **Auto-upgrade eligibility** — whether a version bump can be auto-merged without human review

This metadata lives in `.agent/packages.json` (see §2.1 for the `.agent/` directory rationale):

```jsonc
[
  {
    "category": "app-editors",
    "name": "zed",
    "upstream_repo": "zed-industries/zed",
    "upstream_type": "github-release",
    "version_pattern": "v(.*)",
    "repackage": false,
    "auto_upgrade": true
  },
  {
    "category": "media-sound",
    "name": "surgext",
    "upstream_repo": "surge-synthesizer/surge",
    "upstream_type": "github-release",
    "version_pattern": "release_xt_(.*)",
    "repackage": true,
    "auto_upgrade": false
  }
]
```

Note: `current_versions` is intentionally omitted — the overlay tree itself is the source of truth for what versions exist. The version-check workflow derives current versions by scanning ebuild filenames at runtime.

### 5.3 Steps (Autonomous Upgrade)

| # | Step | Details |
|---|---|---|
| 1 | **Detect new version** | Query upstream (GitHub Releases API, PyPI, etc.) using metadata from `.agent/packages.json`. Compare to versions found by scanning ebuild filenames in the overlay. |
| 2 | **Verify sources available** | Confirm the upstream source tarball (and any supplementary archives, e.g. crates tarballs) are downloadable before proceeding. |
| 3 | **Create branch** | `upgrade/<category>/<name>-<new_version>` |
| 4 | **Copy ebuild** | Copy the latest existing ebuild to `<name>-<new_version>.ebuild`. |
| 5 | **Check for dependency changes** | Diff upstream build manifests between old and new versions (see §5.5). Update the ebuild as needed. |
| 6 | **Regenerate Manifest** | `cd <category>/<package> && pkgdev manifest` — fetches new source archives and updates checksums. |
| 7 | **Lint** | `pkgcheck scan` on the package directory. |
| 8 | **Build test** | `ebuild ./<name>-<new_version>.ebuild clean compile` inside the Gentoo container. If build fails, the agent fixes the ebuild and re-runs (see §5.4 for retry strategy). |
| 9 | **Verify build output** | Check that expected binaries exist in the build image, verify version strings, and confirm dynamic linkage is sane (`ldd`). |
| 10 | **Final integration test** | `emerge` the package inside a disposable container to confirm Portage integration (dependency resolution, slot handling, post-install actions). Never run on the host (see §5.4). |
| 11 | **Open PR** | If lint and build succeed, open a PR. If `auto_upgrade` is true and all checks pass, the PR can be auto-merged. |
| 12 | **Notify** | Email / issue comment on failure. |

### 5.4 Build & Test Tooling: `ebuild` for Iteration, `emerge` for Final Testing

The build/test process uses a **two-tier approach**:

**Tier 1 — `ebuild` (primary, used for development iteration):**

The `ebuild` command is the primary tool for building and testing ebuilds during development, both in CI and locally. Unlike `emerge` (Portage), `ebuild` operates directly on a single `.ebuild` file from the overlay source tree without interacting with the system package database. This provides:

* **Isolation** — Clear separation between the development overlay and the installed system. No risk of polluting the host or system repo.
* **Consistency** — The same `ebuild ./pkg-1.0.ebuild clean compile` command works identically in CI containers and on a developer's workstation.
* **Granular control** — Individual phases (`clean`, `fetch`, `unpack`, `prepare`, `compile`, `install`) can be run and retried independently.
* **Speed on retry** — After a compile-phase failure, re-running `ebuild ./pkg.ebuild compile` (without `clean`) reuses the already-unpacked and patched source tree, skipping the slow unpack/patch phase.

All iterative development — fixing dependency issues, adjusting USE flags, debugging compile failures — should use `ebuild`. This is the tool agents use for the vast majority of build/test cycles.

**Tier 2 — `emerge` (final integration test, container only):**

Once an ebuild compiles successfully with `ebuild`, a final `emerge` test inside a Gentoo container confirms that the package integrates correctly with Portage (dependency resolution, slot handling, post-install actions). This step is **never run on the host system** — it executes exclusively inside a disposable container to prevent any system modification.

**Important:** The existing toolchain, both locally and in the container, is assumed to be sufficient. Agents must follow the safety constraints in §8.4 regarding system tool installation and file modification.

The workflow uses `pkgdev manifest` (from `dev-util/pkgdev`) for Manifest generation rather than `ebuild manifest` or `repoman manifest`, as `pkgdev` is the modern replacement and handles fetching and hashing correctly.

### 5.5 Dependency Change Detection (Upgrade Sub-Process)

When upgrading an ebuild, always check for upstream dependency changes before considering the update complete. The exact checks depend on the build system:

#### Cargo / Rust packages (e.g. `app-editors/zed`)

Diff the upstream `Cargo.toml` between old and new versions and look for:

| Change detected | Action |
|---|---|
| A git dependency's `rev =` changed | Update the commit hash in `GIT_CRATES` |
| A new `{ git = "...", rev = "..." }` dependency appeared | Add a new entry to `GIT_CRATES` |
| A git dependency was removed | Remove its entry from `GIT_CRATES` |
| New workspace members added | Fetch their `Cargo.toml` files and scan for git deps |
| `rust-version` changed | Update `RUST_MIN_VER` in the ebuild |
| Crates.io version bumps | No action — handled by the crates tarball |

Also check release notes for mentions of new system-level libraries that would affect `DEPEND`/`BDEPEND`.

#### CMake / Meson packages

Diff `CMakeLists.txt` or `meson.build` for changed `find_package()`, `dependency()`, or version requirements. Update `DEPEND`/`BDEPEND` accordingly.

#### Binary repackage packages

Typically no dependency changes, but verify runtime library requirements by checking `ldd` output after build.

### 5.6 Source Repackaging

Some packages (e.g. Surge XT) require source repackaging because upstream tarballs do not include git submodules. The existing `repackage-surge.yml` handles this for Surge XT.

This pattern should be generalized into a **reusable workflow** (`.github/workflows/repackage-source.yml`) that accepts:

* `upstream_repo`
* `version`
* `tag_pattern`
* `tarball_name_pattern`
* `release_tag_pattern`

The upgrade workflow will call the repackage workflow first when the package registry has `"repackage": true`.

---

## 6. Gentoo Container Environment

### 6.1 Why a Container?

* Provides a reproducible Gentoo stage3 environment with a synced portage tree.
* Avoids polluting the developer's host system.
* Runs identically in GitHub Actions and locally.

### 6.2 Container Image

Use the official `gentoo/stage3` Docker image as a base. Build a custom image on top:

```dockerfile
FROM gentoo/stage3:latest

# Sync portage tree
RUN emerge-webrsync

# Install overlay tooling
RUN emerge --oneshot app-portage/repoman dev-util/pkgcheck dev-util/pkgdev

# Configure the overlay mount point
RUN mkdir -p /var/db/repos/adaptive-overlay
COPY metadata/ /var/db/repos/adaptive-overlay/metadata/
COPY profiles/ /var/db/repos/adaptive-overlay/profiles/

# repos.conf entry for the overlay
RUN echo '[adaptive-overlay]\nlocation = /var/db/repos/adaptive-overlay\nauto-sync = no' \
    > /etc/portage/repos.conf/adaptive-overlay.conf
```

At workflow runtime, the repo contents are bind-mounted into the container so that the latest ebuild changes are visible.

### 6.3 Caching

* The portage tree sync is expensive. Cache the synced tree as a Docker layer or GitHub Actions cache.
* `distfiles` (downloaded source tarballs) should be cached between runs to speed up repeated builds.
* The custom container image should be published to GHCR (GitHub Container Registry) and rebuilt weekly or on portage tree updates.

### 6.4 Local Usage

Developers can run the same container locally:

```bash
# Quick lint check
./scripts/lint.sh media-sound/carla

# Full build test (runs: ebuild ./carla-2.6.0.ebuild clean compile)
./scripts/test-build.sh media-sound/carla carla-2.6.0.ebuild
```

These wrapper scripts invoke `docker run` (or `podman run`) with the correct bind mounts and arguments, matching what the GitHub Actions workflows do.

---

## 7. Reusable Workflows & Actions

### 7.1 `lint-ebuild` (Reusable Workflow)

**Inputs:** `package_dir` (e.g. `media-sound/carla`)

**Steps:**

1. Start Gentoo container.
2. Run `pkgcheck scan <package_dir>` — fail on errors, warn on warnings.
3. Run `pkgdev manifest` to regenerate the Manifest (fetches sources and updates checksums).
4. Optionally run `shellcheck` on any helper scripts.

### 7.2 `test-ebuild` (Reusable Workflow)

**Inputs:** `package_dir` (e.g. `media-sound/carla`), `ebuild_file` (e.g. `carla-2.6.0.ebuild`)

**Steps:**

1. Start Gentoo container with cached portage tree and distfiles. Bind-mount the overlay source tree.
2. `ebuild ./<ebuild_file> clean compile` — full build from source in the overlay directory. Iterate with `ebuild` on failures.
3. Verify build output: check expected binaries exist, confirm version strings, validate linkage with `ldd`.
4. `emerge --oneshot <category>/<package>` — final integration test inside the container to confirm Portage-level correctness. This step runs only in the container, never on the host.
5. Upload build log as GitHub Actions artifact.
6. Report pass/fail.

### 7.3 `repackage-source` (Reusable Workflow)

Generalization of the existing `repackage-surge.yml`.

**Inputs:** `upstream_repo`, `version`, `tag_pattern`, `tarball_prefix`, `release_tag_prefix`

**Steps:**

1. Clone upstream at the specified tag with submodules.
2. Create tarball excluding `.git` directories.
3. Create a GitHub Release with the tarball attached.

### 7.4 `check-upstream-versions` (Reusable Workflow)

**Inputs:** none (reads `.agent/packages.json` and scans the overlay tree)

**Steps:**

1. For each package in `.agent/packages.json`:
   a. Derive current versions by scanning ebuild filenames in `<category>/<name>/`.
   b. Query the upstream source for the latest version.
   c. Compare to the versions found on disk.
2. Output a list of packages that have new upstream versions.
3. For each new version, dispatch the appropriate upgrade or repackage workflow.

---

## 8. Agent Collaboration Model

### 8.1 Agent Capabilities

The AI coding agent (e.g. GitHub Copilot) should be able to:

* Read `.agent/packages.json` and per-package instructions in `.agent/instructions/`.
* Generate new ebuilds by inspecting upstream build systems.
* Copy and modify existing ebuilds for version bumps.
* Run lint and build workflows and interpret their output.
* Open PRs and interact via PR comments.

Agents must always operate within the safety constraints defined in §8.4 — no system tool installation or system file modification without explicit approval.

### 8.2 Agent Entrypoints

| Task | Entry point |
|---|---|
| Create new ebuild | Issue assigned to agent → agent creates branch, drafts ebuild, opens PR |
| Upgrade ebuild | Workflow dispatches upgrade → agent (or script) performs the version bump |
| Fix lint/build failure | Agent reads CI failure logs, makes corrections, pushes to PR branch |

### 8.3 Providing Context to Agents

To help agents produce high-quality ebuilds:

* Maintain `.agent/ebuild_guidelines.md` describing overlay-specific conventions (preferred USE flags, licensing practices, Manifest handling, etc.).
* Provide per-package upgrade instructions in `.agent/instructions/` (e.g. the Zed update process from §5.5 as `.agent/instructions/app-editors-zed.md`).
* Store reusable agent skill documents in `.agent/skills/` (e.g. "how to upgrade a Cargo-based ebuild", "how to handle GIT_CRATES").
* Include example ebuilds in the overlay that demonstrate common patterns (cmake-based, cargo-based, binary repackage, etc.).
* `.agent/packages.json` provides structured upstream metadata the agent can consume for version checking and upgrade automation.

### 8.4 Agent Safety Constraints

Agents operate under strict safety rules that protect the developer's system while still allowing full automation in controlled environments. The installed toolchain — both locally and in containers — is assumed to be sufficient for all workflow tasks.

#### System tool installation

| Environment | Rule |
|---|---|
| **Local system** | Agents must **never** install system tools (via `emerge`, `apt`, `pip install --system`, etc.). All required tools are already present. |
| **CI container** | Tool installation is permitted **only** if explicitly defined as part of the workflow (e.g. in the Dockerfile or a workflow step). Agents must not install ad-hoc tools without prior approval. |

If an agent encounters a missing tool, it must **pause and request human guidance** — post a PR comment describing the missing tool, apply the `waiting-for-human` label, and stop work on that step until the human responds.

#### System file modification

| Environment | Rule |
|---|---|
| **Local system** | Agents must **never** modify system files (e.g. `/etc/portage/*`, `/var/db/repos/*`, `/usr/*`) without explicit permission from the human via a PR comment or issue thread. All agent work products should be confined to the overlay directory and designated temp workspaces. |
| **CI container** | System file modification is permitted **only** if defined as part of the workflow (e.g. configuring `repos.conf` for the overlay in the Dockerfile). Even in containers, agents should seek approval via PR comment before making system changes not already anticipated by the workflow definition. |

#### Rationale

These constraints allow:
* **Full automation in CI/cloud** — Containers are disposable; workflow-defined system changes are safe and reproducible.
* **Protection for local systems** — A developer's workstation is never used as an experimental testbed. The `ebuild` tool (§5.4) provides build/test capability without touching the system, and containers handle the final `emerge` integration test.
* **Flexibility with guardrails** — When workflows evolve to need new tools or system changes, they are added to the workflow definition (Dockerfile, workflow YAML) with human review, not installed ad-hoc by agents.

---

## 9. Local Development Experience

### 9.1 Scripts

Create a `scripts/` directory with the following helpers:

| Script | Purpose |
|---|---|
| `scripts/lint.sh <pkg_dir>` | Run pkgcheck inside the Gentoo container on the specified package. |
| `scripts/test-build.sh <pkg_dir> <ebuild_file>` | Run `ebuild ./<file> clean compile` inside the container. |
| `scripts/check-updates.sh` | Run the version-check logic locally, printing packages that have upstream updates. |
| `scripts/new-ebuild.sh <cat> <name> <ver>` | Scaffold a new ebuild skeleton with metadata.xml. |

### 9.2 Container Runtime

Scripts should support both Docker and Podman. Detect which is available and use it. The container image tag defaults to `ghcr.io/<OWNER>/adaptive-overlay-testenv:latest` (where `<OWNER>` is the GitHub repository owner, e.g. `faraclas`) and can be overridden via the `TESTENV_IMAGE` environment variable.

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

The work is broken into sequential phases. Each phase produces usable, testable deliverables.

### Phase 1 — Foundation (Container & Lint)

> Goal: Establish the container environment and basic lint CI.

| Item | Description |
|---|---|
| 1.1 | Create `Dockerfile` for the Gentoo test environment. |
| 1.2 | Set up GHCR publishing workflow for the container image (weekly rebuild). |
| 1.3 | Create the `lint-ebuild` reusable workflow. |
| 1.4 | Create `scripts/lint.sh` for local use. |
| 1.5 | Add a CI workflow that lints changed ebuilds on every PR. |

### Phase 2 — Build Testing

> Goal: Enable full emerge testing in CI and locally.

| Item | Description |
|---|---|
| 2.1 | Create the `test-ebuild` reusable workflow. |
| 2.2 | Create `scripts/test-build.sh` for local use. |
| 2.3 | Integrate build testing into the PR CI pipeline (triggered for changed ebuilds). |
| 2.4 | Implement distfiles and portage tree caching for faster CI runs. |

### Phase 3 — Package Registry & Version Checking

> Goal: Track packages and detect upstream updates.

| Item | Description |
|---|---|
| 3.1 | Create `.agent/packages.json` with upstream tracking metadata for all current packages. |
| 3.2 | Create the `check-upstream-versions` workflow/script (reads `.agent/packages.json`, scans overlay for current versions). |
| 3.3 | Create `scripts/check-updates.sh` for local use. |
| 3.4 | Set up scheduled cron trigger (e.g. twice weekly). |

### Phase 4 — Automated Ebuild Upgrades

> Goal: End-to-end autonomous version bumps.

| Item | Description |
|---|---|
| 4.1 | Create the `upgrade-ebuild.yml` workflow with dispatch inputs. |
| 4.2 | Implement the copy-and-update ebuild logic including dependency change detection (§5.5). |
| 4.3 | Integrate lint + `ebuild` build test into the upgrade workflow. |
| 4.4 | Implement auto-PR creation with appropriate labels. |
| 4.5 | Generalize `repackage-surge.yml` into a reusable `repackage-source.yml` workflow. |
| 4.6 | Wire the version-check workflow to automatically trigger upgrades. |

### Phase 5 — New Ebuild Creation Workflow

> Goal: Agent-assisted new ebuild creation with human collaboration.

| Item | Description |
|---|---|
| 5.1 | Create `.agent/ebuild_guidelines.md` — conventions and patterns for agents. |
| 5.2 | Create `scripts/new-ebuild.sh` — scaffold a new ebuild skeleton. |
| 5.3 | Define the `new-ebuild.yml` workflow with issue/dispatch triggers. |
| 5.4 | Implement the human-in-the-loop mechanism (labels, PR comments, review requests). |
| 5.5 | Document the agent collaboration process. Populate `.agent/skills/` and `.agent/instructions/` with initial content. |

### Phase 6 — Upstream Release Triggers

> Goal: React to upstream GitHub releases in near-real-time.

| Item | Description |
|---|---|
| 6.1 | Evaluate options: `repository_dispatch` via external webhook vs. polling workflow. |
| 6.2 | Implement the chosen trigger mechanism for GitHub-hosted upstreams. |
| 6.3 | Connect release triggers to the upgrade workflow. |

### Phase 7 — Polish & Documentation

> Goal: Comprehensive documentation and developer experience.

| Item | Description |
|---|---|
| 7.1 | Update `README.md` with contributing/CI documentation. |
| 7.2 | Add a `CONTRIBUTING.md` covering the workflow for human and agent contributors. |
| 7.3 | Create optional `Makefile` or `Taskfile.yml`. |
| 7.4 | Review and harden all workflows (permissions, secrets, error handling). |

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

Phases 1–2 (container + testing) are prerequisites for everything else. Phase 3 (version checking) and Phase 5 (new ebuilds) can proceed in parallel once Phase 1 is done. Phase 4 (upgrades) depends on Phases 2 and 3. Phase 6 (release triggers) extends Phase 4. Phase 7 wraps up after the core workflows are functional.

---

## 12. Secrets & Permissions Required

| Secret / Permission | Used By | Purpose |
|---|---|---|
| `GITHUB_TOKEN` (default) | All workflows | Create PRs, releases, push branches |
| `MAIL_USERNAME` | Version check, notifications | SMTP authentication for email alerts |
| `MAIL_PASSWORD` | Version check, notifications | SMTP authentication for email alerts (must be stored as a GitHub encrypted secret — never commit to source) |
| `MAIL_TO` | Version check, notifications | Notification recipient |

> **Note on notifications:** Email is used for out-of-band alerts (matching the existing `repackage-surge.yml` pattern). For tighter GitHub integration, consider supplementing email with GitHub Issue comments or Discussions posts so that notification history is co-located with the code. Workflows can create issue comments using the default `GITHUB_TOKEN` without additional secrets.
| GHCR write access | Container image workflow | Push the test environment image |

---

## 13. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Gentoo container builds are slow | Long CI times | Aggressive caching of portage tree, distfiles, and compiled packages (binpkgs). Build only the package under test, not full `@world`. |
| Upstream API rate limits | Version checks fail | Cache API responses. Use conditional requests (`If-None-Match`). Limit check frequency. |
| Ebuild complexity varies widely | Agent may produce incorrect ebuilds | Provide clear guidelines and examples. Require human review for new ebuilds. Allow auto-merge only for version bumps of packages with `auto_upgrade: true`. |
| Supply-chain attacks via upstream | Auto-merged bump includes malicious code | Even for `auto_upgrade` packages, the build-test step acts as a first gate. Add a checksum/signature verification step where upstream provides signed releases. Consider a brief hold period (e.g. 24 hours) before auto-merge to allow community detection of compromised releases. Security-critical packages should never be `auto_upgrade: true`. |
| Container image staleness | Tests against outdated portage tree | Weekly automated rebuild of the container image. Allow manual rebuild dispatch. |
| Flaky upstream sources | Build tests fail due to transient download errors | Retry logic in emerge. Cache distfiles. Use mirrors. |

---

## 14. Success Criteria

The workflow system is considered complete when:

1. Every PR automatically receives lint and build-test results.
2. Version bumps for `auto_upgrade` packages happen without human intervention, from detection through merge.
3. An agent can be assigned a "create new ebuild" issue and produce a working, tested PR with minimal human guidance.
4. All CI workflows can be replicated locally using the provided scripts and container image.
5. The package registry accurately reflects the overlay contents and is kept up to date by automation.
