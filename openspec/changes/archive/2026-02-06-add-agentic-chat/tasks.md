## 1. Settings Extension

- [x] 1.1 Add `engineBaseUrl` field to Settings model
- [x] 1.2 Add `engineAuthType` and `engineUsername` fields for basic auth
- [x] 1.3 Add `agenticSessionId` field for session persistence
- [x] 1.4 Update settings provider with engine configuration methods
- [x] 1.5 Add engine settings section to settings page

## 2. Agentic Chat Provider

- [x] 2.1 Create `AgenticChatState` model with messages, loading, error states
- [x] 2.2 Create `AgenticChatNotifier` provider
- [x] 2.3 Implement `loadHistory()` to fetch messages from engine API
- [x] 2.4 Implement `sendMessage()` to post messages to engine API
- [x] 2.5 Implement `clearChat()` to reset session and messages
- [x] 2.6 Handle session_id generation and persistence

## 3. Engine API Service

- [x] 3.1 Create engine API service with base URL and auth configuration
- [x] 3.2 Implement `GET /messages` endpoint integration for history
- [x] 3.3 Implement `POST /messages` endpoint integration for sending
- [x] 3.4 Handle basic authentication header generation
- [x] 3.5 Add error handling and retry logic

## 4. Agentic Chat Page

- [x] 4.1 Create `AgenticChatPage` widget reusing chat UI patterns
- [x] 4.2 Integrate voice mode selector and settings navigation
- [x] 4.3 Add health check banner for engine connection issues
- [x] 4.4 Call `loadHistory()` on page initialization
- [x] 4.5 Implement clear chat with session reset

## 5. Navigation & Default Page

- [x] 5.1 Add `/agentic` route to app router
- [x] 5.2 Update default route from `/` (simple chat) to agentic chat
- [x] 5.3 Keep simple chat accessible via `/simple` route
- [x] 5.4 Update settings navigation to return to correct page

## 6. Testing & Validation

- [x] 6.1 Test engine connection with and without authentication
- [x] 6.2 Test session persistence across app restarts
- [x] 6.3 Test message history loading
- [x] 6.4 Test clear chat resets session_id
- [x] 6.5 Test voice input/output integration
