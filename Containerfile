FROM ghcr.io/astral-sh/uv:debian-slim

RUN useradd --home-dir=/app --no-create-home --shell=/usr/bin/sh app

RUN mkdir /app && chown app:app /app

WORKDIR /app

EXPOSE 8000

ENV PATH="/app/.venv/bin:$PATH" \
  PYTHONUNBUFFERED=1 \
  DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
  apt-get upgrade -y && \
  apt-get install ca-certificates -y && \
  apt-get clean

ADD ./pyproject.toml ./uv.lock ./VERSION /app/

USER app

RUN uv sync --locked --no-dev --no-cache

ADD ./engine /app/engine

CMD [ "python", "-m", "engine.api.run" ]
