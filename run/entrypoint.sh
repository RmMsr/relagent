#!/usr/bin/env sh

set -e

if [ "${PROVIDER_BUNDLED}" = "true" ]; then
    : "${PROVIDER_DEFAULT_MODEL:=unsloth/gemma-4-E2B-it-GGUF:Q4_K_M}"
    PROVIDER_API_BASE="http://127.0.0.1:8080/v1"
    export PROVIDER_API_BASE

    # shellcheck disable=SC2086
    /opt/llama/llama-server \
        --host 127.0.0.1 \
        --port 8080 \
        --parallel 1 \
        --ctx-size 2048 \
        --flash-attn on \
        --cache-type-k q8_0 \
        --cache-type-v q8_0 \
        --cors-origins localhost \
        -hf "${PROVIDER_DEFAULT_MODEL}" \
        $PROVIDER_ADDITIONAL_ARGS \
        &
fi

exec python -m engine.api.run
