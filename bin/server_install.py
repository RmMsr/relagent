#!/usr/bin/env python

import shutil
from pathlib import Path

from _util import run_subprocess

APP_DIR = Path.home() / ".local" / "share" / "org.venkado.relagent-engine"
SYSTEMD_USER_DIR = Path.home() / ".config" / "systemd" / "user"
SYSTEMD_CONTAINER_DIR = Path.home() / ".config" / "containers" / "systemd"
SERVICE_NAME = "relagent-engine.service"
AUTO_UPDATE_TIMER = "podman-auto-update.timer"


def main() -> None:
    project_root = Path(__file__).resolve().parent.parent

    # Copy container systemd unit
    copy_file(
        project_root / "run" / "relagent-engine.container",
        SYSTEMD_CONTAINER_DIR / "relagent-engine.container",
    )

    # Copy settings file
    copy_file(project_root / "run" / "settings-template.ini", APP_DIR / "settings.ini")

    # Ensure default data_dir exists
    (APP_DIR / "data").mkdir(exist_ok=True)

    # Enable and setup podman auto update
    enable_systemd_user_unit(unit_name=AUTO_UPDATE_TIMER)
    override_systemd_user_unit(
        unit_name=AUTO_UPDATE_TIMER,
        override_src=project_root / "run" / "podman-auto-update.override.conf",
    )

    # Reload and restart services
    reload_systemd()
    start_service(AUTO_UPDATE_TIMER)
    start_service(SERVICE_NAME)

    print(
        "Installation complete. Please review the settings file: %s"
        % (APP_DIR / "settings.ini")
    )


def copy_file(src: Path, dst: Path):
    """Copy src to dst if dst does not exist. If dst exists but differs, keep a copy'."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        # Compare contents
        try:
            if dst.read_bytes() != src.read_bytes():
                dst_rel = dst.with_name(dst.name + ".new-please-merge")
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
    run_subprocess(["systemctl", "--user", "enable", unit_name])
    print(f"Enabled {unit_name}")


def override_systemd_user_unit(unit_name: str, override_src: Path):
    override_dir = SYSTEMD_USER_DIR / f"{unit_name}.d"
    override_dir.mkdir(parents=True, exist_ok=True)
    copy_file(override_src, override_dir / "override.conf")


def reload_systemd():
    run_subprocess(["systemctl", "--user", "daemon-reload"])
    print("Reloaded user systemd")


def start_service(service_name: str):
    run_subprocess(["systemctl", "--user", "restart", service_name])
    print(f"Started {service_name}")


if __name__ == "__main__":
    main()
