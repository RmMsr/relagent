#!/usr/bin/env python

import subprocess
import sys
from pathlib import Path

from _util import find_container_framework, run_subprocess

REPO_ROOT = Path(__file__).parent.parent
VERSION_FILE = REPO_ROOT / "VERSION"
IMAGE_BASE = "registry.gitlab.com/rmmsr/relagent"


def get_version() -> str:
    """Read version from VERSION file."""
    if not VERSION_FILE.exists():
        print(f"Warning: {VERSION_FILE} not found, using 'latest'", file=sys.stderr)
        return "latest"
    return VERSION_FILE.read_text().strip()


def build_with_framework(framework: str) -> str:
    """Build container image with version tag. Returns the version."""
    version = get_version()
    image_versioned = f"{IMAGE_BASE}:{version}"
    image_latest = f"{IMAGE_BASE}:latest"

    # Build with version tag
    command = [framework, "build", "--tag", image_versioned, "-f", "Containerfile", "."]
    print(f"Building image: {image_versioned}")
    print(f"Running command: {' '.join(command)}")
    try:
        run_subprocess(
            command,
            cwd=str(REPO_ROOT),
            raise_error=True,
        )
    except subprocess.CalledProcessError as e:
        print(
            f"{framework} build failed with exit code {e.returncode}.", file=sys.stderr
        )
        sys.exit(1)

    # Tag as latest
    tag_command = [framework, "tag", image_versioned, image_latest]
    print(f"Tagging as: {image_latest}")
    run_subprocess(tag_command, cwd=str(REPO_ROOT))

    return version


if __name__ == "__main__":
    framework = find_container_framework()
    version = build_with_framework(framework)
    print("\nBuilt images:")
    print(f"  {IMAGE_BASE}:{version}")
    print(f"  {IMAGE_BASE}:latest")
