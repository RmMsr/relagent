from typing import Generator
import uuid
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from engine.adapters.test_adapters import StubAgentExecution
from engine.api.v1 import (
    api_router,
    dependency_approval_service,
    dependency_chat_service,
)
from engine.domain.exceptions import ChatContextNotFound, SessionNotFound
from engine.domain.models import (
    AgentStats,
    AssistantMessage,
    ChatResponse,
    Grant,
    MessagesResponse,
    SessionInfo,
    UserMessage,
)
from engine.domain.ports.persistence import Persistence
from engine.domain.services import ApprovalService, ChatService
from engine.domain.types import ApprovalType, SensitivityLevel

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
        agent_execution=StubAgentExecution(),
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


@pytest.fixture
def mock_approval_service() -> MagicMock:
    return MagicMock(spec=ApprovalService)


@pytest.fixture
def app_with_approval_mock(
    mock_approval_service: MagicMock,
) -> Generator[FastAPI, None, None]:
    test_app = FastAPI()
    test_app.include_router(api_router, prefix="/api/v1")
    test_app.dependency_overrides[dependency_approval_service] = lambda: (
        mock_approval_service
    )
    with patch("engine.api.helpers.SECRET_ACCESS_KEY", "test_api_key"):
        yield test_app


@pytest.fixture
def client_with_approval_mock(app_with_approval_mock: FastAPI) -> TestClient:
    return TestClient(
        app_with_approval_mock,
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
                sensitivity_level=SensitivityLevel.Personal,
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
                sensitivity_level=SensitivityLevel.Personal,
            )
        )

        response = client_with_service_mock.post(
            "/api/v1/messages",
            json={"messages": [{"role": "user", "content": "Hello"}]},
        )

        assert response.status_code == 200
        assert response.json() == {
            "session_id": str(session_id),
            "sensitivity_level": SensitivityLevel.Personal.value,
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
                sensitivity_level=SensitivityLevel.Personal,
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

        response = client_with_service_mock.delete(f"/api/v1/sessions/{session_id}")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "deleted"
        assert data["session_id"] == str(session_id)
        mock_chat_service.delete_session.assert_called_once_with(session_id=session_id)

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
        response = client_with_service_mock.delete("/api/v1/sessions/not-a-valid-uuid")

        assert response.status_code == 422


class TestGetGlobalGrants:
    def test_requires_authentication(self, app_with_approval_mock: FastAPI):
        assert_required_authentication(
            TestClient(app_with_approval_mock),
            method="get",
            endpoint="/api/v1/grants",
        )

    def test_returns_empty_list(
        self, client_with_approval_mock: TestClient, mock_approval_service: MagicMock
    ):
        mock_approval_service.active_global_grants.return_value = []

        response = client_with_approval_mock.get("/api/v1/grants")

        assert response.status_code == 200
        assert response.json() == []

    def test_returns_grants(
        self, client_with_approval_mock: TestClient, mock_approval_service: MagicMock
    ):
        mock_approval_service.active_global_grants.return_value = [
            Grant(
                approval_type=ApprovalType.OutgoingData,
                component="web_search",
                max_sensitivity=SensitivityLevel.OpenInformation,
            )
        ]

        response = client_with_approval_mock.get("/api/v1/grants")

        assert response.status_code == 200
        data = response.json()
        assert len(data) == 1
        assert data[0]["component"] == "web_search"
        assert data[0]["approval_type"] == ApprovalType.OutgoingData.value


class TestCreateGrant:
    def test_requires_authentication(self, app_with_approval_mock: FastAPI):
        assert_required_authentication(
            TestClient(app_with_approval_mock),
            method="post",
            endpoint="/api/v1/grants",
            payload={"approval_type": "data/out", "component": "web_search"},
        )

    def test_creates_grant(
        self, client_with_approval_mock: TestClient, mock_approval_service: MagicMock
    ):
        response = client_with_approval_mock.post(
            "/api/v1/grants",
            json={"approval_type": "data/out", "component": "web_search"},
        )

        assert response.status_code == 200
        assert response.json() == {"status": "created"}

    def test_delegates_to_approval_service(
        self, client_with_approval_mock: TestClient, mock_approval_service: MagicMock
    ):
        client_with_approval_mock.post(
            "/api/v1/grants",
            json={"approval_type": "data/out", "component": "web_search"},
        )

        mock_approval_service.register_global_grant.assert_called_once()
        grant = mock_approval_service.register_global_grant.call_args.kwargs["grant"]
        assert grant.component == "web_search"
        assert grant.approval_type == ApprovalType.OutgoingData

    def test_invalid_body(self, client_with_approval_mock: TestClient):
        response = client_with_approval_mock.post(
            "/api/v1/grants",
            json={"approval_type": "not-a-valid-type"},
        )

        assert response.status_code == 422


class TestCreateSessionGrant:
    def test_requires_authentication(self, app_with_approval_mock: FastAPI):
        session_id = uuid.uuid4()
        assert_required_authentication(
            TestClient(app_with_approval_mock),
            method="post",
            endpoint=f"/api/v1/sessions/{session_id}/grants",
            payload={"approval_type": "data/out", "component": "web_search"},
        )

    def test_creates_grant(
        self, client_with_approval_mock: TestClient, mock_approval_service: MagicMock
    ):
        session_id = uuid.uuid4()
        response = client_with_approval_mock.post(
            f"/api/v1/sessions/{session_id}/grants",
            json={"approval_type": "data/out", "component": "web_search"},
        )

        assert response.status_code == 200
        assert response.json() == {"status": "created"}

    def test_delegates_to_approval_service(
        self, client_with_approval_mock: TestClient, mock_approval_service: MagicMock
    ):
        session_id = uuid.uuid4()
        client_with_approval_mock.post(
            f"/api/v1/sessions/{session_id}/grants",
            json={"approval_type": "data/out", "component": "web_search"},
        )

        mock_approval_service.register_session_grant.assert_called_once()
        call_kwargs = mock_approval_service.register_session_grant.call_args.kwargs
        assert call_kwargs["session_id"] == session_id
        assert call_kwargs["grant"].component == "web_search"
        assert call_kwargs["grant"].approval_type == ApprovalType.OutgoingData

    def test_invalid_uuid_format(self, client_with_approval_mock: TestClient):
        response = client_with_approval_mock.post(
            "/api/v1/sessions/not-a-valid-uuid/grants",
            json={"approval_type": "data/out", "component": "web_search"},
        )

        assert response.status_code == 422

    def test_invalid_body(self, client_with_approval_mock: TestClient):
        session_id = uuid.uuid4()
        response = client_with_approval_mock.post(
            f"/api/v1/sessions/{session_id}/grants",
            json={"approval_type": "not-a-valid-type"},
        )

        assert response.status_code == 422


class TestGetSessionGrants:
    def test_requires_authentication(self, app_with_approval_mock: FastAPI):
        session_id = uuid.uuid4()
        assert_required_authentication(
            TestClient(app_with_approval_mock),
            method="get",
            endpoint=f"/api/v1/sessions/{session_id}/grants",
        )

    def test_returns_grants_for_session(
        self, client_with_approval_mock: TestClient, mock_approval_service: MagicMock
    ):
        session_id = uuid.uuid4()
        mock_approval_service.active_session_grants.return_value = [
            Grant(
                approval_type=ApprovalType.OutgoingData,
                component="web_search",
                max_sensitivity=SensitivityLevel.Personal,
            )
        ]

        response = client_with_approval_mock.get(
            f"/api/v1/sessions/{session_id}/grants"
        )

        assert response.status_code == 200
        data = response.json()
        assert len(data) == 1
        assert data[0]["component"] == "web_search"
        mock_approval_service.active_session_grants.assert_called_once_with(
            session_id=session_id
        )

    def test_returns_empty_list(
        self, client_with_approval_mock: TestClient, mock_approval_service: MagicMock
    ):
        mock_approval_service.active_session_grants.return_value = []

        response = client_with_approval_mock.get(
            f"/api/v1/sessions/{uuid.uuid4()}/grants"
        )

        assert response.status_code == 200
        assert response.json() == []

    def test_invalid_uuid_format(self, client_with_approval_mock: TestClient):
        response = client_with_approval_mock.get(
            "/api/v1/sessions/not-a-valid-uuid/grants"
        )

        assert response.status_code == 422


class TestSetSessionSensitivity:
    def test_requires_authentication(self, app: FastAPI):
        session_id = uuid.uuid4()
        assert_required_authentication(
            TestClient(app),
            method="put",
            endpoint=f"/api/v1/sessions/{session_id}/sensitivity",
            payload={"sensitivity_level": SensitivityLevel.Personal.value},
        )

    def test_sets_sensitivity_level(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        response = client_with_service_mock.put(
            f"/api/v1/sessions/{session_id}/sensitivity",
            json={"sensitivity_level": SensitivityLevel.Confidential.value},
        )

        assert response.status_code == 200
        assert response.json() == {"status": "updated"}

    def test_delegates_to_service(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        client_with_service_mock.put(
            f"/api/v1/sessions/{session_id}/sensitivity",
            json={"sensitivity_level": SensitivityLevel.Confidential.value},
        )

        mock_chat_service.set_sensitivity_level.assert_called_once_with(
            session_id=session_id, sensitivity_level=SensitivityLevel.Confidential
        )

    def test_invalid_sensitivity_level(self, client_with_service_mock: TestClient):
        session_id = uuid.uuid4()
        response = client_with_service_mock.put(
            f"/api/v1/sessions/{session_id}/sensitivity",
            json={"sensitivity_level": 99},
        )

        assert response.status_code == 422

    def test_invalid_uuid_format(self, client_with_service_mock: TestClient):
        response = client_with_service_mock.put(
            "/api/v1/sessions/not-a-valid-uuid/sensitivity",
            json={"sensitivity_level": SensitivityLevel.Personal.value},
        )

        assert response.status_code == 422


class TestContinueSession:
    def test_returns_chat_response(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        mock_chat_service.continue_session = AsyncMock(
            return_value=ChatResponse(
                session_id=session_id,
                message=AssistantMessage(content="Continuing with current grants"),
                sensitivity_level=SensitivityLevel.Personal,
            )
        )

        response = client_with_service_mock.post(
            f"/api/v1/sessions/{session_id}/continue"
        )

        assert response.status_code == 200
        data = response.json()
        assert data["session_id"] == str(session_id)
        assert data["message"]["content"] == "Continuing with current grants"
        assert data["sensitivity_level"] == SensitivityLevel.Personal.value

    def test_delegates_to_service(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        mock_chat_service.continue_session = AsyncMock(
            return_value=ChatResponse(
                session_id=session_id,
                message=AssistantMessage(content="Response"),
                sensitivity_level=SensitivityLevel.Personal,
            )
        )

        client_with_service_mock.post(f"/api/v1/sessions/{session_id}/continue")

        mock_chat_service.continue_session.assert_called_once_with(
            session_id=session_id
        )

    def test_session_not_found(
        self, client_with_service_mock: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        mock_chat_service.continue_session = AsyncMock(
            side_effect=SessionNotFound(session_id=session_id)
        )

        response = client_with_service_mock.post(
            f"/api/v1/sessions/{session_id}/continue"
        )

        assert response.status_code == 404
        assert response.json()["detail"] == "Session not found"

    def test_invalid_uuid_format(self, client_with_service_mock: TestClient):
        response = client_with_service_mock.post(
            "/api/v1/sessions/not-a-valid-uuid/continue"
        )

        assert response.status_code == 422
