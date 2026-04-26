from abc import ABC, abstractmethod
from uuid import UUID

from engine.domain.models import AssistantMessage, ChatContext, SystemAction


class AgentExecution(ABC):
    @abstractmethod
    async def run_basic_query(
        self,
        context: ChatContext,
        query: str | None = None,
        session_id: UUID | None = None,
    ) -> AssistantMessage | SystemAction:
        """Executes basic agentic query within context"""

        raise NotImplementedError

    @abstractmethod
    async def generate_title(self, query: str) -> str:
        """Generates title for the given query"""

        raise NotImplementedError
