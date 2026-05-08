## 1. Engine domain model

- [x] 1.1 Add `message_id: UUID = Field(default_factory=uuid4)` to `UserMessage`, `AssistantMessage`, `SystemAction` in `engine/domain/models.py`
- [x] 1.2 Remove `sequence_id` from `UserMessage`, `AssistantMessage`, `SystemAction`
- [x] 1.3 Remove `ChatContext._next_sequence_id` and any code that assigns sequence IDs
- [x] 1.4 Update `engine/domain/services.py` (`_add_messages_to_context_with_sequence_ids` and any other site keyed on sequence_id) to key on `message_id`
- [x] 1.5 Update `engine/domain/immutability.py` checks to identify messages by `message_id`
- [x] 1.6 Update `engine/domain/exceptions.py` payloads to reference `message_id` rather than `sequence_id`

## 2. Engine persistence

- [x] 2.1 Add a `message_id TEXT` column to the message table in `sqlite_event_store.py` (or equivalent), with a unique index per session
- [x] 2.2 Implement `messages_after(session_id, message_id)` that resolves the row's primary-key position and returns subsequent rows in insertion order
- [x] 2.3 Add self-healing read for NULL `message_id`: mint UUID, single UPDATE on that row, return the message with the minted ID. Mark with `# BACKWARD COMPAT:` comment naming the removal trigger
- [x] 2.4 Add self-healing read for NULL `final`: assume `true`, single UPDATE, return. Mark with `# BACKWARD COMPAT:` comment

## 3. Engine API

- [x] 3.1 Replace `?from_id=<int>` with `?after=<uuid>` on `GET /sessions/{id}/messages` in `engine/api/v1.py`
- [x] 3.2 Update `POST /sessions/{id}/messages` to accept a body with `message_id`; return prior cycle response when `message_id` already exists in the session
- [x] 3.3 Drop `latest_sequence_id` from the `MessagesAppendedEvent` payload (`engine/api/events.py`, `engine/domain/ports/events.py`); event becomes notification-only with just `session_id`

## 4. App models

- [x] 4.1 Replace `AgenticMessage.id: int?` with `messageId: String` (non-nullable) in `apps/lib/agentic/models.dart`
- [x] 4.2 Update `AgenticMessage.user(text)` to generate a UUID at construction time
- [x] 4.3 Update `AgenticMessage.error(...)` to generate a UUID at construction time
- [x] 4.4 Update `AgenticMessage.fromJson` to read `message_id` from the engine response (require non-null after compat shim)
- [x] 4.5 Add a `uuid` package dependency or implement a small UUID generator helper

## 5. App services

- [x] 5.1 Update `services.dart` send-message function to include `message_id` in the request body
- [x] 5.2 Update `getMessageHistory` to take an optional `String? afterMessageId` instead of `int? fromId`, and translate it to `?after=<uuid>`
- [x] 5.3 Update `MessagesAppendedEvent` parsing in `sse_client.dart` to drop `latestSequenceId`

## 6. App ingestion function

- [x] 6.1 Rename `AgenticChatNotifier._mergeRefresh` to `_ingestMessages`; change signature to `void _ingestMessages(List<AgenticMessage> incoming)` that mutates state in place
- [x] 6.2 Implement the contract: append-if-new (preserve incoming order), skip-if-known-and-final, replace-if-known-and-non-final
- [x] 6.3 Replace direct `state = state.copyWith(messages: ...)` assignments in `loadHistory`, `sendMessage`, `triggerContinuation`, `stopCycle`, `retryFailedMessages` with calls to `_ingestMessages`
- [x] 6.4 Optimistic local user message in `sendMessage` is added via `_ingestMessages([userMessage])`
- [x] 6.5 Local error messages are added via `_ingestMessages([errorMessage])`
- [x] 6.6 Remove the `id == null` branch from the merge logic — every message has a non-null `messageId` now
- [x] 6.7 Simplify `retryFailedMessages`: drop the "trailing user with no engine id" walk; reissue trailing user messages whose cycle hasn't settled (no `Assistant`/`SystemAction` final after them); idempotent POST handles dedup

## 7. App SSE flow

- [x] 7.1 Remove `MessageEventDedup` class from `apps/lib/providers/sse_provider.dart` and its test counterpart
- [x] 7.2 Add `_fetchInFlight: bool` and `_refetchPending: bool` to `SseNotifier` (or to the chat notifier — pick one place)
- [x] 7.3 Implement `fetchSinceCursor()`: cursor = `state.messages.lastWhere((m) => m.isFinal, orElse: null)?.messageId`; coalesce concurrent calls via the in-flight/pending pair
- [x] 7.4 Update `MessagesAppendedEvent` handler to call `fetchSinceCursor()` instead of `loadHistory(fromId:)`
- [x] 7.5 Remove `_seedDedupFromChat` and the call site

## 8. Engine tests

- [x] 8.1 Update `engine/tests/domain/services/...` tests to assert `message_id` instead of `sequence_id`
- [x] 8.2 Update `engine/tests/adapters/test_sqlite_event_store.py` to cover the `?after=<uuid>` query and the self-healing read paths (NULL `message_id`, NULL `final`)
- [x] 8.3 Update `engine/tests/test_api_endpoints.py` to cover idempotent POST (same `message_id` returns same response) and `?after=<uuid>` happy/edge cases (unknown UUID, missing param)
- [x] 8.4 Update `engine/tests/test_api_events.py` to assert `messages.appended` no longer carries `latest_sequence_id`

## 9. App tests

- [x] 9.1 Update `apps/test/agentic/models_test.dart` to assert non-null `messageId` on user/error factories and from JSON
- [x] 9.2 Add unit tests for `_ingestMessages` covering the four cases: new, present-and-final, present-and-non-final, repeated-call idempotence
- [x] 9.3 Update `apps/test/agentic/services_test.dart` to assert the `?after=<uuid>` query and the `message_id` POST body
- [x] 9.4 Replace `MessageEventDedup` tests with `fetchSinceCursor` coalescing tests (in-flight, refetch-pending, post-fetch recursion)
- [x] 9.5 Update `apps/test/agentic/sse_client_test.dart` for the slimmed `MessagesAppendedEvent`

## 10. Verification

- [ ] 10.1 Manual: send a user message on device A, observe it on device B without duplicates and in correct order once the cycle settles
- [ ] 10.2 Manual: kill network mid-POST, restore, retry — verify no duplicate user message is created on the engine side
- [ ] 10.3 Manual: open a pre-cutover session, confirm messages render and self-healing UPDATEs run exactly once per row
- [ ] 10.4 Manual: trigger many rapid `messages.appended` events — verify fetch coalescing produces at most two fetches (current + one queued)
