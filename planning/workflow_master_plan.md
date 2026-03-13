# Workflow Master Plan — adaptive-overlay

## 1. Purpose & Goals

This document defines the automation strategy for the **adaptive-overlay** Gentoo overlay repository. The overlay provides ebuilds that are missing from other repos, track upstream more closely, or expose additional build features.

Two primary workflows must be supported:

| Workflow | Autonomy Level | Trigger |
|---|---|---|
| **New ebuild creation** | Collaborative (agent + human) | On-demand |
| **Ebuild upgrades** | Mostly/fully autonomous | On-demand, scheduled, or upstream-release |

Cross-cutting concerns that apply to both workflows:

* Ebuild quality checks (repoman/pkgcheck linting, manifest verification)
* Build & install testing inside a Gentoo container
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
│  │  • Supports: emerge, pkgcheck, repoman                       │   │
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
| 3 | **Lint** | CI | Run `pkgcheck scan` and `repoman manifest` inside the Gentoo container. |
| 4 | **Human review checkpoint** | Human | Agent opens a PR and requests review. If there are open questions (USE flags, optional deps, patches), the agent comments on the PR asking for input. |
| 5 | **Build test** | CI | Inside a Gentoo container: `emerge --pretend`, then `emerge` the package. Record build log as artifact. |
| 6 | **Iterate** | Agent + Human | Address review feedback and test failures. Repeat steps 3–5. |
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

A central file, `planning/packages.json` (or YAML), tracks each package the overlay provides:

```jsonc
[
  {
    "category": "app-editors",
    "name": "zed",
    "upstream_repo": "zed-industries/zed",         // GitHub owner/repo
    "upstream_type": "github-release",              // github-release | pypi | crate | custom
    "version_pattern": "v(.*)",                     // regex to extract version from tag
    "current_versions": ["0.226.5", "0.227.1"],
    "repackage": false,                             // whether source needs repackaging
    "auto_upgrade": true                            // whether fully autonomous upgrade is enabled
  },
  {
    "category": "media-sound",
    "name": "surgext",
    "upstream_repo": "surge-synthesizer/surge",
    "upstream_type": "github-release",
    "version_pattern": "release_xt_(.*)",
    "current_versions": ["1.3.4"],
    "repackage": true,
    "auto_upgrade": false
  }
  // ...
]
```

This registry is the single source of truth for the scheduled version-check job.

### 5.3 Steps (Autonomous Upgrade)

| # | Step | Details |
|---|---|---|
| 1 | **Detect new version** | Query upstream (GitHub Releases API, PyPI, etc.) and compare to `current_versions` in the package registry. |
| 2 | **Create branch** | `upgrade/<category>/<name>-<new_version>` |
| 3 | **Copy & update ebuild** | Copy the latest existing ebuild to `<name>-<new_version>.ebuild`. Update `SRC_URI`, checksums, and any version-specific patches. |
| 4 | **Regenerate Manifest** | Run `ebuild <name>-<new_version>.ebuild manifest` inside the container. |
| 5 | **Lint** | `pkgcheck scan` on the package directory. |
| 6 | **Build test** | `emerge =<category>/<name>-<new_version>` inside the Gentoo container. |
| 7 | **Open PR** | If lint and build succeed, open a PR. If `auto_upgrade` is true and all checks pass, the PR can be auto-merged. |
| 8 | **Notify** | Email / issue comment on failure. |

### 5.4 Source Repackaging

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
RUN emerge --oneshot app-portage/repoman dev-util/pkgcheck

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

