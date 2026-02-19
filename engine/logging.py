import logging
import os


def init_logging():
    log_level = os.getenv("LOG_LEVEL", "INFO")
    logging.basicConfig(level=getattr(logging, log_level.upper()))


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)
