from fastapi import APIRouter

from engine.models import ChatMessage, ChatRequest, ChatResponse
from engine.services import user_input

api_router = APIRouter()


@api_router.post("/messages")
async def messages(body: ChatRequest | str) -> ChatResponse | str:
    plain_body = not isinstance(body, ChatRequest)

    request: ChatRequest | None = None

    if not plain_body:
        request = body
    else:
        request = ChatRequest(messages=[ChatMessage(role="user", content=body)])

    response = await user_input(request=request)

    if plain_body:
        return response.content
    else:
        return response
