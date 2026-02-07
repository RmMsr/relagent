import time
from typing import Sequence

from pydantic_ai import (
    AgentRunResult,
    ModelMessage,
    ModelRequest,
    ModelResponse,
    TextPart,
    UserPromptPart,
)

from engine.adapters.pydantic_ai_execution.agent_definitions import (
    discussion_agent,
    title_summarizer_agent,
)
from engine.domain.models import AgentStats, AssistantMessage, ChatContext, ChatMessage
from engine.domain.ports import AgentExecution


class PydanticAgentAdapter(AgentExecution):
    def __init__(self, debug_dumps: bool = False) -> None:
        super().__init__()
        self.debug_dumps = debug_dumps

    async def run_basic_query(
        self, context: ChatContext, query: str
    ) -> AssistantMessage:
        history = self._get_history_from_messages(context.messages)

        start_time = time.time()
        ai_response = await discussion_agent.run(query, message_history=history)
        agent_duration_seconds = time.time() - start_time

        answering_model_name = getattr(discussion_agent.model, "model_name", "") or None

        stats = AgentStats(
            agent_name=discussion_agent.name,
            answering_model_name=answering_model_name,
            duration_seconds=agent_duration_seconds,
            input_tokens=ai_response.usage().input_tokens,
            output_tokens=ai_response.usage().output_tokens,
            requests_count=ai_response.usage().requests,
            tool_calls_count=ai_response.usage().tool_calls,
        )
        if self.debug_dumps:
            self._dump_raw_messages(ai_response, "basic_query")
        return AssistantMessage(
            role="assistant", content=ai_response.output, stats=stats
        )

    async def generate_title(self, query: str) -> str:
        ai_response = await title_summarizer_agent.run(query)
        if self.debug_dumps:
            self._dump_raw_messages(ai_response, "title_summarizer")
        return ai_response.output

    def _get_history_from_messages(
        self, messages: Sequence[ChatMessage]
    ) -> Sequence[ModelMessage]:
        results: list[ModelMessage] = []
        for msg in messages:
            match msg.role:
                case "user":
                    results.append(
                        ModelRequest(parts=[UserPromptPart(content=msg.content)])
                    )
                case "assistant":
                    results.append(ModelResponse(parts=[TextPart(content=msg.content)]))
        return results

    def _dump_raw_messages(self, result: AgentRunResult, prefix: str = "") -> None:
        """
        Helps debugging by dumping raw messages to a YAML file
        """

        import json
        from pathlib import Path

        import yaml

        from engine.constants import DATA_DIR

        file_prefix = prefix + "_" if prefix else ""

        file_path = Path(DATA_DIR) / "debug" / (file_prefix + "last_messages_raw.yaml")
        file_path.parent.mkdir(parents=True, exist_ok=True)
        with open(file=file_path, mode="w") as fh:
            yaml.safe_dump(json.loads(result.all_messages_json()), fh)
