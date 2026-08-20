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


class TestNewApprovalEndpoints:
    """Per-approval grant/decline routes plus the stop endpoint."""

    def test_grant_endpoint_then_continue(
        self,
        client: TestClient,
        stub: StubAgentExecution,
    ):
        stub.prime_basic_query(AssistantMessage(content="Hi"))
        resp = client.post(
            "/api/v1/messages",
            json={"messages": [{"role": "user", "content": "Hi"}]},
        )
        session_id = resp.json()["session_id"]

        approval = Approval(
            type=ApprovalType.OutgoingData,
            component="web_search",
            purpose="Searching the web",
            sensitivity=SensitivityLevel.OpenInformation,
            allowed_parameters={"query": "x"},
        )
        stub.prime_basic_query(SystemAction(approvals=[approval]))
        resp = client.post(
            "/api/v1/messages",
            json={
                "session_id": session_id,
                "messages": [{"role": "user", "content": "Search please"}],
            },
        )
        approval_id = resp.json()["message"]["approvals"][0]["id"]

        resp = client.post(
            f"/api/v1/sessions/{session_id}/approvals/{approval_id}/grant",
            json={
                "grant": {
                    "approval_type": ApprovalType.OutgoingData.value,
                    "component": "web_search",
                    "max_sensitivity": SensitivityLevel.OpenInformation.value,
                    "wildcard_parameter": "query",
                }
            },
        )
        assert resp.status_code == 200
        assert resp.json() == {"status": "granted"}

        stub.prime_basic_query(AssistantMessage(content="Here are results"))
        resp = client.post(f"/api/v1/sessions/{session_id}/continue")
        assert resp.status_code == 200
        assert resp.json()["message"]["role"] == "assistant"

        resp = client.get(f"/api/v1/messages/{session_id}")
        messages = resp.json()["messages"]
        # All settled
        assert all(m["final"] for m in messages)
        # Granted approval is recorded
        system_msg = next(m for m in messages if m["role"] == "system")
        assert system_msg["approvals"][0]["granted"] is True

    def test_decline_endpoint_then_continue(
        self,
        client: TestClient,
        stub: StubAgentExecution,
    ):
        stub.prime_basic_query(AssistantMessage(content="Hi"))
        resp = client.post(
            "/api/v1/messages",
            json={"messages": [{"role": "user", "content": "Hi"}]},
        )
        session_id = resp.json()["session_id"]

        approval = Approval(
            type=ApprovalType.OutgoingData,
            component="web_search",
            purpose="Searching the web",
            sensitivity=SensitivityLevel.OpenInformation,
            allowed_parameters={"query": "x"},
        )
        stub.prime_basic_query(SystemAction(approvals=[approval]))
        resp = client.post(
            "/api/v1/messages",
            json={
                "session_id": session_id,
                "messages": [{"role": "user", "content": "Search please"}],
            },
        )
        approval_id = resp.json()["message"]["approvals"][0]["id"]

        resp = client.post(
            f"/api/v1/sessions/{session_id}/approvals/{approval_id}/decline"
        )
        assert resp.status_code == 200
        assert resp.json() == {"status": "declined"}

        stub.prime_basic_query(AssistantMessage(content="Continuing without search"))
        resp = client.post(f"/api/v1/sessions/{session_id}/continue")
        assert resp.status_code == 200

        resp = client.get(f"/api/v1/messages/{session_id}")
        messages = resp.json()["messages"]
        system_msg = next(m for m in messages if m["role"] == "system")
        assert system_msg["approvals"][0]["granted"] is False

    def test_stop_endpoint_settles_cycle_with_pending_approval(
        self,
        client: TestClient,
        stub: StubAgentExecution,
    ):
        stub.prime_basic_query(AssistantMessage(content="Hi"))
        resp = client.post(
            "/api/v1/messages",
            json={"messages": [{"role": "user", "content": "Hi"}]},
        )
        session_id = resp.json()["session_id"]

        approval = Approval(
            type=ApprovalType.OutgoingData,
            component="web_search",
            purpose="Searching",
            sensitivity=SensitivityLevel.OpenInformation,
            allowed_parameters={"query": "x"},
        )
        stub.prime_basic_query(SystemAction(approvals=[approval]))
        resp = client.post(
            "/api/v1/messages",
            json={
                "session_id": session_id,
                "messages": [{"role": "user", "content": "Search please"}],
            },
        )
        assert resp.status_code == 200

        resp = client.post(f"/api/v1/sessions/{session_id}/stop")
        assert resp.status_code == 200
        body = resp.json()
        assert body["session_id"] == session_id
        # All returned messages are settled
        assert all(m["final"] for m in body["messages"])
        # Pending approval is now declined
        system_msg = next(m for m in body["messages"] if m["role"] == "system")
        assert system_msg["approvals"][0]["granted"] is False
        # No AssistantMessage was added by the stop
        assert not any(m["role"] == "assistant" for m in body["messages"][-2:])

    def test_stop_with_no_in_flight_returns_409(self, client: TestClient, stub):
        stub.prime_basic_query(AssistantMessage(content="Hi"))
        resp = client.post(
            "/api/v1/messages",
            json={"messages": [{"role": "user", "content": "Hi"}]},
        )
        session_id = resp.json()["session_id"]

        resp = client.post(f"/api/v1/sessions/{session_id}/stop")
        assert resp.status_code == 409
        assert resp.json()["detail"]["error"] == "no_in_flight_cycle"

    def test_stop_unknown_session_returns_404(self, client: TestClient):
        resp = client.post("/api/v1/sessions/00000000-0000-0000-0000-000000000001/stop")
        assert resp.status_code == 404


class TestPhoenixTraceRegression:
    """Reproduce trace 27d80f45f403fbecfca0256c67d13143: a second user
    message arrived while an approval was still pending. Under the new
    model the second /messages call hits the in-flight guard and returns
    409 instead of producing the broken interleaved-history pattern."""

    def test_second_message_during_in_flight_cycle_returns_409(
        self,
        client: TestClient,
        stub: StubAgentExecution,
        monkeypatch: pytest.MonkeyPatch,
    ):
        monkeypatch.setenv("ENGINE_IN_FLIGHT_TIMEOUT_SECONDS", "0")
        monkeypatch.setenv("ENGINE_IN_FLIGHT_POLL_INTERVAL_MS", "1")

        stub.prime_basic_query(AssistantMessage(content="Hi"))
        resp = client.post(
            "/api/v1/messages",
            json={"messages": [{"role": "user", "content": "Hi"}]},
        )
        session_id = resp.json()["session_id"]

        approval = Approval(
            type=ApprovalType.OutgoingData,
            component="web_search",
            purpose="Searching",
            sensitivity=SensitivityLevel.OpenInformation,
            allowed_parameters={"query": "x"},
        )
        stub.prime_basic_query(SystemAction(approvals=[approval]))
        resp = client.post(
            "/api/v1/messages",
            json={
                "session_id": session_id,
                "messages": [{"role": "user", "content": "First request"}],
            },
        )
        assert resp.status_code == 200

        resp = client.post(
            "/api/v1/messages",
            json={
                "session_id": session_id,
                "messages": [{"role": "user", "content": "retry"}],
            },
        )
        assert resp.status_code == 409
        detail = resp.json()["detail"]
        assert detail["error"] == "session_in_flight"
        assert detail["session_id"] == session_id
