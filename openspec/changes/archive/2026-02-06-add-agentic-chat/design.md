## Context

The Relagent engine provides a persistent chat backend with agentic capabilities. The Flutter app needs a dedicated page to connect to this engine, separate from the existing simple chat that connects to any OpenAI-compatible API.

## Goals / Non-Goals

**Goals:**
- Connect to Relagent engine via configurable URL
- Support basic HTTP authentication
- Persist session_id locally to resume conversations
- Fetch message history from engine on app load
- Provide same voice input/output experience as simple chat

**Non-Goals:**
- Implement engine-side features (tool use, MCP) - those are backend concerns
- Replace simple chat entirely - keep it as an alternative
- Implement advanced auth (OAuth, tokens) - basic auth is sufficient for now

## Decisions

**Session Management:**
- Generate UUID for `session_id` on first launch
- Store in SharedPreferences alongside other settings
- Clear and regenerate on explicit "clear chat" action
- Include `session_id` in all API requests

**API Design:**
- `GET /messages?session_id={id}` - Fetch history for session
- `POST /messages` with body `{session_id, content}` - Send message
- Basic auth via `Authorization: Basic base64(username:password)` header

**State Architecture:**
- New `AgenticChatProvider` separate from existing `ChatProvider`
- Reuse chat UI widgets (`ChatHistory`, `ChatInput`, message bubbles)
- Reuse voice-related providers (recording, TTS, audio coordinator)

**Navigation:**
- Agentic chat at `/` (default)
- Simple chat at `/simple`
- Both accessible; engine connection issues show helpful banner

## Risks / Trade-offs

**Risk:** Engine offline shows empty chat
→ **Mitigation:** Health check banner with "Configure Engine" action

**Risk:** Session loss if SharedPreferences cleared
→ **Acceptable:** User can start fresh conversation; no critical data lost

**Trade-off:** Separate provider vs extending ChatProvider
→ **Decision:** Separate provider for cleaner separation of concerns; engine API differs from OpenAI API

## Open Questions

None - decisions made.

## Future Changes

**History Pagination with Message Sequence Numbers:**
- Add sequence numbers to messages for reliable ordering
- Implement paginated history fetch (`GET /messages?session_id={id}&after_seq={n}&limit={n}`)
- Load more on scroll-up in chat history

**Session Listing and Switching:**
- Engine endpoint to list sessions (`GET /sessions`)
- Session metadata (title, last activity, message count)
- App UI for session list and switching between conversations
