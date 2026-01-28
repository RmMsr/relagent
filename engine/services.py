import datetime
import logging

from engine.agents import simple_chat_agent, title_summarizer_agent
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

    if session.title is None:
        title = await title_summarizer_agent.run(request.messages[0].content)
        session.title = title.output

    result = await simple_chat_agent.run(request.messages[-1].content)

    session.updated_at = datetime.datetime.now()
    session.save_as_yaml()

    return ChatResponse(content=result.output, session_id=session.session_id)


def create_session() -> SessionInfo:
    session = SessionInfo()
    session.save_as_yaml()
    logger.info("New session created: %s", session.session_id)
    return session
