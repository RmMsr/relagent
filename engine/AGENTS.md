## Project Overview

This is the Relagent engine, an agentic service for the Relagent apps. It provides a REST API and is responsible for agent orchestration, persistence and LLM access.

- Agents and tools are created using Pydantic AI
- Data is persisted in the form of YAML files
- The API is built using FastAPI

## Technology Stack

- Python 3.12+
- Pydantic for data models
- Pydantic AI for agents and tools
- FastAPI for API endpoints
- pydantic-yaml for YAML serialization
- portalocker for file locking

## Package Management

Uses `uv` for dependency management with dependencies in `pyproject.toml`.

```bash
uv sync --group dev    # Install dependencies
uv run pytest          # Run tests
uv run ruff check engine/ tests/   # Lint
uv run pyright engine/ # Type check
```

## Key Modules

- `engine/models.py` - Pydantic data models and YAML persistence with file locking
- `engine/services.py` - Business logic and service layer
- `engine/constants.py` - Configuration constants
- `engine/agents.py` - Pydantic AI agent definitions
- `engine/tools.py` - Agent tools (username, current time)
- `engine/run.py` - FastAPI application and endpoints

## Data Storage

Session data is stored in `DATA_DIR/sessions/{session_id}/session_info.yaml` using YAML format with portalocker for concurrent write protection.

## Development

Code needs to be formatted using Ruff and quality checked using Pyright.
