#!/usr/bin/env python3
"""
Script to create GitHub issues from the backlog_issues.json file.

Usage:
    python3 planning/create_issues_from_backlog.py

Environment Variables:
    GITHUB_TOKEN: GitHub personal access token with repo scope
"""

import json
import os
import sys
import requests
from typing import Dict, List

def create_issue(repo: str, issue_data: Dict, token: str) -> Dict:
    """
    Create a single GitHub issue.

    Args:
        repo: Repository in format "owner/repo"
        issue_data: Dictionary containing title, body, and labels
        token: GitHub API token

    Returns:
        Response data from GitHub API
    """
    url = f"https://api.github.com/repos/{repo}/issues"
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github.v3+json"
    }

    payload = {
        "title": issue_data["title"],
        "body": issue_data["body"],
        "labels": issue_data.get("labels", [])
    }

    response = requests.post(url, headers=headers, json=payload)

    if response.status_code == 201:
        issue_number = response.json()["number"]
        print(f"✓ Created issue #{issue_number}: {issue_data['title']}")
        return response.json()
    else:
        print(f"✗ Failed to create issue: {issue_data['title']}")
        print(f"  Status: {response.status_code}")
        print(f"  Response: {response.json().get('message', 'Unknown error')}")
        return None

def main():
    # Get GitHub token from environment
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not token:
        print("Error: GITHUB_TOKEN environment variable not set")
        print("Please set it with: export GITHUB_TOKEN=your_token_here")
        sys.exit(1)

    # Repository info
    repo = "Faraclas/adaptive-overlay"

    # Load issues from JSON file
    script_dir = os.path.dirname(os.path.abspath(__file__))
    json_file = os.path.join(script_dir, "backlog_issues.json")

    try:
        with open(json_file, "r") as f:
            issues = json.load(f)
    except FileNotFoundError:
        print(f"Error: Could not find {json_file}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in {json_file}: {e}")
        sys.exit(1)

    print(f"Found {len(issues)} issues to create")
    print("=" * 60)

    created_issues = []
    failed_issues = []

    # Create each issue
    for issue_data in issues:
        result = create_issue(repo, issue_data, token)
        if result:
            created_issues.append(result)
        else:
            failed_issues.append(issue_data)

    # Summary
    print("=" * 60)
    print(f"\nSummary:")
    print(f"  Created: {len(created_issues)} issues")
    print(f"  Failed:  {len(failed_issues)} issues")

    if failed_issues:
        print("\nFailed issues:")
        for issue in failed_issues:
            print(f"  - {issue['title']}")
        sys.exit(1)
    else:
        print("\n✓ All issues created successfully!")
        print("\nIssue numbers created:")
        for issue in created_issues:
            print(f"  #{issue['number']}: {issue['title']}")

if __name__ == "__main__":
    main()
