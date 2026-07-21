# Project Overview

This is the Relagent project. A privacy focused, self-hosted agentic AI assistant.

**Main components**:

- /engine: Python fastapi based backend. Assume `uv` version manager
- /apps: The flutter frontend (mobile, desktop, web). Assume `fvm` version manager

IMPORTANT: Check also the subproject: @engine/AGENTS.md for the python backend and @apps/AGENTS.md for Flutter frontend.

**Other relevant parts**:

- /bin: Development utilities as POSIX shell or Python scripts
- /dart_packages: Shared library for voice integration
- /docs: Project documentation and development guidelines
- /openspec: Artifacts with organized changes
- /tools/voice_catalog: Management of ASR and TTS models (Dart app)

## Project guide and rules

**MCP Tool Preference**: ALWAYS prefer MCP tools especially for flutter (dart-flutter_*) over shell commands when available. Caveat: the `dart-flutter_*` inspection tools (`get_app_logs`, `get_runtime_errors`, DTD) only attach to an app that `dart-flutter_launch_app` started. They cannot inspect an already-running or pre-compiled artifact (e.g. the web bundle the engine serves at `/app/`) — to debug one, reproduce it in dev mode via `launch_app` first, or fall back to shell tools if that is not possible.

### CRITICAL RULES

- Read existing files before writing. Don't re-read unless changed.
- Thorough in reasoning, concise in output.
- Skip files over 10KB unless required.
- Friendly, but brief technical communication.
- Use the openspec framework for all changes. Make sure the specs stay in sync.
- Regard automated quality control and AI driven testing as a high priority.

### Major design principles

- Simplicity is key. If it is easy to understand it is easy to explain and maintain.
- Globally aim for: Structure, transparency and uniformity.
- Locally aim for: Clear, intentional, self-explanatory code.
- Refactoring of unrelated code to honor principles is better than breaking them.
- Compatibility between apps and engine is guaranteed for the same version. Patch level changes should not break compatibility. Breaking changes should be named explicitly.

### Research and Discussion

- Suggest research and discuss options whenever a new paradigm is needed.

### Commit Messages

Commit frequently to build checkpoints for all increments.

**Commit message format**:

1. Start with short conventional commit summary title. Max 60 characters. Prefixed with feat;, fix: or chore:.
2. Describe only the major improvements and change patterns in one short paragraph. Add intention where context fits. Max 4 sentences. Prefeer user perspective.
3. Quickly list fixes and other relevant differences.
4. Skip insignificant details, focus on higher level impact.

**Security**: Never commit personal data, device names, IP addresses, or other dev environment details.

### Implementation Priorities

When implementing features, prioritize:

1. **Existing functionality** in app code or dependencies over custom solutions
2. **Simple implementation** over optimization or customization
3. **Obvious choices** over multiple options and competing implementations
4. **Smaller, focused classes** over complex monolithic code
5. **Readable and maintainable code** over quick results

When fixing a bug or implementing a minor logic change, write the tests first.

**Additional documents for architectural decissions:**

- **[README.md](README.md)** - Introduction and general information
- **[docs/development.md](docs/development.md)** - Development values, priorities, and environment setup
- **[docs/vision.md](docs/vision.md)** - Project vision and future direction
- **[docs/goals.md](docs/goals.md)** - Project motivation and guiding principles (privacy, open source, accessibility)
- **[apps/AGENTS.md](apps/AGENTS.md)** - Flutter app specific instructions
- **[engine/AGENTS.md](engine/AGENTS.md)** - Python engine specific instructions

## Key Principles

This project prioritizes:

- **Privacy and data sovereignty** - All processing happens locally or on user-controlled servers
- **Simplicity** - Easy to understand, minimal dependencies, readable code
- **Open source** - 100% open source with open-weight AI models
- **Accessibility** - Runnable on consumer-grade hardware

## Style

### Code Comments

- **Prefer better code** over comments - good names, structure, and small functions
- **Comments should explain why**, not what - if needed explain intention, complex logic, side effects. Keep them short and concise
- **Classes/modules** need brief explanations of responsibility
- **Avoid obvious comments** that just rephrase the code
- Assume readers have basic programming knowledge but not much time to read

### Code Formatting

- Use `.editorconfig` and linters for consistency
- Goal is **self-explanatory code**

### UI Design Principles

- **Simple, intuitive interface** - minimal user attention required
- **Hands-free usage** - primary use case, interactions work without screen visibility
- **Obvious touch areas** - reasonably sized with immediate feedback
- **Minimal distraction** - buttons show the state they will activate

### Language

Use friendly, factual and inclusive language. Avoid conflicted terms like: master, slave, one-shot, white-list

### Tool Usage Priority

**Priority Order:**

1. AI Tools (MCP Servers):
   - Always use available AI tools first (e.g., Flutter MCP tools, Dart Tooling Daemon, etc.)
   - If a MCP tool does not work, try to fix it
   - Examples: dart-flutter_*, perfetto_*, websearch_*, codesearch_*, etc.

2. Task specific utilities:
   - Use bin/generate_schema.py to get a current /openapi-schema.json before implementing any api related changes
   - Use bin/sync-dependencies.sh whenever dependencies are to be changed

3. Language Tools:
   - Use linters and static analysis tools to ensure code quality
   - Use language/framework-specific documentation tools for API lookups

4. Generic Tools:
   - Use web search only when specialized tools don't cover the need
   - Use web fetch for specific URLs provided by the user

5. Last Resort - Shell Commands:
   - Only use when NO AI/MCP tools are available for the specific task
   - Avoid shell commands for operations that have dedicated AI tool equivalents
   - Example: Use `dart-flutter_hot_reload` instead of `flutter hot reload`

## Retrospective and Self-Improving

After each bigger task or set of related changes, the agent should suggest a retrospective and reflection:

### What Worked Well?

- Note patterns that saved time or improved quality
- Celebrate good decisions that should be repeated

### What Could Be Better?

- Identify friction points, unclear docs, or missing context
- Flag code that is harder to maintain than expected

### Actionable Improvements

For each improvement opportunity, suggest and implement one of the following:

1. **AGENTS.md improvements**: If guidance was missing, misleading, or wrong, propose concrete fixes
2. **New skills**: If a repetitive workflow would benefit from automation, suggest creating a skill
3. **New commands**: If a recurring bash task could be a script, suggest adding it to `/bin`
4. **New sub-agents**: If a specialized task always requires similar research, suggest a reusable agent prompt
5. **Code improvements**: Refactor anything that caused confusion or repeated work

Keep suggestions focused and actionable. Prefer improving documentation over adding infrastructure.
