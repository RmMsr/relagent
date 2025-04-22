#!/usr/bin/env python

import os
import shutil
from pathlib import Path

from _util import run_subprocess


def main() -> None:
    project_root = os.path.dirname(os.path.dirname(__file__))
    
    # Systemd container file
    container_file = os.path.join(project_root, 'run', 'relagent.container')
    container_dest_dir = Path.home() / '.config' / 'containers' / 'systemd'
    container_dest_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(container_file, container_dest_dir)
    print(f"Copied {container_file} to {container_dest_dir}")

    # Settings file
    settings_file = os.path.join(project_root, 'settings.ini.template')
    settings_dest_dir = Path.home() / '.config' / 'relagent'
    settings_dest_dir.mkdir(parents=True, exist_ok=True)
    settings_dest_file = settings_dest_dir / 'settings.ini'
    if settings_dest_file.exists():
        print(f"{settings_dest_file} already exists, not overwriting")
    else:
        shutil.copy2(settings_file, settings_dest_file)
        print(f"Copied {settings_file} to {settings_dest_file}. Please adjust it to configure the server.")

    # Reload user systemd
    run_subprocess(['systemctl', '--user', 'daemon-reload'])
    print("Reloaded user systemd")

    # Start the service (the service name is relagent.service)
    run_subprocess(['systemctl', '--user', 'start', 'relagent.service'])
    print("Started relagent service")
    
if __name__ == "__main__":
    main()
