import os

from ddgs import DDGS  # type: ignore[import-untyped]
from pydantic_ai import ApprovalRequired, RunContext, Tool

from engine.log_config import get_logger

logger = get_logger(__name__)


async def user_name(ctx: RunContext) -> str:
    """Returns the current username."""
    return os.getenv("USER", "unknown")


user_name_tool = Tool(user_name)


async def current_date_and_time(ctx: RunContext) -> str:
    """Returns the current date and time in UTC."""
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).isoformat()


current_date_and_time_tool = Tool(current_date_and_time)


async def web_search(ctx: RunContext, query: str) -> list[dict[str, str]]:
    """Searches the web for the given query."""

    if not ctx.tool_call_approved:
        logger.info("Web search without existing approval")
        raise ApprovalRequired({"tool": "web_search", "query": query})

    # TODO: Expose backend to approval
    backend = (
        ctx.tool_call_metadata.get("search-backend")
        if ctx.tool_call_metadata
        else "duckduckgo"
    )
    logger.info(f"Using search backend: {backend}")

    return DDGS().text(query, backend=backend)


web_search_tool = Tool(web_search)
