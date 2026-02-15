from abc import ABC, abstractmethod
from uuid import UUID

from engine.domain.exceptions import SessionNotFound
from engine.domain.models import ChatContext, SessionInfo


class Persistence(ABC):
    @abstractmethod
    def load_session(self, session_id: UUID) -> SessionInfo:
        """
        Loads SessionInfo from persistence layer
        """

        raise NotImplementedError

    @abstractmethod
    def list_recent_sessions(self, limit: int = 100) -> list[SessionInfo]:
        """
        List recent sessions sorted by last modified time.
        Returns up to `limit` sessions (default: 100).
        """

        raise NotImplementedError

    @abstractmethod
    def save_session(self, session: SessionInfo) -> None:
        """
        Persists SessionInfo with updated timestamps
        """

        raise NotImplementedError

    @abstractmethod
    def delete_session(self, session_id: UUID) -> None:
        """
        Delete a session and all its associated data.
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

    def find_session(self, session_id: UUID) -> SessionInfo | None:
        """
        Non-throwing version of load_session
        """
        try:
            return self.load_session(session_id=session_id)
        except SessionNotFound:
            return None
