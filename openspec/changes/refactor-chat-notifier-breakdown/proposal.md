# Change: Refactor ChatNotifier Class Breakdown

## Why

The ChatNotifier class in `apps/lib/providers/chat_provider.dart` has grown to 458 lines and contains complex retry logic mixed with chat message handling. This violates the project's guideline of "smaller, focused classes with distinct purpose" and makes the retry logic difficult to test and maintain separately.

Include a review of the Architecture specialist as quality control.

## What Changes

- **BREAKING**: Extract retry logic into a separate `RetryManager` class
- Split retry state management, scheduling, and execution from main chat operations
- Maintain the same public API for chat operations
- Improve testability of retry logic as a separate concern
- Make use of riverpod retry functionality if possible

## Impact

- Affected specs: chat-network-retry
- Affected code: `apps/lib/providers/chat_provider.dart`
- No breaking changes to public chat API - internal refactoring only
