## 1. Engine — Expose sensitivity in MessagesResponse

- [x] 1.1 Add optional `sensitivity_level: SensitivityLevel | None` field to `MessagesResponse` in `engine/domain/models.py`
- [x] 1.2 Populate it from `context.sensitivity_level` in `ChatService.get_messages()` in `engine/domain/services.py`
- [x] 1.3 Add a test asserting `GET /messages/{id}` response includes the correct `sensitivity_level`

## 2. Flutter — Read and apply sensitivity from history response

- [x] 2.1 Parse `sensitivity_level` from the `GET /messages` JSON in `getMessageHistory()` (`apps/lib/agentic/services.dart`) — return it alongside messages (adjust return type or introduce a wrapper)
- [x] 2.2 Apply the returned sensitivity to state in both load paths of `loadHistory()` (`apps/lib/providers/agentic_chat_provider.dart`) — null-safe, only overwrite when present
- [x] 2.3 Add a test covering that `loadHistory()` sets `sensitivityLevel` from the response and does not reset state when the field is absent

## 3. New session — pass sensitivity on first message

- [x] 3.1 Add optional `sensitivity_level: SensitivityLevel | None` to `ChatRequest` in `engine/domain/models.py` and apply it to the context before processing in `engine/domain/services.py`
- [x] 3.2 Include `sensitivityLevel` in the `POST /messages` body in `sendAgenticMessage()` (`apps/lib/agentic/services.dart`) only when `sessionId` is null
- [x] 3.3 Add a test asserting the engine applies the `sensitivity_level` from `ChatRequest` on new session creation, and that it is absent for existing sessions
