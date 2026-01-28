from importlib.metadata import version as get_package_version
from pathlib import Path


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
