import os

from engine.helpers import get_version
from engine.settings import get_setting

VERSION: str = get_version()

DATA_DIR: str = os.path.expandvars(
    get_setting("persistence", "data_dir", default="./data")
)

PROVIDER_API_BASE: str = get_setting(
    "provider", "api_base", default="http://localhost:11434"
)
PROVIDER_API_KEY: str = get_setting("provider", "api_key")

DEFAULT_MODEL: str = get_setting("provider", "default_model", default="olmo-3")
