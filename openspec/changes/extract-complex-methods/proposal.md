# Change: Extract Complex Methods

## Why

Several methods in the codebase have grown complex and handle multiple concerns, making them difficult to understand, test, and maintain. This violates the project's guideline of breaking complex logic into smaller functions.

Include a review of the Architecture specialist as quality control.

## What Changes

- Extract error handling logic from `_handleSendError` in chat_provider.dart
- Extract retry scheduling logic from `_scheduleRetry` in chat_provider.dart
- Extract backoff calculation into a separate utility function
- Extract HealthCheckBanner widget from chat_page.dart
- Simplify method signatures and improve readability

## Impact

- Affected specs: chat-network-retry, chat-history
- Affected code: `apps/lib/providers/chat_provider.dart`, `apps/lib/pages/chat_page.dart`
- Breaking changes to public API are ok if it improves architecture or
  simplicity
