#!/usr/bin/env python
"""
Synchronize version from VERSION file to all project artifacts.

Usage:
    python bin/update-version.py           # Sync current version to all files
    python bin/update-version.py --bump minor  # Bump minor version and sync
    python bin/update-version.py --bump major  # Bump major version and sync
    python bin/update-version.py --bump patch  # Bump patch version and sync
    python bin/update-version.py --preview     # Add -pre suffix and sync
    python bin/update-version.py --stable      # Remove -pre suffix and sync
"""

import argparse
import re
import sys
from pathlib import Path

# Repository root (parent of bin/)
REPO_ROOT = Path(__file__).parent.parent

VERSION_FILE = REPO_ROOT / "VERSION"
PYPROJECT_FILE = REPO_ROOT / "pyproject.toml"
PUBSPEC_FILE = REPO_ROOT / "apps" / "pubspec.yaml"
CONTAINER_FILE = REPO_ROOT / "run" / "relagent-engine.container"

# Semver regex: MAJOR.MINOR.PATCH with optional pre-release
SEMVER_PATTERN = re.compile(
    r"^(\d+)\.(\d+)\.(\d+)(?:-([a-zA-Z0-9.-]+))?(?:\+([a-zA-Z0-9.-]+))?$"
)


def read_version() -> str:
    """Read version from VERSION file."""
    if not VERSION_FILE.exists():
        print(f"Error: {VERSION_FILE} not found", file=sys.stderr)
        sys.exit(1)
    return VERSION_FILE.read_text().strip()


def write_version(version: str) -> None:
    """Write version to VERSION file."""
    VERSION_FILE.write_text(f"{version}\n")


def validate_semver(version: str) -> bool:
    """Validate that version follows semver format."""
    return SEMVER_PATTERN.match(version) is not None


def parse_semver(version: str) -> tuple[int, int, int, str | None]:
    """Parse semver into components (major, minor, patch, prerelease)."""
    match = SEMVER_PATTERN.match(version)
    if not match:
        raise ValueError(f"Invalid semver: {version}")
    major, minor, patch, prerelease, _ = match.groups()
    return int(major), int(minor), int(patch), prerelease


def add_prerelease_suffix(version: str, suffix: str = "pre") -> str:
    """Add a pre-release suffix to the version."""
    major, minor, patch, _ = parse_semver(version)
    return f"{major}.{minor}.{patch}-{suffix}"


def remove_prerelease_suffix(version: str) -> str:
    """Remove pre-release suffix from version."""
    major, minor, patch, _ = parse_semver(version)
    return f"{major}.{minor}.{patch}"


def bump_version(version: str, bump_type: str) -> str:
    """Bump version according to type (major, minor, patch)."""
    major, minor, patch, _ = parse_semver(version)

    if bump_type == "major":
        return f"{major + 1}.0.0"
    elif bump_type == "minor":
        return f"{major}.{minor + 1}.0"
    elif bump_type == "patch":
        return f"{major}.{minor}.{patch + 1}"
    else:
        raise ValueError(f"Invalid bump type: {bump_type}")


def update_pyproject(version: str) -> bool:
    """Update version in pyproject.toml."""
    if not PYPROJECT_FILE.exists():
        print(f"Warning: {PYPROJECT_FILE} not found, skipping", file=sys.stderr)
        return False

    content = PYPROJECT_FILE.read_text()
    # Match version = "X.Y.Z" in [project] section
    pattern = r'^(version\s*=\s*")[^"]*(")'
    new_content, count = re.subn(
        pattern, rf"\g<1>{version}\g<2>", content, flags=re.MULTILINE
    )

    if count == 0:
        print(f"Warning: Could not find version in {PYPROJECT_FILE}", file=sys.stderr)
        return False

    PYPROJECT_FILE.write_text(new_content)
    return True


def update_pubspec(version: str) -> bool:
    """Update version in pubspec.yaml, preserving build number if present."""
    if not PUBSPEC_FILE.exists():
        print(f"Warning: {PUBSPEC_FILE} not found, skipping", file=sys.stderr)
        return False

    content = PUBSPEC_FILE.read_text()
    # Match version: X.Y.Z, X.Y.Z-prerelease, or X.Y.Z+BUILD
    pattern = r"^(version:\s*)[\d.]+(?:-[a-zA-Z0-9.-]+)?(?:\+(\d+))?"

    def replacement(match: re.Match[str]) -> str:
        prefix = match.group(1)
        build_number = match.group(2)
        if build_number:
            return f"{prefix}{version}+{build_number}"
        return f"{prefix}{version}"

    new_content, count = re.subn(pattern, replacement, content, flags=re.MULTILINE)

    if count == 0:
        print(f"Warning: Could not find version in {PUBSPEC_FILE}", file=sys.stderr)
        return False

    PUBSPEC_FILE.write_text(new_content)
    return True


def update_container(version: str) -> bool:
    """Update container image version in relagent.container."""
    if not CONTAINER_FILE.exists():
        print(f"Warning: {CONTAINER_FILE} not found, skipping", file=sys.stderr)
        return False

    content = CONTAINER_FILE.read_text()
    # Match Image=registry.gitlab.com/rmmsr/relagent:VERSION
    pattern = (
        r"^(Image=registry\.gitlab\.com/rmmsr/relagent:)[\d.]+(?:-[a-zA-Z0-9.-]+)?"
    )

    new_content, count = re.subn(
        pattern, rf"\g<1>{version}", content, flags=re.MULTILINE
    )

    if count == 0:
        print(
            f"Warning: Could not find Image version in {CONTAINER_FILE}",
            file=sys.stderr,
        )
        return False

    CONTAINER_FILE.write_text(new_content)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Synchronize version across all project artifacts"
    )
    parser.add_argument(
        "--bump",
        choices=["major", "minor", "patch"],
        help="Bump version before syncing",
    )
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Add -pre suffix to version",
    )
    parser.add_argument(
        "--stable",
        action="store_true",
        help="Remove -pre suffix from version",
    )
    args = parser.parse_args()

    # Read current version
    version = read_version()

    if not validate_semver(version):
        print(f"Error: Invalid semver in VERSION file: {version}", file=sys.stderr)
        return 1

    print(f"Current version: {version}")

    # Bump if requested
    if args.bump:
        version = bump_version(version, args.bump)
        write_version(version)

    # Add or remove pre-release suffix
    if args.preview and args.stable:
        print("Error: Cannot use both --preview and --stable", file=sys.stderr)
        return 1

    if args.preview:
        version = add_prerelease_suffix(version)
        write_version(version)
    elif args.stable:
        if "-" in version:
            version = remove_prerelease_suffix(version)
            write_version(version)

    # Update all artifacts
    print(f"New version: {version}")
    update_pyproject(version)
    # Sync dependencies after pyproject update
    import subprocess

    try:
        subprocess.run(
            ["uv", "sync"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError as e:
        print(f"Error: uv sync failed with exit code {e.returncode}", file=sys.stderr)
        return 1
    update_pubspec(version)
    update_container(version)

    return 0


if __name__ == "__main__":
    sys.exit(main())
