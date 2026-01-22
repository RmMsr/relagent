FROM ghcr.io/astral-sh/uv:debian-slim

RUN useradd --home-dir=/app --no-create-home --shell=/usr/bin/sh app

RUN apt-get update && apt-get install -y && apt-get clean

RUN mkdir /app && chown app:app /app

WORKDIR /app

EXPOSE 8000

ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1

ADD ./pyproject.toml ./uv.lock /app/

USER app

RUN uv sync --locked --no-dev --no-cache

ADD ./engine /app/engine

CMD [ "python", "-m", "engine.run" ]
