#!/usr/bin/env python

import shutil
import subprocess
import sys
from pathlib import Path

from _util import find_container_framework, run_subprocess
from server_build import build_with_framework


def ensure_host_directory(directory: Path) -> None:
    """Ensure that the host directory exists."""
    if not directory.exists():
        print(f"Creating host directory: {directory}")
        directory.mkdir(parents=True, exist_ok=True)


def run_with_framework(framework: str, version: str) -> None:
    home_app_dir = Path(".local") / "share" / "org.venkado.relagent-engine"
    hugging_face_dir = Path(".cache") / "huggingface" / "hub"

    host_home_app_dir = Path.home() / home_app_dir
    host_hugging_face_dir = Path.home() / hugging_face_dir

    settings_file = host_home_app_dir / "settings.ini"
    if not settings_file.exists():
        settings_file.parent.mkdir(parents=True, exist_ok=True)
        template_file = Path(__file__).parent.parent / "run" / "settings-template.ini"
        print(f"Copying settings template to {settings_file}")
        shutil.copy2(template_file, settings_file)

    ensure_host_directory(host_home_app_dir / "data")
    ensure_host_directory(host_hugging_face_dir)

    command = [
        framework,
        "run",
        "--name=relagent-engine",
        "--replace",
        "--read-only",
        f"--volume={settings_file}:{Path('/app') / home_app_dir / 'settings.ini'}:ro",
        f"--volume={host_home_app_dir / 'data'}:{Path('/app') / home_app_dir / 'data'}:rw",
        f"--volume={host_hugging_face_dir}:{Path('/app') / hugging_face_dir}:rw",
        "--env=PROVIDER_ADDITIONAL_ARGS",
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
    version = build_with_framework(framework, target="bundled", allow_cache=True)
    run_with_framework(framework, version=version)
