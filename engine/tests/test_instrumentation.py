import configparser

from engine.api.instrumentation import _parse_otlp_headers
from engine.settings import override_config_parser, reset_env


class TestParseOtlpHeaders:
    def test_single_header(self):
        assert _parse_otlp_headers("Authorization=Bearer mytoken") == {
            "Authorization": "Bearer mytoken"
        }

    def test_multiple_headers(self):
        assert _parse_otlp_headers("Authorization=Bearer mytoken;X-API-Key=abc123") == {
            "Authorization": "Bearer mytoken",
            "X-API-Key": "abc123",
        }

    def test_value_with_equals_padding(self):
        assert _parse_otlp_headers("Authorization=Bearer base64token==") == {
            "Authorization": "Bearer base64token=="
        }

    def test_empty_string(self):
        assert _parse_otlp_headers("") == {}

    def test_malformed_entry_skipped(self):
        assert _parse_otlp_headers(
            "Authorization=Bearer token;BADENTRY;X-API-Key=abc"
        ) == {
            "Authorization": "Bearer token",
            "X-API-Key": "abc",
        }

    def test_whitespace_stripped(self):
        assert _parse_otlp_headers(" Authorization = Bearer token ") == {
            "Authorization": "Bearer token"
        }


class TestResetEnvPreservesOtlpHeaders:
    def test_otlp_headers_survives_reset(self, monkeypatch):
        monkeypatch.setenv(
            "INSTRUMENTATION_OTLP_HEADERS", "Authorization=Bearer mytoken"
        )

        import engine.settings as settings_module

        settings_module._env_reset_done = False
        override_config_parser(configparser.ConfigParser())

        reset_env()

        import os

        assert (
            os.environ.get("INSTRUMENTATION_OTLP_HEADERS")
            == "Authorization=Bearer mytoken"
        )
