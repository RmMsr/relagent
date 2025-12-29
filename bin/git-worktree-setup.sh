#!/usr/bin/env sh

# Once a git worktree is generated this script symlinks shared files and directories
# to allow sharing them across worktrees.

# Check if we're in a git worktree (not the main worktree)
is_worktree() {
    [ -f ".git" ] && [ ! -d ".git" ]
}

# Create symlink for a relative path (file or directory)
create_symlink() {
    relative_path="$1"

    # Get main repo name
    main_repo_name=$(basename "$(dirname "$(git rev-parse --git-common-dir)")")

    source_path="../$main_repo_name/$relative_path"
    dest_path="$relative_path"

    # Calculate number of directories in relative_path
    num_dirs=$(echo "$relative_path" | awk -F'/' '{print NF}')

    if [ -d "$source_path" ]; then
        # Directory: create symlinks for each file/subdir
        mkdir -p "$dest_path"

        num_dots=$((num_dirs + 1))
        dots=""
        i=1
        while [ "$i" -le "$num_dots" ]; do
            dots="${dots}../"
            i=$((i + 1))
        done

        for source_file in "$source_path"/*; do
            [ -e "$source_file" ] || continue
            filename=$(basename "$source_file")
            dest_file="$dest_path/$filename"
            [ -e "$dest_file" ] && continue
            ln -sf "${dots}$main_repo_name/$relative_path/$filename" "$dest_file"
        done

    elif [ -f "$source_path" ]; then
        # File: direct symlink
        [ -e "$dest_path" ] && return
        dots=""
        i=1
        while [ "$i" -le "$num_dirs" ]; do
            dots="${dots}../"
            i=$((i + 1))
        done
        ln -sf "${dots}$main_repo_name/$relative_path" "$dest_path"
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
