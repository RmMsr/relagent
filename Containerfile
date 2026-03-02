FROM ghcr.io/cirruslabs/flutter:latest AS flutter-builder

RUN chown -R ubuntu:ubuntu /sdks/flutter && \
  mkdir /app && chown ubuntu:ubuntu /app

WORKDIR /app

USER ubuntu

RUN flutter precache --web

ADD apps/pubspec.yaml apps/pubspec.lock ./

RUN flutter pub get --enforce-lockfile

ADD apps/lib ./lib
ADD apps/web ./web
ADD apps/assets/config.web.json ./assets/config.json
ADD apps/assets/icon ./assets/icon
ADD apps/assets/silero_vad.onnx ./assets/

RUN flutter build web --release --base-href=/app/

FROM ghcr.io/astral-sh/uv:debian-slim

RUN useradd --home-dir=/app --no-create-home --shell=/usr/bin/sh app

RUN mkdir /app && \
  mkdir -p /app/.local/share/uv && \
  mkdir -p /app/.local/share/org.venkado.relagent-engine/data && \
  chown -R app:app /app

WORKDIR /app

EXPOSE 8000

ENV PATH="/app/.venv/bin:$PATH" \
  PYTHONUNBUFFERED=1 \
  DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
  apt-get upgrade -y && \
  apt-get install ca-certificates -y && \
  apt-get clean

ADD run/settings-template.ini /app/.local/share/org.venkado.relagent-engine/settings.ini

ADD pyproject.toml uv.lock VERSION ./

USER app

RUN uv sync --locked --no-dev --no-cache

ADD engine ./engine

COPY --chown=root:root --from=flutter-builder /app/build/web ./web

CMD [ "python", "-m", "engine.api.run" ]
