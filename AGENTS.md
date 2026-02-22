
# Relagent Project Guide

This file provides high-level guidance for working with the Relagent codebase.

**IMPORTANT: Check also the subproject: @engine/AGENTS.md for the python backend and @apps/AGENTS.md for Flutter frontend.**

**MCP Tool Preference**: ALWAYS prefer MCP tools especially for flutter (dart-flutter_*) over shell commands when available. See apps/AGENTS.md for complete reference table and usage guidelines.

## Project Overview

Relagent ("Relatable Agentic Minion") is a privacy-focused AI assistant project consisting of:

- **Engine** - Python-based agentic service with API and persistence
- **Flutter mobile/desktop/web app** - Multi-platform frontend with on-device speech recognition

## Project guide and rules

**CRITICAL RULES - Always follow these:**

- Use the openspec framework for all changes. Make sure the specs stay in sync.
- Regard automated quality control and AI driven testing as a priority.

Major design principles:

- Simplicity is key. If it is easy to understand it is easy to explain and maintain.
- Globally aim for: Structure, transparency and uniformity.
- Locally aim for: Clear, intentional, self-explanatory code.
- Refactoring of unrelated code to honor principles is better than breaking them.

### Commit Messages

Commit frequently to build checkpoints for all increments.

- **Commit message format**:

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

### Code Comments

- **Prefer better code** over comments - good names, structure, and small functions
- **Comments should explain why**, not what - focus on intention, complex logic, side effects
- **Classes/modules** need brief explanations of responsibility
- **Avoid obvious comments** that just rephrase the code
- Assume readers have basic programming knowledge

### Code Formatting

- Use `.editorconfig` and linters for consistency
- Goal is **self-explanatory code** most of the time

### UI Design Principles

- **Simple, intuitive interface** - minimal user attention required
- **Hands-free usage** - primary use case, interactions work without screen visibility
- **Obvious touch areas** - reasonably sized with immediate feedback
- **Minimal distraction** - buttons show the state they will activate

## Repository Structure

```text
relagent/
├── apps/                  # Flutter application (see apps/AGENTS.md for details)
├── engine/                # Python engine (see engine/CLAUDE.md for details)
├── docs/                  # Project documentation
│   ├── development.md     # Development values and priorities
│   ├── vision.md          # Project vision and use cases
│   └── goals.md           # Project goals and principles
└── README.md              # Main project readme
```

## Technology Stack

**Frontend (Active Development):**

- Flutter multi-platform app - See [apps/AGENTS.md](apps/AGENTS.md) for details

**Engine:**

- Python-based agentic service with API and persistence
- Connects to any OpenAI-compatible LLM server (LM Studio, Ollama, vLLM, etc.)

**Experiments:**

- Python prototypes in `experiments/` directory

## Getting Started

1. **For Flutter app development**: See [apps/AGENTS.md](apps/AGENTS.md) for architecture and patterns
2. **For project vision and goals**: Review docs in `docs/` directory
3. **For installation**: Follow instructions in [README.md](README.md)

## Tool Usage Priority

**Priority Order:**

1. **First Priority - AI Tools (MCP Servers):**
   - Always use available AI tools first (e.g., Flutter MCP tools, Dart Tooling Daemon, etc.)
   - These provide structured, safe, and context-aware operations
   - Examples: dart-flutter_*, perfetto_*, websearch_*, codesearch_*, etc.

2. **Project specific utilities:**
   - Use bin/generate_schema.py to get a current /openapi-schema.json before implementing any api related changes

3. **Second Priority - Specialized Tools:**
   - Use language/framework-specific documentation tools for API lookups
   - Use available skills or tasks specific sub agents
   - Use package manager tools for dependency/package discovery
   - Use project-specific tools for building, testing, linting

4. **Third Priority - Generic Tools:**
   - Use web search only when specialized tools don't cover the need
   - Use web fetch for specific URLs provided by the user

5. **Last Resort - Shell Commands:**
   - Only use when NO AI/MCP tools are available for the specific task
   - Avoid shell commands for operations that have dedicated AI tool equivalents
   - Example: Use `dart-flutter_hot_reload` instead of `flutter hot reload`

**Critical Rules:**

- **If a fitting AI tool exists, it MUST be used** - no exceptions
- **If the AI tool doesn't work, FIX IT FIRST** before looking for alternatives
- **Executing identical shell commands is a LAST RESORT** - only when no AI tool exists or can be fixed
- **ALWAYS check for available MCP servers** before falling back to generic tools
- **MCP tools provide superior safety, context awareness, and integration**

This ensures optimal use of AI capabilities while maintaining accuracy and development efficiency.

**Python Conventions:**

- Standard Python naming (snake_case for functions/variables)
- Minimal dependencies, focus on readability

## Language

Use friendly, inclusive language. Avoid: master, slave, one-shot, white-list
