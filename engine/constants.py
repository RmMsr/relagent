from pathlib import Path

from engine.helpers import get_version
from engine.settings import get_setting, get_setting_bool

VERSION: str = get_version()

DATA_DIR: Path = Path(
    get_setting("persistence", "data_dir", default="./data")
).expanduser()

PROVIDER_API_BASE: str = get_setting(
    "provider", "api_base", default="http://localhost:11434"
)
PROVIDER_API_KEY: str = get_setting("provider", "api_key")

DEFAULT_MODEL: str = get_setting("provider", "default_model", default="olmo-3")

DEBUG_DUMPS: bool = get_setting_bool("debug", "raw_data_dump", default=False)
