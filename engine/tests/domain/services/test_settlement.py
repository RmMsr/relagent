import asyncio
from uuid import UUID, uuid4

import pytest

from engine.adapters.test_adapters import (
    MemoryEventStoreAdapter,
    MemoryPersistence,
    StubAgentExecution,
)
from engine.domain.exceptions import (
    ChatContextNotFound,
    NoInFlightCycleToStop,
    SessionInFlightTimeout,
)
from engine.domain.models import (
    Approval,
    AssistantMessage,
    ChatContext,
    ChatRequest,
    SessionInfo,
    SystemAction,
    UserMessage,
)
from engine.domain.ports.events import SessionMessagesAppendedEvent
from engine.domain.ports.persistence import Persistence
from engine.domain.services import ChatService
from engine.domain.types import ApprovalType, SensitivityLevel


def _approval(granted: bool | None = None) -> Approval:
    return Approval(
        type=ApprovalType.OutgoingData,
        component="web_search",
        purpose="Searching the web",
        sensitivity=SensitivityLevel.OpenInformation,
        granted=granted,
    )


def _persist_context(persistence: Persistence, messages: list) -> UUID:
    session = SessionInfo()
    persistence.save_session(session)
    persistence.save_context(session.session_id, ChatContext(messages=messages))
    return session.session_id


class TestSettleCycle:
    def test_simple_user_to_assistant_cycle(
        self, chat_service: ChatService, persistence: Persistence
    ):
        session = SessionInfo()
        persistence.save_session(session)
        echo: StubAgentExecution = chat_service.agent_execution  # type: ignore[assignment]
        echo.prime_basic_query(AssistantMessage(content="Hi"))

        asyncio.run(
            chat_service.perform_user_input(
                ChatRequest(
                    session_id=session.session_id,
                    messages=[UserMessage(content="Hello")],
                )
            )
        )

        loaded = persistence.load_context(session.session_id)
        assert isinstance(loaded.messages[0], UserMessage)
        assert loaded.messages[0].final is True
        assert isinstance(loaded.messages[1], AssistantMessage)
        assert loaded.messages[1].final is True

    def test_cycle_with_one_system_action(
        self, chat_service: ChatService, persistence: Persistence
    ):
        approval = _approval(granted=True)
        session_id = _persist_context(
            persistence,
            [
                UserMessage(content="search", final=False),
                SystemAction(approvals=[approval], final=False),
            ],
        )
        echo: StubAgentExecution = chat_service.agent_execution  # type: ignore[assignment]
        echo.prime_basic_query(AssistantMessage(content="found it"))

        asyncio.run(chat_service.continue_session(session_id=session_id))

        loaded = persistence.load_context(session_id)
        assert all(m.final for m in loaded.messages)
        assert isinstance(loaded.messages[-1], AssistantMessage)

    def test_cycle_with_multiple_system_actions(
        self, chat_service: ChatService, persistence: Persistence
    ):
        session_id = _persist_context(
            persistence,
            [
                UserMessage(content="do it", final=False),
                SystemAction(approvals=[_approval(granted=True)], final=False),
                SystemAction(approvals=[_approval(granted=True)], final=False),
            ],
        )
        echo: StubAgentExecution = chat_service.agent_execution  # type: ignore[assignment]
        echo.prime_basic_query(AssistantMessage(content="done"))

        asyncio.run(chat_service.continue_session(session_id=session_id))

        loaded = persistence.load_context(session_id)
        assert all(m.final for m in loaded.messages)

    def test_settlement_does_not_touch_prior_settled_history(
        self, chat_service: ChatService, persistence: Persistence
    ):
        session_id = _persist_context(
            persistence,
            [
                UserMessage(content="old", final=True),
                AssistantMessage(content="old reply"),
                UserMessage(content="new", final=False),
            ],
        )
        echo: StubAgentExecution = chat_service.agent_execution  # type: ignore[assignment]
        echo.prime_basic_query(AssistantMessage(content="new reply"))

        asyncio.run(chat_service.continue_session(session_id=session_id))

        loaded = persistence.load_context(session_id)
        assert all(m.final for m in loaded.messages)
        assert loaded.messages[0].content == "old"
        assert loaded.messages[2].content == "new"


