# Issues

One Markdown file per problem we carry a local patch for, or follow
upstream without one. Each file says why the patch exists, where the
upstream issue/PR is, and when the patch can be dropped.

This directory is not part of the Portage tree: nothing here is installed
and no ebuild reads it. pkgcheck lists it under `UnknownCategoryDirs` (a
warning, like `containers/` and `planning/`).

## Layout

```text
issues/
├── <pkg>-<slug>.md      # one issue
└── <pkg>-<slug>/        # only when one file is not enough
    ├── README.md        # the issue, same format
    └── ...              # repro scripts, test code, logs (text only)
```

- `<pkg>` is the package name without category (`cua-driver`,
  `hermes-agent`). `<slug>` names the problem, not an upstream number, so
  the name survives filing, re-filing and duplicate closures.
- No binary files: pkgcheck reports them anywhere in the repo.
- Each carried patch starts with a `Tracking: issues/<file>` header line.

## Format

```markdown
# <package>: <one-line problem>

- Package: `<cat>/<pkg>`
- Patch: `files/<patch>` (used by <ebuild versions>), or none
- Upstream: issue/PR links, or none filed
- Status: <state> (checked YYYY-MM-DD)
- Drop when: <condition>

## Problem
## Upstream (history, details)
## Notes
```

| State | Meaning |
| --- | --- |
| `open` | Upstream issue/PR exists, fix not released |
| `unfiled` | Should go upstream, nothing filed yet |
| `local` | Distro-specific, no upstream ask planned |
| `watching` | No local patch, we follow it upstream |
| `resolved` | Fixed in a release we ship; say which |

Drafts of upstream reports go in the issue file (a `## Draft` section)
until filed; then replace the draft with the link. GitHub keeps the text.

## On every upgrade

For each issue file naming the package:

1. Re-check every upstream ref live (state, merge commit, first release
   containing it). Never trust a saved status or a kanban card.
2. If the new release has the fix: drop the patch from the new ebuild,
   build-test without it, set `Status: resolved (<release>)`.
3. Otherwise: confirm the patch still applies, rename it to the first
   version it was rebased for if it changed, update "Patch" and the
   checked date.
4. When the last ebuild using a patch is removed, delete the patch and
   mark the issue `resolved` (or delete a `local` issue file).
