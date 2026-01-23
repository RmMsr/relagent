from contextlib import asynccontextmanager
from importlib.metadata import version as get_package_version
from pathlib import Path

from fastapi import FastAPI

from engine.instrumentation import init_instrumentation
from engine.models import ChatRequest, ChatResponse
from engine.services import user_input
from engine.settings import get_setting, get_setting_int, reset_env


@asynccontextmanager
async def lifespan(app: FastAPI):
    reset_env()
    init_instrumentation(app=app)
    yield


app = FastAPI(lifespan=lifespan)


@app.post("/api/v1/message")
async def chat(body: ChatRequest | str) -> ChatResponse | str:
    plain_body = not isinstance(body, ChatRequest)

    request: ChatRequest | None = None

    if not plain_body:
        request = body
    else:
        request = ChatRequest(content=body)

    response = await user_input(request=request)

    if plain_body:
        return response.content
    else:
        return response


def _get_version() -> str:
    """Get package version from installed metadata or VERSION file."""
    # Try installed package metadata first
    try:
        return get_package_version("relagent-engine")
    except Exception:
        pass

    # Fall back to VERSION file (for development or container without editable install)
    try:
        # VERSION file is at repo root, engine/ is one level down
        version_file = Path(__file__).parent.parent / "VERSION"
        if version_file.exists():
            return version_file.read_text().strip()
    except Exception:
        pass

    return "unknown"


@app.get("/status")
async def status() -> dict[str, str]:
    """Return service status including version information."""
    return {
        "name": "relagent-engine",
        "version": _get_version(),
        "status": "ok",
    }


def _print_banner() -> None:
    """Print startup banner with ASCII art."""
    banner = r"""
  ____      _                        _
 |  _ \ ___| | __ _  __ _  ___ _ __ | |_
 | |_) / _ \ |/ _` |/ _` |/ _ \ '_ \| __|
 |  _ <  __/ | (_| | (_| |  __/ | | | |_
 |_| \_\___|_|\__,_|\__, |\___|_| |_|\__|
                    |___/
"""
    print(banner)
    print(f"  Engine v{_get_version()}")
    print()


if __name__ == "__main__":
    import uvicorn

    _print_banner()

    uvicorn.run(
        app="engine.run:app",
        host=get_setting("server", "address", default="127.0.0.1"),
        port=get_setting_int("server", "port", default=8000),
        workers=get_setting_int("server", "workers", default=1),
    )
