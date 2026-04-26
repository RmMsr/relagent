## Why

The engine supports sensitivity levels on chat contexts and a permission system using Approval and Grant objects, but the full end-to-end flow is incomplete. The apps ignore both — `SystemAction` messages are silently dropped, and `sensitivity_level` from `ChatResponse` is discarded. The engine also lacks a way to resume/continue a session after state changes (grants, sensitivity adjustments, error recovery). Both app and engine need coordinated changes to complete this feature.

## What Changes

- **Sensitivity level indicator**: A floating, color-coded element on the chat page showing the current session sensitivity level (green for OpenInformation through bright red for Internal). Tapping opens a picker to switch levels via the `PUT /session/{id}/sensitivity` endpoint.
- **SystemAction message rendering**: `SystemAction` messages from the engine are rendered in the chat history. Notifications appear as system notes. Approvals appear as actionable UI elements.
- **Approval UI with per-approval resolution and explicit continuation**: When the engine returns approvals, each is resolved individually — grant (with scope + expiry) or skip. The user can also adjust sensitivity during this phase. Once all approvals are addressed, the user explicitly continues the session. The engine resumes with whatever permission state exists — skipped approvals mean the engine works without those capabilities (recovery path).
  Each approval card shows the request details (`purpose`, `component`, `type`) and the approval's sensitivity level (color-coded). The sensitivity-adjust option is visually prominent when the approval's sensitivity differs from the session level, guiding the user to adjust rather than grant at a mismatched level.
- **Session continuation endpoint (engine)**: A new `POST /session/{id}/continue` endpoint that triggers an agent run with the current session state and returns a `ChatResponse`. This serves approval resolution, sensitivity change re-evaluation, and general error recovery. Grant and sensitivity endpoints remain fire-and-forget state mutations; continuation is a separate explicit action.
- **App model updates**: `AgenticMessage` and related models are extended to represent `SystemAction` (approvals + notifications) alongside user/assistant messages. The `fromJson` parser handles the `system` role.

## Capabilities

### New Capabilities
- `sensitivity-indicator`: Floating color-coded sensitivity level display and picker on the chat page
- `approval-ui`: Actionable approval cards in chat history with grant/skip, expiry controls, and explicit continuation
- `session-continuation`: Engine endpoint (`POST /session/{id}/continue`) that triggers an agent run with current state and returns a `ChatResponse`. Serves approval resolution, sensitivity re-evaluation, and error recovery.

### Modified Capabilities
- `agentic-chat`: Chat message model and history parsing must handle `SystemAction` (role=system) messages containing approvals and notifications, and the chat response must track `sensitivity_level`

## Impact

- **App models** (`apps/lib/agentic/models.dart`): New types for sensitivity level, approval, grant; extended `AgenticMessage` or new message subtypes for system actions
- **App services** (`apps/lib/agentic/services.dart`): New API calls for `PUT /session/{id}/sensitivity`, `POST /session/{id}/grants`, `POST /grants`
- **Chat provider** (`apps/lib/providers/agentic_chat_provider.dart`): State tracks current sensitivity level; handles grant creation and re-triggering agent runs
- **Chat page** (`apps/lib/pages/agentic_chat_page.dart`): Floating sensitivity indicator overlay; updated message list rendering
- **Chat widgets** (`apps/lib/agentic/widgets.dart`): New widgets for system action cards, approval cards, sensitivity picker
- **Engine API** (`engine/api/v1.py`, `engine/domain/services.py`): New `POST /session/{id}/continue` endpoint; existing grant and sensitivity endpoints unchanged
- **Engine API endpoints used by app**: `PUT /session/{id}/sensitivity`, `POST /session/{id}/grants`, `POST /grants`, `POST /session/{id}/continue` (new), existing `POST /messages` and `GET /messages/{id}`
