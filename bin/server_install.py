#!/usr/bin/env python

import shutil
from pathlib import Path

from _util import run_subprocess

CONFIG_DIR = Path.home() / '.config' / 'relagent'
SYSTEMD_USER_DIR = Path.home() / '.config' / 'systemd' / 'user'
SYSTEMD_CONTAINER_DIR = Path.home() / '.config' / 'containers' / 'systemd'
SERVICE_NAME = 'relagent.service'
AUTO_UPDATE_TIMER = 'podman-auto-update.timer'

def main() -> None:
    project_root = Path(__file__).resolve().parent.parent

    # Copy container systemd unit
    copy_file(project_root / 'run' / 'relagent.container', SYSTEMD_CONTAINER_DIR / 'relagent.container')

    # Copy settings file
    copy_file(project_root / 'settings.ini.template', CONFIG_DIR / 'settings.ini')
    print(f"Please check {CONFIG_DIR / 'settings.ini'} and adjust to your needs.")

    # Setup podman registry login
    if not run_subprocess(['podman', 'login', '--get-login', 'registry.gitlab.com'], quiet=True):
        secret_name = 'relagent-registry'
        if not run_subprocess(['podman', 'secret', 'inspect', secret_name], check=False):
            print("Please enter your credentials for registry.gitlab.com.")
            username = input("Registry username: ")
            password = input("Registry secret: ")
            run_subprocess(['podman', 'secret', 'create', secret_name, '-'], input=password.encode())
        run_subprocess(['podman', 'login', '--username', username, '--secret', secret_name, 'registry.gitlab.com'])


    # Enable and setup podman auto update
    enable_systemd_user_unit(unit_name=AUTO_UPDATE_TIMER)
    override_systemd_user_unit(unit_name=AUTO_UPDATE_TIMER, override_src=project_root / 'run' / 'podman-auto-update.override.conf')

    # Reload and start service
    reload_systemd()
    start_service(SERVICE_NAME)

def copy_file(src: Path, dst: Path):
    """Copy src to dst if dst does not exist. If dst exists but differs, keep a copy'."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        # Compare contents
        try:
            if dst.read_bytes() != src.read_bytes():
                dst_rel = dst.with_name(dst.name + '.relagent')
                shutil.copy2(src, dst_rel)
                print(f"Change detected. Please manually merge {dst_rel} into {dst}.")
                return
        except Exception as e:
            print(f"Could not compare {src} and {dst}: {e}. Skipping.")
            return
    else:
        shutil.copy2(src, dst)
        print(f"Created {dst}")

def enable_systemd_user_unit(unit_name: str):
    run_subprocess(['systemctl', '--user', 'enable', unit_name])
    print(f"Enabled {unit_name}")

def override_systemd_user_unit(unit_name: str, override_src: Path):
    override_dir = SYSTEMD_USER_DIR / f"{unit_name}.d"
    override_dir.mkdir(parents=True, exist_ok=True)
    copy_file(override_src, override_dir / 'override.conf')

def reload_systemd():
    run_subprocess(['systemctl', '--user', 'daemon-reload'])
    print("Reloaded user systemd")

def start_service(service_name: str):
    run_subprocess(['systemctl', '--user', 'start', service_name])
    print(f"Started {service_name}")

if __name__ == "__main__":
    main()
