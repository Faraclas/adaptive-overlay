# Copilot Coding Agent — adaptive-overlay

This is `adaptive-overlay`, a Gentoo Linux overlay containing
custom ebuilds. It uses EAPI 8, masters `gentoo`, and produces
thin-manifests (unsigned).

---

## Safety — read this first

**Before doing anything, read
`.agent/instructions/general.md`.**

The hard rules:

- **Never install software on the host.** No `emerge`, `apt`,
  `pip install`, or any other package manager.
- **Never run `sudo`.**
- **Never modify system files** (`/etc`, `/usr`, `/var`).
- **Stay inside the overlay directory.** Do not touch files
  outside the repo root except `/home/elias/tmp/` for scratch.

Violating any of these is a showstopper. Stop and ask if you
are unsure.

---

## Agent context files

Read these to understand the repo and the task at hand:

- **`.agent/instructions/general.md`** — Safety rules and
  repo conventions. **READ FIRST.**
- **`.agent/skills/`** — Package-specific upgrade procedures
  (e.g. `update-zed-editor.md` for `app-editors/zed`).
- **`.agent/packages.json`** — Package registry with upstream
  metadata.

---

## Available scripts

All scripts live in `scripts/`. They handle Gentoo container
operations so you do not need Gentoo tools installed locally.
The agent environment is Ubuntu (via `.devcontainer`); these
scripts bridge the gap.

- **`scripts/upgrade-ebuild.sh <cat/pkg> --apply --json`**
  Detect upstream changes, apply mechanical updates, and
  output structured JSON.

- **`scripts/manifest.sh <cat/pkg>`**
  Generate `Manifest` in a Gentoo container.

- **`scripts/lint.sh [cat/pkg]`**
  Run pkgcheck QA scan in a Gentoo container.

- **`scripts/test-build.sh <cat/pkg> [ebuild-file]`**
  Build-test in a Gentoo container.

- **`scripts/check-updates.sh --json`**
  Check all packages for upstream updates.

---

## Workflow for upgrade issues

When you are assigned an upgrade issue, follow these steps:

1. **Read the issue body.** It contains structured JSON output
   from `upgrade-ebuild.sh` describing what changed upstream
   and what was already applied mechanically.
2. **Read the relevant skills doc** in `.agent/skills/`
   (e.g. `update-zed-editor.md` for `app-editors/zed`).
3. **Understand what the upgrade script already did.** The
   script applies mechanical changes (commit hash updates,
   version bumps). The JSON tells you what still needs agent
   attention.
4. **Make the intelligent edits.** This includes things like:
   - Inserting or removing `GIT_CRATES` entries
   - Updating `RUST_MIN_VER`
   - Adjusting patches in `files/`
   - Fixing dependency atoms
5. **Generate the Manifest:**

   ```sh
   scripts/manifest.sh <cat/pkg>
   ```

6. **Run the linter:**

   ```sh
   scripts/lint.sh <cat/pkg>
   ```

7. **If manifest or lint fails**, diagnose the error, fix the
   ebuild or metadata, and re-run until clean.
8. **Open a PR** with a clear summary of every change you
   made and why.

---

## Overlay structure

Packages live in `<category>/<name>/` directories:

```text
<category>/<name>/
├── <name>-<version>.ebuild
├── Manifest
├── metadata.xml
└── files/
```

- `.ebuild` — one or more versioned ebuilds
- `Manifest` — thin-manifest (auto-generated)
- `metadata.xml` — upstream, maintainer, USE flags
- `files/` — optional: patches, config snippets

Only these file types belong in the overlay tree. Do not leave
helper scripts, scratch files, or extra documentation in the
committed tree.

---

## Key constraint

The agent runs on Ubuntu, not Gentoo. All Gentoo-specific
operations (manifest generation, linting, build testing) are
handled by the `scripts/` wrappers which run inside disposable
Gentoo containers. You never need `emerge`, `ebuild`, or
`pkgcheck` installed locally — just call the scripts.
