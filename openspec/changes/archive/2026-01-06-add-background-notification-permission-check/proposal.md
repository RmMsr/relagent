# Change: Add notification and Bluetooth permission checks when background service starts

## Why

When continuous audio mode is activated and background service starts, multiple runtime permissions are required for proper operation on newer Android versions:
- **Notification permission (Android 13+)**: Required to show foreground service notifications
- **Bluetooth permission (Android 12+)**: Required for audio routing to Bluetooth headsets

Without these runtime permission requests, the app cannot function properly on newer Android versions.

## What Changes

- Add permission checks for notifications (Android 13+) and Bluetooth (Android 12+) when background audio service starts
- Use Android's newer permission interface for runtime permission requests
- Handle multiple permission requests efficiently (request together when both needed)
- Gracefully handle cases where permissions are denied with clear error messages
- Maintain backward compatibility with pre-Android 12 devices

## Impact

- Affected specs: background-audio-management
- Affected code: Background service initialization code (MainActivity.kt)
- User experience: Users on Android 12+ will be prompted for Bluetooth permission on first use
- User experience: Users on Android 13+ will be prompted for notification permission on first use