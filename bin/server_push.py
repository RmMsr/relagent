#!/usr/bin/env python

import re
from pathlib import Path

from _util import ensure_registry_login, find_container_framework, run_subprocess
from server_build import IMAGE_BASE, build_with_framework

REPO_ROOT = Path(__file__).parent.parent


def push_with_framework(
    framework: str, version: str, additional_versions: list[str]
) -> list[str]:
    """Push both versioned and latest image tags."""
    done_versions: list[str] = []

    image = f"{IMAGE_BASE}:{version}"

    print(f"Pushing: {image}")
    if run_subprocess([framework, "image", "push", image], cwd=REPO_ROOT):
        done_versions.append(version)
    else:
        print(f"Failed to push {image}")
        return []

    for v in additional_versions:
        print(f"Pushing: {IMAGE_BASE}:{v}")
        if run_subprocess(
            [framework, "image", "push", image, f"{IMAGE_BASE}:{v}"], cwd=REPO_ROOT
        ):
            done_versions.append(v)

    return done_versions


if __name__ == "__main__":
    framework = find_container_framework()
    ensure_registry_login()

    version = build_with_framework(framework, allow_cache=False)
    additional_versions: list[str] = ["any"]

    # Avoid anyone receives an unstable version by mistake
    # Asume stable release if version matches semantic versioning
    if bool(re.match(r"^\d+\.\d+\.\d+$", version)):
        additional_versions.append("latest")

    pushed_versions = push_with_framework(framework, version, additional_versions)
    print("\nPushed images:")
    for v in pushed_versions:
        print(f"  {IMAGE_BASE}:{v}")