# Full build test
./scripts/test-build.sh media-sound/carla-2.6.0
```

These wrapper scripts invoke `docker run` (or `podman run`) with the correct bind mounts and arguments, matching what the GitHub Actions workflows do.

---

## 7. Reusable Workflows & Actions

### 7.1 `lint-ebuild` (Reusable Workflow)

**Inputs:** `package_dir` (e.g. `media-sound/carla`)

**Steps:**

1. Start Gentoo container.
2. Run `pkgcheck scan <package_dir>` — fail on errors, warn on warnings.
3. Run `repoman manifest` to verify Manifest correctness.
4. Optionally run `shellcheck` on any helper scripts.

### 7.2 `test-ebuild` (Reusable Workflow)

**Inputs:** `package_atom` (e.g. `=media-sound/carla-2.6.0`)

**Steps:**

1. Start Gentoo container with cached portage tree and distfiles.
2. `emerge --pretend <package_atom>` — verify dependency resolution.
3. `emerge <package_atom>` — full compile and install.
4. Upload build log as GitHub Actions artifact.
5. Report pass/fail.

### 7.3 `repackage-source` (Reusable Workflow)

Generalization of the existing `repackage-surge.yml`.

**Inputs:** `upstream_repo`, `version`, `tag_pattern`, `tarball_prefix`, `release_tag_prefix`

**Steps:**

1. Clone upstream at the specified tag with submodules.
2. Create tarball excluding `.git` directories.
3. Create a GitHub Release with the tarball attached.

### 7.4 `check-upstream-versions` (Reusable Workflow)

**Inputs:** none (reads the package registry)

**Steps:**

1. For each package in `packages.json`:
   a. Query the upstream source for the latest version.
   b. Compare to known versions in the registry.
2. Output a list of packages that have new upstream versions.
3. For each new version, dispatch the appropriate upgrade or repackage workflow.

---

## 8. Agent Collaboration Model

### 8.1 Agent Capabilities

The AI coding agent (e.g. GitHub Copilot) should be able to:

* Read the package registry and ebuild templates.
* Generate new ebuilds by inspecting upstream build systems.
* Copy and modify existing ebuilds for version bumps.
* Run lint and build workflows and interpret their output.
* Open PRs and interact via PR comments.

### 8.2 Agent Entrypoints

| Task | Entry point |
|---|---|
| Create new ebuild | Issue assigned to agent → agent creates branch, drafts ebuild, opens PR |
| Upgrade ebuild | Workflow dispatches upgrade → agent (or script) performs the version bump |
| Fix lint/build failure | Agent reads CI failure logs, makes corrections, pushes to PR branch |

### 8.3 Providing Context to Agents

To help agents produce high-quality ebuilds:

* Maintain a `planning/ebuild_guidelines.md` document describing overlay-specific conventions (preferred USE flags, licensing practices, Manifest handling, etc.).
* Include example ebuilds in the repo that demonstrate common patterns (cmake-based, cargo-based, binary repackage, etc.).
* The package registry provides structured metadata the agent can consume.

---

## 9. Local Development Experience

### 9.1 Scripts

Create a `scripts/` directory with the following helpers:

| Script | Purpose |
|---|---|
| `scripts/lint.sh <pkg_dir>` | Run pkgcheck inside the Gentoo container on the specified package. |
| `scripts/test-build.sh <pkg_atom>` | Emerge the specified package inside the container. |
| `scripts/check-updates.sh` | Run the version-check logic locally, printing packages that have upstream updates. |
| `scripts/new-ebuild.sh <cat> <name> <ver>` | Scaffold a new ebuild skeleton with metadata.xml. |

### 9.2 Container Runtime

Scripts should support both Docker and Podman. Detect which is available and use it. The container image tag defaults to `ghcr.io/faraclas/adaptive-overlay-testenv:latest` but can be overridden via environment variable.

### 9.3 Makefile / Taskfile (Optional)

A top-level `Makefile` or `Taskfile.yml` can provide convenient aliases:

```makefile
lint:
	./scripts/lint.sh $(PKG)

test:
	./scripts/test-build.sh $(ATOM)

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
| 3.1 | Create `packages.json` (or YAML) with metadata for all current packages. |
| 3.2 | Create the `check-upstream-versions` workflow/script. |
| 3.3 | Create `scripts/check-updates.sh` for local use. |
| 3.4 | Set up scheduled cron trigger (e.g. twice weekly). |

### Phase 4 — Automated Ebuild Upgrades

> Goal: End-to-end autonomous version bumps.

| Item | Description |
|---|---|
| 4.1 | Create the `upgrade-ebuild.yml` workflow with dispatch inputs. |
| 4.2 | Implement the copy-and-update ebuild logic (script or agent instructions). |
| 4.3 | Integrate lint + build test into the upgrade workflow. |
| 4.4 | Implement auto-PR creation with appropriate labels. |
| 4.5 | Generalize `repackage-surge.yml` into a reusable `repackage-source.yml` workflow. |
| 4.6 | Wire the version-check workflow to automatically trigger upgrades. |

### Phase 5 — New Ebuild Creation Workflow

> Goal: Agent-assisted new ebuild creation with human collaboration.

| Item | Description |
|---|---|
| 5.1 | Create `planning/ebuild_guidelines.md` — conventions and patterns for agents. |
| 5.2 | Create `scripts/new-ebuild.sh` — scaffold a new ebuild skeleton. |
| 5.3 | Define the `new-ebuild.yml` workflow with issue/dispatch triggers. |
| 5.4 | Implement the human-in-the-loop mechanism (labels, PR comments, review requests). |
| 5.5 | Document the agent collaboration process. |

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
| `MAIL_PASSWORD` | Version check, notifications | SMTP authentication for email alerts |
| `MAIL_TO` | Version check, notifications | Notification recipient |
| GHCR write access | Container image workflow | Push the test environment image |

---

## 13. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Gentoo container builds are slow | Long CI times | Aggressive caching of portage tree, distfiles, and compiled packages (binpkgs). Build only the package under test, not full `@world`. |
| Upstream API rate limits | Version checks fail | Cache API responses. Use conditional requests (`If-None-Match`). Limit check frequency. |
| Ebuild complexity varies widely | Agent may produce incorrect ebuilds | Provide clear guidelines and examples. Require human review for new ebuilds. Allow auto-merge only for version bumps of packages with `auto_upgrade: true`. |
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
