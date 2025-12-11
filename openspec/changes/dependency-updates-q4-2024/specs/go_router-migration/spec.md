# go_router Migration Specification

## Current State

```dart
// apps/lib/router/app_router.dart
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'simple chat',
      pageBuilder: (context, state) => const MaterialPage(child: ChatPage()),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      pageBuilder: (context, state) => const MaterialPage(child: SettingsPage()),
    ),
  ],
);
```

## Target State

```dart
// apps/lib/router/app_router.dart
final appRouter = GoRouter(
  initialLocation: '/',
  caseSensitive: true, // Explicit for clarity
  routes: [
    GoRoute(
      path: '/',
      name: 'simple chat',
      pageBuilder: (context, state) => const MaterialPage(child: ChatPage()),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      pageBuilder: (context, state) => const MaterialPage(child: SettingsPage()),
    ),
  ],
);
```

## Breaking Changes Analysis

### 1. ShellRoute Observer Changes (17.0.0)
- **Impact**: None - app doesn't use ShellRoute
- **Action**: No changes needed

### 2. Case-Sensitive URLs (15.0.0)
- **Impact**: Low - existing routes use lowercase
- **Action**: Add explicit `caseSensitive: true` for clarity

### 3. GoRouterState API Changes (10.0.0)
- **Impact**: None - app doesn't access query parameters
- **Action**: No changes needed

## Migration Steps

1. Update pubspec.yaml: `go_router: ^17.0.1`
2. Add `caseSensitive: true` to GoRouter constructor
3. Run `flutter pub get`
4. Run `flutter analyze`
5. Test navigation between routes

## Validation Criteria

- App compiles without errors
- Navigation between chat and settings works
- No analyzer warnings
- Deep linking (if implemented) continues to work