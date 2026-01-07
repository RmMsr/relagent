# Change: Improve Separation of Concerns

## Why

Several components in the codebase mix UI logic with business logic, and business logic with infrastructure concerns. This makes testing difficult and violates the single responsibility principle.

## What Changes

- Separate UI state management from business logic in providers
- Isolate infrastructure concerns (SharedPreferences, secure storage) from domain logic
- Create clear boundaries between chat operations and retry logic
- Improve dependency injection patterns for better testability

## Impact

- Affected specs: user-settings, chat-network-retry
- Affected code: Various providers and service classes
- Breaking changes to public API are ok if it improves architecture or
  simplicity
