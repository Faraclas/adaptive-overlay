# GitHub Projects Access: User vs Repository Level

## The Problem

GitHub has two types of Projects V2:
1. **User-level projects** (`https://github.com/users/<username>/projects/<number>`)
2. **Repository-level projects** (`https://github.com/<owner>/<repo>/projects/<number>`)

Bot integrations (like the Claude agent) can **only** access repository-level and organization-level projects. They cannot access user-level projects due to GitHub's security model.

## Diagnostic

Run the diagnostic script to confirm the issue:
```bash
./planning/diagnose_project_access.sh
```

If all queries return empty arrays, your project is user-level and not accessible to bots.

## Solution: Convert to Repository Project

Unfortunately, GitHub doesn't provide a direct "convert" function. You have two options:

### Option A: Create a New Repository-Level Project

1. Go to your repository: https://github.com/Faraclas/adaptive-overlay
2. Click on "Projects" tab
3. Click "Link a project" > "New project"
4. Create the project at the repository level
5. Once created, run:
   ```bash
   # Get the project number from the URL
   ./planning/add_issues_to_project.sh <project_number>
   ```

### Option B: Manually Copy Items to Repository Project

If you want to keep your existing user project and just copy the issues:

1. Create a new repository-level project (as above)
2. The bot can then add items to the repository project:
   ```bash
   gh project item-add <repo-project-number> \
     --owner Faraclas \
     --url "https://github.com/Faraclas/adaptive-overlay/issues/7"
   ```

### Option C: Continue with User Project (Manual)

If you prefer to keep the user-level project:

**Quick Web UI method (30 seconds):**
1. Go to https://github.com/users/Faraclas/projects/1
2. Press Cmd/Ctrl+K or click "+"
3. Search: `repo:Faraclas/adaptive-overlay is:issue Phase`
4. Select all 31 issues (#7-#37) and add them

**With personal token:**
```bash
# Your personal gh CLI has the right permissions
gh auth login  # Use your personal account
./planning/add_issues_to_project.sh 1
```

## Why This Limitation Exists

GitHub's security model prevents bots from:
- Accessing personal user data (including user-level projects)
- Modifying user settings without explicit repository/org context
- This protects user privacy and prevents unauthorized access

Bots can only operate on:
- Repository resources (issues, PRs, code)
- Organization resources (if installed at org level)
- Repository-scoped or org-scoped projects

## Verification

After creating a repository-level project, verify the bot can access it:

```bash
gh api graphql -f query='
query {
  repository(owner: "Faraclas", name: "adaptive-overlay") {
    projectsV2(first: 10) {
      nodes {
        id
        number
        title
        url
      }
    }
  }
}'
```

If this returns your project, the bot can add items to it automatically.
