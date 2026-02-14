import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from engine.constants import VERSION
from engine.settings import get_setting, get_setting_int, reset_env

from .instrumentation import init_instrumentation
from .v1 import api_router

logger = logging.getLogger(__name__)

EVENT_PRUNE_INTERVAL_SECONDS = 3600  # 1 hour


@asynccontextmanager
async def _lifespan(app: FastAPI):
    reset_env()

    # async def prune_events_periodically():
    #     while True:
    #         await asyncio.sleep(EVENT_PRUNE_INTERVAL_SECONDS)
    #         try:
    #             event_store = get_global_event_store()
    #             deleted = event_store.prune_old_events()
    #             if deleted > 0:
    #                 logger.info("Periodic pruning: removed %d old events", deleted)
    #         except Exception as e:
    #             logger.warning("Event pruning failed: %s", e)

    # task = asyncio.create_task(prune_events_periodically())
    # try:
    #     await task
    # except asyncio.CancelledError:
    #     pass
    yield  # Executing FastAPI
    # task.cancel()


app = FastAPI(lifespan=_lifespan, version=VERSION)
init_instrumentation(app=app)
app.include_router(api_router, prefix="/api/v1")
# app.openapi = lambda: custom_openapi(app)


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
        app="engine.api.run:app",
        host=get_setting("server", "address", default="127.0.0.1"),
        port=get_setting_int("server", "port", default=8000),
        workers=get_setting_int("server", "workers", default=1),
    )
