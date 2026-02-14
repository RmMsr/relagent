## 1. Convert package imports in services/

- [x] 1.1 Update `apps/lib/services/api_health_check.dart`: change `package:relagent/chat/auth_detection.dart` to `/chat/auth_detection.dart`
- [x] 1.2 Update `apps/lib/services/api_health_check.dart`: change `package:relagent/models/settings.dart` to `/models/settings.dart`
- [x] 1.3 Update `apps/lib/services/api_health_check.dart`: change `package:relagent/utils/logger.dart` to `/utils/logger.dart`

## 2. Convert package imports in main.dart

- [x] 2.1 Update `apps/lib/main.dart`: change `package:relagent/models/app_info.dart` to `/models/app_info.dart`

## 3. Convert package imports in chat/

- [x] 3.1 Update `apps/lib/chat/auth_detection.dart`: change `package:relagent/models/settings.dart` to `/models/settings.dart`
- [x] 3.2 Update `apps/lib/chat/services.dart`: change `package:relagent/chat/models.dart` to `/chat/models.dart`
- [x] 3.3 Update `apps/lib/chat/services.dart`: change `package:relagent/models/settings.dart` to `/models/settings.dart`
- [x] 3.4 Update `apps/lib/chat/widgets.dart`: change `package:relagent/chat/models.dart` to `/chat/models.dart`

## 4. Verify

- [x] 4.1 Run Dart static analysis to verify no import errors
- [x] 4.2 Verify all files compile without errors
