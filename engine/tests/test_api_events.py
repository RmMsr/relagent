"""Tests for SSE event serialization and HTTP streaming."""

import json
import uuid
from datetime import datetime
from typing import Generator
from unittest.mock import MagicMock, patch

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from engine.adapters.test_adapters import MemoryEventStoreAdapter
from engine.api.events import BaseEventConverter
from engine.api.v1 import (
    api_router,
    dependency_chat_service,
    dependency_event_store,
)
from engine.domain.ports.events import (
    SessionMessagesAppendedEvent,
    SessionUpdatedEvent,
)
from engine.domain.services import ChatService
from engine.tests.utils import assert_required_authentication


class TestEventConversion:
    """Tests for SSE event serialization."""

    @pytest.fixture
    def event_store(self) -> MemoryEventStoreAdapter:
        return MemoryEventStoreAdapter()

    def test_session_updated_event_format(self):
        session_id = uuid.UUID("151a0cfb-74bb-4978-8881-3d15e4017a5e")
        event = SessionUpdatedEvent(
            id=1, session_id=session_id, created_at=datetime(2025, 1, 1, 0, 0, 0)
        )

        converter = BaseEventConverter()
        sse = converter.convert_to_sse(event)

        assert sse.event == "session.updated"
        assert sse.id == "1"
        assert sse.data is not None
        assert json.loads(sse.data) == {
            "session_id": str(session_id),
            "created_at": "2025-01-01T00:00:00",
        }

    def test_messages_appended_event_format(self):
        session_id = uuid.UUID("151a0cfb-74bb-4978-8881-3d15e4017a5e")
        event = SessionMessagesAppendedEvent(
            id=1,
            session_id=session_id,
            created_at=datetime(2025, 1, 1, 0, 0, 0),
        )

        converter = BaseEventConverter()
        sse = converter.convert_to_sse(event)

        assert sse.event == "session.messages.appended"
        assert sse.id == "1"
        assert sse.data is not None
        assert json.loads(sse.data) == {
            "session_id": str(session_id),
            "created_at": "2025-01-01T00:00:00",
        }


class TestSSEHttpEndpoint:
    @pytest.fixture
    def event_store(self) -> MemoryEventStoreAdapter:
        return MemoryEventStoreAdapter()

    @pytest.fixture
    def mock_chat_service(self) -> MagicMock:
        return MagicMock(spec=ChatService)

    @pytest.fixture
    def app(
        self, mock_chat_service: MagicMock, event_store: MemoryEventStoreAdapter
    ) -> Generator[FastAPI, None, None]:
        test_app = FastAPI()
        test_app.include_router(api_router, prefix="/api/v1")
        test_app.dependency_overrides[dependency_chat_service] = lambda: (
            mock_chat_service
        )
        test_app.dependency_overrides[dependency_event_store] = lambda: event_store
        with patch("engine.api.helpers.SECRET_ACCESS_KEY", "test_api_key"):
            yield test_app

    @pytest.fixture
    def client(self, app: FastAPI) -> TestClient:
        return TestClient(
            app, raise_server_exceptions=False, headers={"X-API-Key": "test_api_key"}
        )

    def test_requires_authentication(self, app: FastAPI):
        assert_required_authentication(
            client=TestClient(app), endpoint="/api/v1/events", method="GET"
        )

    def test_endpoint_returns_event_stream_content_type(
        self, client: TestClient, event_store: MemoryEventStoreAdapter
    ):
        session_id = uuid.UUID("151a0cfb-74bb-4978-8881-3d15e4017a5e")
        event_store.publish(SessionUpdatedEvent(session_id=session_id))

        with client.stream("GET", "/api/v1/events") as response:
            assert response.status_code == 200
            assert "text/event-stream" in response.headers["content-type"]
            next(response.iter_lines())

    def test_endpoint_streams_existing_events(
        self, client: TestClient, event_store: MemoryEventStoreAdapter
    ):
        session_id = uuid.UUID("151a0cfb-74bb-4978-8881-3d15e4017a5e")
        event_store.publish(SessionUpdatedEvent(session_id=session_id))

        with client.stream("GET", "/api/v1/events", timeout=0.1) as response:
            lines: list[str] = []
            for line in response.iter_lines():
                lines.append(line)
                if line == "\n\n":
                    break

            assert lines.count("event: session.updated") == 1
            assert lines.count("id: 1") == 1

    def test_endpoint_respects_last_event_id_header(
        self, client: TestClient, event_store: MemoryEventStoreAdapter
    ):
        session_id = uuid.UUID("151a0cfb-74bb-4978-8881-3d15e4017a5e")
        event_store.publish(SessionUpdatedEvent(session_id=session_id))
        event_store.publish(SessionUpdatedEvent(session_id=session_id))
        event_store.publish(SessionUpdatedEvent(session_id=session_id))

        with client.stream(
            "GET", "/api/v1/events", headers={"Last-Event-ID": "2"}, timeout=0.1
        ) as response:
            lines: list[str] = []
            for line in response.iter_lines():
                lines.append(line)
                if line == "\n\n":
                    break

            assert lines.count("event: session.updated") == 1
            assert lines.count("id: 3") == 1

    def test_multiple_clients_receive_same_events(
        self, app: FastAPI, event_store: MemoryEventStoreAdapter
    ):
        session_id = uuid.UUID("151a0cfb-74bb-4978-8881-3d15e4017a5e")
        event_store.publish(SessionUpdatedEvent(session_id=session_id))

        client1 = TestClient(
            app, raise_server_exceptions=False, headers={"X-API-Key": "test_api_key"}
        )
        client2 = TestClient(
            app, raise_server_exceptions=False, headers={"X-API-Key": "test_api_key"}
        )

        def get_first_id(client: TestClient) -> str:
            with client.stream("GET", "/api/v1/events", timeout=0.1) as response:
                for line in response.iter_lines():
                    if line.startswith("id:"):
                        return line
            return ""

        assert get_first_id(client1) == "id: 1"
        assert get_first_id(client2) == "id: 1"

    def test_works_with_double_newline_data(
        self, app: FastAPI, client: TestClient, event_store: MemoryEventStoreAdapter
    ):
        session_id = uuid.UUID("151a0cfb-74bb-4978-8881-3d15e4017a5e")
        event = SessionUpdatedEvent(
            session_id=session_id, created_at=datetime(2025, 1, 1, 0, 0, 0)
        )
        event.session_id = "test\n\nid"  # type: ignore
        event_store.publish(event)

        with client.stream("GET", "/api/v1/events", timeout=0.1) as response:
            lines: list[str] = []
            for line in response.iter_lines():
                lines.append(line)
                if line == "\n\n":
                    break

            assert lines.count("event: session.updated") == 1
            assert lines.count("id: 1") == 1
            assert (
                lines.count(
                    'data: {"session_id": "test\\n\\nid", "created_at": "2025-01-01T00:00:00"}'
                )
                == 1
            )
