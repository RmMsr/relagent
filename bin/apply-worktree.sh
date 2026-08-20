#!/usr/bin/env sh

# Unicode symbols for output
ERROR_SYM="❌"
SUCCESS_SYM="✅"

# Git Worktree Apply Script
# Completes the worktree workflow started by start-worktree.sh
#
# Workflow:
# 1. Use start-worktree.sh to create a worktree from main (or other branch)
# 2. Work on changes in the worktree directory
# 3. Run apply-worktree.sh from within the worktree to:
#    - Commit pending changes with AI-generated message
#    - Squash all commits not in local main (unless --no-squash)
#    - Switch to main branch in source directory
#    - Fast-forward merge the worktree branch
#    - Remove the worktree
#    - Delete the branch
#
# Usage: Run from within a worktree directory created by start-worktree.sh
# Optional parameter: --target-branch BRANCH_NAME (default: main)
# Optional parameter: --no-squash (keep individual commits instead of squashing)

set -eu

TARGET_BRANCH="main"
SQUASH=true

print_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Completes the worktree workflow started by start-worktree.sh. Run this
from within a worktree directory created by start-worktree.sh.

Workflow:
  1. Use start-worktree.sh to create a worktree from main (or other branch)
  2. Work on changes in the worktree directory
  3. Run apply-worktree.sh from within the worktree to:
     - Commit pending changes with AI-generated message
     - Squash all commits not in local main (unless --no-squash)
     - Switch to main branch in source directory
     - Fast-forward merge the worktree branch
     - Remove the worktree
     - Delete the branch

Options:
  --target-branch BRANCH_NAME  Branch to merge into (default: main)
  --no-squash                  Keep individual commits instead of squashing
  -h, --help                   Show this help message and exit
EOF
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        --target-branch)
            TARGET_BRANCH="$2"
            shift 2
            ;;
        --no-squash)
            SQUASH=false
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--target-branch BRANCH_NAME] [--no-squash]"
            exit 1
            ;;
    esac
done

# Use ai to perform a simple task
ask_ai() {
    export OPENCODE_PERMISSION='{"bash":"deny", "read":"deny", "glob":"deny", "list":"deny", "grep":"deny"}'
    if result=$(echo "$@" | timeout --kill-after=5s 1m relagent-cli ask); then
        echo "$result"
    else
        return 1
    fi
}

commit_if_needed() {
    if [ -z "$(git status --porcelain)" ]; then
        echo "No uncomitted changes found"
        return 0
    fi

    echo "Generating commit message..."

    git add --all

    query="Write a conventional commit message.

Let the title be brief, max 60 characters.

Give a list of significant changes. Leave out insignificant details. Use minimal formatting.

## Diff

$(git diff --staged)"

    message=$(ask_ai "$query")
    if [ -z "$message" ]; then
        message="Latest changes (default message)"
    fi

    git commit --all --message "$message" > /dev/null
    echo "${SUCCESS_SYM} New commit: $(git show --oneline --no-patch)"
}

squash_changes() {
    commits_since_main=$(git rev-list --abbrev-commit main-worktree/HEAD..HEAD)
    num_commits=$(echo "$commits_since_main" | wc -w)
    if [ "$num_commits" -lt 2 ]; then
        echo "Branch contains $num_commits commits. No squash needed"
        return 0;
    fi

    echo "Generating squash commit..."

    git_log=$(git log --stat main-worktree/HEAD..)

    git reset --soft "$(git merge-base main-worktree/HEAD HEAD)"

    query="We are squashing multiple commits. Summarize the following git messages into one conventional commit.

No multi turn discussion or reasoning. Just generate a reasonable commit message. If there is not enough input, return nothing.

## Instructions

1. Generate a short one line summary as title. Max 60 characters. Prefixed with feat:, fix: or chore:
2. Describe only the major improvements and change patterns in one short paragraph. Add intention where context fits. Max 4 sentences. Use the collected commit messages for additional context.
3. Quickly list fixes and other relevant differences.
4. Skip insignificant details, focus on higher level impact.

## Existing commit messages

$git_log"

    message="$(ask_ai "$query")"

    git commit --all --message "$message" > /dev/null

    echo "${SUCCESS_SYM} Squashed $num_commits commits into: $(git show --oneline --no-patch)"
}

is_worktree() {
    [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]
}

main() {
    if ! is_worktree; then
        echo "${ERROR_SYM} Error: Not in a git worktree directory"
        echo "Run this script from within a worktree created by start-worktree.sh"
        exit 1
    fi

    # Get current branch name
    branch=$(git branch --show-current)
    if [ -z "$branch" ]; then
        echo "${ERROR_SYM} Error: Could not determine current branch"
        exit 1
    fi

    # Get main repository path
    main_repo=$(dirname "$(git rev-parse --git-common-dir)")

    echo "Applying worktree: $branch"
    echo "To main worktree repo: $main_repo"

    commit_if_needed

    if [ "$SQUASH" = true ]; then
        squash_changes
    fi

    # Switch to target branch in source directory
    echo "Switching to worktree main and $TARGET_BRANCH branch..."
    if ! cd "$main_repo"; then
        echo "${ERROR_SYM} Error: Could not switch to main repo directory"
        exit 1
    fi
    if [ "$(git branch --show-current)" != "$TARGET_BRANCH" ]; then
        if ! git checkout "$TARGET_BRANCH"; then
            echo "${ERROR_SYM} Error: Could not checkout $TARGET_BRANCH branch"
            exit 1
        fi
    fi

    # Fast-forward merge (will fail if not possible)
    echo "Merging $branch into $TARGET_BRANCH..."
    if ! git merge --ff-only "$branch"; then
        echo "${ERROR_SYM} Error: Could not fast-forward merge $branch"
        echo "Check for conflicts or non-fast-forward situation"
        exit 1
    fi
    echo "${SUCCESS_SYM} Successfully merged $branch"

    # Remove worktree
    echo "Removing worktree..."
    if ! git worktree remove "../$branch" 2>/dev/null; then
        echo "${ERROR_SYM} Error: Could not remove worktree"
        exit 1
    fi

    # Delete branch
    echo "Deleting branch $branch..."
    if ! git branch -D "$branch"; then
        echo "${ERROR_SYM} Error: Could not delete branch $branch"
        exit 1
    fi

    echo "${SUCCESS_SYM} Worktree applied and cleaned up successfully!"
    echo "Return to: $(pwd)"
}

main "$@"
