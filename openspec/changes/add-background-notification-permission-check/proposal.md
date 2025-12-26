# Change: Add notification permission check when background service starts

## Why

When continuous audio mode is activated and background service starts, notification permissions are required for proper operation. Newer Android versions have a specific interface for requesting notification permissions that should be used.

## What Changes

- Add permission check for notifications when background audio service starts
- Use Android's newer permission interface for notification requests
- Gracefully handle cases where permission is denied

## Impact

- Affected specs: background-audio-management
- Affected code: Background service initialization code