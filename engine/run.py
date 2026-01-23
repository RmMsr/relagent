from contextlib import asynccontextmanager

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


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app="engine.run:app",
        host=get_setting("server", "address", default="127.0.0.1"),
        port=get_setting_int("server", "port", default=8000),
        workers=get_setting_int("server", "workers", default=1),
    )
