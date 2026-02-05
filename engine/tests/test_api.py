import uuid
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from engine.api import api_router, dependency_chat_service
from engine.domain.exceptions import ChatContextNotFound
from engine.domain.models import (
    AssistantMessage,
    ChatResponse,
    MessagesResponse,
    UserMessage,
)
from engine.domain.services import ChatService


@pytest.fixture
def mock_chat_service() -> MagicMock:
    service = MagicMock(spec=ChatService)
    return service


@pytest.fixture
def app(mock_chat_service: MagicMock) -> FastAPI:
    test_app = FastAPI()
    test_app.include_router(api_router, prefix="/api/v1")
    test_app.dependency_overrides[dependency_chat_service] = lambda: mock_chat_service
    return test_app


@pytest.fixture
def client(app: FastAPI) -> TestClient:
    return TestClient(app, raise_server_exceptions=False)


class TestPostMessages:
    def test_valid_chat_request(self, client: TestClient, mock_chat_service: MagicMock):
        session_id = uuid.uuid4()
        mock_chat_service.perform_user_input = AsyncMock(
            return_value=ChatResponse(
                session_id=session_id,
                message=AssistantMessage(content="Hello, it is 9:55"),
            )
        )

        response = client.post(
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

    def test_valid_chat_request_without_session_id(
        self, client: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        mock_chat_service.perform_user_input = AsyncMock(
            return_value=ChatResponse(
                session_id=session_id,
                message=AssistantMessage(content="Response"),
            )
        )

        response = client.post(
            "/api/v1/messages",
            json={"messages": [{"role": "user", "content": "Hello"}]},
        )

        assert response.status_code == 200
        data = response.json()
        assert "session_id" in data

    def test_invalid_body_missing_content(self, client: TestClient):
        response = client.post(
            "/api/v1/messages",
            json={"messages": [{"role": "user"}]},
        )

        assert response.status_code == 422

    def test_invalid_session_id(self, client: TestClient):
        response = client.post(
            "/api/v1/messages",
            json={
                "session_id": "123456",
                "messages": [{"role": "user", "content": "Hello"}],
            },
        )

        assert response.status_code == 422

    def test_invalid_json_body(self, client: TestClient):
        response = client.post(
            "/api/v1/messages",
            content="not valid json",
            headers={"Content-Type": "application/json"},
        )

        assert response.status_code == 422


class TestGetMessages:
    def test_valid_session(self, client: TestClient, mock_chat_service: MagicMock):
        session_id = uuid.uuid4()
        mock_chat_service.get_messages.return_value = MessagesResponse(
            session_id=session_id,
            messages=[
                UserMessage(content="Hello"),
                AssistantMessage(content="Hi!"),
            ],
        )

        response = client.get(f"/api/v1/messages/{session_id}")

        assert response.status_code == 200
        data = response.json()
        assert data["session_id"] == str(session_id)
        assert len(data["messages"]) == 2
        assert data["messages"][0]["role"] == "user"
        assert data["messages"][1]["role"] == "assistant"

    def test_invalid_uuid_format(self, client: TestClient):
        response = client.get("/api/v1/messages/not-a-valid-uuid")

        assert response.status_code == 422

    def test_non_existent_session(
        self, client: TestClient, mock_chat_service: MagicMock
    ):
        session_id = uuid.uuid4()
        mock_chat_service.get_messages.side_effect = ChatContextNotFound(
            session_id=session_id
        )

        response = client.get(f"/api/v1/messages/{session_id}")

        assert response.status_code == 404
        assert response.json()["detail"] == "Session not found"
