# Change: Add Network Error Handling and Retry

## Why

Users experience poor reliability when network connectivity is unstable, with chat messages failing silently or requiring manual resubmission. The app should gracefully handle temporary network issues by implementing automatic retry logic with proper ordering and failure handling.

## What Changes

- Add network connectivity monitoring using OS internet status when available
- Implement message retry mechanism with 5-minute timeout for failed deliveries
- Ensure message order is maintained during retries
- Fail older messages if newer messages succeed while older ones are still pending
- Add user feedback for retry status and final failures

## Impact

- Affected code: `apps/lib/providers/chat_provider.dart`, `apps/lib/chat/services.dart`
- New dependencies: Network connectivity monitoring
- User experience: More reliable message delivery with automatic recovery
- No breaking changes to existing message flow