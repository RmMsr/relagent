## Context

The Relagent app currently stores chat sessions in YAML format on disk but provides no user interface for managing them. Users can only access the current active session, and there's no way to browse history, switch contexts, or organize conversations. This design introduces a complete session management system across the Flutter app and Engine API.

## Goals / Non-Goals

**Goals:**
- Enable users to view and switch between recent chat sessions
- Provide session deletion with confirmation to prevent data loss
- Implement real-time session list updates via events
- Add API support for paginated/limit session retrieval
- Update persistence layer timestamps for accurate sorting
- Handle edge cases like active session deletion gracefully

**Non-Goals:**
- Session renaming (sessions use auto-generated titles only)
- Session search/filtering beyond chronological listing
- Multi-device session synchronization
- Session export/import functionality
- Session archival (soft delete vs hard delete)

## Decisions

### 1. Event-Driven Architecture for Real-Time Updates
**Decision**: Use an event bus/stream pattern for session lifecycle events (created/deleted).

**Rationale**: 
- Decouples the sessions list UI from the session creation/deletion logic
- Enables multiple UI components to react to the same events
- Follows existing patterns in the Flutter codebase for state management

**Alternatives considered**:
- Direct callback passing: Too tightly coupled, doesn't scale to multiple listeners
- State management library (Provider/BLoC): Overkill for this feature, adds complexity

### 2. Folder Timestamp as "Last Modified" Source
**Decision**: Update filesystem folder modification time to track session activity.

**Rationale**:
- Leverages existing filesystem metadata, no additional storage needed
- Works across all platforms (Windows, Linux, macOS)
- Sorting by mtime is efficient and doesn't require reading session contents

**Alternatives considered**:
- Store timestamp in YAML metadata: Requires reading file to get timestamp
- Separate index file: Adds complexity and sync issues

### 3. Default Limit of 100 Sessions
**Decision**: API returns max 100 sessions by default, overrideable via parameter.

**Rationale**:
- Balances performance (not loading thousands of sessions) with usability
- 100 sessions covers several months of daily use
- Apps can request fewer for pagination if needed later

**Alternatives considered**:
- No limit: Risk of performance issues with many sessions
- Lower default (20): Too restrictive for power users

### 4. Auto-Create New Session on Active Session Deletion
**Decision**: When the active session is deleted, automatically create a new empty session.

**Rationale**:
- Ensures the user always has a session to chat in
- Better UX than leaving the user in a "no session" state
- Matches the mental model of "starting fresh"

**Alternatives considered**:
- Navigate to sessions page: Interrupts user flow
- Show empty state: Requires extra user action to continue

### 5. New Session Button Replaces Delete Button
**Decision**: Replace the delete button on the chat page with a "New Session" button.

**Rationale**:
- Creating new sessions is a more common action than deleting
- Deletion moved to sessions list where context is clearer
- Reduces accidental deletions from the main chat interface

**Alternatives considered**:
- Keep both buttons: Clutters UI
- Move delete to overflow menu: Less discoverable

### 6. Session Title from First User Message
**Decision**: Auto-generate session titles from the first user message.

**Rationale**:
- Provides meaningful context without user input
- Consistent with how users mentally identify conversations
- Falls back to "New Session" if no messages exist

**Alternatives considered**:
- User-defined titles: Adds friction to session creation
- Timestamp-based titles: Less meaningful than content-based

## Risks / Trade-offs

**Risk**: Folder timestamp updates may not work on all filesystems (e.g., some network drives, FAT32 on Windows).
→ **Mitigation**: Graceful fallback to file content reading for timestamp if filesystem doesn't support mtime updates.

**Risk**: Frequent timestamp updates could cause filesystem wear on SD cards or flash storage.
→ **Mitigation**: Only update on significant events (new message, session switch), not on every minor operation.

**Risk**: Session list could become stale if events are missed.
→ **Mitigation**: Implement pull-to-refresh on sessions page as fallback mechanism.

**Risk**: Auto-creating sessions on deletion could lead to unwanted empty sessions.
→ **Mitigation**: Only auto-create if the user is currently on the chat page; if on sessions page, just show notification.

**Risk**: Large session lists (100+) could impact initial load time.
→ **Mitigation**: Implement lazy loading or virtualization in the UI; consider pagination in future iterations.

## Migration Plan

This feature adds new functionality without breaking existing behavior:

1. **Phase 1**: Deploy Engine API changes (limit parameter)
   - Backward compatible: old clients work without changes
   
2. **Phase 2**: Update Flutter app with persistence layer changes
   - Existing sessions continue to work
   - New sessions get proper timestamps
   
3. **Phase 3**: Deploy new UI (sessions page, button changes)
   - Event system enables real-time updates
   - Active session deletion handling prevents data loss

**Rollback**: Remove new UI routes, revert to original delete button behavior. Sessions data remains intact.

## Open Questions

1. Should we implement session expiration/cleanup for very old sessions (e.g., auto-delete after 1 year)?
2. Do we need to support session duplication/cloning?
3. Should deleted sessions be recoverable (trash/recycle bin) or permanently deleted?
4. What's the maximum session title length to display before truncation?
