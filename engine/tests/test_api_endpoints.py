from typing import Generator
import uuid
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from engine.adapters.test_adapters import EchoAgentExecution
from engine.api.v1 import api_router, dependency_chat_service
from engine.domain.exceptions import ChatContextNotFound, SessionNotFound
from engine.domain.models import (
    AgentStats,
    AssistantMessage,
    ChatResponse,
    MessagesResponse,
    SessionInfo,
    UserMessage,
)
from engine.domain.ports.persistence import Persistence
from engine.domain.services import ChatService

from .utils import assert_required_authentication


@pytest.fixture
def mock_chat_service() -> MagicMock:
    service = MagicMock(spec=ChatService)
    return service


@pytest.fixture
def app_with_service_mock(
    mock_chat_service: MagicMock,
) -> Generator[FastAPI, None, None]:
    test_app = FastAPI()
    test_app.include_router(api_router, prefix="/api/v1")
    test_app.dependency_overrides[dependency_chat_service] = lambda: mock_chat_service
    with patch("engine.api.helpers.SECRET_ACCESS_KEY", "test_api_key"):
        yield test_app


@pytest.fixture
def client_with_service_mock(app_with_service_mock: FastAPI) -> TestClient:
    return TestClient(
        app_with_service_mock,
        raise_server_exceptions=True,
        headers={"X-API-Key": "test_api_key"},
    )


@pytest.fixture
def app(persistence: Persistence) -> Generator[FastAPI, None, None]:
    test_app = FastAPI()
    test_app.include_router(api_router, prefix="/api/v1")
    chat_service = ChatService(
        persistence_repository=persistence,
        agent_execution=EchoAgentExecution(),
    )
    test_app.dependency_overrides[dependency_chat_service] = lambda: chat_service
    with patch("engine.api.helpers.SECRET_ACCESS_KEY", "test_api_key"):
        yield test_app


@pytest.fixture
def client(app: FastAPI) -> TestClient:
    return TestClient(
        app,
        raise_server_exceptions=True,
        headers={"X-API-Key": "test_api_key"},
    )


