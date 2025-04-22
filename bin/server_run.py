#!/usr/bin/env python

import os
import subprocess
import sys
from pathlib import Path

from _util import find_container_framework
from server_build import build_with_framework


def run_with_framework(framework: str) -> None:
    try:
        command = [
            f"{framework} run",
            "--name=relagent",
            "--replace",
            f"--volume={Path.home()}/.config/relagent/settings.ini:/root/.config/relagent/settings.ini:ro",
            "gitlab.com/rmmsr/relagent",
        ]
        print(f"Running command: {' '.join(command)}")
        subprocess.run(
            command,
            cwd=os.path.dirname(os.path.dirname(__file__)),
        )
    except subprocess.CalledProcessError as e:
        print(f"{framework} run failed with exit code {e.returncode}.", file=sys.stderr)
        print(f"Command: {' '.join(e.cmd)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    framework = find_container_framework()
    build_with_framework(framework)
    run_with_framework(framework)