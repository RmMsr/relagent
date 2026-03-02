import json
from typing import Any

from fastapi import FastAPI
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import (  # type: ignore[reportUnknownVariableType]
    FastAPIInstrumentor,
)
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.semconv.attributes import service_attributes
from opentelemetry.trace import Span

from engine.constants import SERVICE_NAME
from engine.logging import get_logger
from engine.settings import get_setting

logger = get_logger(__name__)


def init_global_instrumentation():
    service_name = SERVICE_NAME
    resource = Resource.create(
        {
            service_attributes.SERVICE_NAME: service_name,
        }
    )

    tracer_provider = TracerProvider(resource=resource)
    trace.set_tracer_provider(tracer_provider)

    endpoint = get_setting("instrumentation", "otlp_endpoint")

    if endpoint and get_setting(
        "instrumentation", "gen_ai_collector_enabled", default=False
    ):
        # Add the OpenInference span processor for Phoenix to capture pydantic_ai traces
        logger.debug("Adding OpenInference span processor for Pydantic AI")

        from openinference.instrumentation.pydantic_ai import (
            OpenInferenceSpanProcessor,
        )

        tracer_provider.add_span_processor(OpenInferenceSpanProcessor())

    if endpoint:
        exporter = OTLPSpanExporter(endpoint=endpoint)
        tracer_provider.add_span_processor(SimpleSpanProcessor(exporter))

    logger.debug(
        "Tracing initialized. Endpoint: %s", endpoint if endpoint else "OTLP Default"
    )


def init_app_instrumentation(app: FastAPI):
    def server_request_hook(span: Span, scope: dict[str, Any]):
        span.set_attribute("trace.source", "server_request")
        if span and span.is_recording():
            span.set_attribute("openinference.span.kind", "CHAIN")

    def client_request_hook(
        span: Span, scope: dict[str, Any], message: dict[str, bytes]
    ):
        span.set_attribute("trace.source", "client_request")
        if span and span.is_recording():
            if (b"content-type", b"application/json") in scope.get("headers", []):
                body_raw = message.get("body", b"")
                try:
                    body = json.loads(body_raw)
                    for key, value in _flatten_json(
                        body, "client_request.body"
                    ).items():
                        span.set_attribute(key, value)
                except json.JSONDecodeError:
                    body_raw = body_raw.decode("utf-8", errors="replace")
                    span.set_attribute("client_request.body_raw", body_raw[:500])

    def client_response_hook(
        span: Span, scope: dict[str, Any], message: dict[str, Any]
    ):
        span.set_attribute("trace.source", "client_response")
        if span and span.is_recording():
            if (b"content-type", b"application/json") in scope.get("headers", []):
                body_raw = message.get("body", b"")
                try:
                    body = json.loads(body_raw)
                    for key, value in _flatten_json(
                        body, "client_response.body"
                    ).items():
                        span.set_attribute(key, value)
                except json.JSONDecodeError:
                    body_raw = body_raw.decode("utf-8", errors="replace")
                    span.set_attribute("client_response.body_raw", body_raw[:500])

    FastAPIInstrumentor.instrument_app(
        app,
        server_request_hook=server_request_hook,
        client_request_hook=client_request_hook,
        client_response_hook=client_response_hook,
        http_capture_headers_server_request=[
            "user-agent",
            "content-type",
        ],
        http_capture_headers_server_response=["content-type"],
        excluded_urls="/health",
    )


def _flatten_json(data: Any, prefix: str = "", max_depth: int = 5) -> dict[str, Any]:
    """Flatten nested JSON into dot-notation attributes."""
    if max_depth <= 0 or data is None:
        return {}
    if isinstance(data, dict):
        result = {}
        for key, value in data.items():
            new_key = f"{prefix}.{key}" if prefix else key
            if isinstance(value, dict) and max_depth > 1:
                result.update(_flatten_json(value, new_key, max_depth - 1))
            elif isinstance(value, list) and max_depth > 1:
                for i, item in enumerate(value[:10]):
                    if isinstance(item, dict):
                        result.update(
                            _flatten_json(item, f"{new_key}[{i}]", max_depth - 1)
                        )
                    else:
                        result[f"{new_key}[{i}]"] = item
            else:
                if isinstance(value, (str, int, float, bool)):
                    result[new_key] = value
                else:
                    result[new_key] = str(value)
        return result
    if isinstance(data, list):
        return (
            {prefix: json.dumps(data)[:500]} if len(str(data)) > 500 else {prefix: data}
        )
    if isinstance(data, (str, int, float, bool)):
        return {prefix: data}
    return {prefix: str(data)[:500]}
