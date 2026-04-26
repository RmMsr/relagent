import configparser
import os
from configparser import ConfigParser
from pathlib import Path
from typing import Any

from engine.log_config import get_logger

logger = get_logger(__name__)


def get_setting(
    section: str,
    name: str,
    *,
    default: Any = None,
    write_log: bool = True,
    obscure_value: bool = False,
) -> Any:
    value: Any = default
    try:
        value = _get_config_parser().get(section, name, fallback=default)
    except (configparser.NoSectionError, ValueError):
        pass

    env = os.getenv(f"{section.upper()}_{name.upper()}")
    if env:
        value = env

    if write_log:
        logger.debug(
            "Setting '%s.%s' is %s",
            section,
            name,
            "<hidden>" if value and obscure_value else repr(value),
        )
    return value


def get_setting_int(
    section: str,
    name: str,
    *,
    default: int = 0,
    write_log: bool = True,
    obscure_value: bool = False,
) -> int:
    value: int = default
    try:
        value = _get_config_parser().getint(section, name, fallback=default)
    except (configparser.NoSectionError, ValueError):
        pass

    try:
        env = os.getenv(f"{section.upper()}_{name.upper()}")
        if env:
            value = int(env)
    except ValueError:
        pass

    if write_log:
        logger.debug(
            "Setting '%s.%s' is %s",
            section,
            name,
            "<hidden>" if value and obscure_value else repr(value),
        )
    return value


def get_setting_bool(
    section: str,
    name: str,
    *,
    default: bool = False,
    write_log: bool = True,
    obscure_value: bool = False,
) -> bool:
    value: bool = default
    try:
        value = _get_config_parser().getboolean(section, name, fallback=default)
    except (configparser.NoSectionError, ValueError):
        pass

    try:
        env = os.getenv(f"{section.upper()}_{name.upper()}")
        if env:
            value = bool(env)
    except ValueError:
        pass

    if write_log:
        logger.debug(
            "Setting '%s.%s' is %s",
            section,
            name,
            "<hidden>" if value and obscure_value else repr(value),
        )
    return value


_env_reset_done = False


def reset_env():
    """Ensure no unintended configuration affects runtime behaviour.

    Idempotent - safe to call multiple times (e.g. from forked workers).
    """
    global _env_reset_done
    if _env_reset_done:
        return

    backup = dict[str, str]()
    keep = [
        "INSTRUMENTATION_OTLP_ENDPOINT",
        "INSTRUMENTATION_OTLP_HEADERS",
        "INSTRUMENTATION_GEN_AI_COLLECTOR_ENABLED",
        "LOG_LEVEL",
        "PROVIDER_API_BASE",
        "PROVIDER_API_KEY",
        "PROVIDER_DEFAULT_MODEL",
        "PWD",
        "SERVER_SECRET_ACCESS_KEY",
    ]

    for k in keep:
        if k in os.environ:
            backup[k] = os.environ[k]

    os.environ.clear()

    for k, v in backup.items():
        os.environ[k] = v

    _env_reset_done = True

    from engine.log_config import init_logging

    init_logging()
    logger.debug("Environment reset to: %s", sorted(os.environ.keys()))


_config_parser: ConfigParser | None = None


def override_config_parser(parser: ConfigParser) -> None:
    """Replace the config parser. Used by tests to prevent reading settings.ini."""
    global _config_parser
    _config_parser = parser


def _get_config_parser() -> ConfigParser:
    global _config_parser
    if _config_parser is not None:
        return _config_parser

    config_parser = configparser.ConfigParser()

    settings_file: Path = (
        Path("~") / ".local" / "share" / "org.venkado.relagent-engine" / "settings.ini"
    ).expanduser()

    if settings_file.exists():
        config_parser.read(settings_file)
        logger.debug("Using settings at '%s'", settings_file)
    else:
        logger.warning(
            "Settings file not found at '%s'. Using defaults and environment variables.",
            settings_file,
        )

    _config_parser = config_parser
    return config_parser
