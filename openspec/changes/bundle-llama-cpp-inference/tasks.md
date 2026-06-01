## 1. Bundled inference container

- [x] 1.1 Add `llama` and `bundled` build stages to `Containerfile` on top of the base `app` image; keep `slim` as the default engine-only image
- [x] 1.2 In `run/entrypoint.sh`, when `PROVIDER_BUNDLED=true`, start `llama-server` on loopback (single-parallel, small context, quantized KV cache), default the model, and export `PROVIDER_API_BASE` before launching the engine
- [x] 1.3 Build both default and `bundled` targets in `bin/server_build.py`; tag the bundled image with a `-bundled` suffix
- [x] 1.4 Run the bundled target from `bin/server_run.py`
- [x] 1.5 Document the bundled image as the easiest first-try option, state its limited performance, first-start model download, and multi-second CPU latency, and point productive setups at an external provider (`README.md`, `docs/installation.md`)

## 2. Engine: descriptive provider-unavailable reporting

- [x] 2.1 Add `ProviderUnavailable` to `engine/domain/exceptions.py`
- [x] 2.2 In `engine/adapters/pydantic_ai_execution/queries.py`, map `ModelAPIError` and `ModelHTTPError(5xx)` to `ProviderUnavailable`; leave `4xx` to propagate
- [x] 2.3 Build a descriptive reason that names `PROVIDER_API_BASE` and surfaces the provider's own message/body
- [x] 2.4 In `engine/api/v1.py`, map `ProviderUnavailable` on `/messages` and `/continue` to `503` with a structured `provider_unavailable` body and `Retry-After`
- [x] 2.5 Tests: adapter mapping (connection, 5xx, 4xx pass-through, reason content) and route `503` contract

## 3. App: surface and retry

- [x] 3.1 Add `ProviderUnavailableException`; parse the `provider_unavailable` body in `tryParseConflict`; handle `503` in `_httpException` (including a bare `503`)
- [x] 3.2 Make `sendAgenticMessage` accept an injectable client for tests
- [x] 3.3 Change `retryFailedMessages()` to keep the trailing error and not duplicate the re-issued user message
- [x] 3.4 Tests: `provider_unavailable` parsing, `503` mapping, retry-preserves-error

## 4. Follow-ups (not in this change)

- [ ] 4.1 General engine error handler so unhandled exceptions also return a descriptive body instead of a generic `500`
- [ ] 4.2 Teach the app's `_extractErrorDetails` to read a structured `detail` object (not only list/string) for non-provider errors
