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


_global_instrumentation_initialized: bool = False


def init_global_instrumentation():
    global _global_instrumentation_initialized
    if _global_instrumentation_initialized:
        logger.debug("Instrumentation already initialized, skipping")
        return

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

    _global_instrumentation_initialized = True

    logger.debug(
        "Tracing initialized. Endpoint: %s", endpoint if endpoint else "OTLP Default"
    )


def init_app_instrumentation(app: FastAPI):
    def server_request_hook(span: Span, scope: dict[str, Any]):
        if span and span.is_recording():
            span.set_attribute("openinference.span.kind", "CHAIN")

    def client_request_hook(span: Span, scope: dict[str, Any], message: dict[str, Any]):
        if span and span.is_recording():
            if "body" in message:
                span.set_attribute(
                    "client_request.message.body", message.get("body", "")
                )

    def client_response_hook(
        span: Span, scope: dict[str, Any], message: dict[str, Any]
    ):
        if span and span.is_recording():
            if "body" in message:
                span.set_attribute(
                    "client_response.message.body", message.get("body", "")
                )

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
