#!/usr/bin/env python

import os
import shutil
import subprocess
from pathlib import Path


def main() -> None:
    project_root = os.path.dirname(os.path.dirname(__file__))
    src = os.path.join(project_root, 'run', 'relagent.container')
    dest_dir = Path.home() / '.config' / 'containers' / 'systemd'
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / 'relagent.container'
    shutil.copy2(src, dest)
    print(f"Copied {src} to {dest}")

    # Reload user systemd
    subprocess.run(['systemctl', '--user', 'daemon-reload'], check=True)
    print("Reloaded user systemd")

    # Start the service (the service name is relagent.service)
    subprocess.run(['systemctl', '--user', 'start', 'relagent.service'], check=True)
    print("Started relagent service")
    
if __name__ == "__main__":
    main()
