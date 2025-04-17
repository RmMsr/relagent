import os

from smolagents import LiteLLMModel, Model

MODEL = os.getenv("MODEL")
API_BASE = os.getenv("API_BASE")


def get_model(use_case: str = "") -> Model:
    model_name = MODEL

    if not model_name:
        match use_case:
            case "free":
                model_name = "openrouter/qwen/qwen-2.5-coder-32b-instruct:free"
            case "multi_free":
                model_name = "openrouter/qwen/qwen2.5-vl-3b-instruct:free"

    return LiteLLMModel(
        model_id=model_name,
        api_base=API_BASE,
    )
