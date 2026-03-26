## 1. YAML Persistence Layer - Timestamp Updates

- [x] 1.1 Add method to update session folder modification time on message save
- [x] 1.2 Add method to update session folder modification time on session access
- [x] 1.3 Implement cross-platform timestamp update (Windows, Linux, macOS)
- [x] 1.4 Add timestamp retrieval method for session sorting
- [ ] 1.5 Test timestamp updates work correctly on all platforms

## 2. Engine API - Session Listing Enhancement

- [x] 2.1 Add `limit` query parameter to session listing endpoint
- [x] 2.2 Implement default limit of 100 sessions
- [x] 2.3 Add validation for limit parameter (positive integer, max 1000)
- [x] 2.4 Update session sorting to use folder modification timestamp
- [ ] 2.5 Test API returns sessions sorted by last modified time

## 3. Event System - Session Lifecycle Events

- [x] 3.1 Define SessionEvent class with created/deleted types
- [x] 3.2 Create event bus/stream for session events
- [x] 3.3 Emit session_created event when new session is created
- [x] 3.4 Emit session_deleted event when session is deleted
- [x] 3.5 Create subscription mechanism for components to listen to events

## 4. Flutter App - Sessions Page

- [x] 4.1 Create SessionsPage widget with route
- [x] 4.2 Implement session list UI with ListView
- [x] 4.3 Add session title display with dynamic text truncation
- [x] 4.4 Add relative modification time display (e.g., "2 minutes ago")
- [x] 4.5 Implement session selection to switch to chat page
- [x] 4.6 Add delete button with confirmation dialog
- [x] 4.7 Add empty state when no sessions exist
- [x] 4.8 Visually distinguish active session in the list
- [ ] 4.9 Subscribe to session events to update list in real-time
- [x] 4.10 Add navigation to sessions page from app menu

## 5. Flutter App - Chat Page Modifications

- [x] 5.1 Replace delete button with "New Session" button in AppBar
- [x] 5.2 Implement new session creation on button tap
- [x] 5.3 Clear chat input when switching sessions
- [x] 5.4 Load session messages when switching to different session
- [x] 5.5 Update active session tracking
- [ ] 5.6 Handle active session deletion notification
- [ ] 5.7 Auto-create new session when active session is deleted
- [ ] 5.8 Show snackbar notification on active session deletion
- [x] 5.9 Update app bar title to show current session name

## 6. Integration and State Management

- [x] 6.1 Wire up session events between engine and Flutter app
- [x] 6.2 Ensure session state persists across app restarts
- [ ] 6.3 Handle edge case: user on sessions page when session created elsewhere
- [ ] 6.4 Handle edge case: session deleted while user viewing it
- [x] 6.5 Add loading states for session operations
- [x] 6.6 Add error handling for failed session operations

## 7. Testing

- [x] 7.1 Test session creation and deletion flow
- [x] 7.2 Test switching between multiple sessions
- [ ] 7.3 Test active session deletion notification
- [ ] 7.4 Test real-time updates when sessions list is visible
- [x] 7.5 Test API limit parameter functionality
- [x] 7.6 Test timestamp updates on different platforms
- [x] 7.7 Test empty state when no sessions exist
- [x] 7.8 Test navigation between sessions page and chat page
