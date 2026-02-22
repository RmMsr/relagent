from typing import Any

from fastapi.testclient import TestClient


def assert_required_authentication(
    client: TestClient,
    endpoint: str,
    method: str = "get",
    success_code: int = 200,
    payload: Any = None,
):
    # Ensure client is not yet authenticated
    client.headers.pop("X-API-Key", None)

    response = client.request(
        method=method,
        url=endpoint,
        json=payload,
    )
    assert response.status_code == 401, (
        "Should reject missing API key in header with status 401, but got %i"
        % response.status_code
    )

    response = client.request(
        method=method,
        url=endpoint,
        json=payload,
        headers={"X-API-Key": "wrong_key"},
    )
    assert response.status_code == 401, (
        "Should reject wrong API key in header with status 401, but got %i"
        % response.status_code
    )

    response = client.request(
        method=method,
        url=endpoint,
        json=payload,
        headers={"X-API-Key": "test_api_key"},
    )
    assert response.status_code == success_code, (
        "Should accept valid API key in header with status %i, but got %i"
        % (success_code, response.status_code)
    )
