from abc import ABC, abstractmethod
from uuid import UUID

from engine.domain.models import ChatContext, SessionInfo


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
    def save_context(self, session_id: UUID, context: ChatContext) -> None:
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
