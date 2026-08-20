FROM ghcr.io/cirruslabs/flutter:3.41.9 AS flutter-builder

RUN chown -R ubuntu:ubuntu /sdks/flutter && \
    mkdir -p /dart_packages/sherpa_voice && \
    chown ubuntu:ubuntu /dart_packages/sherpa_voice && \
    mkdir /app && \
    chown ubuntu:ubuntu /app

USER ubuntu

RUN flutter precache --web

ADD dart_packages/sherpa_voice/pubspec.yaml /dart_packages/sherpa_voice/
ADD dart_packages/sherpa_voice/lib /dart_packages/sherpa_voice/lib
ADD dart_packages/agentic_client/pubspec.yaml /dart_packages/agentic_client/
ADD dart_packages/agentic_client/lib /dart_packages/agentic_client/lib

WORKDIR /app

ADD apps/pubspec.yaml apps/pubspec.lock ./

RUN flutter pub get --enforce-lockfile

ADD apps/lib ./lib
ADD apps/web ./web
ADD apps/assets/config.web.json ./assets/config.json
ADD apps/assets/icon ./assets/icon
ADD apps/assets/silero_vad.onnx apps/assets/voice-models.json ./assets/

RUN flutter build web --release --wasm --base-href=/app/

FROM ghcr.io/astral-sh/uv:debian-slim AS app

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

ADD run/settings-template.ini \
    /app/.local/share/org.venkado.relagent-engine/settings.ini

ADD run/entrypoint.sh /app/entrypoint.sh

ADD pyproject.toml uv.lock VERSION ./

USER app

RUN uv sync --locked --no-dev --no-cache

ADD engine ./engine

COPY --chown=root:root --from=flutter-builder /app/build/web ./web

CMD [ "/app/entrypoint.sh" ]

FROM ghcr.io/ggml-org/llama.cpp:server AS llama

FROM app AS bundled

USER root

COPY --from=llama /app/ /opt/llama/

ENV LD_LIBRARY_PATH=/opt/llama PROVIDER_BUNDLED=true

RUN apt-get update && \
    apt-get install libssl3 libgomp1 -y && \
    apt-get clean

USER app

RUN mkdir -p /app/.cache/llama.cpp/

FROM app AS slim
