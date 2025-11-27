# Development

## Values and Priorities

This software should simple and easy to understand. It needs to be open, privacy focused and transparent to the user.

Implementation should prioritize:

- Existing functionality over custom solutions or additional dependencies
- Simple implementation over strong optimization, high customization or personal taste
- Readable and maintainable code over quick results

Formatting and consistency are important. Use .editorconfig and linters.

In order to value privacy, we have to care about security. Be explicit on tradeoffs and keep dependencies to a minimum.

### Coding style

Respect the rules of linters and editor configuration (.editorconfig).

Use line comments only if they add significant to the understandability of the code. If renaming can do the same, use better names, order or structure.

Use blocks of comments to briefly explain functionality and responsibility of classes. Skip them if the complexity is low. If functions are getting highly complex, try breaking the logic into smaller pieces.

## Environment

Typical development environment is a Linux/Unix system with:

- Podman or Docker for containerization
- Flutter SDK
- Android SDK
- Android emulator

## Design

### User Interface

In general the Interface should be simple, intuitive and require minimal attention of the user. One common use case is hands free usage. So most interactions should work without looking at the creeen. If interaction is needed the area to touch should be obvious, reasonable sized and have in immediate effect. So the user get's distraction as short as possible.

Buttons should show the state that they will activate on press.

## Debugging

In order to capture the flutter logs run the app and capture the logs:

```
cd apps
flutter run 2>&1 | tee flutter_log.txt
```
