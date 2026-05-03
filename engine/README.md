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

## API surface

The engine exposes a small REST API (under `/api/v1`) plus a Server-Sent
Events stream at `/api/v1/events`. The full schema lives in
[`openapi-schema.json`](openapi-schema.json). The notes below cover the
endpoints involved in the strict-ordering chat protocol.

### Send and continue

| Endpoint | Purpose |
| --- | --- |
| `POST /messages` | Send a user message. Returns `409 session_in_flight` if the target session has an unsettled cycle — clients SHOULD queue locally and retry after settlement. |
| `POST /sessions/{id}/continue` | Drive the agent's next iteration. Called by clients after every approval in the trailing in-flight `SystemAction` is decided; the engine never auto-continues. |
| `POST /sessions/{id}/stop` | Settle the in-flight cycle without invoking the agent: every undecided approval becomes `granted=false`, the trailing `SystemAction(s)` and the cycle's `UserMessage` flip to `final=true`. Returns the settled message list. `409 no_in_flight_cycle` if there is nothing to stop. |

### Per-approval decisions

The previous "decide-all-at-once" endpoints were removed in favour of per-approval calls:

| Removed | Replacement |
| --- | --- |
| `POST /sessions/{id}/grants` | `POST /sessions/{id}/approvals/{approval_id}/grant` (per approval; global grants still go to `POST /grants`). |
| `POST /sessions/{id}/reject_approvals` | `POST /sessions/{id}/approvals/{approval_id}/decline` (per approval). |

Both endpoints mutate the trailing `SystemAction(final=false)` in place and do NOT invoke the agent — the client follows up with `POST /sessions/{id}/continue` once every approval in the group is decided.

### In-flight guard

Every persisted message carries a `final: bool`. A cycle is "in-flight" while its trailing message is `final=false`; settlement (an `AssistantMessage` append, or `POST /stop`) flips `final` to `true` on every preceding in-flight message back to and including the cycle's `UserMessage`. The persistence layer rejects writes that would mutate or remove a `final=true` record (`MessageImmutabilityError`). Pre-cutover stored messages without the `final` field load as `final=true` via a read-time default — no migration job runs.
