from pydantic_ai import Agent
from pydantic_ai.models.openai import OpenAIChatModel
from pydantic_ai.providers.ollama import OllamaProvider

from engine.constants import DEFAULT_MODEL, PROVIDER_API_BASE, PROVIDER_API_KEY
from engine.tools import current_time_tool, user_name_tool

provider = OllamaProvider(base_url=PROVIDER_API_BASE, api_key=PROVIDER_API_KEY)
default_model = OpenAIChatModel(
    model_name=DEFAULT_MODEL,
    provider=provider,
)

main_agent = Agent(
    model=default_model,
    instrument=True,
    tools=[user_name_tool, current_time_tool],
)
