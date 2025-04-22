FROM ghcr.io/astral-sh/uv:debian-slim

WORKDIR /app

EXPOSE 7860

ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y

ADD ./pyproject.toml ./uv.lock /app/

RUN uv sync --frozen --no-dev

ADD ./experiments /app/experiments

CMD [ "experiments/gradio-standalone.py" ]
