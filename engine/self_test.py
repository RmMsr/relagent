import time
from enum import Enum
from uuid import uuid4

from pydantic import BaseModel

from engine.adapters.yaml_persistence.yaml_adapter import YamlPersistenceAdapter
from engine.constants import DATA_DIR
from engine.domain.models import ChatContext, SessionInfo
from engine.domain.ports.agent_execution import AgentExecution


class SelfTestStatus(str, Enum):
    ok = "ok"
    warning = "warning"
    error = "error"


class SelfTestResult(BaseModel):
    name: str
    status: SelfTestStatus
    detail: str | None = None


async def check_llm_response_time(execution: AgentExecution) -> SelfTestResult:
    """Run two minimal LLM requests; evaluate second against 1-second threshold."""
    times: list[float] = []
    for _ in range(2):
        try:
            start = time.monotonic()
            await execution.generate_title("ping")
            times.append(time.monotonic() - start)
        except Exception as e:
            return SelfTestResult(
                name="LLM response time",
                status=SelfTestStatus.error,
                detail=f"{e} — check the engine's provider settings",
            )

    first, second = times
    detail = f"cold start {first:.3f}s, subsequent {second:.3f}s"
    status = SelfTestStatus.ok if second <= 1.0 else SelfTestStatus.warning
    return SelfTestResult(name="LLM response time", status=status, detail=detail)


async def check_llm_tool_calling(execution: AgentExecution) -> SelfTestResult:
    """Verify LLM can invoke the current_date_and_time tool."""
    try:
        result = await execution.run_basic_query(
            context=ChatContext(), query="What is the current time?"
        )
        tool_calls = 0
        model_name = ""
        if result.stats:
            tool_calls = result.stats.tool_calls_count or 0
            model_name = result.stats.answering_model_name or ""
        if tool_calls > 0:
            return SelfTestResult(
                name="LLM tool calling",
                status=SelfTestStatus.ok,
                detail=f"invoked {tool_calls} tool call(s) using '{model_name}'",
            )
        return SelfTestResult(
            name="LLM tool calling",
            status=SelfTestStatus.error,
            detail=f"no tools were invoked, tried model '{model_name}' — try another default model in the engine settings",
        )
    except Exception as e:
        return SelfTestResult(
            name="LLM tool calling",
            status=SelfTestStatus.error,
            detail=f"{e} — check the engine's provider settings",
        )


async def check_data_persistence(execution: AgentExecution) -> SelfTestResult:
    """Create and delete an ephemeral session to verify persistence."""
    adapter = YamlPersistenceAdapter(DATA_DIR)
    session_id = uuid4()
    start = time.monotonic()
    try:
        adapter.save_session(SessionInfo(session_id=session_id, title="selftest"))
    except Exception as e:
        return SelfTestResult(
            name="Engine data persistence",
            status=SelfTestStatus.error,
            detail=f"Save failed: {e} — check the engine's data_dir setting",
        )
    try:
        adapter.delete_session(session_id)
    except Exception as e:
        return SelfTestResult(
            name="Engine data persistence",
            status=SelfTestStatus.error,
            detail=f"Delete failed (stray ID: {session_id}): {e} — check the engine's data_dir setting",
        )
    elapsed = time.monotonic() - start
    return SelfTestResult(
        name="Engine data persistence",
        status=SelfTestStatus.ok,
        detail=f"saved and deleted a session in {elapsed:.3f}s",
    )


async def run_all_tests(execution: AgentExecution) -> list[SelfTestResult]:
    results: list[SelfTestResult] = []
    for test in [
        check_llm_response_time,
        check_llm_tool_calling,
        check_data_persistence,
    ]:
        try:
            results.append(await test(execution=execution))
        except Exception as e:
            results.append(
                SelfTestResult(
                    name=test.__name__,
                    status=SelfTestStatus.error,
                    detail=f"Unexpected error: {e}",
                )
            )
    return results
