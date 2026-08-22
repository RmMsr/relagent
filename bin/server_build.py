#!/usr/bin/env python

import json
import subprocess
import sys
from pathlib import Path

from _util import ensure_registry_login, find_container_framework, run_subprocess

REPO_ROOT = Path(__file__).parent.parent
VERSION_FILE = REPO_ROOT / "VERSION"
FVMRC_FILE = REPO_ROOT / ".fvmrc"
IMAGE_BASE = "registry.gitlab.com/rmmsr/relagent"


def get_version() -> str:
    """Read version from VERSION file."""
    if not VERSION_FILE.exists():
        print(f"Warning: {VERSION_FILE} not found, using 'latest'", file=sys.stderr)
        return "latest"
    return VERSION_FILE.read_text().strip()


def get_flutter_ci_image() -> str:
    """Build the flutter-ci image reference from the pinned Flutter version in .fvmrc."""
    flutter_version = json.loads(FVMRC_FILE.read_text())["flutter"]
    return f"{IMAGE_BASE}/flutter-ci:{flutter_version}"


def build_with_framework(framework: str, target: str = "", allow_cache: bool = False) -> str:
    """Build container image with version tag. Returns the version."""
    version = get_version()

    if target:
        version += f"-{target}"

    image = f"{IMAGE_BASE}:{version}"

    ensure_registry_login()

    # Build with version tags
    command = [
        framework,
        "build",
        "--tag",
        image,
        "--build-arg",
        f"FLUTTER_CI_IMAGE={get_flutter_ci_image()}",
        "-f",
        "Containerfile",
    ]
    if target:
        command.extend(["--target", target])
    if not allow_cache:
        command.append("--no-cache")
    command.append(".")

    print(f"Building image: {image}")
    print(f"Running command: {' '.join(command)}")
    try:
        run_subprocess(
            command,
            cwd=REPO_ROOT,
            raise_error=True,
        )
    except subprocess.CalledProcessError as e:
        print(
            f"{framework} build failed with exit code {e.returncode}.", file=sys.stderr
        )
        sys.exit(1)

    return version


if __name__ == "__main__":
    framework = find_container_framework()
    versions = [
        build_with_framework(framework, allow_cache=True),
        build_with_framework(framework, target="bundled", allow_cache=True),
    ]
    print("\nBuilt images:")
    for ver in versions:
        print(f"  {IMAGE_BASE}:{ver}")
