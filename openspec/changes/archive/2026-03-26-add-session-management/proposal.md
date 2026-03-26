## Why

Users currently cannot view or manage their previous chat sessions. All conversation history is either lost or inaccessible when starting a new session, making it impossible to reference past conversations or organize work across multiple sessions. This change enables users to browse, switch between, and manage their conversation history.

## What Changes

- **New Sessions Page**: A dedicated page listing recent sessions with title, relative modification time, and delete option
- **API Enhancement**: Add `limit` parameter to session listing endpoint (default: 100 sessions)
- **YAML Persistence Update**: Modify folder modification timestamps when sessions are accessed/modified to enable proper sorting
- **Chat UI Update**: Replace existing delete button with "New Session" button on the agentic chat page
- **Event System**: Add events for session creation and deletion
- **Active Session Handling**: Automatic notification and new session creation when the active session is deleted
- **Real-time Updates**: Sessions list auto-updates when new sessions are created

## Capabilities

### New Capabilities
- `session-management`: Core functionality for listing, switching between, and deleting chat sessions. Includes session metadata (title, last modified), chronological sorting, and deletion with confirmation.
- `session-events`: Event system for session lifecycle (created, deleted) enabling real-time updates and notifications across the app.
- `yaml-persistence-timestamp`: Updates to YAML persistence layer to modify folder timestamps on session access/modification, enabling accurate "last modified" tracking for session sorting.

### Modified Capabilities
- `chat-history`: Extend to support session switching - the chat history view needs to handle loading different sessions without page reload, and integrate with the new session management system.

## Impact

**Affected Components:**
- Flutter app: New sessions page, modifications to agentic chat page, event handling
- Engine API: Session listing endpoint modification
- Persistence layer: YAML storage timestamp management

**API Changes:**
- Session listing endpoint adds optional `limit` query parameter
- No breaking changes - existing behavior preserved when parameter omitted

**Dependencies:**
- Relies on existing chat history persistence structure
- Builds on current event system patterns in the app
