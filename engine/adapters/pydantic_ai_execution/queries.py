import time
from itertools import zip_longest
from typing import Any, Sequence
from uuid import UUID

from pydantic_ai import (
    Agent,
    AgentRunResult,
    DeferredToolRequests,
    DeferredToolResults,
    ModelMessage,
    ModelRequest,
    ModelResponse,
    TextPart,
    ToolCallPart,
    UserPromptPart,
)
from pydantic_ai.exceptions import ModelAPIError, ModelHTTPError

from engine.constants import PROVIDER_API_BASE
from engine.domain.exceptions import ProviderUnavailable
from engine.domain.models import (
    AgentStats,
    Approval,
    AssistantMessage,
    ChatContext,
    ChatMessage,
    SystemAction,
    UserMessage,
)
from engine.domain.ports.agent_execution import AgentExecution
from engine.domain.services import ApprovalService
from engine.domain.types import ApprovalType, SensitivityLevel
from engine.log_config import get_logger

from .agent_definitions import (
    discussion_agent,
    title_summarizer_agent,
)

logger = get_logger(__name__)


def _provider_body_snippet(body: object) -> str:
    """Short, single-line view of a provider error body for the reason text."""
    text = str(body).strip()
    if not text:
        return ""
    text = " ".join(text.split())
    return text[:200] + "…" if len(text) > 200 else text


def _map_provider_error(exc: ModelAPIError) -> None:
    """Translate a pydantic_ai transport error into ProviderUnavailable.

    A connection failure (provider not running / unreachable) and a 5xx (e.g.
    bundled llama.cpp still loading the model) both mean "not available, retry".
    A 4xx is a client/config error and is left to propagate unchanged.

    The reason names the configured endpoint and surfaces the provider's own
    message so the user gets a descriptive, actionable detail instead of a bare
    status code.
    """
    if isinstance(exc, ModelHTTPError):
        if exc.status_code >= 500:
            reason = (
                f"Inference provider at {PROVIDER_API_BASE} returned "
                f"HTTP {exc.status_code} — it may still be loading the model"
            )
            body = _provider_body_snippet(exc.body)
            if body:
                reason += f": {body}"
            raise ProviderUnavailable(reason) from exc
        return
    message = (exc.message or "connection failed").strip().rstrip(".")
    raise ProviderUnavailable(
        f"Cannot reach the inference provider at {PROVIDER_API_BASE} — "
        f"it may be offline or still starting up ({message})"
    ) from exc


