#!/bin/bash
# Simple script to create all backlog issues using gh CLI
# Usage: ./create_issues_with_gh.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_FILE="$SCRIPT_DIR/backlog_issues.json"

if ! command -v gh &> /dev/null; then
    echo "Error: gh CLI is not installed"
    echo "Install it from: https://cli.github.com/"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed"
    echo "Install it with: apt-get install jq (or brew install jq on Mac)"
    exit 1
fi

echo "Authenticating with GitHub..."
gh auth status || gh auth login

echo ""
echo "Creating issues from $JSON_FILE..."
echo "========================================"

# Get the number of issues
ISSUE_COUNT=$(jq 'length' "$JSON_FILE")
echo "Found $ISSUE_COUNT issues to create"
echo ""

# Counter for created issues
created=0
failed=0

# Read and create each issue
for i in $(seq 0 $(($ISSUE_COUNT - 1))); do
    # Extract issue data
    title=$(jq -r ".[$i].title" "$JSON_FILE")
    body=$(jq -r ".[$i].body" "$JSON_FILE")
    labels=$(jq -r ".[$i].labels | join(\",\")" "$JSON_FILE")

    echo "Creating: $title"

    # Create the issue
    if gh issue create \
        --repo Faraclas/adaptive-overlay \
        --title "$title" \
        --body "$body" \
        --label "$labels" > /dev/null 2>&1; then
        echo "  ✓ Created"
        ((created++))
    else
        echo "  ✗ Failed"
        ((failed++))
    fi
done

echo ""
echo "========================================"
echo "Summary:"
echo "  Created: $created issues"
echo "  Failed:  $failed issues"
echo ""

if [ $failed -eq 0 ]; then
    echo "✓ All issues created successfully!"
else
    echo "⚠ Some issues failed to create"
    exit 1
fi
