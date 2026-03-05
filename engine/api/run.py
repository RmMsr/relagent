from fastapi import FastAPI
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from engine.api.helpers import (
    check_secret_key,
    is_web_available,
    lifespan,
)
from engine.constants import VERSION, WEB_DIR
from engine.logging import get_logger, init_logging
from engine.settings import get_setting, get_setting_int

from .instrumentation import init_app_instrumentation, init_global_instrumentation
from .v1 import api_router

logger = get_logger(__name__)

init_logging()
init_global_instrumentation()
check_secret_key()


app = FastAPI(version=VERSION, lifespan=lifespan, title="Relagent Engine API")
app.include_router(api_router, prefix="/api/v1")
init_app_instrumentation(app=app)


@app.get("/health")
async def health():
    return "ok"


# Serve Relagent web app if build directory exists
if is_web_available():

    @app.get(
        "/",
        tags=["web-app"],
        name="Relagent web app",
        response_class=HTMLResponse,
    )
    async def root_page() -> RedirectResponse:
        return RedirectResponse(url="/app/")

    app.mount(
        "/app",
        StaticFiles(directory=WEB_DIR, html=True, check_dir=True),
        name="web-app",
    )


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
    print(f" Engine v{VERSION}")
    print()


if __name__ == "__main__":
    import uvicorn

    _print_banner()

    uvicorn.run(
        app="engine.api.run:app",
        host=get_setting("server", "address", default="127.0.0.1"),
        port=get_setting_int("server", "port", default=8000),
        workers=get_setting_int("server", "workers", default=1),
    )
