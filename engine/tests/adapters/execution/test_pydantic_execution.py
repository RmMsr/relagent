from datetime import datetime, timezone
from unittest.mock import patch

import pytest
from pydantic_ai import (
    ModelMessage,
    ModelRequest,
    ModelResponse,
    TextPart,
    ToolCallPart,
    ToolReturnPart,
    UserPromptPart,
    models,
)
from pydantic_ai.exceptions import ModelAPIError, ModelHTTPError
from pydantic_ai.models.function import AgentInfo, FunctionModel
from pydantic_ai.models.test import TestModel

from engine.adapters.pydantic_ai_execution.agent_definitions import (
    discussion_agent,
    title_summarizer_agent,
)
from engine.adapters.pydantic_ai_execution.queries import PydanticAgentAdapter
from engine.domain.exceptions import ProviderUnavailable
from engine.domain.models import (
    Approval,
    AssistantMessage,
    ChatContext,
    Grant,
    SystemAction,
    UserMessage,
)
from engine.domain.services import ApprovalService
from engine.domain.types import ApprovalType, SensitivityLevel

pytestmark = pytest.mark.anyio
models.ALLOW_MODEL_REQUESTS = False


@pytest.fixture
def adapter(approval_service: ApprovalService) -> PydanticAgentAdapter:
    return PydanticAgentAdapter(approval_service=approval_service)


def _final_output(content: str, language_code: str | None = None) -> ModelResponse:
    """A ModelResponse that ends the run via the discussion_agent output tool.

    The agent's output_type is DiscussionResponse, so a plain TextPart no longer
    terminates the run — the model must call the `final_result` tool.
    """
    args: dict[str, object] = {"content": content}
    if language_code is not None:
        args["language_code"] = language_code
    return ModelResponse(parts=[ToolCallPart(tool_name="final_result", args=args)])


class TestPydanticExecutionAdapterQueries:
    async def test_run_basic_query(self, adapter: PydanticAgentAdapter):
        context = ChatContext(messages=[])
        test_model = TestModel(
            custom_output_args={"content": "Test response"}, call_tools=[]
        )
        with discussion_agent.override(model=test_model):
            result = await adapter.run_basic_query(context=context, query="test")

        assert isinstance(result, AssistantMessage)
        assert result.message_id is not None
        assert result.stats is not None
        assert result.stats.answering_model_name == "test"
        assert result.content == "Test response"

    async def test_run_basic_query_captures_language_code(
        self, adapter: PydanticAgentAdapter
    ):
        context = ChatContext(messages=[])
        test_model = TestModel(
            custom_output_args={"content": "Bonjour.", "language_code": "fr"},
            call_tools=[],
        )
        with discussion_agent.override(model=test_model):
            result = await adapter.run_basic_query(context=context, query="test")

        assert isinstance(result, AssistantMessage)
        assert result.language_code == "fr"
        assert result.content == "Bonjour."

    async def test_run_basic_query_without_language_code_leaves_it_unset(
        self, adapter: PydanticAgentAdapter
    ):
        context = ChatContext(messages=[])
        test_model = TestModel(
            custom_output_args={"content": "Test response"}, call_tools=[]
        )
        with discussion_agent.override(model=test_model):
            result = await adapter.run_basic_query(context=context, query="test")

        assert isinstance(result, AssistantMessage)
        assert result.language_code is None
        assert result.content == "Test response"

    async def test_generate_title(self, adapter: PydanticAgentAdapter):
        test_model = TestModel(custom_output_text="Book inquiry")
        with title_summarizer_agent.override(model=test_model):
            result = await adapter.generate_title(query="Question about a book")

        assert result == "Book inquiry"

    async def test_run_agent_and_handle_permissions_simple_run(
        self, adapter: PydanticAgentAdapter
    ):
        context = ChatContext(messages=[])

        def model_function(
            messages: list[ModelMessage], info: AgentInfo
        ) -> ModelResponse:
            return _final_output("Test response")

        test_model = FunctionModel(function=model_function)

        with discussion_agent.override(model=test_model):
            result = await adapter.run_agent_and_handle_permissions(
                context=context, agent=discussion_agent, query="test"
            )

        assert isinstance(result, AssistantMessage)
        assert result.message_id is not None
        assert result.stats is not None
        assert result.content == "Test response"


def _tool_approval(
    tool_call_id: str = "call_1",
    component: str = "web_search",
    query: str = "test query",
) -> Approval:
    return Approval(
        type=ApprovalType.OutgoingData,
        component=component,
        purpose="test",
        allowed_parameters={"query": query},
        internal_parameters={"tool_call_id": tool_call_id},
    )


