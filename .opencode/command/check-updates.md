# Check for Updates

Perform a comprehensive check for available updates. Make sure to considder global AGENTS file for system specific instructions. Before any change get approval from the user.

1. Check available dart updates. Inform the user there are any updates waiting.
2. Check for flutter updates and perform update
3. Move to /apps and check for Flutter dependency updates using `flutter pub outdated`
4. Create a feature branch if we are on the main branch
5. Migrate all major versions or breaking changes one-by-one. Commit after each. Then update all remaining dependencies. Commit again.
6. Analyze the app once with `flutter analyze` to ensure nothing is broken
7. Check if there are any security advisories for software we did not update
8. Provide a summary with performed changes and outstanding updates
