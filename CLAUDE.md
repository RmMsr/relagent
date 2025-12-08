# Relagent Project Guide

This file provides high-level guidance for working with the Relagent codebase.

## Project Overview

Relagent ("Relatable Agentic Minion") is a privacy-focused AI assistant project consisting of:

- **Flutter mobile/desktop app** (primary focus) - Multi-platform frontend with on-device speech recognition
- **Backend server** (obsolete, being replaced) - Original Python-based chat server, no longer actively developed

The current development focus is on the Flutter app, which connects to any OpenAI-compatible API server.

## Project guide and rules

For all planning and coding please respect the following documents:

- **[README.md](README.md)** - Introduction and general information
- **[docs/development.md](docs/development.md)** - Development values, priorities, and environment setup
- **[docs/vision.md](docs/vision.md)** - Project vision and future direction
- **[docs/goals.md](docs/goals.md)** - Project motivation and guiding principles (privacy, open source, accessibility)
- **[apps/CLAUDE.md](apps/CLAUDE.md)** App specific documentation

## Key Principles

This project prioritizes:

- **Privacy and data sovereignty** - All processing happens locally or on user-controlled servers
- **Simplicity** - Easy to understand, minimal dependencies, readable code
- **Open source** - 100% open source with open-weight AI models
- **Accessibility** - Runnable on consumer-grade hardware

## Development Guidelines

### Implementation Priorities

When implementing features, prioritize:

- **Existing functionality** over custom solutions or additional dependencies
- **Simple implementation** over strong optimization, high customization or personal taste
- **More smaller classes** with distinct purpose over complex state and logic in one class
- **Readable and maintainable code** over quick results

Privacy requires security. Be explicit about tradeoffs and keep dependencies to a minimum.

### Commit Messages

- **Small, focused commits** - Each commit should focus on one aspect
- **Short summary line** - Start with imperative mood (Add, Update, Fix, Change)
- **No period** at end of summary line
- **Optional bullet list** - Major points can be added below the summary

Examples: `Add prime message to initialize chat context`, `Update gitignore`, `Fix navigation issue`

Also make sure not to leak any details about the dev environment like device names or ip addresses.

### Code Comments

- Use **line comments only if they add significant value** to understandability
- **Prefer better names, order or structure** over explanatory comments
- **Classes and modules** deserve a brief explanation of functionality and responsibility
- For complex functions, **break logic into smaller pieces** rather than adding comments
- **Explain intention** of complex logic, side effects, or intentional implementation details
- **Avoid comments** that just rephrase what code already describes
- Assume reader has fundamental understanding of application programming

### Code Formatting

- Use `.editorconfig` and linters for consistency
- Goal is **self-explanatory code** most of the time

### UI Design Principles

- **Simple, intuitive interface** requiring minimal user attention
- Support **hands-free usage** as a common use case
- Interactions should work **without looking at screen** when possible
- Touch areas should be **obvious, reasonably sized, with immediate effect**
- Minimize user distraction
- **Buttons show the state they will activate** on press

## Repository Structure

```
relagent/
├── apps/                    # Flutter application
│   ├── lib/                # Dart source code
│   │   ├── main.dart      # App entry point
│   │   ├── providers/     # Riverpod state management
│   │   ├── pages/         # UI screens
│   │   ├── chat/          # Chat functionality
│   │   └── speech_recognition/  # Sherpa-ONNX ASR integration
│   ├── assets/            # App assets (config, ASR models)
│   └── CLAUDE.md          # Detailed Flutter app documentation
├── docs/                   # Project documentation
│   ├── development.md     # Development values and priorities
│   ├── vision.md          # Project vision and use cases
│   └── goals.md           # Project goals and principles
├── bin/                    # Backend scripts (obsolete)
└── README.md              # Main project readme
```

## Technology Stack

**Frontend (Active Development):**

- **Flutter** - Multi-platform framework (Android, iOS, Linux)
- **Riverpod** - State management
- **go_router** - Navigation
- **Sherpa-ONNX** - On-device streaming speech recognition
- **SharedPreferences** - Settings persistence

**Backend (Obsolete):**

- Python-based server (being phased out)
- Any OpenAI-compatible server can be used instead (LM Studio, Ollama, vLLM, etc.)

## Getting Started

1. **For Flutter app development**: See [apps/CLAUDE.md](apps/CLAUDE.md) for architecture and patterns
2. **For project vision and goals**: Review docs in `docs/` directory
3. **For installation**: Follow instructions in [README.md](README.md)

## Language

App and documentation should be in a friendly, inviting and non-offensing tone. Do not use: master, slave, one-shot, white-list

## Backend Status

The original Python-based backend in `bin/` is obsolete and being replaced. The Flutter app now connects directly to any OpenAI-compatible API server (LM Studio, Ollama, vLLM, etc.). Backend-related code and documentation should be considered deprecated.
