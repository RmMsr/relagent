"""API integration tests with deterministic agent responses.

These tests exercise the full HTTP stack — routing, serialization, persistence,
and service logic — using StubAgentExecution for reproducible scenarios.
"""

from typing import Generator
from unittest.mock import patch

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from engine.adapters.test_adapters import StubAgentExecution
from engine.api.helpers import (
    dependency_approval_service,
    dependency_chat_service,
)
from engine.api.v1 import api_router
from engine.domain.models import (
    Approval,
    AssistantMessage,
    SystemAction,
)
from engine.domain.ports.persistence import Persistence
from engine.domain.services import ApprovalService, ChatService
from engine.domain.types import ApprovalType, SensitivityLevel


@pytest.fixture
def stub(echo_agent_execution: StubAgentExecution) -> StubAgentExecution:
    return echo_agent_execution


@pytest.fixture
def app(
    persistence: Persistence,
    stub: StubAgentExecution,
) -> Generator[FastAPI, None, None]:
    approval_service = ApprovalService(persistence_repository=persistence)
    chat_service = ChatService(
        persistence_repository=persistence,
        agent_execution=stub,
        approval_service=approval_service,
    )
    test_app = FastAPI()
    test_app.include_router(api_router, prefix="/api/v1")
    test_app.dependency_overrides[dependency_chat_service] = lambda: chat_service
    test_app.dependency_overrides[dependency_approval_service] = lambda: (
        approval_service
    )
    with patch("engine.api.helpers.SECRET_ACCESS_KEY", "test_key"):
        yield test_app


@pytest.fixture
def client(app: FastAPI) -> TestClient:
    return TestClient(
        app,
        raise_server_exceptions=True,
        headers={"X-API-Key": "test_key"},
    )


class TestApprovalGrantFlow:
    """User chats, agent requests web_search approval, user grants, agent continues."""

    async def test_chat_then_approval_then_grant_then_continue(
        self,
        client: TestClient,
        stub: StubAgentExecution,
    ):
        # -- Step 1: User says hello, assistant responds --
        stub.prime_basic_query(AssistantMessage(content="Hello! How can I help you?"))

        resp = client.post(
            "/api/v1/messages",
            json={"messages": [{"role": "user", "content": "Hello"}]},
        )
        assert resp.status_code == 200
        data = resp.json()
        session_id = data["session_id"]
        assert data["message"]["role"] == "assistant"
        assert data["message"]["content"] == "Hello! How can I help you?"

        # -- Step 2: User asks about solar storms, agent needs web search --
        approval = Approval(
            type=ApprovalType.OutgoingData,
            component="web_search",
            purpose="Searching the web for 'recent solar storm activity 2026'",
            sensitivity=SensitivityLevel.OpenInformation,
            allowed_parameters={"query": "recent solar storm activity 2026"},
        )
        stub.prime_basic_query(SystemAction(approvals=[approval]))

        resp = client.post(
            "/api/v1/messages",
            json={
                "session_id": session_id,
                "messages": [
                    {
                        "role": "user",
                        "content": "Have there been any major solar storms recently?",
                    }
                ],
            },
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["message"]["role"] == "system"
        assert len(data["message"]["approvals"]) == 1
        returned_approval = data["message"]["approvals"][0]
        assert returned_approval["component"] == "web_search"

        # -- Step 3: User grants the approval --
        resp = client.post(
            f"/api/v1/sessions/{session_id}/grants",
            json={
                "approval_type": ApprovalType.OutgoingData.value,
                "component": "web_search",
                "max_sensitivity": SensitivityLevel.OpenInformation.value,
                "wildcard_parameter": "query",
            },
        )
        assert resp.status_code == 200

        # -- Step 4: Continue session, agent responds with results --
        stub.prime_basic_query(
            AssistantMessage(
                content=(
                    "Yes! A G3-class geomagnetic storm hit Earth on April 12, 2026, "
                    "causing widespread auroras at unusually low latitudes."
                )
            )
        )

        resp = client.post(f"/api/v1/sessions/{session_id}/continue")
        assert resp.status_code == 200
        data = resp.json()
        assert data["message"]["role"] == "assistant"
        assert "storm" in data["message"]["content"].lower()

        # -- Verify: messages endpoint shows full conversation --
        resp = client.get(f"/api/v1/messages/{session_id}")
        assert resp.status_code == 200
        messages = resp.json()["messages"]
        roles = [m["role"] for m in messages]
        assert roles == ["user", "assistant", "user", "system", "assistant"]


class TestApprovalRejectFlow:
    """User chats, agent requests web_search approval, user rejects, agent responds without searching."""

    async def test_chat_then_approval_then_reject_then_continue(
        self,
        client: TestClient,
        stub: StubAgentExecution,
    ):
        # -- Step 1: User says hello, assistant responds --
        stub.prime_basic_query(AssistantMessage(content="Hello! How can I help you?"))

        resp = client.post(
            "/api/v1/messages",
            json={"messages": [{"role": "user", "content": "Hello"}]},
        )
        assert resp.status_code == 200
        session_id = resp.json()["session_id"]

        # -- Step 2: User asks about solar storms, agent needs web search --
        approval = Approval(
            type=ApprovalType.OutgoingData,
            component="web_search",
            purpose="Searching the web for 'recent solar storm activity 2026'",
            sensitivity=SensitivityLevel.OpenInformation,
            allowed_parameters={"query": "recent solar storm activity 2026"},
        )
        stub.prime_basic_query(SystemAction(approvals=[approval]))

        resp = client.post(
            "/api/v1/messages",
            json={
                "session_id": session_id,
                "messages": [
                    {
                        "role": "user",
                        "content": "Have there been any major solar storms recently?",
                    }
                ],
            },
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["message"]["role"] == "system"
        approval_id = data["message"]["approvals"][0]["id"]

        # -- Step 3: User rejects the approval --
        resp = client.post(
            f"/api/v1/sessions/{session_id}/reject_approvals",
            json=[approval_id],
        )
        assert resp.status_code == 200

        # -- Step 4: Continue session, agent responds without web access --
        stub.prime_basic_query(
            AssistantMessage(
                content=(
                    "I don't have access to current information without web search. "
                    "Based on what I know, solar storms are common during solar maximum "
                    "periods, but I can't confirm recent events."
                )
            )
        )

        resp = client.post(f"/api/v1/sessions/{session_id}/continue")
        assert resp.status_code == 200
        data = resp.json()
        assert data["message"]["role"] == "assistant"
        assert "without" in data["message"]["content"].lower()

        # -- Verify: messages endpoint shows full conversation --
        resp = client.get(f"/api/v1/messages/{session_id}")
        assert resp.status_code == 200
        messages = resp.json()["messages"]
        roles = [m["role"] for m in messages]
        assert roles == ["user", "assistant", "user", "system", "assistant"]
