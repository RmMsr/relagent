#!/usr/bin/env sh

# Once a git worktree is generated this script symlinks shared files and directories
# to allow sharing them across worktrees.

# Check if we're in a git worktree (not the main worktree)
is_worktree() {
    [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]
}

# Create symlink for a relative path (file or directory)
create_symlink() {
    relative_path="$1"

    # Get main repository root
    main_repo_root=$(dirname "$(git rev-parse --git-common-dir)")

    # Get current directory
    current_dir=$(pwd)

    # Find worktree root directory
    worktree_root=$(git rev-parse --show-toplevel)

    # Calculate relative path from current dir to worktree root
    relative_to_worktree=$(realpath --relative-to="$current_dir" "$worktree_root")

    # Calculate relative path from worktree root to main repo root
    relative_to_main=$(realpath --relative-to="$worktree_root" "$main_repo_root")

    # Destination path (where symlink will be created) - relative to current directory
    dest_path="$relative_path"

    if [ -d "$main_repo_root/$relative_path" ]; then
        # Directory: create symlinks for each file/subdir
        mkdir -p "$dest_path"

        for source_file in "$main_repo_root/$relative_path"/*; do
            [ -e "$source_file" ] || continue
            filename=$(basename "$source_file")
            dest_file="$dest_path/$filename"
            [ -e "$dest_file" ] && continue
            # Create symlink relative to current directory
            ln -sf "${relative_to_worktree}${relative_to_main:+/${relative_to_main}}/$relative_path/$filename" "$dest_file"
        done

    elif [ -f "$main_repo_root/$relative_path" ]; then
        # File: direct symlink
        [ -e "$dest_path" ] && return
        # Create symlink relative to current directory
        ln -sf "${relative_to_worktree}${relative_to_main:+/${relative_to_main}}/$relative_path" "$dest_path"
    fi
}

main() {
    # Check if we're in a git worktree
    if ! is_worktree; then
        exit 0
    fi

    # Create symlinks
    create_symlink "apps/assets"
    create_symlink ".env"
}

# Check if being called as a post-checkout hook
if [ $# -ge 3 ] && [ "$3" != "0" ]; then
    # Called as post-checkout hook, only run in worktrees
    if is_worktree; then
        create_symlink "apps/assets"
        create_symlink ".env"
    fi
    exit 0
fi

# Otherwise run as standalone script
main "$@"
