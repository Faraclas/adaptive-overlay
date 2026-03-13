#!/bin/bash
# Script to add all backlog issues to the GitHub project board
# Usage: ./planning/add_issues_to_project.sh <project_number>

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <project_number>"
    echo "Example: $0 1"
    echo ""
    echo "To find your project number, visit your project board URL:"
    echo "https://github.com/users/Faraclas/projects/<number>"
    exit 1
fi

PROJECT_NUM=$1
OWNER="Faraclas"
REPO="adaptive-overlay"

echo "Adding issues #7-#37 to project #${PROJECT_NUM}..."
echo "=================================================="
echo ""

# First, verify the project is accessible
echo "Verifying project access..."
PROJECT_CHECK=$(gh api graphql -f query='
query {
  repository(owner: "'"${OWNER}"'", name: "'"${REPO}"'") {
    projectsV2(first: 20) {
      nodes {
        number
        title
        url
      }
    }
  }
}' 2>&1)

if echo "$PROJECT_CHECK" | grep -q "\"nodes\":\[\]"; then
    echo "❌ ERROR: No repository-level projects found!"
    echo ""
    echo "The project at https://github.com/users/${OWNER}/projects/${PROJECT_NUM}"
    echo "appears to be a USER-LEVEL project."
    echo ""
    echo "Bot integrations cannot access user-level projects."
    echo "Please create a REPOSITORY-LEVEL project instead:"
    echo ""
    echo "  1. Go to: https://github.com/${OWNER}/${REPO}"
    echo "  2. Click 'Projects' tab → 'Link a project' → 'New project'"
    echo "  3. Create the project at the repository level"
    echo "  4. Run this script again with the new project number"
    echo ""
    echo "See planning/BOT_ACCESS_SOLUTION.md for detailed instructions."
    echo ""
    exit 1
fi

echo "✓ Found repository projects:"
echo "$PROJECT_CHECK" | grep -o '"number":[0-9]*' | cut -d: -f2 | while read num; do
    echo "  - Project #${num}"
done
echo ""

# Check if gh CLI is available
if ! command -v gh &> /dev/null; then
    echo "Error: gh CLI is not installed"
    echo "Install it from: https://cli.github.com/"
    exit 1
fi

# Check if user has project scope
if ! gh auth status 2>&1 | grep -q "project"; then
    echo "Warning: Token may not have 'project' scope"
    echo "Run: gh auth refresh -s project"
    echo ""
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Add each issue to the project
success=0
failed=0

for issue_num in {7..37}; do
    echo -n "Adding issue #${issue_num}... "

    if gh project item-add ${PROJECT_NUM} --owner ${OWNER} \
        --url "https://github.com/${OWNER}/${REPO}/issues/${issue_num}" 2>&1; then
        echo "✓"
        ((success++))
    else
        echo "✗"
        ((failed++))
    fi
done

echo ""
echo "=================================================="
echo "Summary:"
echo "  Successfully added: ${success} issues"
echo "  Failed: ${failed} issues"
echo ""

if [ $failed -eq 0 ]; then
    echo "✓ All issues added successfully!"
    echo ""
    echo "View your project board at:"
    echo "https://github.com/users/${OWNER}/projects/${PROJECT_NUM}"
else
    echo "⚠ Some issues failed to add"
    echo "You may need to add them manually or check your permissions"
fi
