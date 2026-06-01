## Why

Relagent needs an inference provider (an OpenAI-compatible LLM server) to do
anything useful. Until now, every new user had to set one up before the first
conversation, which is a steep first step for evaluation. At the same time, when
that provider is offline or still starting, the app surfaced a bare `HTTP 503` /
"Engine error occurred" with no usable detail — unhelpful exactly when a new user
is most likely to hit it (nothing running yet).

This change documents two branch themes that address both: a batteries-included
container for trying Relagent out, and descriptive surfacing of internal errors.

## What Changes

- Add a `bundled` container target that ships a CPU inference server
  (`llama.cpp`) alongside the engine, so Relagent works out of the box with no
  external provider. The bundled image is for demo, showcasing, and first-try /
  evaluation use — explicitly **not** for productive or permanent installations.
- Detect inference-provider transport failures (unreachable, or up-but-warming-up)
  and report them as a retryable `503` carrying a **descriptive reason** that
  names the configured endpoint and the provider's own message.
- Surface that description in the app as a friendly, retryable error, and keep
  the error in the conversation history across a retry so the user can follow
  the sequence of events.

## Capabilities

### Added Capabilities

- `bundled-inference-container`: A container image variant that bundles a
  CPU-based `llama.cpp` inference server with the engine for zero-setup
  demo / first-try use, not for production.
- `engine-error-reporting`: Internal engine errors that are surfaced to the
  client carry a human-readable description, and the app displays that
  description rather than only a status code. The first concrete instance is
  inference-provider unavailability reported as a retryable `503`.

## Impact

- `Containerfile`: adds `llama` and `bundled` build stages on top of the base
  `app` image; `slim` stays the default engine-only image.
- `run/entrypoint.sh`: when `PROVIDER_BUNDLED=true`, starts `llama-server`
  (loopback, single-parallel, small context, quantized KV cache) and points
  `PROVIDER_API_BASE` at it before launching the engine.
- `bin/server_build.py` / `bin/server_run.py`: build and run the `bundled`
  target; image tags gain a `-bundled` suffix.
- `engine/domain/exceptions.py`: new `ProviderUnavailable`.
- `engine/adapters/pydantic_ai_execution/queries.py`: map pydantic_ai
  `ModelAPIError` / `ModelHTTPError(5xx)` to `ProviderUnavailable` with a
  descriptive reason; 4xx is left to propagate.
- `engine/api/v1.py`: map `ProviderUnavailable` to `503` with a structured
  `provider_unavailable` body and `Retry-After`.
- `apps/lib/agentic/services.dart`: `ProviderUnavailableException`, parse the
  `provider_unavailable` body, handle `503`.
- `apps/lib/providers/agentic_chat_provider.dart`: retry keeps the trailing
  error in history and does not duplicate the user message.

## Known Risks

- **Bundled performance expectations**: CPU inference is slow; users may judge
  Relagent by the bundled model's latency. Mitigated by documenting it as a
  demo/first-try option with several-seconds response times, not production.
- **First-start model download**: the bundled image downloads the default model
  (~3.5 GB) on first run; the engine is reachable before the model is ready,
  which is the exact window the `503`/retry handling covers.
- **Partial error coverage**: only the inference-provider failure path is mapped
  to a descriptive `503` today. Other unhandled engine exceptions still return a
  generic `500`; a general engine error handler is a follow-up (see tasks).
