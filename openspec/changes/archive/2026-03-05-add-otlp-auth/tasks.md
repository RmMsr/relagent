## 1. Settings

- [x] 1.1 Add `INSTRUMENTATION_OTLP_HEADERS` to the `keep` list in `reset_env()` in `engine/settings.py`

## 2. Instrumentation

- [x] 2.1 In `init_global_instrumentation()`, read `otlp_headers` via `get_setting("instrumentation", "otlp_headers", obscure_value=True)`
- [x] 2.2 Implement `_parse_otlp_headers(raw: str) -> dict[str, str]`: split on `;`, then split each pair on the first `=`, strip whitespace, skip malformed entries
- [x] 2.3 Pass the parsed headers dict to `OTLPSpanExporter(endpoint=endpoint, headers=headers)` (only when headers is non-empty)

## 3. Tests

- [x] 3.1 Unit-test `_parse_otlp_headers`: single header, multiple headers, value with `=` padding, empty string, malformed entry
- [x] 3.2 Test that `INSTRUMENTATION_OTLP_HEADERS` survives `reset_env()`

## 4. Verification

- [x] 4.1 Run `uv run ruff check engine/` and fix any issues
- [x] 4.2 Run `uv run pyright engine/` and fix any issues
- [x] 4.3 Run `uv run pytest engine/tests/` and confirm all tests pass
