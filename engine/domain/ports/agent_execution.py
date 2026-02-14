from abc import ABC, abstractmethod

from engine.domain.models import AssistantMessage, ChatContext


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
