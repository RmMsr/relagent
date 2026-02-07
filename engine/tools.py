import os

from ddgs import DDGS  # type: ignore[import-untyped]
from pydantic_ai import RunContext, Tool


async def user_name(ctx: RunContext) -> str:
    """
    Returns the current username.
    """
    return os.getenv("USER", "unknown")


user_name_tool = Tool(user_name)


async def current_date_and_time(ctx: RunContext) -> str:
    """
    Returns the current date and time in UTC.
    """
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).isoformat()


current_date_and_time_tool = Tool(current_date_and_time)


async def web_search(ctx: RunContext, query: str) -> list[dict[str, str]]:
    """
    Searches the web for the given query.
    """

    return DDGS().text(query, backend="duckduckgo")


web_search_tool = Tool(web_search)
