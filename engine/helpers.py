from importlib.metadata import version as get_package_version
from pathlib import Path

from engine.adapters.sqlite_event_store.sqlite_backend import SqliteEventStoreAdapter
from engine.domain.ports.events import EventStore


def get_version() -> str:
    """Get package version from installed metadata or VERSION file."""
    try:
        return get_package_version("relagent-engine")
    except Exception:
        pass

    try:
        version_file = Path(__file__).parent.parent / "VERSION"
        if version_file.exists():
            return version_file.read_text().strip()
    except Exception:
        pass

    return "unknown"


def get_global_event_store() -> EventStore:
    """Maintrains a single reusable EventStore instance."""
    from engine.constants import DATA_DIR

    if hasattr(get_global_event_store, "_instance"):
        return getattr(get_global_event_store, "_instance")
    setattr(
        get_global_event_store,
        "_instance",
        SqliteEventStoreAdapter(db_path=DATA_DIR / "events.db"),
    )
    return getattr(get_global_event_store, "_instance")
