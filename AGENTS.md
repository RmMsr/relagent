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

This file provides high-level guidance for working with the Relagent codebase.

## Project Overview

Relagent ("Relatable Agentic Minion") is a privacy-focused AI assistant project consisting of:

- **Flutter mobile/desktop app** (primary focus) - Multi-platform frontend with on-device speech recognition
- **Backend server** (obsolete, being replaced) - Original Python-based chat server, no longer actively developed

The current development focus is on the Flutter app, which connects to any OpenAI-compatible API server.

## Project guide and rules

**CRITICAL RULES - Always follow these:**

### Branching Strategy
**Use branches for complex changes** - Simple isolated changes can go directly to main:

**Direct to main (single commit):**
- Documentation updates (`docs/`, `README.md`, `AGENTS.md`)
- Simple code style/formatting changes
- Typos and minor fixes
- Single-file changes with no dependencies

**Use branches for complex changes:**
- **New features**: `experiment/feature-name`
- **Bug fixes**: `fix/issue-description`
- **Refactoring**: `refactor/component-name`
- **Performance**: `perf/optimization-area`
- **Dependencies**: `deps/package-name`
- **OpenSpec changes**: `openspec/change-description`
- Any change requiring multiple commits or affecting multiple files

**Branch workflow**:
1. Create appropriate branch from main
2. Make changes with small, focused commits  
3. Test changes thoroughly
4. Merge as one commit to main when ready

### Commit Messages
- **Small, focused commits** - One aspect per commit
- **Main branch commits**: Isolated changes focusing on one aspect
- **Feature branch commits**: After every small increment for anchor points
- **Commit message format**: 
  - Start with short summary block
  - Answer: What's new for users, bugs fixed, major changes, relation to previous/future work
  - Examples: `Add prime message to initialize chat context`, `Update gitignore`, `Fix navigation issue`

**Security**: Never commit device names, IP addresses, or other dev environment details.

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

**Python (experiments/):**
- `uv sync` - Install dependencies
- No specific test framework configured

## Code Style Guidelines

**General:**
- Prefer self-explanatory code over comments
- Break complex logic into smaller functions
- Follow existing patterns in neighboring files

**Python Conventions:**
- Standard Python naming (snake_case for functions/variables)
- Minimal dependencies, focus on readability

## Language

Use friendly, inclusive language. Avoid: master, slave, one-shot, white-list

## Backend Status

The original Python-based backend in `bin/` is obsolete and being replaced. The Flutter app now connects directly to any OpenAI-compatible API server (LM Studio, Ollama, vLLM, etc.). Backend-related code and documentation should be considered deprecated.
