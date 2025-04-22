#!/usr/bin/env python

import os

from _util import find_container_framework, run_subprocess


def build_with_framework(framework: str) -> None:
    image = "registry.gitlab.com/rmmsr/relagent"
    command = [framework, "build", "--tag", image, "-f", "Containerfile", "."]
    print(f"Running command: {' '.join(command)}")
    run_subprocess(
        command,
        cwd=os.path.dirname(os.path.dirname(__file__)),
    )


if __name__ == "__main__":
    framework = find_container_framework()
    build_with_framework(framework)
