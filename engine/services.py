import logging

from engine.agents import main_agent
from engine.exceptions import SessionNotFound
from engine.models import ChatRequest, ChatResponse, SessionInfo

logger = logging.getLogger(__name__)


async def user_input(request: ChatRequest) -> ChatResponse:
    session: SessionInfo | None = None
    if request.session_id:
        try:
            session = SessionInfo.load_from_yaml(session_id=request.session_id)
        except SessionNotFound:
            session = create_session()
    else:
        session = create_session()

    result = await main_agent.run(request.content)
    return ChatResponse(content=result.output, session_id=session.session_id)


def create_session() -> SessionInfo:
    session = SessionInfo(title="New chat")
    session.save_as_yaml()
    logger.info("New session created: %s", session.session_id)
    return session
