#!/bin/bash
# Diagnostic script to understand GitHub project access issues
# This helps debug why bot/app integrations can't access user-level projects

echo "============================================"
echo "GitHub Project Access Diagnostic"
echo "============================================"
echo ""

echo "1. Checking authentication..."
gh auth status 2>&1 | head -10
echo ""

echo "2. Checking viewer identity..."
gh api graphql -f query='{viewer{login id}}' 2>&1
echo ""

echo "3. Checking user project access..."
gh api graphql -f query='
query {
  user(login: "Faraclas") {
    projectsV2(first: 10) {
      nodes {
        id
        number
        title
        url
      }
    }
  }
}' 2>&1
echo ""

echo "4. Checking repository projects..."
gh api graphql -f query='
query {
  repository(owner: "Faraclas", name: "adaptive-overlay") {
    projectsV2(first: 10) {
      nodes {
        id
        number
        title
      }
    }
  }
}' 2>&1
echo ""

echo "5. Checking if issue has project items..."
gh api graphql -f query='
query {
  repository(owner: "Faraclas", name: "adaptive-overlay") {
    issue(number: 7) {
      projectItems(first: 10) {
        nodes {
          project {
            id
            title
            number
          }
        }
      }
    }
  }
}' 2>&1
echo ""

echo "6. Attempting to list projects via gh CLI..."
gh project list --owner Faraclas 2>&1
echo ""

echo "7. Testing mutation permissions..."
gh api graphql -f query='
{
  __type(name: "Mutation") {
    fields {
      name
    }
  }
}' 2>&1 | jq -r '.data.__type.fields[] | select(.name | contains("project") or contains("Project")) | .name' | head -20
echo ""

echo "============================================"
echo "Diagnosis Summary:"
echo "============================================"
echo ""
echo "If all queries return empty or FORBIDDEN:"
echo "  - Bot/App tokens cannot access user-level projects"
echo "  - This is a GitHub platform limitation"
echo "  - User must manually add items or use personal token"
echo ""
echo "If repository projects exist:"
echo "  - Bot can add items to repository-level projects"
echo "  - Use: gh project item-add <number> --owner <repo-owner> --url <issue-url>"
echo ""
echo "Recommended solutions:"
echo "1. Move project to repository level (Settings > Projects)"
echo "2. Use personal access token with 'project' scope"
echo "3. Manually add items via web UI"
echo "============================================"
