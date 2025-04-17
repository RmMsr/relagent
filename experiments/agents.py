from smolagents import CodeAgent, DuckDuckGoSearchTool, Model, MultiStepAgent, load_tool

image_generation_tool = load_tool("m-ric/text-to-image", trust_remote_code=True)


def get_agent(model: Model) -> MultiStepAgent:
    return CodeAgent(
        description="Very brief answering",
        model=model,
        tools=[image_generation_tool, DuckDuckGoSearchTool()],
        add_base_tools=False,
    )
