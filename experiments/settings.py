import configparser
import os
from typing import Any

CONFIG_PATH = os.path.join(
    os.getenv("HOME"), ".config", "relagent", "settings.ini"
)

config = configparser.ConfigParser()
config.read(CONFIG_PATH)

def get_setting(section: str, name: str, *, default: Any = None) -> Any:
    try:
        value = config.get(section, name, fallback=default)
        return value if value else default
    except (configparser.NoSectionError, ValueError):
        return default


def get_setting_int(section: str, name: str, *, default: int = 0) -> int:
    try:
        value = config.getint(section, name, fallback=default)
        return value if value else default
    except (configparser.NoSectionError, ValueError):
        return default