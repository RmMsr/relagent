#!/usr/bin/env sh

# Once a git worktree is generated this scripts symlinks all asset files
# to allow sharing them across worktrees.

# Source and destination paths for symlinks
SOURCE_DIR="../$(basename $(dirname $(git rev-parse --git-common-dir)))/apps/assets"
DEST_DIR="apps/assets"

# Check if we're in a git worktree (not the main worktree)
is_worktree() {
    [ -f ".git" ] && [ ! -d ".git" ]
}

# Create symlinks for apps/assets
create_symlinks() {
    # Check if source directory exists
    if [ ! -d "$SOURCE_DIR" ]; then
        return 1
    fi

    # Create destination directory if it doesn't exist
    mkdir -p "$DEST_DIR"

    # Get main repo name for dynamic symlink path
    main_repo_name=$(basename $(dirname $(git rev-parse --git-common-dir)))

    # Loop through files and directories in source
    for source_path in "$SOURCE_DIR"/*; do
        # Skip if no files match
        [ -e "$source_path" ] || continue

        # Get just the filename
        filename=$(basename "$source_path")
        dest_path="$DEST_DIR/$filename"

        # Skip if destination already exists
        [ -e "$dest_path" ] && continue

        # Create relative symlink
        ln -sf "../../../$main_repo_name/apps/assets/$filename" "$dest_path"
    done
}

main() {
    # Check if we're in a git worktree
    if ! is_worktree; then
        exit 0
    fi

    # Create symlinks
    create_symlinks
}

# Check if being called as a post-checkout hook
if [ $# -ge 3 ] && [ "$3" != "0" ]; then
    # Called as post-checkout hook, only run in worktrees
    if is_worktree; then
        create_symlinks
    fi
    exit 0
fi

# Otherwise run as standalone script
main "$@"
