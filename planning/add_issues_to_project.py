#!/usr/bin/env python3
"""
Script to add backlog issues to a GitHub Project V2 board.

Usage:
    python3 planning/add_issues_to_project.py <project_number>

Example:
    python3 planning/add_issues_to_project.py 1

Environment Variables:
    GITHUB_TOKEN: GitHub personal access token with 'project' scope
"""

import json
import os
import sys
import requests

def get_project_id(owner: str, project_number: int, token: str) -> str:
    """Get the global node ID for a user's project."""
    query = """
    query($owner: String!, $number: Int!) {
      user(login: $owner) {
        projectV2(number: $number) {
          id
          title
          url
        }
      }
    }
    """

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    response = requests.post(
        "https://api.github.com/graphql",
        headers=headers,
        json={
            "query": query,
            "variables": {
                "owner": owner,
                "number": project_number
            }
        }
    )

    if response.status_code != 200:
        print(f"Error: Failed to query project (HTTP {response.status_code})")
        print(response.text)
        return None

    data = response.json()

    if "errors" in data:
        print(f"GraphQL Error: {data['errors']}")
        return None

    project = data.get("data", {}).get("user", {}).get("projectV2")
    if not project:
        print(f"Error: Could not find project #{project_number} for user {owner}")
        print("This might be a permissions issue or the project doesn't exist.")
        return None

    print(f"Found project: {project['title']}")
    print(f"URL: {project['url']}")
    return project["id"]

def get_issue_node_id(owner: str, repo: str, issue_number: int, token: str) -> str:
    """Get the global node ID for an issue."""
    url = f"https://api.github.com/repos/{owner}/{repo}/issues/{issue_number}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github.v3+json"
    }

    response = requests.get(url, headers=headers)

    if response.status_code == 200:
        return response.json()["node_id"]
    else:
        print(f"Warning: Could not get node ID for issue #{issue_number}")
        return None

def add_item_to_project(project_id: str, content_id: str, token: str) -> bool:
    """Add an issue to a project."""
    mutation = """
    mutation($projectId: ID!, $contentId: ID!) {
      addProjectV2ItemById(input: {projectId: $projectId, contentId: $contentId}) {
        item {
          id
        }
      }
    }
    """

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    response = requests.post(
        "https://api.github.com/graphql",
        headers=headers,
        json={
            "query": mutation,
            "variables": {
                "projectId": project_id,
                "contentId": content_id
            }
        }
    )

    if response.status_code != 200:
        return False

    data = response.json()

    if "errors" in data:
        print(f"  Error: {data['errors'][0].get('message', 'Unknown error')}")
        return False

    return True

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 planning/add_issues_to_project.py <project_number>")
        print("Example: python3 planning/add_issues_to_project.py 1")
        sys.exit(1)

    project_number = int(sys.argv[1])

    # Get GitHub token from environment
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not token:
        print("Error: GITHUB_TOKEN environment variable not set")
        print("Please set it with: export GITHUB_TOKEN=your_token_here")
        print("\nMake sure your token has the 'project' scope:")
        print("  gh auth refresh -s project")
        sys.exit(1)

    owner = "Faraclas"
    repo = "adaptive-overlay"

    print("=" * 60)
    print("Add Backlog Issues to GitHub Project")
    print("=" * 60)
    print()

    # Get the project ID
    print(f"Getting project #{project_number} for {owner}...")
    project_id = get_project_id(owner, project_number, token)

    if not project_id:
        print("\nPossible solutions:")
        print("1. Verify the project number in the URL: https://github.com/users/Faraclas/projects/<number>")
        print("2. Make sure the project is set to 'Public' or grant access to the app/token")
        print("3. Ensure your token has the 'project' scope: gh auth refresh -s project")
        print("4. Try adding issues manually through the GitHub web interface")
        sys.exit(1)

    print(f"✓ Project ID: {project_id}")
    print()

    # Add all issues (#7-#37)
    print("Adding issues #7-#37 to the project...")
    print("-" * 60)

    success_count = 0
    failed_count = 0

    for issue_num in range(7, 38):  # 7-37 inclusive
        print(f"Adding issue #{issue_num}... ", end="", flush=True)

        # Get the issue node ID
        issue_node_id = get_issue_node_id(owner, repo, issue_num, token)

        if not issue_node_id:
            print("✗ (could not get issue)")
            failed_count += 1
            continue

        # Add to project
        if add_item_to_project(project_id, issue_node_id, token):
            print("✓")
            success_count += 1
        else:
            print("✗")
            failed_count += 1

    # Summary
    print()
    print("=" * 60)
    print(f"Summary:")
    print(f"  Successfully added: {success_count} issues")
    print(f"  Failed: {failed_count} issues")
    print()

    if failed_count == 0:
        print("✓ All 31 issues added to the project board!")
        print(f"\nView your project at:")
        print(f"https://github.com/users/{owner}/projects/{project_number}")
    else:
        print("⚠ Some issues failed to add")
        print("Check permissions and try adding failed issues manually")
        sys.exit(1)

if __name__ == "__main__":
    main()
