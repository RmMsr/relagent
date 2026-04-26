# Project Overview

Relagent engine — agentic REST API service for agent orchestration, persistence and LLM access.

## Technology Stack

- Python 3.12+
- FastAPI for API endpoints
- Pydantic for data models
- Pydantic AI for agents and tools
- PyYAML data serialization
- portalocker for file locking

## Package Management

Uses `uv` with `pyproject.toml`:

```bash
uv sync --group dev          # Install dependencies
uv run pytest engine/tests/  # Run tests
uv run ruff check engine/    # Lint
uv run pyright engine/       # Type check
```

## Core Modules

- `adapters/`: Concrete implementations for domain ports
  - `pydantic_ai_execution/`: Pydantic AI agent execution adapter
    - `queries.py`: Orchestrates agent runs, permission resolution, and history construction
    - `tools.py`: Tool definitions (e.g. web_search)
    - `agent_definitions.py`: Agent configuration
  - `sqlite_event_store/`: Event store using a SQLite database
  - `yaml_persistence/`: Persistence layer using YAML files
  - `test_adapters.py`: In-memory adapters for testing (MemoryPersistence, StubAgentExecution)
- `api/`: FastAPI endpoints and routers
  - `v1.py`: REST API — sessions, messages, grants, approvals, continuation
  - `demo.py`: Self-contained demo server with scripted agent responses
  - `helpers.py`: Dependency injection wiring
- `domain/`: High level logic and core classes
  - `ports/`: Abstract interfaces (AgentExecution, Persistence, EventStore)
  - `models.py`: Data structures (Approval, Grant, SystemAction, ChatContext, PermissionKey)
  - `services.py`: ChatService (session/message lifecycle) and ApprovalService (grant resolution)
  - `types.py`: Enums (ApprovalType, SensitivityLevel)

## Data Storage

Per default is all data stored in `~/.local/share/org.venkado.relagent-engine/data/`.
Sessions for example in `$DATA_DIR/sessions/{session_id}/session_info.yaml`.

## Approval Sysyem

Tool calls usually require the user's approval. Approvals and grants are part of the visible
domain and handled by the PermissionService. The Execution adapter like PydanticAgentAdapter

## Development

### Architecture

- Separate modules following the hexagonal architecture with ports and adapters
- The project should be able to run in a distributed environment like Kubernetes, even if it is run in one single container for most cases

### Code Quality

- Format with Ruff
- Type-check with Pyright
