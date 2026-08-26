import os

from engine.tests.conftest import reset_test_environment


def test_reset_test_environment_removes_inherited_variables(monkeypatch):
    monkeypatch.setenv("PROVIDER_API_BASE", "http://configured.example/v1")
    monkeypatch.setenv("SERVER_SECRET_ACCESS_KEY", "configured-secret")
    monkeypatch.setenv("INSTRUMENTATION_OTLP_HEADERS", "Authorization=Bearer token")
    monkeypatch.setenv("UNRELATED_TEST_VARIABLE", "retained")

    reset_test_environment()

    assert os.getenv("PROVIDER_API_BASE") is None
    assert os.getenv("SERVER_SECRET_ACCESS_KEY") is None
    assert os.getenv("INSTRUMENTATION_OTLP_HEADERS") is None
    assert os.getenv("UNRELATED_TEST_VARIABLE") is None
