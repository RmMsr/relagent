# Relagent Engine

The agentic engine with api and agent orchestration.

## Development

You need the correct python version and uv installed. See [main README.md](../README.md#standalone-or-development-setup) for details.

### Demo mode

Run the engine with deterministic, rule-based responses — no LLM required.
Useful for testing the Flutter app against a predictable API.

```
uv run python -m engine.api.demo
```

Behaviour:
- Messages starting with `search ` trigger a web_search approval flow.
- Granted searches return a canned result; rejected searches explain the limitation.
- Existing grants are remembered — subsequent searches skip the approval step.

### Generate OpenAPI schema

```
./bin/generate_schema.py
# generates: openapi-schema.json
```
