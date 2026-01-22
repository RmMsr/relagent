import os

from pydantic_ai import RunContext, Tool


async def user_name(ctx: RunContext) -> str:
    """
    Returns the current username.
    """
    return os.getenv("USER", "unknown")


user_name_tool = Tool(user_name)


async def current_time(ctx: RunContext) -> str:
    """
    Returns the current time in UTC.
    """
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).isoformat()


current_time_tool = Tool(current_time)
