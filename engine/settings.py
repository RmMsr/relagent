import configparser
import logging
import os
from configparser import ConfigParser
from typing import Any

logger = logging.getLogger(__name__)

_SETTINGS_FILE = os.path.join(
    os.environ.get("HOME", "~"), ".local", "share", "relagent", "settings.ini"
)

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
    finally:
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
    finally:
        if write_log:
            logger.info("Setting '%s.%s' is %s", section, name, repr(value))
    return value


def reset_env():
    """
    Ensure no unintended configuration affects runtime behaviour
    """

    backup = dict[str, str]()
    keep = ["PWD", "HOME"]

    for k in keep:
        if k in os.environ:
            backup[k] = os.environ[k]

    os.environ.clear()

    for k, v in backup.items():
        os.environ[k] = v

    logger.info("Using settings at %s", _SETTINGS_FILE)
    logger.info("Environment reset to: %s", dict(os.environ))
