from settings import get_setting
from smolagents import LiteLLMModel, Model


def get_model(use_case: str = "") -> Model:
    model_name = get_setting("provider", "model", default=None)

    if not model_name:
        match use_case:
            case "free":
                model_name = "openrouter/qwen/qwen-2.5-coder-32b-instruct:free"
            case "multi_free":
                model_name = "openrouter/qwen/qwen2.5-vl-3b-instruct:free"

    api_base = get_setting("provider", "api_base", default=None)
    api_key = get_setting("provider", "api_key", default=None)
    print(
        f"Using model {model_name} with api_base={api_base} and api_key={api_key[:4]}****"
    )

    return LiteLLMModel(
        model_id=model_name,
        api_base=api_base,
        api_key=api_key,
    )