class TestGetApprovalsFromToolCalls:
    def test_get_approvals_for_web_search(self, adapter: PydanticAgentAdapter):
        result = adapter._get_approvals_from_pydantic_tool_calls(
            tool_call_parts=[
                ToolCallPart(
                    tool_name="web_search",
                    tool_call_id="call_1",
                    args={"query": "test query"},
                )
            ],
            context_sensitivity=SensitivityLevel.OpenInformation,
        )
        assert len(result) == 1
        assert result[0].type == ApprovalType.OutgoingData
        assert result[0].component == "web_search"
        assert result[0].purpose == "Searching the web for 'test query'"
        assert result[0].allowed_parameters == {"query": "test query"}
        assert result[0].internal_parameters == {"tool_call_id": "call_1"}
        assert result[0].sensitivity == SensitivityLevel.OpenInformation

    def test_unknown_tool_raises(self, adapter: PydanticAgentAdapter):
        with pytest.raises(ValueError, match="unknown_tool"):
            adapter._get_approvals_from_pydantic_tool_calls(
                tool_call_parts=[
                    ToolCallPart(
                        tool_name="unknown_tool",
                        tool_call_id="call_1",
                        args={"query": "test query"},
                    )
                ],
                context_sensitivity=SensitivityLevel.OpenInformation,
            )

    def test_too_many_args_raises(self, adapter: PydanticAgentAdapter):
        with pytest.raises(ValueError, match="exceeding the limit"):
            adapter._get_approvals_from_pydantic_tool_calls(
                tool_call_parts=[
                    ToolCallPart(
                        tool_name="web_search",
                        tool_call_id="call_1",
                        args={f"param_{i}": f"value_{i}" for i in range(11)},
                    )
                ],
                context_sensitivity=SensitivityLevel.OpenInformation,
            )


