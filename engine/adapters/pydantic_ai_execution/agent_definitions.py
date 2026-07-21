from openai import AsyncOpenAI
from pydantic_ai import Agent, DeferredToolRequests, InstrumentationSettings
from pydantic_ai.models.openai import OpenAIChatModel
from pydantic_ai.providers.openai import OpenAIProvider

from engine.constants import DEFAULT_MODEL, PROVIDER_API_BASE, PROVIDER_API_KEY

from .tools import current_date_and_time_tool, user_name_tool, web_search_tool

provider = OpenAIProvider(
    openai_client=AsyncOpenAI(
        base_url=PROVIDER_API_BASE,
        api_key=PROVIDER_API_KEY,
    )
)

default_model = OpenAIChatModel(
    model_name=DEFAULT_MODEL,
    provider=provider,
)

Agent.instrument_all(
    InstrumentationSettings(
        include_content=True, include_binary_content=True, version=5
    )
)

simple_question_agent = Agent(
    model=default_model,
    instructions="""
        You are a knowledge agent.

        Please answer questions short and precise. Use all information available.
        If in doubt don't guess, but be transparent about your uncertainty.
        Use the tools available if they are likely to improve quality of ans answer.
    """,
    tools=[user_name_tool, current_date_and_time_tool, web_search_tool],
    output_type=[str, DeferredToolRequests],
)

title_summarizer_agent = Agent(
    model=default_model,
    instructions="""
        You are an summarizer of questions.

        Based on the given input you respond quickly with just a few word that
        summarize the nature and topic of the beginning of the conversation.
    """,
)

discussion_agent = Agent(
    model=default_model,
    instructions="""
        You are a helpful assistant.

        Please answer questions short and precise. Ask if the user wants to
        know more before generating longer responses. Use all information
        available.

        Use the tools available if they are likely to improve quality of ans answer.

        Be transparent about unclear data or low confidence levels.
    """,
    tools=[user_name_tool, current_date_and_time_tool, web_search_tool],
    output_type=[str, DeferredToolRequests],
)
