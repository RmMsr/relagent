---
name: version-and-changelog
description: Update the project version and generate a changelog. Use when preparing a preview release (next patch with -pre) or a stable release (minor/major bump).
license: MIT
compatibility: Relagent project
metadata:
  author: relagent
  version: "1.0"
  generatedBy: "1.0.0"
---

# Version & Changelog Update Skill

Update the project version and generate a changelog for releases.

## When to Use

- Preparing a preview release (next patch level with `-pre` suffix)
- Preparing a stable release (minor or major bump, removing `-pre`)
- Any time the version needs to be bumped and changelog updated

## Workflow

### 1. Determine Release Type

Ask the user what kind of release they want:
- **Preview release**: Bump patch and add `-pre` suffix (most common)
- **Stable patch**: Bump patch and remove `-pre` suffix
- **Stable minor**: Bump minor version, remove `-pre`
- **Stable major**: Bump major version, remove `-pre`

### 2. Update Version

Execute `bin/update-version.py` with the appropriate parameters:

```bash
# Preview release (most common)
python bin/update-version.py --bump patch --preview

# Stable patch release
python bin/update-version.py --bump patch --stable

# Stable minor release
python bin/update-version.py --bump minor --stable

# Stable major release
python bin/update-version.py --bump major --stable
```

Note the **new version** and **build number** (version code) from the script output.

### 3. Determine Change Range

Determine the git range for changelog:

- **If on a non-main worktree or branch**: Get changes since `main`
  ```bash
  git log main..HEAD --oneline
  ```

- **If on main branch**: Get changes since the last VERSION file change
  ```bash
  git log -1 --format=%H -- VERSION
  git log <last-version-commit>..HEAD --oneline
  ```

### 4. Compose Changelog

Review the git log and commit messages. For each main component (**engine** and **apps**), compose a list of **major user-noticeable changes**.

**Include:**
- New features
- Bug fixes affecting user experience
- UI/UX changes
- API changes
- Performance improvements visible to users

**Exclude or briefly mention:**
- Comment changes
- Documentation updates
- Dependency updates (just mention "dependency updates" without details)
- Refactoring without user impact
- CI/CD changes

Focus on the bigger picture, leave out implementation details.

### 5. Update CHANGELOG.md

Prepend `CHANGELOG.md` with the new entry using this format:

```markdown
## Version X.Y.Z (build NNN) - YYYY-MM-DD HH:MM

### Engine

- Major change description
- Another user-visible change

### Apps

- New feature or improvement
- Bug fix description

### Other

- Brief mention of minor changes (dependencies, docs, etc.)
```

**Notes:**
- The H2 heading contains: version string and build number in parentheses
- Round the datetime to the nearest 15 minutes
- List engine changes first, then apps, then other
- Keep descriptions concise and user-focused

### 6. Update Android Changelog

Extract **only the apps changes** and write to:

```
metadata/android/en-US/changelogs/${buildnumber}0.txt
```

Format as a simple dash list without further formatting:

```
- New feature description
- Bug fix description
- UI improvement
```

Create the `changelogs` directory if it doesn't exist.

## Example

For a preview release `0.1.24-pre` with build number `42`:

1. Run: `python bin/update-version.py --bump patch --preview`
2. Output shows: `New version: 0.1.24-pre`, `New version code: 42`
3. Get changes from git log
4. Update CHANGELOG.md:

```markdown
## Version 0.1.24-pre (build 42) - 2025-05-01 14:30

### Engine

- Added streaming support for conversation responses
- Fixed memory leak in long-running sessions

### Apps

- New dark mode toggle in settings
- Improved message rendering performance

### Other

- Minor dependency updates and documentation fixes
```

5. Write to `metadata/android/en-US/changelogs/420.txt`:

```
- New dark mode toggle in settings
- Improved message rendering performance
```
