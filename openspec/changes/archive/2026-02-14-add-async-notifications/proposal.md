# Change: Add Async Notifications via SSE

## Why

Multiple clients (e.g., phone + desktop) need real-time updates when session data changes. Currently, clients must poll or miss updates entirely. Additionally, future scheduled tasks will run in separate processes and need to notify connected clients.

The app also needs a unified notification system that doesn't block the UI. Current implementations (SnackBar after settings save, MaterialBanner for errors) hide controls or disrupt interaction.

## What Changes

- **Engine**: New SSE endpoint `/api/v1/events` with documentation that streams thin notifications
- **Engine**: SQLite-backed event store for cross-process writes and reconnection replay
- **Engine**: New event publisher port for use in services (session updated, message created)
- **Data**: Messages become an explicit ID so apps can check if they already have the latest one
- **App**: SSE client with automatic reconnection and catch up using last known event ID
- **App**: Refresh relevant data when notifications received
- **App**: Typed event model replacing generic SseEvent container
- **App**: Duplicate event deduplication for pending update events

## Event Format

Standard SSE with thin event payloads:

```
event: session.updated
id: 42
data: {"session_id": "abc123"}

event: session.messages.appended
id: 43
data: {"session_id": "abc123", "latest_message_id": "25"}
```

- `event:` - dot-separated event type
- `id:` - monotonic event ID for `Last-Event-ID` replay
- `data:` - JSON with identifiers only (no payload data)

Clients fetch updated data via existing REST endpoints (e.g., `GET /api/v1/messages/{session_id}?from_id={messages_from_id}`).

## Impact

- Affected specs: NEW `async-notifications` capability, NEW `app-event-handling` capability
- Affected code:
  - Engine: new `/api/v1/events` endpoint, event publisher and sqlite backend adapter, publish events in existing service methods
  - App: typed event model replacing generic SseEvent, SSE client provider, integration with chat provider for refresh triggers
- New dependency: `sse-starlette` (engine), SQLite for event persistence (already available)

## Design Decisions

### SQLite over Redis
- Single container deployment, no external services
- Handles cross-process writes safely (cron/worker scenarios)
- Natural support for event replay via incrementing IDs
- Event TTL pruning keeps storage bounded

### Thin Events
- Simpler implementation, no stale data races
- Extra GET request acceptable for secondary device updates
- Consistent pattern for all event types

### Client Reconciliation and multiplexing
- Client remembers and sends last event ID on reconnect
- Server replays missed events
- Client ignores events when data is already loaded (for example latest message id from event is not greater than the last message id in the client)
- Client may fetch full state after connection loss for safety
- Every incoming event is sent to all subscribed clients
- Clients decide if they need to act on the event

### Quality Gates
- Creating duplicated events should be avoided
- A SSE keepalive is needed, default from 15s sse-starlette should be sufficient
- Retention: Events are deleted when older than 72 hours
- Replay limit: Last 100 events maximum; older events not re-sent

### Future Event Categories (not yet specified)
Events will eventually cover four categories. Only **Updates** are implemented now:
- **Updates**: Triggers indicating new data is available (implemented)
- **Commands**: Actions the app should execute (e.g., change voice mode) — deferred until engine supports them
- **Notifications**: Informational messages for the user — deferred until engine supports them
- **Approvals**: Permission requests requiring user confirmation — deferred until engine supports them

When these categories are needed, they should get their own spec requirements with concrete scenarios based on actual engine payloads.

### App Notification System (deferred)
A unified notification UI (non-blocking, minimizable, with queue management and persistence) is planned but deferred. Current local feedback (disconnect, settings save) remains as-is until the notification system has real engine-driven use cases to design against.

## Exclusion

- No data except ids are sent in events
- User level isolation is important, but will be implemented later
- Complex retry, deduplication or other logic will not be added without proof it is needed
- Commands, Notifications, Approvals, and `required_action` field are not specified until the engine provides them
- Notification queue, persistence, approval bottom sheet, and CommandRouter are deferred