class TestStopCycle:
    def test_declines_undecided_approvals(
        self, chat_service: ChatService, persistence: Persistence
    ):
        a1 = _approval(granted=None)
        a2 = _approval(granted=None)
        session_id = _persist_context(
            persistence,
            [
                UserMessage(content="hi", final=False),
                SystemAction(approvals=[a1, a2], final=False),
            ],
        )

        chat_service.stop_cycle(session_id)

        loaded = persistence.load_context(session_id)
        assert isinstance(loaded.messages[1], SystemAction)
        assert loaded.messages[1].approvals[0].granted is False
        assert loaded.messages[1].approvals[1].granted is False
        assert loaded.messages[1].final is True
        assert loaded.messages[0].final is True

    def test_preserves_already_decided_approvals(
        self, chat_service: ChatService, persistence: Persistence
    ):
        granted = _approval(granted=True)
        undecided = _approval(granted=None)
        session_id = _persist_context(
            persistence,
            [
                UserMessage(content="hi", final=False),
                SystemAction(approvals=[granted, undecided], final=False),
            ],
        )

        chat_service.stop_cycle(session_id)

        loaded = persistence.load_context(session_id)
        assert isinstance(loaded.messages[1], SystemAction)
        assert loaded.messages[1].approvals[0].granted is True
        assert loaded.messages[1].approvals[1].granted is False

    def test_all_decided_marks_final_without_changing_decisions(
        self, chat_service: ChatService, persistence: Persistence
    ):
        session_id = _persist_context(
            persistence,
            [
                UserMessage(content="hi", final=False),
                SystemAction(
                    approvals=[_approval(granted=True), _approval(granted=False)],
                    final=False,
                ),
            ],
        )

        chat_service.stop_cycle(session_id)

        loaded = persistence.load_context(session_id)
        assert isinstance(loaded.messages[1], SystemAction)
        assert loaded.messages[1].approvals[0].granted is True
        assert loaded.messages[1].approvals[1].granted is False
        assert all(m.final for m in loaded.messages)

    def test_no_in_flight_raises(
        self, chat_service: ChatService, persistence: Persistence
    ):
        session_id = _persist_context(
            persistence,
            [
                UserMessage(content="done", final=True),
                AssistantMessage(content="reply"),
            ],
        )

        with pytest.raises(NoInFlightCycleToStop) as exc:
            chat_service.stop_cycle(session_id)
        assert exc.value.session_id == session_id

    def test_missing_session_raises_context_not_found(
        self, chat_service: ChatService
    ):
        with pytest.raises(ChatContextNotFound):
            chat_service.stop_cycle(uuid4())

    def test_does_not_append_new_record(
        self, chat_service: ChatService, persistence: Persistence
    ):
        session_id = _persist_context(
            persistence,
            [
                UserMessage(content="hi", final=False),
                SystemAction(approvals=[_approval(granted=None)], final=False),
            ],
        )
        before_count = len(persistence.load_context(session_id).messages)

        chat_service.stop_cycle(session_id)

        after_count = len(persistence.load_context(session_id).messages)
        assert after_count == before_count


class TestWaitForSettled:
    def test_already_settled_returns_immediately(
        self, chat_service: ChatService, persistence: Persistence
    ):
        session_id = _persist_context(
            persistence,
            [
                UserMessage(content="hi", final=True),
                AssistantMessage(content="reply"),
            ],
        )

        asyncio.run(
            chat_service.wait_for_settled(
                session_id=session_id, poll_interval=0.001, timeout=1.0
            )
        )

    def test_missing_context_returns_immediately(self, chat_service: ChatService):
        asyncio.run(
            chat_service.wait_for_settled(
                session_id=uuid4(), poll_interval=0.001, timeout=1.0
            )
        )

    def test_in_flight_then_settles(
        self, chat_service: ChatService, persistence: Persistence
    ):
        session_id = _persist_context(
            persistence, [UserMessage(content="hi", final=False)]
        )

        async def settle_after_delay() -> None:
            await asyncio.sleep(0.05)
            ctx = persistence.load_context(session_id)
            ctx.messages[-1].final = True
            persistence.save_context(session_id, ctx)

        async def run() -> None:
            await asyncio.gather(
                chat_service.wait_for_settled(
                    session_id=session_id, poll_interval=0.01, timeout=1.0
                ),
                settle_after_delay(),
            )

        asyncio.run(run())

    def test_timeout_raises_with_trailing_id(
        self, chat_service: ChatService, persistence: Persistence
    ):
        session_id = _persist_context(
            persistence, [UserMessage(content="hi", final=False)]
        )

        with pytest.raises(SessionInFlightTimeout) as exc:
            asyncio.run(
                chat_service.wait_for_settled(
                    session_id=session_id, poll_interval=0.01, timeout=0.05
                )
            )
        assert exc.value.session_id == session_id

    def test_perform_user_input_waits_for_existing_cycle(
        self,
        chat_service: ChatService,
        persistence: Persistence,
        monkeypatch: pytest.MonkeyPatch,
    ):
        monkeypatch.setenv("ENGINE_IN_FLIGHT_TIMEOUT_SECONDS", "0")
        monkeypatch.setenv("ENGINE_IN_FLIGHT_POLL_INTERVAL_MS", "1")
        session_id = _persist_context(
            persistence, [UserMessage(content="prev", final=False)]
        )

        with pytest.raises(SessionInFlightTimeout):
            asyncio.run(
                chat_service.perform_user_input(
                    ChatRequest(
                        session_id=session_id,
                        messages=[UserMessage(content="new")],
                    )
                )
            )


