# Project Context

## Purpose

Relagent ("Relatable Agentic Minion") is a privacy-focused AI assistant for daily use with informed privacy decisions. The primary use case is an agentic chat agent running on a self-hosted server with full control over which data is used and where it goes.

**Current State:** Proof of concept with core functionality:
- Simple AI conversation via OpenAI-compatible API
- On-device speech recognition (English, streaming ASR)
- Multi-platform support (Android, iOS, Linux)

**Vision:** Daily assistant for text and voice interaction, supporting hands-free usage with features like web search, device access, local memory/RAG, and MCP integration.

## Tech Stack

**Frontend (Active Development):**
- **Flutter** - Multi-platform framework (Android, iOS, Linux)
- **Dart** - Programming language
- **Riverpod** - State management
- **go_router** - Navigation
- **Sherpa-ONNX** - On-device streaming speech recognition
- **SharedPreferences** - Settings persistence

**Backend:**
- Any OpenAI-compatible API server (LM Studio, Lemonade-Server, vLLM, Ollama)
- Original Python-based server is **obsolete** and being phased out

**Development Tools:**
- fvm (Flutter Version Management) - Execute flutter via fvm
- Android SDK - Located in `$ANDROID_HOME`

## Project Conventions

### Code Style

**Formatting:**
- Use `.editorconfig` and linters for consistency
- Goal is self-explanatory code most of the time

**Comments:**
- Use line comments only if they add significant value to understandability
- Prefer better names, order, or structure over explanatory comments
- Classes and modules deserve a brief explanation of functionality and responsibility
- For complex functions, break logic into smaller pieces rather than adding comments
- Explain intention of complex logic, side effects, or intentional implementation details
- Avoid comments that just rephrase what code already describes
- Assume reader has fundamental understanding of application programming

**Language and Tone:**
- App and documentation should use friendly, inviting, non-offending tone
- Do not use: master, slave, one-shot, white-list

### Architecture Patterns

**State Management (Riverpod):**
- Use StateNotifierProvider pattern for state management
- Providers in `lib/providers/`
- Models in `lib/models/`
- Separation of business logic from UI
- Access state with `ref.watch()` (reactive) or `ref.read()` (one-time)
- Trigger actions with `ref.read(provider.notifier).method()`

**Code Organization:**
- Pages in `lib/pages/`
- Feature-specific code in dedicated directories (e.g., `lib/chat/`, `lib/speech_recognition/`)
- More smaller classes with distinct purpose over complex state and logic in one class
- Prioritize existing functionality over custom solutions or additional dependencies
- Simple implementation over strong optimization, high customization, or personal taste
- Readable and maintainable code over quick results

**Configuration:**
- Static config: `assets/config.json` (ASR model paths, not user-editable)
- User settings: Managed via Riverpod, persisted to SharedPreferences

### Testing Strategy

- Run tests with: `fvm flutter test`
- Manual testing logs: `flutter run 2>&1 | tee flutter_log.txt`

### Git Workflow

**Branching:**
- Main branch: `main` (use for PRs)
- Feature branches for development

**Commits:**
- Small, focused commits - each commit should focus on one aspect
- Commits to feature branches after every small increment (anchor points)
- Short summary line starting with imperative mood (Add, Update, Fix, Change)
- No period at end of summary line
- Optional bullet list for major points below summary
- Examples: `Add prime message to initialize chat context`, `Fix navigation issue`

**Commit Message Content:**
- What is new and different from a user perspective
- Which bugs have been fixed
- Major changes in architecture, patterns, or dependencies
- Context if part of previous/future changes

**Security:**
- Do not leak dev environment details (device names, IP addresses) in commits

## Domain Context

**Privacy-First AI Assistant:**
- All data processed and stored within the system (backend and frontend)
- External services require explicit user enablement/allowance
- Works offline (as long as frontend and backend can communicate)
- Self-hosted on user-controlled servers

**Speech Recognition:**
- On-device streaming ASR using Sherpa-ONNX
- Models bundled in `apps/assets/`
- Models from [k2-fsa/sherpa-onnx releases](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models)
- Currently English only (model can be easily replaced)

**User Interface Design:**
- Simple, intuitive interface requiring minimal user attention
- Support hands-free usage as a common use case
- Interactions should work without looking at screen when possible
- Touch areas should be obvious, reasonably sized, with immediate effect
- Minimize user distraction
- Buttons show the state they will activate on press

## Important Constraints

**Core Principles:**
- **Privacy and data sovereignty** - All processing happens locally or on user-controlled servers
- **Simplicity** - Easy to understand, minimal dependencies, readable code
- **Open source** - 100% open source with open-weight AI models
- **Accessibility** - Runnable on consumer-grade hardware (mid-class GPU)

**Security:**
- Privacy requires security - be explicit about tradeoffs
- Keep dependencies to a minimum
- Be careful not to introduce vulnerabilities (command injection, XSS, SQL injection, OWASP top 10)

**Current Limitations (Proof of Concept):**
- Single language support (English ASR by default)
- No multi-user support
- No authentication (assumes local IP access)

**Implementation Priorities:**
1. Existing functionality over custom solutions or additional dependencies
2. Simple implementation over strong optimization, high customization, or personal taste
3. More smaller classes with distinct purpose over complex state and logic in one class
4. Readable and maintainable code over quick results

## External Dependencies

**Required Services:**
- OpenAI-compatible API server (user-configured endpoint):
  - LM Studio (https://lmstudio.ai/)
  - Lemonade-Server (https://lemonade-server.ai/)
  - vLLM (https://github.com/vllm-project/vllm)
  - Ollama (https://github.com/ollama/ollama)

**ASR Models:**
- Sherpa-ONNX models from k2-fsa/sherpa-onnx releases
- Bundled in app assets (not fetched at runtime)

**Development Dependencies:**
- Flutter SDK (via fvm)
- Android SDK (for Android builds, located in `$ANDROID_HOME`)
- Podman or Docker (for obsolete backend, being phased out)
