## 1. Implementation

### Notification Permission (Android 13+)
- [x] Add notification permission check logic in background service start
- [x] Implement notification permission request using newer Android interface
- [x] Handle notification permission denied scenarios

### Bluetooth Permission (Android 12+)
- [x] Add Bluetooth permission check logic for audio routing
- [x] Implement Bluetooth permission request using runtime API
- [x] Handle Bluetooth permission denied scenarios
- [x] Build user-friendly error messages for denied permissions

### Combined Permission Handling
- [x] Request multiple permissions together when needed
- [x] Handle partial permission grants (some granted, some denied)
- [x] Update tests

## 2. Validation

- [x] Test on Android 13+ (notification permission)
- [x] Test on Android 12+ (Bluetooth permission)
- [x] Ensure backward compatibility for pre-Android 12