class TestLoadCountOptimization:
    def test_perform_user_input_loads_context_once_when_settled(
        self,
        chat_service: ChatService,
        persistence: Persistence,
    ):
        session = SessionInfo()
        persistence.save_session(session)
        persistence.save_context(
            session.session_id,
            ChatContext(
                messages=[
                    UserMessage(content="prev", final=True),
                    AssistantMessage(content="reply"),
                ]
            ),
        )

        load_count = 0
        original = persistence.load_context

        def counting_load(session_id):
            nonlocal load_count
            load_count += 1
            return original(session_id=session_id)

        persistence.load_context = counting_load  # type: ignore[method-assign]

        echo: StubAgentExecution = chat_service.agent_execution  # type: ignore[assignment]
        echo.prime_basic_query(AssistantMessage(content="next reply"))

        asyncio.run(
            chat_service.perform_user_input(
                ChatRequest(
                    session_id=session.session_id,
                    messages=[UserMessage(content="hi again")],
                )
            )
        )

        assert load_count == 1


class TestCycleStartPublish:
    def test_perform_user_input_publishes_messages_appended_event(
        self,
        chat_service: ChatService,
        event_store: MemoryEventStoreAdapter,
    ):
        echo: StubAgentExecution = chat_service.agent_execution  # type: ignore[assignment]
        echo.prime_basic_query(AssistantMessage(content="reply"))

        asyncio.run(
            chat_service.perform_user_input(
                ChatRequest(messages=[UserMessage(content="hi")])
            )
        )

        appended = [
            e for e in event_store.events if isinstance(e, SessionMessagesAppendedEvent)
        ]
        assert len(appended) == 1

    def test_continue_session_settle_publishes_messages_appended_event(
        self,
        chat_service: ChatService,
        persistence: Persistence,
        event_store: MemoryEventStoreAdapter,
    ):
        session = SessionInfo()
        persistence.save_session(session)
        persistence.save_context(
            session.session_id,
            ChatContext(
                messages=[
                    UserMessage(content="hi", final=False),
                    SystemAction(approvals=[_approval(granted=True)], final=False),
                ]
            ),
        )
        echo: StubAgentExecution = chat_service.agent_execution  # type: ignore[assignment]
        echo.prime_basic_query(AssistantMessage(content="done"))
        event_store.events.clear()

        asyncio.run(chat_service.continue_session(session_id=session.session_id))

        appended = [
            e for e in event_store.events if isinstance(e, SessionMessagesAppendedEvent)
        ]
        assert len(appended) == 1

    def test_continue_session_appending_system_action_publishes_messages_appended_event(
        self,
        chat_service: ChatService,
        persistence: Persistence,
        event_store: MemoryEventStoreAdapter,
    ):
        session = SessionInfo()
        persistence.save_session(session)
        persistence.save_context(
            session.session_id,
            ChatContext(
                messages=[
                    UserMessage(content="hi", final=False),
                    SystemAction(approvals=[_approval(granted=True)], final=False),
                ]
            ),
        )
        echo: StubAgentExecution = chat_service.agent_execution  # type: ignore[assignment]
        echo.prime_basic_query(SystemAction(approvals=[_approval(granted=None)]))
        event_store.events.clear()

        asyncio.run(chat_service.continue_session(session_id=session.session_id))

        appended = [
            e for e in event_store.events if isinstance(e, SessionMessagesAppendedEvent)
        ]
        assert len(appended) == 1

    def test_stop_cycle_publishes_messages_appended_event(
        self,
        chat_service: ChatService,
        persistence: Persistence,
        event_store: MemoryEventStoreAdapter,
    ):
        session_id = _persist_context(
            persistence,
            [
                UserMessage(content="hi", final=False),
                SystemAction(approvals=[_approval(granted=None)], final=False),
            ],
        )
        event_store.events.clear()

        chat_service.stop_cycle(session_id)

        appended = [
            e for e in event_store.events if isinstance(e, SessionMessagesAppendedEvent)
        ]
        assert len(appended) == 1


