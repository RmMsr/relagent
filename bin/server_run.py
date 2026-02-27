#!/usr/bin/env python

import subprocess
import sys
from pathlib import Path

from _util import find_container_framework, run_subprocess
from server_build import build_with_framework


def run_with_framework(framework: str, version: str) -> None:
    home_app_dir = Path(".local") / "share" / "org.venkado.relagent-engine"
    command = [
        framework,
        "run",
        "--name=relagent-engine",
        "--replace",
        "--read-only",
        f"--volume={Path.home() / home_app_dir / 'settings.ini'}:{Path('/app') / home_app_dir / 'settings.ini'}:ro",
        f"--volume={Path.home() / home_app_dir / 'data'}:{Path('/app') / home_app_dir / 'data'}:rw",
        "--publish=8000:8000",
        "--userns=keep-id:uid=1000,gid=1000",
        f"registry.gitlab.com/rmmsr/relagent:{version}",
    ]
    print(f"Running command: {' '.join(command)}")
    try:
        run_subprocess(
            command,
            cwd=Path(__file__).parent,
            raise_error=True,
        )
    except subprocess.CalledProcessError as e:
        print(f"{framework} run failed with exit code {e.returncode}.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    framework = find_container_framework()
    version = build_with_framework(framework, allow_cache=True)
    run_with_framework(framework, version=version)
