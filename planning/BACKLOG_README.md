# Backlog Issues

This directory contains the structured backlog for implementing the workflow automation system described in `workflow_master_plan.md` Section 10.

## Files

- **backlog_issues.json**: Complete list of all 31 implementation tasks from Section 10, structured as JSON. Each issue includes:
  - Phase and item number
  - Title with phase prefix
  - Detailed body with implementation details
  - Labels for categorization
  - References to relevant sections in the master plan

- **create_issues_from_backlog.py**: Python script to automatically create all GitHub issues from the JSON file

## Creating the Issues

**Note**: Due to network restrictions in automated environments, the issue creation scripts need to be run locally or in an environment with direct GitHub API access.

### Prerequisites

You'll need either:
- A GitHub personal access token with `repo` scope (create at: https://github.com/settings/tokens), OR
- The GitHub CLI (`gh`) installed and authenticated

### Recommended: Using gh CLI (Easiest)

The simplest method is to use the provided bash script with gh CLI:

```bash
# Install gh CLI if needed
# - macOS: brew install gh
# - Linux: see https://github.com/cli/cli/blob/trunk/docs/install_linux.md

# Authenticate
gh auth login

# Run the automated script
./planning/create_issues_with_gh.sh
```

This script will:
1. Verify gh CLI is available and authenticated
2. Read all 33 issues from `backlog_issues.json`
3. Create each issue with proper labels
4. Print a summary of results

### Alternative: Using Python Script

If you have Python and the `requests` library:

```bash
# Install requests if needed
pip3 install requests

# Set your GitHub token
export GITHUB_TOKEN=your_token_here

# Run the script
python3 planning/create_issues_from_backlog.py
```

### Manual Creation (If Automation Fails)

You can create issues manually using the GitHub web interface:

1. Go to https://github.com/Faraclas/adaptive-overlay/issues/new
2. Open `planning/backlog_issues.json`
3. For each item in the JSON array:
   - Copy the `title` field
   - Copy the `body` field
   - Add the labels listed in the `labels` array
   - Click "Submit new issue"

### Single Issue Example with gh CLI

To create just one issue (e.g., the first one):

```bash
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

### Automated: Using the Add Script

Run the provided script to add all issues at once:

```bash
# First, ensure you have the project scope
gh auth refresh -s project

# Run the script with your project number (from the URL)
./planning/add_issues_to_project.sh 1
```

The script will add all 31 issues (#7-#37) to your project board automatically.

### Manual: Using GitHub Web Interface

To add issues manually:

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

**Total**: 31 implementation tasks
