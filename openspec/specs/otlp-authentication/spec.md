## ADDED Requirements

### Requirement: OTLP exporter supports optional header-based authentication
The engine SHALL accept an `otlp_headers` setting in the `[instrumentation]` section. When present, the parsed headers SHALL be passed to the OTLP span exporter on startup. When absent or empty, the exporter SHALL operate without authentication headers.

#### Scenario: No headers configured
- **WHEN** `otlp_headers` is not set
- **THEN** the OTLP exporter is initialised without additional headers

#### Scenario: Single header configured
- **WHEN** `otlp_headers = Authorization=Bearer mytoken`
- **THEN** the OTLP exporter sends `Authorization: Bearer mytoken` with every trace export request

#### Scenario: Multiple headers configured
- **WHEN** `otlp_headers = Authorization=Bearer mytoken;X-API-Key=abc123`
- **THEN** the OTLP exporter sends both `Authorization: Bearer mytoken` and `X-API-Key: abc123` with every trace export request

#### Scenario: Header value contains equals sign
- **WHEN** `otlp_headers = Authorization=Bearer base64token==`
- **THEN** the header value is `Bearer base64token==` (characters after the first `=` are preserved as-is)

### Requirement: Header setting format is identical for INI file and environment variable
The `otlp_headers` value SHALL use the same semicolon-separated `name=value` format whether configured via `settings.ini` or the `INSTRUMENTATION_OTLP_HEADERS` environment variable.

#### Scenario: Configured via environment variable
- **WHEN** `INSTRUMENTATION_OTLP_HEADERS=Authorization=Bearer mytoken` is set
- **THEN** the exporter sends `Authorization: Bearer mytoken`, identical to the INI file equivalent

### Requirement: Auth headers are not written to logs
The engine SHALL NOT log the value of `otlp_headers` in plain text at any log level.

#### Scenario: Headers setting present at startup
- **WHEN** `otlp_headers` is configured and the engine starts
- **THEN** the log output contains no readable header values (value is obscured)

### Requirement: OTLP headers env var survives environment reset
`INSTRUMENTATION_OTLP_HEADERS` SHALL be included in the env var allowlist so it is preserved through the startup `reset_env()` call.

#### Scenario: Env var set before engine start
- **WHEN** `INSTRUMENTATION_OTLP_HEADERS` is set in the process environment before the engine starts
- **THEN** the value is still accessible after `reset_env()` completes