class TestGetHistoryFromMessages:
    def test_empty_messages_returns_empty_history(self, adapter: PydanticAgentAdapter):
        result = adapter._get_known_history_from_messages([])
        assert list(result) == []

    def test_user_message_becomes_model_request(self, adapter: PydanticAgentAdapter):
        msg = UserMessage(content="Hello")
        result = adapter._get_known_history_from_messages([msg])
        assert len(result) == 1
        assert isinstance(result[0], ModelRequest)
        assert isinstance(result[0].parts[0], UserPromptPart)
        assert result[0].parts[0].content == "Hello"
        assert result[0].timestamp == msg.timestamp

    def test_assistant_message_becomes_model_response_with_text_part(
        self, adapter: PydanticAgentAdapter
    ):
        msg = AssistantMessage(content="Hi there")
        result = adapter._get_known_history_from_messages([msg])
        assert len(result) == 1
        assert isinstance(result[0], ModelResponse)
        assert isinstance(result[0].parts[0], TextPart)
        assert result[0].parts[0].content == "Hi there"
        assert result[0].timestamp == msg.timestamp

    def test_mixed_messages_preserve_order(self, adapter: PydanticAgentAdapter):
        messages = [
            UserMessage(content="Question"),
            AssistantMessage(content="Answer"),
            UserMessage(content="Follow-up"),
        ]
        result = adapter._get_known_history_from_messages(messages)
        assert len(result) == 3
        assert isinstance(result[0], ModelRequest)
        assert isinstance(result[1], ModelResponse)
        assert isinstance(result[2], ModelRequest)

    def test_system_action_with_approval_becomes_tool_call_response(
        self, adapter: PydanticAgentAdapter
    ):
        action = SystemAction(approvals=[_tool_approval(tool_call_id="call_1")])
        result = adapter._get_known_history_from_messages([action])
        assert len(result) == 1
        assert isinstance(result[0], ModelResponse)
        part = result[0].parts[0]
        assert isinstance(part, ToolCallPart)
        assert part.tool_call_id == "call_1"
        assert part.tool_name == "web_search"

    def test_system_action_tool_call_args_from_allowed_parameters(
        self, adapter: PydanticAgentAdapter
    ):
        action = SystemAction(approvals=[_tool_approval(query="my search")])
        result = adapter._get_known_history_from_messages([action])
        part = result[0].parts[0]
        assert isinstance(part, ToolCallPart)
        assert part.args_as_dict() == {"query": "my search"}

    def test_system_action_timestamp_preserved(self, adapter: PydanticAgentAdapter):
        ts = datetime(2024, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
        action = SystemAction(approvals=[_tool_approval()], timestamp=ts)
        result = adapter._get_known_history_from_messages([action])
        assert result[0].timestamp == ts

    def test_system_action_multiple_approvals_produce_one_response_with_multiple_parts(
        self, adapter: PydanticAgentAdapter
    ):
        action = SystemAction(
            approvals=[
                _tool_approval(tool_call_id="call_1"),
                _tool_approval(tool_call_id="call_2"),
            ]
        )
        result = adapter._get_known_history_from_messages([action])
        assert len(result) == 1
        assert isinstance(result[0], ModelResponse)
        assert len(result[0].parts) == 2
        assert isinstance(result[0].parts[0], ToolCallPart)
        assert isinstance(result[0].parts[1], ToolCallPart)
        assert result[0].parts[0].tool_call_id == "call_1"
        assert result[0].parts[1].tool_call_id == "call_2"

    def test_system_action_with_no_approvals_is_skipped(
        self, adapter: PydanticAgentAdapter
    ):
        # A notification-only SystemAction has no model history representation.
        # It is skipped; messages before and after it are both included.
        messages = [
            UserMessage(content="Before"),
            SystemAction(approvals=[], notification="Context has been compressed"),
            UserMessage(content="After"),
        ]
        result = adapter._get_known_history_from_messages(messages)
        assert len(result) == 2
        assert isinstance(result[0].parts[0], UserPromptPart)
        assert result[0].parts[0].content == "Before"
        assert isinstance(result[1].parts[0], UserPromptPart)
        assert result[1].parts[0].content == "After"

    def test_history_stops_at_pending_approval(self, adapter: PydanticAgentAdapter):
        """A SystemAction with a pending approval (granted=None) is included
        as ToolCallParts, and all messages after it are dropped."""
        messages = [
            UserMessage(content="Before"),
            SystemAction(approvals=[_tool_approval()]),  # granted=None by default
            UserMessage(content="After"),
        ]
        result = adapter._get_known_history_from_messages(messages)
        assert len(result) == 2
        assert isinstance(result[0], ModelRequest)
        assert result[0].parts[0].content == "Before"
        assert isinstance(result[1], ModelResponse)
        assert isinstance(result[1].parts[0], ToolCallPart)

    def test_completed_granted_cycle_is_skipped(self, adapter: PydanticAgentAdapter):
        """A completed cycle (granted + AssistantMessage after) is omitted."""
        granted_approval = _tool_approval()
        granted_approval.granted = True
        messages = [
            UserMessage(content="Before", final=True),
            SystemAction(approvals=[granted_approval], final=True),
            AssistantMessage(content="Done"),
        ]
        result = adapter._get_known_history_from_messages(messages)
        assert len(result) == 2
        assert isinstance(result[0], ModelRequest)
        assert result[0].parts[0].content == "Before"
        assert isinstance(result[1], ModelResponse)
        assert isinstance(result[1].parts[0], TextPart)
        assert result[1].parts[0].content == "Done"

    def test_completed_denied_cycle_is_skipped(self, adapter: PydanticAgentAdapter):
        """A completed cycle (denied + AssistantMessage after) is omitted."""
        denied_approval = _tool_approval()
        denied_approval.granted = False
        messages = [
            UserMessage(content="Before", final=True),
            SystemAction(approvals=[denied_approval], final=True),
            AssistantMessage(content="OK, I won't do that"),
        ]
        result = adapter._get_known_history_from_messages(messages)
        assert len(result) == 2
        assert isinstance(result[0], ModelRequest)
        assert result[0].parts[0].content == "Before"
        assert isinstance(result[1], ModelResponse)
        assert isinstance(result[1].parts[0], TextPart)
        assert result[1].parts[0].content == "OK, I won't do that"

    def test_trailing_granted_action_is_included(self, adapter: PydanticAgentAdapter):
        """A resolved SystemAction at the tail (no AssistantMessage after)
        is included — pydantic_ai needs the ToolCallParts for DeferredToolResults."""
        granted = _tool_approval()
        granted.granted = True
        messages = [
            UserMessage(content="Search"),
            SystemAction(approvals=[granted]),
        ]
        result = adapter._get_known_history_from_messages(messages)
        assert len(result) == 2
        assert isinstance(result[0], ModelRequest)
        assert result[0].parts[0].content == "Search"
        assert isinstance(result[1], ModelResponse)
        assert isinstance(result[1].parts[0], ToolCallPart)

    def test_trailing_denied_action_is_included(self, adapter: PydanticAgentAdapter):
        """A denied SystemAction at the tail is included as a ToolCallPart so that
        DeferredToolResults can supply the denial and the agent can respond without
        the tool result."""
        denied = _tool_approval()
        denied.granted = False
        messages = [
            UserMessage(content="Search"),
            SystemAction(approvals=[denied]),
        ]
        result = adapter._get_known_history_from_messages(messages)
        assert len(result) == 2
        assert isinstance(result[0], ModelRequest)
        assert result[0].parts[0].content == "Search"
        assert isinstance(result[1], ModelResponse)
        assert isinstance(result[1].parts[0], ToolCallPart)

    def test_assistant_after_resolved_action_is_included(
        self, adapter: PydanticAgentAdapter
    ):
        """The assistant response following a resolved approval cycle is kept."""
        granted = _tool_approval()
        granted.granted = True
        messages = [
            UserMessage(content="Search", final=True),
            SystemAction(approvals=[granted], final=True),
            AssistantMessage(content="Here are results"),
            UserMessage(content="Thanks"),
        ]
        result = adapter._get_known_history_from_messages(messages)
        assert len(result) == 3
        assert isinstance(result[0], ModelRequest)
        assert result[0].parts[0].content == "Search"
        assert isinstance(result[1], ModelResponse)
        assert isinstance(result[1].parts[0], TextPart)
        assert result[1].parts[0].content == "Here are results"
        assert isinstance(result[2], ModelRequest)
        assert result[2].parts[0].content == "Thanks"

    def test_user_message_after_resolved_action_without_assistant_stops(
        self, adapter: PydanticAgentAdapter
    ):
        """A resolved SystemAction at the tail with no AssistantMessage is
        included as ToolCallParts. The following UserMessage is dropped."""
        granted = _tool_approval()
        granted.granted = True
        messages = [
            UserMessage(content="Search"),
            SystemAction(approvals=[granted]),
            UserMessage(content="New question"),
        ]
        result = adapter._get_known_history_from_messages(messages)
        assert len(result) == 2
        assert isinstance(result[0], ModelRequest)
        assert result[0].parts[0].content == "Search"
        assert isinstance(result[1], ModelResponse)
        assert isinstance(result[1].parts[0], ToolCallPart)

    def test_multiple_completed_cycles_all_skipped(self, adapter: PydanticAgentAdapter):
        """Multiple completed approval cycles are all omitted."""
        granted_1 = _tool_approval(tool_call_id="call_1")
        granted_1.granted = True
        granted_2 = _tool_approval(tool_call_id="call_2")
        granted_2.granted = True
        messages = [
            UserMessage(content="First", final=True),
            SystemAction(approvals=[granted_1], final=True),
            AssistantMessage(content="Result 1"),
            UserMessage(content="Second", final=True),
            SystemAction(approvals=[granted_2], final=True),
            AssistantMessage(content="Result 2"),
        ]
        result = adapter._get_known_history_from_messages(messages)
        assert len(result) == 4
        assert isinstance(result[0].parts[0], UserPromptPart)
        assert result[0].parts[0].content == "First"
        assert isinstance(result[1].parts[0], TextPart)
        assert result[1].parts[0].content == "Result 1"
        assert isinstance(result[2].parts[0], UserPromptPart)
        assert result[2].parts[0].content == "Second"
        assert isinstance(result[3].parts[0], TextPart)
        assert result[3].parts[0].content == "Result 2"

    def test_multiple_system_actions_with_approvals(
        self, adapter: PydanticAgentAdapter
    ):
        """Multiple system actions with approvals are handled correctly."""
        approval_1 = _tool_approval(tool_call_id="call_1")
        approval_2 = _tool_approval(tool_call_id="call_2")
        messages = [
            UserMessage(content="First"),
            SystemAction(approvals=[approval_1]),
            SystemAction(approvals=[approval_2]),
            UserMessage(content="Second"),
        ]
        result = adapter._get_known_history_from_messages(messages)
        assert len(result) == 3
        assert isinstance(result[0].parts[0], UserPromptPart)
        assert result[0].parts[0].content == "First"
        assert isinstance(result[1].parts[0], ToolCallPart)
        assert isinstance(result[2].parts[0], ToolCallPart)

    def test_completed_then_pending_includes_only_trailing_pending(
        self, adapter: PydanticAgentAdapter
    ):
        """An older completed cycle is skipped; a newer pending one is included."""
        granted = _tool_approval(tool_call_id="call_1")
        granted.granted = True
        pending = _tool_approval(tool_call_id="call_2")
        messages = [
            UserMessage(content="First", final=True),
            SystemAction(approvals=[granted], final=True),
            AssistantMessage(content="Result"),
            UserMessage(content="Second", final=False),
            SystemAction(approvals=[pending], final=False),
            UserMessage(content="Ignored"),
        ]
        result = adapter._get_known_history_from_messages(messages)
        assert len(result) == 4
        assert isinstance(result[0], ModelRequest)
        assert result[0].parts[0].content == "First"
        assert isinstance(result[1], ModelResponse)
        assert isinstance(result[1].parts[0], TextPart)
        assert result[1].parts[0].content == "Result"
        assert isinstance(result[2], ModelRequest)
        assert result[2].parts[0].content == "Second"
        assert isinstance(result[3], ModelResponse)
        assert isinstance(result[3].parts[0], ToolCallPart)
        assert result[3].parts[0].tool_call_id == "call_2"


class TestGetTrailingApprovals:
    def test_returns_empty_when_no_system_action(self, adapter: PydanticAgentAdapter):
        context = ChatContext(messages=[UserMessage(content="hi")])
        assert adapter._get_trailing_approvals(context) == []

    def test_returns_approvals_from_in_flight_tail_system_action(
        self, adapter: PydanticAgentAdapter
    ):
        approval = _tool_approval()
        context = ChatContext(
            messages=[
                UserMessage(content="hi"),
                SystemAction(approvals=[approval], final=False),
            ]
        )
        result = adapter._get_trailing_approvals(context)
        assert result == [approval]

    def test_does_not_collect_from_settled_system_action(
        self, adapter: PydanticAgentAdapter
    ):
        """A final=True SystemAction is a settled cycle. Collecting its approvals
        would supply DeferredToolResults for a tool call that the history builder
        already skipped, causing pydantic_ai to raise:
          'Tool call results were provided, but the message history does not
           contain any unprocessed tool calls.'"""
        denied = _tool_approval()
        denied.granted = False
        context = ChatContext(
            messages=[
                UserMessage(content="Any european embassy?"),
                SystemAction(approvals=[denied], final=True),
            ]
        )
        assert adapter._get_trailing_approvals(context) == []

    def test_stops_at_settled_system_action_while_collecting_in_flight(
        self, adapter: PydanticAgentAdapter
    ):
        """Walking backwards stops as soon as a non-SystemAction or a final
        SystemAction is encountered."""
        pending = _tool_approval(tool_call_id="call_pending")
        settled = _tool_approval(tool_call_id="call_settled")
        settled.granted = True
        context = ChatContext(
            messages=[
                UserMessage(content="hi"),
                SystemAction(approvals=[settled], final=True),
                SystemAction(approvals=[pending], final=False),
            ]
        )
        result = adapter._get_trailing_approvals(context)
        assert result == [pending]

    def test_stops_at_assistant_message(self, adapter: PydanticAgentAdapter):
        context = ChatContext(
            messages=[
                UserMessage(content="Hi"),
                AssistantMessage(content="Hello"),
                UserMessage(content="Next"),
            ]
        )
        assert adapter._get_trailing_approvals(context) == []


class TestExecutionLoop:
    async def test_run_agent_returns_assistant_message(
        self, adapter: PydanticAgentAdapter
    ):
        context = ChatContext(messages=[])
        with discussion_agent.override(
            model=TestModel(custom_output_args={"content": "Response"}, call_tools=[])
        ):
            result = await adapter.run_agent_and_handle_permissions(
                context=context, query="Hello", agent=discussion_agent
            )

        assert isinstance(result, AssistantMessage)
        assert result.content == "Response"

    async def test_run_agent_with_history(self, adapter: PydanticAgentAdapter):
        context = ChatContext(
            messages=[
                UserMessage(content="Hello"),
                AssistantMessage(content="Good morning"),
            ]
        )

        def model_function(
            messages: list[ModelMessage], info: AgentInfo
        ) -> ModelResponse:
            assert len(messages) == 3
            assert isinstance(messages[-1], ModelRequest)
            return _final_output(f"Response: {messages[-1].parts[0].content}")

        with discussion_agent.override(model=FunctionModel(model_function)):
            result = await adapter.run_agent_and_handle_permissions(
                context=context, query="When is Friday?", agent=discussion_agent
            )

        assert isinstance(result, AssistantMessage)
        assert result.content == "Response: When is Friday?"

    async def test_run_agent_returns_approval(self, adapter: PydanticAgentAdapter):
        context = ChatContext(
            messages=[], sensitivity_level=SensitivityLevel.OpenInformation
        )

        def model_function(
            messages: list[ModelMessage], info: AgentInfo
        ) -> ModelResponse:
            return ModelResponse(
                parts=[
                    ToolCallPart(
                        tool_name="web_search",
                        args={"query": "test"},
                    )
                ],
            )

        with discussion_agent.override(model=FunctionModel(function=model_function)):
            result = await adapter.run_agent_and_handle_permissions(
                context=context, query="What's the weather?", agent=discussion_agent
            )

        assert isinstance(result, SystemAction)
        assert len(result.approvals) == 1
        assert result.approvals[0].component == "web_search"
        assert result.approvals[0].allowed_parameters == {"query": "test"}

    async def test_run_agent_approval_carries_context_sensitivity(
        self, adapter: PydanticAgentAdapter
    ):
        context = ChatContext(
            messages=[], sensitivity_level=SensitivityLevel.Confidential
        )

        def model_function(
            messages: list[ModelMessage], info: AgentInfo
        ) -> ModelResponse:
            return ModelResponse(
                parts=[ToolCallPart(tool_name="web_search", args={"query": "test"})]
            )

        with discussion_agent.override(model=FunctionModel(function=model_function)):
            result = await adapter.run_agent_and_handle_permissions(
                context=context, query="What's the weather?", agent=discussion_agent
            )

        assert isinstance(result, SystemAction)
        assert result.approvals[0].sensitivity == SensitivityLevel.Confidential

    async def test_run_agent_uses_existing_grant(self, adapter: PydanticAgentAdapter):
        context = ChatContext(
            messages=[], sensitivity_level=SensitivityLevel.OpenInformation
        )

        adapter.approval_service.register_global_grant(
            Grant(
                approval_type=ApprovalType.OutgoingData,
                component="web_search",
                allowed_parameters={"query": "test"},
            )
        )

        def model_function(
            messages: list[ModelMessage], info: AgentInfo
        ) -> ModelResponse:
            if len(messages) == 1:
                return ModelResponse(
                    parts=[
                        ToolCallPart(
                            tool_name="web_search",
                            args={"query": "test"},
                        )
                    ],
                )

            return _final_output("I'm done")

        with (
            discussion_agent.override(model=FunctionModel(function=model_function)),
            patch("engine.adapters.pydantic_ai_execution.tools.DDGS") as mock_ddgs,
        ):
            mock_ddgs.return_value.text.return_value = [
                {"title": "Result", "href": "http://example.com"}
            ]
            result = await adapter.run_agent_and_handle_permissions(
                context=context, query="What's the weather?", agent=discussion_agent
            )

        assert isinstance(result, AssistantMessage)
        assert result.content == "I'm done"

    async def test_run_agent_continue_with_sufficient_grant(
        self, adapter: PydanticAgentAdapter
    ):
        context = ChatContext(
            messages=[
                UserMessage(content="What's the weather?"),
                SystemAction(
                    approvals=[
                        Approval(
                            type=ApprovalType.OutgoingData,
                            component="web_search",
                            internal_parameters={"tool_call_id": "call_123"},
                            purpose="Weather search",
                            granted=False,
                        )
                    ]
                ),
            ],
            sensitivity_level=SensitivityLevel.OpenInformation,
        )

        adapter.approval_service.register_global_grant(
            Grant(
                approval_type=ApprovalType.OutgoingData,
                component="web_search",
            )
        )

        def model_function(
            messages: list[ModelMessage], info: AgentInfo
        ) -> ModelResponse:
            assert messages[-1].kind == "request"
            return _final_output("It is sunny")

        with (
            discussion_agent.override(model=FunctionModel(function=model_function)),
            patch("engine.adapters.pydantic_ai_execution.tools.DDGS") as mock_ddgs,
        ):
            mock_ddgs.return_value.text.return_value = [
                {"title": "Result", "href": "http://example.com"}
            ]
            result = await adapter.run_agent_and_handle_permissions(
                context=context, agent=discussion_agent
            )

        assert isinstance(result, AssistantMessage)
        assert result.content == "It is sunny"

    async def test_run_agent_continue_with_rejected_approval_sends_denial(
        self, adapter: PydanticAgentAdapter
    ):
        """Mirrors test_run_agent_continue_with_sufficient_grant but for the
        False path: when the user explicitly rejected the approval (granted=False),
        DeferredToolResults should carry approvals[tool_call_id] = False so that
        pydantic-ai receives the denial and the model can find another path."""
        context = ChatContext(
            messages=[
                UserMessage(content="What's the weather?"),
                SystemAction(
                    approvals=[
                        Approval(
                            type=ApprovalType.OutgoingData,
                            component="web_search",
                            internal_parameters={"tool_call_id": "call_123"},
                            purpose="Weather search",
                            granted=False,  # explicitly rejected by user
                        )
                    ]
                ),
            ],
            sensitivity_level=SensitivityLevel.OpenInformation,
        )

        # No grants registered — the rejection should be forwarded as a denial
        model_called = False

        def model_function(
            messages: list[ModelMessage], info: AgentInfo
        ) -> ModelResponse:
            nonlocal model_called
            model_called = True
            return _final_output("I won't search the web")

        with discussion_agent.override(model=FunctionModel(function=model_function)):
            await adapter.run_agent_and_handle_permissions(
                context=context, agent=discussion_agent
            )

        # The key assertion: the denial must reach pydantic-ai so the model
        # can decide what to do. If the adapter short-circuits with a
        # SystemAction re-ask, the model is never called.
        assert model_called, "Denial was not forwarded to pydantic-ai"

    async def test_run_agent_continue_with_insufficient_grant(
        self, adapter: PydanticAgentAdapter
    ):
        """An undecided approval (granted=None) with a non-matching grant
        should still result in a SystemAction re-ask."""
        context = ChatContext(
            messages=[
                UserMessage(content="What's the weather?"),
                SystemAction(
                    approvals=[
                        Approval(
                            type=ApprovalType.OutgoingData,
                            component="web_search",
                            internal_parameters={"tool_call_id": "call_123"},
                            purpose="Weather search",
                            granted=None,  # undecided — user hasn't responded yet
                        )
                    ]
                ),
            ],
            sensitivity_level=SensitivityLevel.OpenInformation,
        )

        # Grant exists but doesn't match (different query)
        adapter.approval_service.register_global_grant(
            Grant(
                approval_type=ApprovalType.OutgoingData,
                component="web_search",
                allowed_parameters={"query": "Some other query"},
            )
        )

        result = await adapter.run_agent_and_handle_permissions(
            context=context, query="What's the weather?", agent=discussion_agent
        )

        assert isinstance(result, SystemAction)
        assert result.approvals[0].granted is None

    async def test_run_agent_with_session_grant(self, adapter: PydanticAgentAdapter):
        from uuid import uuid4

        query = "test query"
        session_id = uuid4()
        adapter.approval_service.register_session_grant(
            session_id=session_id,
            grant=Grant(
                approval_type=ApprovalType.OutgoingData,
                component="web_search",
                allowed_parameters={"query": query},
            ),
        )

        context = ChatContext(
            messages=[], sensitivity_level=SensitivityLevel.OpenInformation
        )
        call_count = 0

        def model_function(
            messages: list[ModelMessage], info: AgentInfo
        ) -> ModelResponse:
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                return ModelResponse(
                    parts=[
                        ToolCallPart(
                            tool_name="web_search",
                            args={"query": query},
                            tool_call_id="call_1",
                        )
                    ]
                )
            return _final_output("Done")

        with (
            discussion_agent.override(model=FunctionModel(function=model_function)),
            patch("engine.adapters.pydantic_ai_execution.tools.DDGS") as mock_ddgs,
        ):
            mock_ddgs.return_value.text.return_value = []
            result = await adapter.run_agent_and_handle_permissions(
                context=context,
                agent=discussion_agent,
                query="search the web",
                session_id=session_id,
            )

        assert isinstance(result, AssistantMessage)
        assert result.content == "Done"

    async def test_run_agent_session_grant_not_used_without_session_id(
        self, adapter: PydanticAgentAdapter
    ):
        from uuid import uuid4

        query = "test query"
        adapter.approval_service.register_session_grant(
            session_id=uuid4(),
            grant=Grant(
                approval_type=ApprovalType.OutgoingData,
                component="web_search",
                allowed_parameters={"query": query},
            ),
        )

        context = ChatContext(
            messages=[], sensitivity_level=SensitivityLevel.OpenInformation
        )

        def model_function(
            messages: list[ModelMessage], info: AgentInfo
        ) -> ModelResponse:
            return ModelResponse(
                parts=[
                    ToolCallPart(
                        tool_name="web_search",
                        args={"query": query},
                        tool_call_id="call_1",
                    )
                ]
            )

        with discussion_agent.override(model=FunctionModel(function=model_function)):
            result = await adapter.run_agent_and_handle_permissions(
                context=context,
                agent=discussion_agent,
                query="search the web",
                # no session_id
            )

        assert isinstance(result, SystemAction)
        assert len(result.approvals) == 1

    async def test_run_agent_max_iterations_returns_notification(
        self, adapter: PydanticAgentAdapter
    ):
        query = "test query"
        adapter.approval_service.register_global_grant(
            Grant(
                approval_type=ApprovalType.OutgoingData,
                component="web_search",
                allowed_parameters={"query": query},
            )
        )

        context = ChatContext(
            messages=[], sensitivity_level=SensitivityLevel.OpenInformation
        )
        call_count = 0

        def model_function(
            messages: list[ModelMessage], info: AgentInfo
        ) -> ModelResponse:
            nonlocal call_count
            call_count += 1
            return ModelResponse(
                parts=[
                    ToolCallPart(
                        tool_name="web_search",
                        args={"query": query},
                        tool_call_id=f"call_{call_count}",
                    )
                ]
            )

        with (
            discussion_agent.override(model=FunctionModel(function=model_function)),
            patch("engine.adapters.pydantic_ai_execution.tools.DDGS") as mock_ddgs,
        ):
            mock_ddgs.return_value.text.return_value = []
            result = await adapter.run_agent_and_handle_permissions(
                context=context,
                agent=discussion_agent,
                query="search forever",
            )

        assert isinstance(result, SystemAction)
        assert result.notification == "Request cancelled. Maximum iterations reached"
        assert call_count == 10

    async def test_query_dropped_when_context_has_pending_approval_cycle(
        self, adapter: PydanticAgentAdapter
    ):
        """When a user sends a new message while an approval cycle is active,
        the query must be dropped — pydantic_ai rejects a user_prompt when the
        history contains unprocessed tool calls."""
        context = ChatContext(
            messages=[
                UserMessage(content="What's the weather?"),
                SystemAction(
                    approvals=[
                        Approval(
                            type=ApprovalType.OutgoingData,
                            component="web_search",
                            internal_parameters={"tool_call_id": "call_123"},
                            purpose="Weather search",
                            granted=None,
                        )
                    ]
                ),
            ],
            sensitivity_level=SensitivityLevel.OpenInformation,
        )

        # The approval is still pending (granted=None) with no matching grant,
        # so it should be re-asked without crashing.
        result = await adapter.run_agent_and_handle_permissions(
            context=context,
            agent=discussion_agent,
            query="Also check tomorrow",  # new user prompt that must be dropped
        )

        assert isinstance(result, SystemAction)
        assert len(result.approvals) == 1


class TestProviderUnavailableHandling:
    """The adapter maps provider transport failures to ProviderUnavailable so
    higher layers don't depend on pydantic_ai/openai exception types."""

    def _raising_model(self, exc: Exception) -> FunctionModel:
        def model_function(
            messages: list[ModelMessage], info: AgentInfo
        ) -> ModelResponse:
            raise exc

        return FunctionModel(model_function)

    async def test_run_basic_query_raises_on_connection_error(
        self, adapter: PydanticAgentAdapter
    ):
        model = self._raising_model(
            ModelAPIError(model_name="olmo-3", message="Connection error.")
        )
        with discussion_agent.override(model=model):
            with pytest.raises(ProviderUnavailable) as exc_info:
                await adapter.run_basic_query(context=ChatContext(), query="hi")

        # The reason names the configured endpoint and the underlying cause so
        # the user can tell a misconfigured/offline provider from a real bug.
        reason = exc_info.value.reason
        assert "11434" in reason  # default PROVIDER_API_BASE host:port
        assert "Connection error" in reason
        # The provider message is embedded in parentheses; a trailing period
        # from the provider must not leave a stray ".)" inside the brackets.
        assert ".)" not in reason

    async def test_run_basic_query_raises_on_http_5xx(
        self, adapter: PydanticAgentAdapter
    ):
        model = self._raising_model(
            ModelHTTPError(status_code=503, model_name="olmo-3", body="loading model")
        )
        with discussion_agent.override(model=model):
            with pytest.raises(ProviderUnavailable) as exc_info:
                await adapter.run_basic_query(context=ChatContext(), query="hi")

        reason = exc_info.value.reason
        assert "503" in reason
        assert "loading model" in reason  # provider's own body is surfaced

    async def test_run_basic_query_passes_through_http_4xx(
        self, adapter: PydanticAgentAdapter
    ):
        """A 4xx is a client/config error, not provider unavailability."""
        model = self._raising_model(
            ModelHTTPError(status_code=404, model_name="olmo-3", body="no such model")
        )
        with discussion_agent.override(model=model):
            with pytest.raises(ModelHTTPError):
                await adapter.run_basic_query(context=ChatContext(), query="hi")

    async def test_generate_title_raises_on_connection_error(
        self, adapter: PydanticAgentAdapter
    ):
        model = self._raising_model(
            ModelAPIError(model_name="olmo-3", message="Connection error.")
        )
        with title_summarizer_agent.override(model=model):
            with pytest.raises(ProviderUnavailable):
                await adapter.generate_title(query="some question")
