# Agent Instructions — adaptive-overlay

Read this before doing anything in this repo.

This is a Gentoo overlay (`adaptive-overlay`). The `.agent/` directory holds
automation metadata — it is NOT part of the overlay itself and is never
deployed.

---

## Hard rules — no exceptions

1. **Never install software on the host.** Do not run `emerge`, `apt`,
   `dnf`, `pip install`, or any other package manager on the local system.
   All required software is already present.
2. **Never run `sudo` directly** unless it is through a known alias the user
   has set up. If you think you need root, stop and ask.
3. **Never modify system files** (`/etc`, `/usr`, `/var`, etc.) on the local
   system without explicit permission from the user.
4. **Stay inside the overlay directory.** Your working tree is the repo root.
   Do not touch files outside it except for the designated temp workspace
   (see below).
5. **If a tool is missing, stop and ask.** Do not attempt to install it. The
   installed toolchain is assumed to be sufficient.
6. **In CI containers**, only install tools that are defined in the workflow
   file. No ad-hoc installs.

---

## Repository layout & conventions

| Item | Detail |
|---|---|
| EAPI | `8` |
| Masters | `gentoo` |
| Manifests | thin-manifests, unsigned |
| Overlay path (container) | `/var/db/repos/adaptive-overlay` |
| Overlay path (local) | repo root |
| Package metadata | `.agent/packages.json` |
| Package-specific instructions | `.agent/instructions/` |
| Skills / workflows | `.agent/skills/` (if present) |
| CI scripts | `scripts/` |

---

## What you may create or edit in the overlay

- `.ebuild` files
- `Manifest` files
- `metadata.xml` per package
- `files/` directory contents (patches, config snippets) when required by an
  ebuild

**Do not** leave helper scripts, scratch files, or extra documentation inside
the overlay tree after you finish a task. The committed tree should contain
only overlay-standard content.

---

## Temporary workspace

Use `/home/elias/tmp/` for any scratch work:

- Create subdirectories as needed.
- Clean up after yourself when the task is done.

---

## Build testing

### Iterative development — `ebuild` command

```/dev/null/example.sh#L1-2
ebuild ./<package>.ebuild clean compile   # full cycle
ebuild ./<package>.ebuild compile         # retry after failure — skip clean if ebuild unchanged
```

Use this for fast feedback while editing ebuilds. It runs phases individually
without pulling in the full dependency resolver.

### Local container-based testing

```/dev/null/example.sh#L1
scripts/test-build.sh <category>/<package>
```

Runs a build inside a disposable container. Scripts in `scripts/` prefer
Podman and fall back to Docker.

### Linting

```/dev/null/example.sh#L1
scripts/lint.sh
```

Run this before committing.

### Full integration test — `emerge`

`emerge` is for **disposable containers only** — never on the host. Use it as
a final integration check after iterative `ebuild` testing passes.

---

## Summary checklist (quick reference)

- [ ] No package-manager installs on host
- [ ] No `sudo` unless known alias
- [ ] No system file modifications
- [ ] Work confined to overlay directory + `/home/elias/tmp/`
- [ ] Only `.ebuild`, `Manifest`, `metadata.xml`, and `files/` in the overlay
- [ ] Temp files cleaned up
- [ ] `scripts/lint.sh` passes
- [ ] Build tested with `ebuild` or `scripts/test-build.sh`
- [ ] `emerge` only in disposable containers