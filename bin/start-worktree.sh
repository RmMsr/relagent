#!/usr/bin/env sh

# Git Worktree Start Script
# Creates a new worktree with random name from current or specified branch

# Unicode symbols for output
ERROR_SYM="❌"
SUCCESS_SYM="✅"

set -e

# Parse arguments
BRANCH="main"
WORKTREE_NAME=""
while [ $# -gt 0 ]; do
  case $1 in
    --source-branch)
      BRANCH="$2"
      shift 2
      ;;
    --name)
      WORKTREE_NAME="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--source-branch <branch-name>] [--name <worktree-name>]"
      echo "  --source-branch  Specify source branch (default: main)"
      echo "  --name           Specify worktree name (default: random generated)"
      echo ""
      echo "Note: Script is non-interactive and will exit with errors if:"
      echo "  - Target branch already exists"
      echo ""
      echo "Examples:"
      echo "  $0                                    # From main branch, random name"
      echo "  $0 --source-branch develop            # From develop branch, random name"
      echo "  $0 --name feature-x                   # From main branch, named 'feature-x'"
      echo "  $0 --source-branch main --name my-fix # From main branch, named 'my-fix'"
      exit 0
      ;;
    *)
      echo "${ERROR_SYM} Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check if branch exists
if ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "${ERROR_SYM} Error: Branch '$BRANCH' does not exist"
  exit 1
fi

# Get current repo name (basename of git root)
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")

# Generate worktree name only if not provided
if [ -z "$WORKTREE_NAME" ]; then
  # Generate random seed for variety
  if [ -r /dev/urandom ]; then
    seed=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 16 | head -n 1)
  else
    seed=$(date +%N | tail -c 24 | tr -dc '0-9' | head -c 16)
  fi

  # Try to generate a human-friendly suffix using opencode with seed
  suffix=""
  if command -v opencode >/dev/null 2>&1; then
    echo "Fantasizing a nice name..."
    suffix=$(opencode run "Generate a brief friendly and inpiring phrase made of 2-3 words. \
        Take this as an inpiration: $seed. Lower case. No tool usage. No thinking." 2>/dev/null \
        | head -n 3 | tr -dc 'a-zA-Z0-9-')
    if [ -z "$suffix" ] || [ ${#suffix} -gt 20 ]; then
      suffix=""
    fi
  fi

  # Fallback to the random seed if opencode failed or not available
  if [ -z "$suffix" ]; then
    suffix="$seed"
  fi
  WORKTREE_NAME="${REPO_NAME}-${suffix}"
fi

# Build worktree path (standard git worktree behavior: path basename = branch name)
WORKTREE_PATH="../$WORKTREE_NAME"

echo "Current branch: $BRANCH"
echo "Current repo: $REPO_NAME"
echo "Worktree name: $WORKTREE_NAME"
echo "Worktree path: $WORKTREE_PATH"

# Check if branch already exists
if git show-ref --verify --quiet "refs/heads/$WORKTREE_NAME"; then
  echo "${ERROR_SYM} Error: Branch '$WORKTREE_NAME' already exists"
  echo "To recreate, delete it first: git branch -D '$WORKTREE_NAME'"
  if [ -d "$WORKTREE_PATH" ]; then
    echo "And remove worktree: git worktree remove '$WORKTREE_PATH'"
  fi
  exit 1
else
  echo "${SUCCESS_SYM} Branch '$WORKTREE_NAME' doesn't exist, creating fresh copy"
fi

# Warn if not forking from main
if [ "$BRANCH" != "main" ]; then
  echo "Warning: Creating worktree from branch '$BRANCH' (not main)"
  echo "Use --source-branch main to fork from main branch instead"
fi

echo "Creating worktree from branch: $BRANCH"
git worktree add -b "$WORKTREE_NAME" "$WORKTREE_PATH" "$BRANCH"

# Run the existing setup script for symlinks
if [ -f "./bin/git-worktree-setup.sh" ]; then
  cd "$WORKTREE_PATH"
  "$WORKTREE_PATH/bin/git-worktree-setup.sh"
  cd - > /dev/null
fi

echo "${SUCCESS_SYM} Worktree created successfully!"
echo "Switch to: cd $WORKTREE_PATH"
