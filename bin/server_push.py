#!/usr/bin/env python

from pathlib import Path

from _util import ensure_registry_login, find_container_framework, run_subprocess
from server_build import IMAGE_BASE, build_with_framework

REPO_ROOT = Path(__file__).parent.parent


def push_with_framework(framework: str, version: str) -> None:
    """Push both versioned and latest image tags."""
    image_versioned = f"{IMAGE_BASE}:{version}"
    image_latest = f"{IMAGE_BASE}:latest"

    for image in [image_versioned, image_latest]:
        command = [framework, "image", "push", image]
        print(f"Pushing: {image}")
        run_subprocess(command, cwd=REPO_ROOT)


if __name__ == "__main__":
    framework = find_container_framework()
    version = build_with_framework(framework, allow_cache=False)
    ensure_registry_login()
    push_with_framework(framework, version)
    print("\nPushed images:")
    print(f"  {IMAGE_BASE}:{version}")
    print(f"  {IMAGE_BASE}:latest")
