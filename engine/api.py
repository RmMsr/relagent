from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException

from engine.adapters.pydantic_ai_execution import PydanticAgentAdapter
from engine.adapters.yaml_persistence import YamlPersistenceAdapter
from engine.constants import DATA_DIR, DEBUG_DUMPS
from engine.domain.exceptions import ChatContextNotFound
from engine.domain.models import ChatRequest, ChatResponse, MessagesResponse, UserMessage
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
        ChatRequest(messages=[UserMessage(content=body)])
        if plain_body
        else body
    )

    response: ChatResponse = await service.perform_user_input(request=request)

    if plain_body:
        return response.message.content
    else:
        return response


@api_router.get("/messages/{session_id}")
def get_messages(session_id: UUID, service: ChatServiceDepends) -> MessagesResponse:
    try:
        return service.get_messages(session_id=session_id)
    except ChatContextNotFound:
        raise HTTPException(status_code=404, detail="Session not found")
