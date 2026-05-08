## 1. App Models — Sensitivity, Approval, Grant types

- [x] 1.1 Add `SensitivityLevel` enum to app models with 5 values matching engine (`OpenInformation`, `Specific`, `Personal`, `Confidential`, `Internal`) and a static color mapping (green→teal→orange→deepOrange→red)
- [x] 1.2 Add `ApprovalType` enum and `ApprovalData` class mirroring engine's `Approval` (id, type, component, purpose, allowedParameters, sensitivity, granted, expiresAt, note)
- [x] 1.3 Add `GrantRequest` class for building `POST /grants` body (approvalType, component, allowedParameters, maxSensitivity, expiresAt)
- [x] 1.4 Add `AgenticRole.system` and extend `AgenticMessage` with optional fields: `approvals` (List<ApprovalData>?), `notification` (String?), `sensitivityLevel` (SensitivityLevel?)
- [x] 1.5 Update `AgenticMessage.fromJson` to parse `role: "system"` — populate approvals list, notification text, and handle the nested approval JSON structure

## 2. App Services — New API calls

- [x] 2.1 Add `setSensitivityLevel()` service function calling `PUT /session/{id}/sensitivity`
- [x] 2.2 Add `createSessionGrant()` service function calling `POST /session/{id}/grants`
- [x] 2.3 Add `createGlobalGrant()` service function calling `POST /grants`
- [x] 2.4 Add `continueSession()` service function calling `POST /session/{id}/continue`, parsing and returning the `ChatResponse` (message + sensitivity_level)
- [x] 2.5 Update `sendAgenticMessage()` to parse `sensitivity_level` from `ChatResponse` and return it alongside the message

## 3. Chat Provider — Sensitivity state and continuation flow

- [x] 3.1 Add `sensitivityLevel` field to `AgenticChatState` (default: `Personal`), update `copyWith`
- [x] 3.2 Update `sendMessage()` to parse and store `sensitivity_level` from response
- [x] 3.3 Add `changeSensitivity()` method — optimistic update, call `setSensitivityLevel()` API, revert on failure. Mark any pending approval messages as stale.
- [x] 3.4 Add `grantApproval()` method — call session or global grant API, update the specific approval's state in the message list
- [x] 3.5 Add `skipApproval()` method — mark a specific approval as skipped in local state (no API call)
- [x] 3.6 Add `continueSession()` method — call `POST /session/{id}/continue`, show pending state, append response, mark approval group as resolved
- [x] 3.7 Update `loadHistory()` to handle `SystemAction` messages in the loaded history

## 4. Engine — Session Continuation Endpoint

- [x] 4.1 Add `POST /session/{session_id}/continue` route in `engine/api/v1.py`
- [x] 4.2 Implement continuation logic in `ChatService` — re-run agent with current context, grants, and sensitivity level
- [x] 4.3 Return `ChatResponse` from the continue endpoint (message + sensitivity_level)
- [x] 4.4 Handle edge cases: session not found (404), no pending work (return current state or no-op response)

## 5. Sensitivity Indicator Widget

- [x] 5.1 Create `SensitivityIndicator` widget — small colored circle/chip showing level name and color
- [x] 5.2 Create `SensitivityPicker` bottom sheet — list of all 5 levels with names, colors, and current selection
- [x] 5.3 Wire indicator tap → open picker, picker selection → `changeSensitivity()` on provider
- [x] 5.4 Add indicator as `Stack`/`Positioned` overlay in top-right of chat body area in `AgenticChatPage`
- [x] 5.5 Hide indicator when no session is active

## 6. System Action and Approval Widgets

- [x] 6.1 Create `SystemNoteBubble` widget for rendering `SystemAction` notifications as visually distinct system notes
- [x] 6.2 Create `ApprovalCard` widget showing purpose, component, type, and sensitivity badge
- [x] 6.3 Add sensitivity mismatch banner to `ApprovalCard` — conditional, with "Change to [level]" button
- [x] 6.4 Add grant action to `ApprovalCard` — expandable section with scope toggle (session/global) and expiry chip selector (no expiry, 5m, 10m, 30m, 1h, 2h, 3h, 6h, 12h, 24h, 48h)
- [x] 6.5 Add skip action to `ApprovalCard`
- [x] 6.6 Create `ApprovalGroup` widget — renders N approval cards + "Continue" button below. Button disabled until all resolved, label changes for partial permissions.
- [x] 6.7 Add resolved/stale visual states to `ApprovalCard` — granted (shows grant details), skipped (grayed), stale (disabled with "Sensitivity changed" note)

## 7. Chat Page and History Integration

- [x] 7.1 Update `AgenticChatHistory` to render `AgenticRole.system` messages — route to `SystemNoteBubble` or `ApprovalGroup` based on message content
- [x] 7.2 Update `_MessageGroup` grouping logic to handle system messages (system messages should not group with user/assistant)
- [x] 7.3 Handle historical approvals — render as resolved (granted/skipped) when not the latest message; render as actionable when the latest message
- [x] 7.4 Wire `ApprovalGroup` callbacks to provider methods (grantApproval, skipApproval, continueSession, changeSensitivity)

## 8. Testing

- [x] 8.1 Test `AgenticMessage.fromJson` with system role, approvals, and notification payloads
- [x] 8.2 Test sensitivity level color mapping and enum parsing
- [x] 8.3 Test engine `POST /session/{id}/continue` endpoint — approval resolution, sensitivity re-eval, missing session
- [x] 8.4 End-to-end: send message → receive SystemAction with approvals → grant/skip → continue → receive response (deferred — requires agent that produces SystemAction, manual testing recommended)