class TestPostMessages:
    def test_requires_authentication(self, app: FastAPI):
        assert_required_authentication(
            TestClient(app),
            method="post",
            endpoint="/api/v1/messages",
            payload={"messages": [{"role": "user", "content": "Hello"}]},
        )

    def test_valid_chat_request(
        self,
        client_with_service_mock: TestClient,
        mock_chat_service: MagicMock,
    ):
        session_id = uuid.uuid4()
        mock_chat_service.perform_user_input = AsyncMock(
            return_value=ChatResponse(
                session_id=session_id,
                message=AssistantMessage(content="Hello, it is 9:55"),
            )
        )

        response = client_with_service_mock.post(
            "/api/v1/messages",
            json={
                "session_id": str(session_id),
                "messages": [
                    {"role": "user", "content": "Hello"},
                    {"role": "user", "content": "What time is it?"},
                ],
            },
        )

        assert response.status_code == 200
        data = response.json()
        assert data["session_id"] == str(session_id)
        assert data["message"]["role"] == "assistant"
        assert data["message"]["content"] == "Hello, it is 9:55"

    def test_response_includes_agent_stats(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        stats = AgentStats(input_tokens=250, output_tokens=125)
        mock_chat_service.perform_user_input = AsyncMock(
            return_value=ChatResponse(
                session_id=session_id,
                message=AssistantMessage(
                    content="Response",
                    stats=stats,
                    timestamp=datetime(2025, 10, 14, 9, 55),
                ),
            )
        )

        response = client_with_service_mock.post(
            "/api/v1/messages",
            json={"messages": [{"role": "user", "content": "Hello"}]},
        )

        assert response.status_code == 200
        assert response.json() == {
            "session_id": str(session_id),
            "message": {
                "sequence_id": None,
                "role": "assistant",
                "content": "Response",
                "stats": {
                    "agent_name": None,
                    "answering_model_name": None,
                    "duration_seconds": None,
                    "input_tokens": 250,
                    "output_tokens": 125,
                    "requests_count": None,
                    "tool_calls_count": None,
                },
                "timestamp": "2025-10-14T09:55:00",
            },
        }

    def test_valid_chat_request_without_session_id(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        mock_chat_service.perform_user_input = AsyncMock(
            return_value=ChatResponse(
                session_id=session_id,
                message=AssistantMessage(content="Response"),
            )
        )

        response = client_with_service_mock.post(
            "/api/v1/messages",
            json={"messages": [{"role": "user", "content": "Hello"}]},
        )

        assert response.status_code == 200
        data = response.json()
        assert "session_id" in data

    def test_invalid_body_missing_content(self, client_with_service_mock: TestClient):
        response = client_with_service_mock.post(
            "/api/v1/messages",
            json={"messages": [{"role": "user"}]},
        )

        assert response.status_code == 422

    def test_invalid_session_id(self, client_with_service_mock: TestClient):
        response = client_with_service_mock.post(
            "/api/v1/messages",
            json={
                "session_id": "123456",
                "messages": [{"role": "user", "content": "Hello"}],
            },
        )

        assert response.status_code == 422

    def test_invalid_json_body(self, client_with_service_mock: TestClient):
        response = client_with_service_mock.post(
            "/api/v1/messages",
            content="not valid json",
            headers={"Content-Type": "application/json"},
        )

        assert response.status_code == 422


class TestGetMessages:
    def test_requires_authentication(
        self,
        app: FastAPI,
        persisted_session_with_context: SessionInfo,
    ):
        assert_required_authentication(
            TestClient(app),
            method="get",
            endpoint=f"/api/v1/messages/{persisted_session_with_context.session_id}",
        )

    def test_valid_session(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        mock_chat_service.get_messages.return_value = MessagesResponse(
            session_id=session_id,
            messages=[
                UserMessage(content="Hello", timestamp=datetime(2025, 10, 14, 9, 55)),
                AssistantMessage(
                    content="Hi!", timestamp=datetime(2025, 10, 14, 9, 57)
                ),
            ],
        )

        response = client_with_service_mock.get(f"/api/v1/messages/{session_id}")

        assert response.status_code == 200
        assert response.json() == {
            "session_id": str(session_id),
            "messages": [
                {
                    "sequence_id": None,
                    "role": "user",
                    "content": "Hello",
                    "timestamp": "2025-10-14T09:55:00",
                },
                {
                    "sequence_id": None,
                    "role": "assistant",
                    "content": "Hi!",
                    "stats": None,
                    "timestamp": "2025-10-14T09:57:00",
                },
            ],
        }

    def test_invalid_uuid_format(self, client_with_service_mock: TestClient):
        response = client_with_service_mock.get("/api/v1/messages/not-a-valid-uuid")

        assert response.status_code == 422

    def test_non_existent_session(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        mock_chat_service.get_messages.side_effect = ChatContextNotFound(
            session_id=session_id
        )

        response = client_with_service_mock.get(f"/api/v1/messages/{session_id}")

        assert response.status_code == 404
        assert response.json() == {"detail": "Session not found"}

    def test_from_id_parameter_passed_to_service(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        mock_chat_service.get_messages.return_value = MessagesResponse(
            session_id=session_id,
            messages=[
                UserMessage(sequence_id=5, content="After"),
                AssistantMessage(sequence_id=6, content="Response"),
            ],
        )

        response = client_with_service_mock.get(
            f"/api/v1/messages/{session_id}?from_id=5"
        )

        assert response.status_code == 200
        mock_chat_service.get_messages.assert_called_once_with(
            session_id=session_id, from_id=5
        )

    def test_from_id_filters_response_messages(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        mock_chat_service.get_messages.return_value = MessagesResponse(
            session_id=session_id,
            messages=[
                UserMessage(sequence_id=5, content="Message 5"),
            ],
        )

        response = client_with_service_mock.get(
            f"/api/v1/messages/{session_id}?from_id=5"
        )

        assert response.status_code == 200
        messages = response.json()["messages"]
        assert len(messages) == 1
        assert messages[0]["sequence_id"] == 5
        assert messages[0]["content"] == "Message 5"


class TestGetStatus:
    def test_requires_authentication(self, app: FastAPI):
        assert_required_authentication(
            TestClient(app),
            method="get",
            endpoint="/api/v1/status",
        )

    def test_returns_status(self, client: TestClient):
        response = client.get("/api/v1/status")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert "service_name" in data
        assert "version" in data


class TestListSessions:
    def test_requires_authentication(self, app: FastAPI):
        assert_required_authentication(
            TestClient(app),
            method="get",
            endpoint="/api/v1/sessions",
        )

    def test_empty_list(self, client: TestClient):
        response = client.get("/api/v1/sessions")

        assert response.status_code == 200
        assert response.json() == []

    def test_returns_sessions(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session = SessionInfo(
            session_id=uuid.uuid4(),
            title="Test",
            created_at=datetime(2025, 1, 1, 12, 0),
            updated_at=datetime(2025, 1, 1, 12, 0),
        )
        mock_chat_service.list_recent_sessions.return_value = [session]

        response = client_with_service_mock.get("/api/v1/sessions")

        assert response.status_code == 200
        data = response.json()
        assert len(data) == 1
        assert data[0]["session_id"] == str(session.session_id)
        assert data[0]["title"] == "Test"

    def test_limit_parameter(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        mock_chat_service.list_recent_sessions.return_value = []

        client_with_service_mock.get("/api/v1/sessions?limit=5")

        mock_chat_service.list_recent_sessions.assert_called_once_with(limit=5)


class TestGetSession:
    def test_requires_authentication(
        self,
        app: FastAPI,
        persisted_session_with_context: SessionInfo,
    ):
        assert_required_authentication(
            TestClient(app),
            method="get",
            endpoint=f"/api/v1/sessions/{persisted_session_with_context.session_id}",
        )

    def test_returns_session(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session = SessionInfo(
            session_id=uuid.uuid4(),
            title="My Session",
            created_at=datetime(2025, 1, 1, 12, 0),
            updated_at=datetime(2025, 1, 1, 12, 5),
        )
        mock_chat_service.get_session.return_value = session

        response = client_with_service_mock.get(
            f"/api/v1/sessions/{session.session_id}"
        )

        assert response.status_code == 200
        data = response.json()
        assert data["session_id"] == str(session.session_id)
        assert data["title"] == "My Session"

    def test_non_existent_session(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        mock_chat_service.get_session.side_effect = SessionNotFound(
            session_id=session_id
        )

        response = client_with_service_mock.get(f"/api/v1/sessions/{session_id}")

        assert response.status_code == 404
        assert response.json() == {"detail": "Session not found"}

    def test_invalid_uuid_format(self, client_with_service_mock: TestClient):
        response = client_with_service_mock.get("/api/v1/sessions/not-a-valid-uuid")

        assert response.status_code == 422


class TestDeleteSession:
    def test_requires_authentication(
        self,
        app: FastAPI,
        persisted_session_with_context: SessionInfo,
    ):
        assert_required_authentication(
            TestClient(app),
            method="delete",
            endpoint=f"/api/v1/sessions/{persisted_session_with_context.session_id}",
        )

    def test_deletes_session(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        mock_chat_service.delete_session.return_value = None

        response = client_with_service_mock.delete(
            f"/api/v1/sessions/{session_id}"
        )

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "deleted"
        assert data["session_id"] == str(session_id)
        mock_chat_service.delete_session.assert_called_once_with(
            session_id=session_id
        )

    def test_non_existent_session(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        mock_chat_service.delete_session.side_effect = SessionNotFound(
            session_id=session_id
        )

        response = client_with_service_mock.delete(f"/api/v1/sessions/{session_id}")

        assert response.status_code == 404
        assert response.json() == {"detail": "Session not found"}

    def test_invalid_uuid_format(self, client_with_service_mock: TestClient):
        response = client_with_service_mock.delete(
            "/api/v1/sessions/not-a-valid-uuid"
        )

        assert response.status_code == 422
