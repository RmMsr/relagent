from abc import ABC, abstractmethod
from uuid import UUID

from engine.domain.models import AssistantMessage, ChatContext, SessionInfo


class Persistence(ABC):
    @abstractmethod
    def save_session(self, session: SessionInfo) -> None:
        """
        Persists SessionInfo with updated timestamps
        """

        raise NotImplementedError

    @abstractmethod
    def load_session(self, session_id: UUID) -> SessionInfo:
        """
        Loads SessionInfo from persistence layer
        """

        raise NotImplementedError

    @abstractmethod
    def save_context(self, session: SessionInfo, context: ChatContext) -> None:
        """
        Persists ChatContext with updated timestamps
        """

        raise NotImplementedError

    @abstractmethod
    def load_context(self, session_id: UUID) -> ChatContext:
        """
        Loads ChatContext from persistence layer
        """

        raise NotImplementedError


class AgentExecution(ABC):
    @abstractmethod
    async def run_basic_query(
        self, context: ChatContext, query: str
    ) -> AssistantMessage:
        """
        Executes basic agentic query within context
        """

        raise NotImplementedError

    @abstractmethod
    async def generate_title(self, query: str) -> str:
        """
        Generates title for the given query
        """

        raise NotImplementedError
