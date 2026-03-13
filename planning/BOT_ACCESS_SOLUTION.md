# How to Enable Bot Access to Your Project Board

## The Core Issue

After extensive testing, I've confirmed that the Claude bot **cannot** access your project at:
- `https://github.com/users/Faraclas/projects/1`

This is because it's a **user-level project**, and GitHub's security model prevents bot/app integrations from accessing user-level projects, regardless of permission settings.

## The Solution: Create a Repository-Level Project

Here's how to enable the bot to automatically add issues:

### Step 1: Create a Repository-Level Project

1. Go to: https://github.com/Faraclas/adaptive-overlay
2. Click the **"Projects"** tab at the top
3. Click **"Link a project"** → **"New project"**
4. Create your project (you can use the same name: "Adaptive Overlay Development")

**Important**: Make sure you're creating it from the repository page, NOT from your user profile.

### Step 2: Verify the Bot Can See It

Once created, I can verify access with:

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

If this returns your new project, we're good to go!

### Step 3: Add Issues Automatically

Then I can run:

```bash
./planning/add_issues_to_project.sh <project_number>
```

This will automatically add all 31 issues (#7-#37) to the board.

## What About My Existing User-Level Project?

You have two options:

### Option A: Use Both Projects
- Keep your user-level project for personal planning
- Use the repository-level project for bot automation
- Manually sync between them as needed

### Option B: Migrate Everything
1. Create the repository-level project
2. Let the bot add all issues automatically
3. Manually recreate any custom fields/views from your user project
4. Archive the old user-level project

## Why Can't the Bot Access User Projects?

GitHub's security model:
- **User-level projects** = Personal data, private to your account
- **Repository-level projects** = Repository resource, accessible to integrations
- **Organization-level projects** = Org resource, accessible to integrations

Bots can only access repository and organization resources. This protects user privacy and prevents unauthorized access to personal data.

## Testing Results Summary

All attempts to access the user-level project failed:

| Method | Result |
|--------|--------|
| `user.projectsV2` query | Empty array |
| `repository.projectsV2` query | Empty array |
| `viewer.projectsV2` query | Empty array |
| Direct node ID access | NOT_FOUND |
| `gh project` commands | Resource not accessible |
| Project permission changes | No effect (still inaccessible) |

**Conclusion**: The bot cannot see user-level projects at all. This is by design in GitHub's API.

## Next Steps

Once you create a repository-level project, please let me know the project number (from the URL), and I'll immediately add all 31 issues to it automatically!
