## Why

OTLP trace exporters on managed observability platforms (e.g. Scaleway Cockpit, Grafana Cloud, Honeycomb) require authentication headers. Currently the engine only accepts an endpoint URL, so users on any authenticated backend cannot export traces.

## What Changes

- Add optional authentication configuration for the OTLP exporter in `engine/api/instrumentation.py`
- Support **Bearer token** auth (`Authorization: Bearer <token>`) as a first-class convenience setting
- Support **custom headers** as a flexible fallback for any other header-based scheme (e.g. `X-API-Key`, service-specific headers)
- Expose the new settings via `settings.ini` and environment variables
- Add new env var names to the `reset_env()` allowlist in `engine/settings.py`

## Capabilities

### New Capabilities

- `otlp-authentication`: Optional header-based authentication for the OTLP span exporter, supporting bearer token and arbitrary custom headers via engine settings.

### Modified Capabilities

<!-- No existing spec-level requirements are changing -->

## Impact

- `engine/api/instrumentation.py`: Read auth settings and pass `headers` dict to `OTLPSpanExporter`
- `engine/settings.py`: Add new env var names to the `reset_env()` allowlist
- `settings.ini` (user config): New `[instrumentation]` keys documented for users
- No API contract changes, no Flutter app changes