class PydanticAgentAdapter(AgentExecution):
    _MAX_TOOL_ARGS = 10

    approval_service: ApprovalService

    def __init__(
        self, approval_service: ApprovalService, debug_dumps: bool = False
    ) -> None:
        super().__init__()
        self.approval_service = approval_service
        self.debug_dumps = debug_dumps

    async def run_basic_query(
        self,
        context: ChatContext,
        query: str | None = None,
        session_id: UUID | None = None,
    ) -> AssistantMessage | SystemAction:
        response = await self.run_agent_and_handle_permissions(
            context=context, agent=discussion_agent, query=query, session_id=session_id
        )

        return response

    async def run_agent_and_handle_permissions(
        self,
        context: ChatContext,
        agent: Agent[None, Any],
        query: str | None = None,
        session_id: UUID | None = None,
    ) -> AssistantMessage | SystemAction:
        history = self._get_known_history_from_messages(context.messages)

        remaining_iterations = 10
        final_message: AssistantMessage | SystemAction | None = None
        deferred_tool_results: DeferredToolResults | None = None
        agent_duration_seconds = 0.0
        stats = AgentStats()

        deferred_query: str | None = None
        trailing_approvals = self._get_trailing_approvals(context)
        if trailing_approvals:
            deferred_tool_results, open_approvals = self._resolve_approvals(
                trailing_approvals, session_id
            )
            if open_approvals:
                return SystemAction(approvals=open_approvals)
            # pydantic_ai rejects a user_prompt when history has unprocessed tool calls;
            # defer the query to the next iteration so it isn't lost.
            deferred_query = query
            query = None

        while final_message is None:
            if remaining_iterations <= 0:
                final_message = SystemAction(
                    notification="Request cancelled. Maximum iterations reached"
                )
                continue

            remaining_iterations -= 1

            start_time = time.monotonic()
            try:
                result = await agent.run(
                    message_history=history,
                    user_prompt=query,
                    deferred_tool_results=deferred_tool_results,
                )
            except ModelAPIError as exc:
                _map_provider_error(exc)
                raise
            agent_duration_seconds += time.monotonic() - start_time
            query = deferred_query if deferred_query else None
            deferred_query = None
            deferred_tool_results = None
            response = result.response

            if isinstance(result.output, DeferredToolRequests):
                approvals = self._get_approvals_from_pydantic_tool_calls(
                    tool_call_parts=response.tool_calls,
                    context_sensitivity=context.sensitivity_level,
                )
                deferred_tool_results, open_approvals = self._resolve_approvals(
                    approvals, session_id
                )
                if open_approvals:
                    final_message = SystemAction(approvals=open_approvals)
            elif isinstance(response.text, str):
                final_message = AssistantMessage(content=response.text)
            else:
                logger.warning("No usable output in %s. Retrying", response)

            history = result.all_messages()

            self._update_stats_with_run_result(
                stats=stats,
                result=result,
                agent_name=agent.name,
                duration_seconds=agent_duration_seconds,
            )

            if self.debug_dumps:
                self._dump_raw_messages(result, agent.name or "unknown")

        final_message.stats = stats
        return final_message

    def _get_trailing_approvals(self, context: ChatContext) -> list[Approval]:
        """Return all approvals from trailing in-flight SystemActions.

        Only SystemActions with final=False are collected. A final=True
        SystemAction is a settled cycle — its deferred tool results must not be
        replayed. Doing so would supply DeferredToolResults for a tool that
        causes pydantic_ai to raise:
          "Tool call results were provided, but the message history does not
           contain any unprocessed tool calls."
        """
        approvals: list[Approval] = []
        for msg in reversed(context.messages):
            if isinstance(msg, SystemAction) and not msg.final:
                approvals.extend(msg.approvals)
            else:
                break
        approvals.reverse()
        return approvals

    def _resolve_approvals(
        self,
        approvals: list[Approval],
        session_id: UUID | None,
    ) -> tuple[DeferredToolResults, list[Approval]]:
        """Build DeferredToolResults from approvals and return any still-open ones.

        Returns (deferred_tool_results, open_approvals).
        If open_approvals is non-empty, caller must ask the user before proceeding.
        """
        deferred_tool_results = DeferredToolResults()
        open_approvals: list[Approval] = []

        for approval in approvals:
            tool_call_id = approval.internal_parameters.get("tool_call_id")
            if not isinstance(tool_call_id, str):
                continue

            if approval.granted is True:
                deferred_tool_results.approvals[tool_call_id] = True
            elif approval.granted is False:
                deferred_tool_results.approvals[tool_call_id] = False
            else:
                open_approvals.append(approval)

        if open_approvals:
            satisfied, missing = (
                self.approval_service.get_satisfied_and_missing_approvals(
                    required_approvals=open_approvals, session_id=session_id
                )
            )
            for approval, _ in satisfied:
                tool_call_id = approval.internal_parameters.get("tool_call_id")
                if isinstance(tool_call_id, str):
                    deferred_tool_results.approvals[tool_call_id] = True
            open_approvals = missing

        return deferred_tool_results, open_approvals

    async def generate_title(self, query: str) -> str:
        try:
            ai_response = await title_summarizer_agent.run(query)
        except ModelAPIError as exc:
            _map_provider_error(exc)
            raise
        if self.debug_dumps:
            self._dump_raw_messages(ai_response, "title_summarizer")
        return ai_response.output

    def _get_known_history_from_messages(
        self, messages: Sequence[ChatMessage]
    ) -> list[ModelMessage]:
        """Construct Pydantic AI history from Relagent context messages.

        Rules:
        - UserMessage / AssistantMessage: included until cut off.
        - SystemAction settled (final=True) AND all decided AND followed by
          AssistantMessage: skipped (the AssistantMessage carries the result).
        - SystemAction settled (final=True) AND all decided WITHOUT a following
          AssistantMessage: stopped cycle — skipped entirely (no tool call
          emitted, since there is no result to pair with it).
        - SystemAction with unresolved approvals: emit tool call parts and cut
          off so the agent processes deferred tool calls.
        """

        results: list[ModelMessage] = []
        reached_cut_off: bool = False

        for msg, next_msg in zip_longest(messages, messages[1:], fillvalue=None):
            match msg:
                case UserMessage():
                    if reached_cut_off:
                        break
                    results.append(
                        ModelRequest(
                            parts=[UserPromptPart(content=msg.content)],
                            timestamp=msg.timestamp,
                        )
                    )
                case AssistantMessage():
                    if reached_cut_off:
                        break
                    results.append(
                        ModelResponse(
                            parts=[TextPart(content=msg.content)],
                            timestamp=msg.timestamp,
                        )
                    )
                case SystemAction():
                    if not msg.approvals:
                        # Skip: No relevant data for the agent
                        continue

                    all_decided: bool = all(
                        a.granted is not None for a in msg.approvals
                    )

                    # Settled with all decisions: either followed by an
                    # AssistantMessage (normal completion) or a stopped cycle
                    # (no result to emit). In both cases we skip the tool call
                    # request — pydantic_ai would reject an unpaired ToolCallPart.
                    if msg.final and all_decided:
                        continue

                    if not all_decided:
                        reached_cut_off = True

                    tool_call_parts: list[ToolCallPart] = []
                    for approval in msg.approvals:
                        tool_call_id = approval.internal_parameters.get("tool_call_id")
                        if not isinstance(tool_call_id, str) or not tool_call_id:
                            raise ValueError(
                                f"Tool call ID is required for tool call part. Got Approval: {approval}"
                            )
                        tool_call_parts.append(
                            ToolCallPart(
                                tool_call_id=tool_call_id,
                                tool_name=approval.component or "unknown",
                                args=approval.allowed_parameters,
                            )
                        )

                    results.append(
                        ModelResponse(parts=tool_call_parts, timestamp=msg.timestamp)
                    )

                    if isinstance(next_msg, SystemAction):
                        # Continue: Next message might contain more approvals
                        continue

                    # Stop to allow the agent to perform tool calls
                    break

        return results

    def _dump_raw_messages(
        self, result: AgentRunResult[object], prefix: str = ""
    ) -> None:
        """Helps debugging by dumping raw messages to a YAML file"""

        import json
        from pathlib import Path

        import yaml

        from engine.constants import DATA_DIR

        file_prefix = prefix + "_" if prefix else ""

        file_path = Path(DATA_DIR) / "debug" / (file_prefix + "last_messages_raw.yaml")
        file_path.parent.mkdir(parents=True, exist_ok=True)
        with open(file=file_path, mode="w") as fh:
            yaml.safe_dump(json.loads(result.all_messages_json()), fh)

    def _get_approvals_from_pydantic_tool_calls(
        self, tool_call_parts: list[ToolCallPart], context_sensitivity: SensitivityLevel
    ) -> list[Approval]:
        approvals = []
        for tool_call in tool_call_parts:
            if tool_call.tool_name == "web_search":
                args = tool_call.args_as_dict()
                if len(args) > self._MAX_TOOL_ARGS:
                    raise ValueError(
                        f"Tool call '{tool_call.tool_name}' has {len(args)} parameters, "
                        f"exceeding the limit of {self._MAX_TOOL_ARGS}."
                    )
                approvals.append(
                    Approval(
                        type=ApprovalType.OutgoingData,
                        component=tool_call.tool_name,
                        internal_parameters={"tool_call_id": tool_call.tool_call_id},
                        allowed_parameters=args,
                        purpose=f"Searching the web for '{args.get('query', 'None')}'",
                        sensitivity=context_sensitivity,
                    )
                )
            else:
                raise ValueError(
                    f"Cannot determine approvals for tool: {tool_call.tool_name}"
                )

        return approvals

    def _update_stats_with_run_result(
        self,
        stats: AgentStats,
        result: AgentRunResult[object],
        duration_seconds: float = 0.0,
        agent_name: str | None = None,
    ) -> None:
        if stats.agent_name is None:
            stats.agent_name = agent_name

        if stats.answering_model_name is None and result.response.model_name:
            stats.answering_model_name = result.response.model_name

        if stats.duration_seconds is None:
            stats.duration_seconds = duration_seconds
        else:
            stats.duration_seconds += duration_seconds

        if stats.input_tokens is None:
            stats.input_tokens = result.usage().input_tokens
        else:
            stats.input_tokens += result.usage().input_tokens

        if stats.output_tokens is None:
            stats.output_tokens = result.usage().output_tokens
        else:
            stats.output_tokens += result.usage().output_tokens

        if stats.requests_count is None:
            stats.requests_count = result.usage().requests
        else:
            stats.requests_count += result.usage().requests

        if stats.tool_calls_count is None:
            stats.tool_calls_count = result.usage().tool_calls
        else:
            stats.tool_calls_count += result.usage().tool_calls
