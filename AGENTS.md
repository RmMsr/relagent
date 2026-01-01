<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# Relagent Project Guide

**IMPORTANT: When working on Flutter app code, also read @apps/AGENTS.md for Flutter-specific patterns, MCP tools, and architectural guidelines.**

**MCP Tool Preference**: ALWAYS prefer MCP tools especially for flutter (dart-flutter_*) over shell commands when available. See apps/AGENTS.md for complete reference table and usage guidelines.

This file provides high-level guidance for working with the Relagent codebase.

## Project Overview

Relagent ("Relatable Agentic Minion") is a privacy-focused AI assistant project consisting of:

- **Flutter mobile/desktop app** (primary focus) - Multi-platform frontend with on-device speech recognition
- **Backend server** (obsolete, being replaced) - Original Python-based chat server, no longer actively developed

The current development focus is on the Flutter app, which connects to any OpenAI-compatible API server.

## Project guide and rules

**CRITICAL RULES - Always follow these:**

### Branching Strategy
**Use git worktree workflow**: This projects includes scripts to simplify
creation of branches and merging them back on a local scenarion.

To start a branch:
1. Run `bin/start-worktree.sh`
2. Change into the newly created directory
3. Make your changes using small iterative commits

When done, squash all into main:
1. Run `bin/apply-worktree.sh`
2. Change into the main worktree directory.
3. You see a single new commit on top of the main branch.

This is a substitute for classic branches and pull requests and optimized for a
single user and high level of automation.

### Commit Messages
Commit frequently to build checkpoints for all increments.
- **Commit message format**:
  - Start with short summary title.
  - Answer: What's new for users, bugs fixed, major changes, relation to previous/future work
  - Examples: `Add prime message to initialize chat context`, `Update gitignore`, `Fix navigation issue`
  - Leave out insignificant details.

**Security**: Never commit personal data, device names, IP addresses, or other dev environment details.

### Implementation Priorities
When implementing features, prioritize:
1. **Existing functionality** over custom solutions
2. **Simple implementation** over optimization or customization
3. **Smaller, focused classes** over complex monolithic code
4. **Readable and maintainable code** over quick results

**Additional documents for reference:**
- **[README.md](README.md)** - Introduction and general information
- **[docs/development.md](docs/development.md)** - Development values, priorities, and environment setup
- **[docs/vision.md](docs/vision.md)** - Project vision and future direction
- **[docs/goals.md](docs/goals.md)** - Project motivation and guiding principles (privacy, open source, accessibility)
- **[apps/AGENTS.md](apps/AGENTS.md)** - Flutter app specific documentation

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

```
relagent/
├── apps/                    # Flutter application (see apps/AGENTS.md for details)
├── docs/                   # Project documentation
│   ├── development.md     # Development values and priorities
│   ├── vision.md          # Project vision and use cases
│   └── goals.md           # Project goals and principles
├── bin/                    # Backend scripts (obsolete)
├── experiments/            # Python experiments and prototypes
└── README.md              # Main project readme
```

## Technology Stack

**Frontend (Active Development):**
- Flutter multi-platform app - See [apps/AGENTS.md](apps/AGENTS.md) for details

**Backend (Obsolete):**
- Python-based server (being phased out)
- Any OpenAI-compatible server can be used instead (LM Studio, Ollama, vLLM, etc.)

**Experiments:**
- Python prototypes in `experiments/` directory

## Getting Started

1. **For Flutter app development**: See [apps/AGENTS.md](apps/AGENTS.md) for architecture and patterns
2. **For project vision and goals**: Review docs in `docs/` directory
3. **For installation**: Follow instructions in [README.md](README.md)

## Build/Lint/Test Commands

**Flutter (apps/):**
- See [apps/AGENTS.md](apps/AGENTS.md) for Flutter-specific commands
- **IMPORTANT**: Always address warnings, deprecations, and analysis issues as part of any iteration
- Run `flutter analyze` and fix all issues before completing changes

**Python (experiments/):**
- `uv sync` - Install dependencies
- No specific test framework configured

## Code Style Guidelines

**General:**
- Prefer self-explanatory code over comments
- Break complex logic into smaller functions
- Follow existing patterns in neighboring files

## Tool Usage Priority

**AI TOOLS (MCP SERVERS) ALWAYS TAKE PRECEDENCE OVER SHELL COMMANDS**

**Priority Order:**

1. **First Priority - AI Tools (MCP Servers):**
   - Always use available AI tools first (e.g., Flutter MCP tools, Dart Tooling Daemon, etc.)
   - These provide structured, safe, and context-aware operations
   - Examples: dart-flutter_*, perfetto_*, websearch_*, codesearch_*, etc.

2. **Second Priority - Specialized Tools:**
   - Use language/framework-specific documentation tools for API lookups
   - Use package manager tools for dependency/package discovery
   - Use project-specific tools for building, testing, linting

3. **Third Priority - Generic Tools:**
   - Use web search only when specialized tools don't cover the need
   - Use web fetch for specific URLs provided by the user

4. **Last Resort - Shell Commands:**
   - Only use when NO AI/MCP tools are available for the specific task
   - Avoid shell commands for operations that have dedicated AI tool equivalents
   - Example: Use `dart-flutter_hot_reload` instead of `flutter hot reload`

**Critical Rules:**
- **If a fitting AI tool exists, it MUST be used** - no exceptions
- **If the AI tool doesn't work, FIX IT FIRST** before looking for alternatives
- **NEVER use shell commands when AI tools exist** for the same functionality
- **Executing identical shell commands is a LAST RESORT** - only when no AI tool exists or can be fixed
- **ALWAYS check for available MCP servers** before falling back to generic tools
- **MCP tools provide superior safety, context awareness, and integration**

This ensures optimal use of AI capabilities while maintaining accuracy and development efficiency.

**Python Conventions:**
- Standard Python naming (snake_case for functions/variables)
- Minimal dependencies, focus on readability

## Language

Use friendly, inclusive language. Avoid: master, slave, one-shot, white-list

## Backend Status

The original Python-based backend in `bin/` is obsolete and being replaced. The Flutter app now connects directly to any OpenAI-compatible API server (LM Studio, Ollama, vLLM, etc.). Backend-related code and documentation should be considered deprecated.
