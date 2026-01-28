from contextlib import asynccontextmanager

from fastapi import FastAPI

from engine.api import api_router
from engine.constants import VERSION
from engine.instrumentation import init_instrumentation
from engine.settings import get_setting, get_setting_int, reset_env


@asynccontextmanager
async def _lifespan(app: FastAPI):
    reset_env()
    yield


app = FastAPI(lifespan=_lifespan, version=VERSION)
init_instrumentation(app=app)

app.include_router(api_router, prefix="/api/v1")


@app.get("/status")
async def status() -> dict[str, str]:
    return {
        "name": "relagent-engine",
        "version": VERSION,
        "status": "ok",
    }


def _print_banner() -> None:
    banner = r"""
  ____      _                        _
 |  _ \ ___| | __ _  __ _  ___ _ __ | |_
 | |_) / _ \ |/ _` |/ _` |/ _ \ '_ \| __|
 |  _ <  __/ | (_| | (_| |  __/ | | | |_
 |_| \_\___|_|\__,_|\__, |\___|_| |_|\__|
                    |___/
"""
    print(banner)
    print(f"  Engine v{VERSION}")
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
