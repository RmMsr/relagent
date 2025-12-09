# Development

## Values and Priorities

This software should simple and easy to understand. It needs to be open, privacy focused and transparent to the user.

Implementation should prioritize:

- Existing functionality over custom solutions or additional dependencies
- Simple implementation over strong optimization, high customization or personal taste
- More smaller classes with distinct purpose over complex state and logic in one class.
- Readable and maintainable code over quick results

In order to value privacy, we have to care about security. Be explicit on tradeoffs and keep dependencies to a minimum.

### Coding style

Formatting and consistency are important. Use .editorconfig and linters.

The goal is to have self-explanarory code most of the time.

Use line comments only if they add significant to the understandability of the code. If renaming can do the same, use better names, order or structure.

Classes and modules deserve an brief explanation what their functionality and responsibility is. If functions are getting highly complex, try breaking the logic into smaller pieces. Assume an reader that has a fundamental understanding of application programming. Explain the intention of complex logic, side effects or intentional specific implementation details. Leave out comments that just rephrase what the code already describes.

### Commits

Commits to main should be isolated increments and focus on one aspect.

Commits to feature branches should happen after every small increment. So we get anchor points to compare or go back to.

Commits messages should start with one short block summarizing the change. Major points can be added as list below. Main answers a commit message should give are:

- What is new and different form an user perspective
- Which bugs have been fixed
- What are the major changes if any in architecture, patterns or dependencies
- If this is part of a previous or future change, say brief what this build upon and what is next

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
