import logging

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from engine.constants import VERSION, WEB_DIR
from engine.settings import get_setting, get_setting_int, reset_env

from .instrumentation import init_instrumentation
from .v1 import api_router

logger = logging.getLogger(__name__)

reset_env()

app = FastAPI(version=VERSION)
app.include_router(api_router, prefix="/api/v1")
init_instrumentation(app=app)


@app.get("/status")
async def status() -> dict[str, str]:
    return {
        "name": "relagent-engine",
        "version": VERSION,
        "status": "ok",
    }


# Serve Relagent web app if build directory exists
if WEB_DIR.is_dir() and (WEB_DIR / "index.html").exists():

    @app.get("/app/{path:path}")
    async def serve_web_app(path: str) -> FileResponse:
        """Serve web app, falling back to index.html for single page routing."""
        file_path = WEB_DIR / path
        if file_path.is_file():
            return FileResponse(file_path)
        return FileResponse(WEB_DIR / "index.html")

    app.mount("/app", StaticFiles(directory=WEB_DIR, html=True), name="web-app")
    logger.info("Serving web app from %s at /app", WEB_DIR)


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
        app="engine.api.run:app",
        host=get_setting("server", "address", default="127.0.0.1"),
        port=get_setting_int("server", "port", default=8000),
        workers=get_setting_int("server", "workers", default=1),
    )
