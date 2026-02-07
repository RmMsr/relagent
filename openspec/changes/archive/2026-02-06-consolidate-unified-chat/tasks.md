# Tasks: Backend Selection with Separate Chat Pages

## 1. Settings Model Updates
- [x] 1.1 Add `ChatBackendType` enum (openAiCompatible, relagentEngine)
- [x] 1.2 Add `selectedBackend` field to Settings class
- [x] 1.3 Update Settings.defaults() with default backend (relagentEngine - main use case)
- [x] 1.4 Update copyWith, toJson, fromJson for new field

## 2. Settings UI Updates
- [x] 2.1 Add backend selection section in settings page (SegmentedButton)
- [x] 2.2 Add explanatory text for each backend option
- [x] 2.3 Group URL/auth fields under their respective backend sections (optional enhancement)

## 3. Router Updates
- [x] 3.1 Update splash_page.dart to check `selectedBackend` setting
- [x] 3.2 Route to `AgenticChatPage` when relagentEngine selected
- [x] 3.3 Route to `ChatPage` when openAiCompatible selected

## 4. Verification
- [x] 4.1 Run flutter analyze and fix issues
- [x] 4.2 Test switching between backends in settings
- [x] 4.3 Verify each chat page works with its backend
