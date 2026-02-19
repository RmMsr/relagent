import configparser
import logging
import os
from configparser import ConfigParser
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

_SETTINGS_FILE: Path = (
    Path("~") / ".local" / "share" / "relagent" / "settings.ini"
).expanduser()


config: ConfigParser = configparser.ConfigParser()
config.read(_SETTINGS_FILE)


def get_setting(
    section: str, name: str, *, default: Any = None, write_log: bool = True
) -> Any:
    value: Any = default
    try:
        value = config.get(section, name, fallback=default)
    except (configparser.NoSectionError, ValueError):
        pass

    env = os.getenv(f"{section.upper()}_{name.upper()}")
    if env:
        value = env

    if write_log:
        logger.info("Setting '%s.%s' is %s", section, name, repr(value))
    return value


def get_setting_int(
    section: str, name: str, *, default: int = 0, write_log: bool = True
) -> int:
    value: int = default
    try:
        value = config.getint(section, name, fallback=default)
    except (configparser.NoSectionError, ValueError):
        pass

    try:
        env = os.getenv(f"{section.upper()}_{name.upper()}")
        if env:
            value = int(env)
    except ValueError:
        pass

    if write_log:
        logger.info("Setting '%s.%s' is %s", section, name, repr(value))
    return value


def get_setting_bool(
    section: str, name: str, *, default: bool = False, write_log: bool = True
) -> bool:
    value: bool = default
    try:
        value = config.getboolean(section, name, fallback=default)
    except (configparser.NoSectionError, ValueError):
        pass

    try:
        env = os.getenv(f"{section.upper()}_{name.upper()}")
        if env:
            value = bool(env)
    except ValueError:
        pass

    if write_log:
        logger.info("Setting '%s.%s' is %s", section, name, repr(value))
    return value


_env_reset_done = False


def reset_env():
    """
    Ensure no unintended configuration affects runtime behaviour.

    Idempotent - safe to call multiple times (e.g. from forked workers).
    """
    global _env_reset_done
    if _env_reset_done:
        return

    backup = dict[str, str]()
    keep = [
        "INSTRUMENTATION_OTLP_ENDPOINT",
        "INSTRUMENTATION_GEN_AI_COLLECTOR_ENABLED",
        "PWD",
    ]

    for k in keep:
        if k in os.environ:
            backup[k] = os.environ[k]

    os.environ.clear()

    for k, v in backup.items():
        os.environ[k] = v

    _env_reset_done = True
    logger.info("Using settings at %s", _SETTINGS_FILE)
    logger.info("Environment reset to: %s", sorted(os.environ.keys()))
