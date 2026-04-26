# Development

## Values and Priorities

This software should simple and easy to understand. It needs to be open, privacy focused and transparent to the user.

Implementation should prioritize:

- Existing functionality over custom solutions or additional dependencies
- Simple implementation over strong optimization, high customization or personal taste
- More smaller classes with distinct purpose over complex state and logic in one class.
- Readable and maintainable code over quick results

In order to value privacy, we have to care about security. Be explicit on tradeoffs and keep dependencies to a minimum.

## Style and workflows

### Coding style

Formatting and consistency are important. Use .editorconfig and linters.

The goal is to have self-explanarory code most of the time.

Use line comments only if they add significant to the understandability of the code. If renaming can do the same, use better names, order or structure.

Classes and modules deserve an brief explanation what their functionality and responsibility is. If functions are getting highly complex, try breaking the logic into smaller pieces. Assume an reader that has a fundamental understanding of application programming. Explain the intention of complex logic, side effects or intentional specific implementation details. Leave out comments that just rephrase what the code already describes.

Test functions do not need docstrings. The test name should be sufficient. Inline comments follow the same rule as production code.

### Commits

Commits to main should be isolated changes and focus on one aspect.

Commits to feature branches should happen after every small increment. So we get anchor points to compare or go back to.

Conventional commits are a good baseline. Commit messages should start with one short block summarizing the change. Major points can be added as list below. Main answers a commit message should give are:

- What is new and different form an user perspective
- What are the major changes if any in architecture, patterns or dependencies
- Which bugs have been fixed
- If this is part of a previous or future change, say brief what this build upon and what is next

Leave out insignificant details.

### Branches

All changes should happen in branches. For local development git worktrees are very useful to isolate changes into separate worktrees.

To start a branch:

1. Run `bin/start-worktree.sh`
2. Change into the newly created directory
3. Make your changes using small iterative commits

When done, squash all into main:

1. Run `bin/apply-worktree.sh`
2. Change into the main worktree directory.
3. You see a single new commit on top of the main branch.

## Architecture and patterns

Simple and predictable solutions are most important. Things should do what they say and not more. When there is complicated logic needed it should be contained locally with clear boundaries and expectations.

Follow common practices for architecture, organization and library usage.

Keep the number of class members small. Functions should be short and have only one effect. Break apart classes, structured and functions early.

Exceptions can be made, but need to be clearly stated as such.

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

**Preferred Method**: Use Flutter MCP tools for debugging:
- `dart-flutter_get_runtime_errors` - Get Flutter-specific runtime errors
- `dart-flutter_hot_reload` - Apply code changes and test immediately
- `dart-flutter_analyze_files` - Check for code issues

**Alternative Method**: Capture full logs with shell commands:

```
cd apps
flutter run 2>&1 | tee flutter.log
```
