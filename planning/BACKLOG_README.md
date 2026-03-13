# Backlog Issues

This directory contains the structured backlog for implementing the workflow automation system described in `workflow_master_plan.md` Section 10.

## Files

- **backlog_issues.json**: Complete list of all 33 implementation tasks from Section 10, structured as JSON. Each issue includes:
  - Phase and item number
  - Title with phase prefix
  - Detailed body with implementation details
  - Labels for categorization
  - References to relevant sections in the master plan

- **create_issues_from_backlog.py**: Python script to automatically create all GitHub issues from the JSON file

## Creating the Issues

### Prerequisites

You'll need a GitHub personal access token with `repo` scope. Create one at:
https://github.com/settings/tokens

### Option 1: Using the Python Script

```bash
# Set your GitHub token
export GITHUB_TOKEN=your_token_here

# Run the script
python3 planning/create_issues_from_backlog.py
```

The script will:
1. Read all issues from `backlog_issues.json`
2. Create each issue in the `Faraclas/adaptive-overlay` repository
3. Apply the appropriate labels
4. Print a summary of created issues

### Option 2: Manual Creation

You can also create issues manually by reading `backlog_issues.json` and creating them through the GitHub web interface or gh CLI.

### Option 3: Using gh CLI

If you prefer using the GitHub CLI:

```bash
# Authenticate
gh auth login

# Create each issue (example for first issue)
gh issue create \
  --repo Faraclas/adaptive-overlay \
  --title "[Phase 1.1] Create Containerfile for Gentoo test environment" \
  --body "$(jq -r '.[0].body' planning/backlog_issues.json)" \
  --label "phase-1,infrastructure,container"
```

## Implementation Order

The issues should be tackled in phase order as they have dependencies:

1. **Phase 1** (Foundation): Container environment and linting infrastructure
2. **Phase 2** (Build Testing): Build/test workflows and caching
3. **Phase 3** (Package Registry): Version checking infrastructure
4. **Phase 4** (Automated Upgrades): Autonomous version bump workflows
5. **Phase 5** (New Ebuild Creation): Collaborative ebuild creation
6. **Phase 6** (Release Triggers): Upstream release automation
7. **Phase 7** (Polish): Documentation and security hardening

See `workflow_master_plan.md` Section 11 (Dependency Graph) for detailed dependencies.

## Adding to GitHub Project

After creating the issues, they can be added to the project board at:
https://github.com/users/Faraclas/projects/1

To add all created issues to the current iteration/backlog:

1. Go to the project board
2. Click "+ Add item" or use the command palette (Cmd/Ctrl+K)
3. Search for the phase labels (e.g., `label:phase-1`)
4. Select and add the issues
5. Set the iteration/status as needed

## Total Tasks

- **Phase 1**: 5 tasks (Foundation)
- **Phase 2**: 4 tasks (Build Testing)
- **Phase 3**: 4 tasks (Package Registry & Version Checking)
- **Phase 4**: 6 tasks (Automated Ebuild Upgrades)
- **Phase 5**: 5 tasks (New Ebuild Creation Workflow)
- **Phase 6**: 3 tasks (Upstream Release Triggers)
- **Phase 7**: 4 tasks (Polish & Documentation)

**Total**: 33 implementation tasks
