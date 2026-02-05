from typing import Annotated

from fastapi import APIRouter, Depends

from engine.adapters.pydantic_ai_execution import PydanticAgentAdapter
from engine.adapters.yaml_persistence import YamlPersistenceAdapter
from engine.constants import DATA_DIR, DEBUG_DUMPS
from engine.domain.models import ChatMessage, ChatRequest, ChatResponse
from engine.domain.services import ChatService

api_router = APIRouter()


def dependency_chat_service() -> ChatService:
    return ChatService(
        persistence_repository=YamlPersistenceAdapter(data_dir=DATA_DIR),
        agent_execution=PydanticAgentAdapter(debug_dumps=DEBUG_DUMPS),
    )


ChatServiceDepends = Annotated[ChatService, Depends(dependency_chat_service)]


@api_router.post("/messages")
async def messages(
    body: ChatRequest | str, service: ChatServiceDepends
) -> ChatResponse | str:
    plain_body = not isinstance(body, ChatRequest)

    # Wrap request text into ChatRequest if needed
    request: ChatRequest = (
        ChatRequest(messages=[ChatMessage(role="user", content=body)])
        if plain_body
        else body
    )

    response: ChatResponse = await service.perform_user_input(request=request)

    if plain_body:
        return response.content
    else:
        return response
