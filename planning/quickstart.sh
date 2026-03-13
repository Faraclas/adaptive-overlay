#!/bin/bash
# Quick Start: Create All Backlog Issues
#
# This script checks prerequisites and runs the issue creation process.
# Run this from the repository root: ./planning/quickstart.sh

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Adaptive Overlay - Backlog Issue Creation Quickstart   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Check if we're in the repo root
if [ ! -f "planning/backlog_issues.json" ]; then
    echo "❌ Error: Please run this script from the repository root"
    echo "   Example: ./planning/quickstart.sh"
    exit 1
fi

echo "✓ Found backlog_issues.json"
echo ""

# Check for gh CLI
if command -v gh &> /dev/null; then
    echo "✓ Found gh CLI"

    # Check auth status
    if gh auth status &> /dev/null; then
        echo "✓ GitHub CLI is authenticated"
        echo ""
        echo "Ready to create issues! Choose an option:"
        echo ""
        echo "  1. Create ALL issues now (recommended)"
        echo "  2. Create issues one phase at a time"
        echo "  3. Cancel and review backlog first"
        echo ""
        read -p "Enter choice (1-3): " choice

        case $choice in
            1)
                echo ""
                echo "Creating all 31 issues..."
                ./planning/create_issues_with_gh.sh
                ;;
            2)
                echo ""
                echo "Phase-by-phase creation not yet implemented."
                echo "Please run: ./planning/create_issues_with_gh.sh"
                echo "Then filter by labels in GitHub Projects."
                ;;
            3)
                echo ""
                echo "Review the backlog with:"
                echo "  cat planning/BACKLOG_README.md"
                echo "  cat planning/backlog_issues.json | jq"
                echo ""
                echo "When ready, run: ./planning/create_issues_with_gh.sh"
                ;;
            *)
                echo "Invalid choice. Exiting."
                exit 1
                ;;
        esac
    else
        echo "⚠ GitHub CLI is installed but not authenticated"
        echo ""
        echo "To authenticate, run:"
        echo "  gh auth login"
        echo ""
        echo "Then re-run this script."
        exit 1
    fi
else
    echo "⚠ GitHub CLI (gh) not found"
    echo ""
    echo "Install gh CLI first:"
    echo "  - macOS:   brew install gh"
    echo "  - Linux:   See https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
    echo "  - Windows: See https://github.com/cli/cli/releases"
    echo ""
    echo "Alternative: Use Python script"

    if command -v python3 &> /dev/null && python3 -c "import requests" &> /dev/null; then
        echo "  ✓ Python 3 and requests are available"
        echo ""
        read -p "Create GitHub token and use Python script? (y/n): " use_python

        if [ "$use_python" = "y" ]; then
            echo ""
            echo "1. Create a token at: https://github.com/settings/tokens"
            echo "   Required scope: 'repo'"
            echo ""
            read -p "2. Enter your GitHub token: " token

            if [ -n "$token" ]; then
                export GITHUB_TOKEN="$token"
                echo ""
                echo "Creating issues..."
                python3 planning/create_issues_from_backlog.py
            else
                echo "No token provided. Exiting."
                exit 1
            fi
        fi
    else
        echo "  ✗ Python 3 or requests module not available"
        echo ""
        echo "Install gh CLI for the easiest experience:"
        echo "  https://cli.github.com/"
    fi
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "Next Steps:"
echo "  1. Visit: https://github.com/users/Faraclas/projects/1"
echo "  2. Add created issues to your project board"
echo "  3. Set iteration/sprint for each phase"
echo "  4. Start with Phase 1 tasks"
echo ""
echo "See planning/ISSUE_GENERATION_SUMMARY.md for details"
echo "═══════════════════════════════════════════════════════════"
