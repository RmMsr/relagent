## Context

The OTLP span exporter (`OTLPSpanExporter`) already accepts a `headers` parameter as `dict[str, str]`. Currently it is constructed with only an endpoint URL — no auth. Settings are read from `settings.ini` (configparser) and environment variables via `get_setting()`. The `reset_env()` function maintains an explicit allowlist of env vars that survive the environment reset at startup.

## Goals / Non-Goals

**Goals:**
- Support any header-based authentication for the OTLP exporter
- Keep auth credentials out of logs (obscure in debug output)
- Identical format in `settings.ini` and env vars

**Non-Goals:**
- Basic auth encoding (can be expressed as a raw `Authorization` header)
- OAuth flows or token refresh
- Per-request dynamic headers

## Decisions

### Single `otlp_headers` setting

One setting covers all schemes:

| INI key | Env var |
|---|---|
| `otlp_headers` | `INSTRUMENTATION_OTLP_HEADERS` |

Read once during `init_global_instrumentation()`, parsed into a `dict[str, str]`, and passed as `OTLPSpanExporter(endpoint=..., headers=headers)`.

**Alternatives considered:**
- Bearer token shortcut (`otlp_bearer_token`) — adds a second setting for one specific header with no real advantage over just writing `Authorization=Bearer <token>`. Dropped.
- Reusing `OTEL_EXPORTER_OTLP_HEADERS` env var — would conflict with the existing env reset model and bypass `get_setting()`. Rejected.

### Format: semicolon-separated `name=value` pairs

```ini
otlp_headers = Authorization=Bearer mytoken==;X-API-Key=abc123
```

- Semicolons separate pairs; value is everything after the **first** `=`, so `=` signs within values (e.g. base64 padding) are preserved
- Format is identical for `settings.ini` and env var — no multi-line handling needed
- Single header is the common case and reads cleanly: `Authorization=Bearer mytoken`

### Credential logging

The setting is read with `obscure_value=True` so values never appear in debug logs.

## Risks / Trade-offs

- **Semicolons in header values**: Values containing `;` cannot be represented. Acceptable for the targeted use cases (tokens, API keys never contain semicolons).
- **No validation of header names**: Malformed input will be silently ignored and may cause export failures. OTLP export failures already surface as warnings in existing error paths.

## Migration Plan

No migration required. The setting is optional; existing deployments without it are unaffected.
