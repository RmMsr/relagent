"""Demo server with deterministic agent responses.

Start to get predictable behaviour for manual testing:

    uv run python -m engine.api.demo

The server runs on the same port as the real engine and accepts the same API
calls, but uses a rule-based agent instead of calling an LLM.

Rules:
- Messages starting with "search " trigger a web_search approval request.
- After approval grant + continue, the agent returns a canned search result.
- After approval reject + continue, the agent explains it cannot search.
- Everything else gets an ELIZA-style response.
"""

import re

from fastapi import FastAPI

from engine.adapters.test_adapters import MemoryPersistence
from engine.api.helpers import (
    dependency_approval_service,
    dependency_chat_service,
)
from engine.api.v1 import api_router
from engine.constants import VERSION
from engine.domain.models import (
    Approval,
    AssistantMessage,
    ChatContext,
    SystemAction,
)
from engine.domain.ports.agent_execution import AgentExecution
from engine.domain.services import ApprovalService, ChatService
from engine.domain.types import ApprovalType
from engine.log_config import get_logger, init_logging

logger = get_logger(__name__)


# ---------------------------------------------------------------------------
# Demo agent
# ---------------------------------------------------------------------------


class DemoAgentExecution(AgentExecution):
    """Rule-based agent for demo and integration testing.

    Inspects the user query and context state to produce deterministic
    responses without calling an LLM.
    """

    def __init__(self, approval_service: ApprovalService) -> None:
        self.approval_service = approval_service

    async def run_basic_query(
        self,
        context: ChatContext,
        query: str | None = None,
        session_id=None,
    ) -> AssistantMessage | SystemAction:
        # Continue after approval decision
        if query is None:
            return self._handle_continue(context, session_id=session_id)

        # New message starting with "search " → check grants, then approval
        if query.lower().startswith("search "):
            search_query = query[len("search ") :].strip()
            approval = Approval(
                type=ApprovalType.OutgoingData,
                component="web_search",
                purpose=f"Searching the web for '{search_query}'",
                sensitivity=context.sensitivity_level,
                allowed_parameters={"query": search_query},
            )
            _, missing = self.approval_service.get_satisfied_and_missing_approvals(
                required_approvals=[approval], session_id=session_id
            )
            if missing:
                return SystemAction(approvals=missing)
            return AssistantMessage(
                content=f"Here are the search results for '{search_query}': "
                "Nothing notable found in recent news."
            )

        # Everything else → ELIZA-style
        return AssistantMessage(content=self._eliza_respond(query))

    async def generate_title(self, query: str) -> str:
        return query[:50]

    # -- ELIZA-style responses ------------------------------------------------

    _REFLECTIONS = {
        "i": "you",
        "me": "you",
        "my": "your",
        "mine": "yours",
        "am": "are",
        "i'm": "you're",
        "i'd": "you'd",
        "i've": "you've",
        "i'll": "you'll",
        "you": "I",
        "your": "my",
        "yours": "mine",
        "you're": "I'm",
        "you've": "I've",
        "you'll": "I'll",
        "myself": "yourself",
        "yourself": "myself",
    }

    _PATTERNS: list[tuple[re.Pattern[str], list[str]]] = [
        (
            re.compile(r"\bhello\b|\bhi\b|\bhey\b", re.I),
            [
                "Hello! How are you feeling today?",
                "Hi there! What's on your mind?",
                "Hey! What would you like to talk about?",
            ],
        ),
        (
            re.compile(r"i need (.*)", re.I),
            [
                "Why do you need {0}?",
                "Would it really help you to get {0}?",
                "Are you sure you need {0}?",
            ],
        ),
        (
            re.compile(r"why don'?t you (.*)", re.I),
            [
                "Do you really think I don't {0}?",
                "Perhaps eventually I will {0}.",
                "Do you really want me to {0}?",
            ],
        ),
        (
            re.compile(r"i can'?t (.*)", re.I),
            [
                "How do you know you can't {0}?",
                "Perhaps you could {0} if you tried.",
                "What would it take for you to {0}?",
            ],
        ),
        (
            re.compile(r"i (?:am|'m) (.*)", re.I),
            [
                "How long have you been {0}?",
                "How do you feel about being {0}?",
                "Do you enjoy being {0}?",
            ],
        ),
        (
            re.compile(r"how (.*)", re.I),
            [
                "How do you suppose?",
                "What answer would please you most?",
                "What do you think?",
            ],
        ),
        (
            re.compile(r"because (.*)", re.I),
            [
                "Is that the real reason?",
                "What other reasons come to mind?",
                "Does that reason apply to anything else?",
            ],
        ),
        (
            re.compile(r"(.*)\bsorry\b(.*)", re.I),
            [
                "No need to apologize.",
                "Apologies are not necessary. What are you feeling?",
            ],
        ),
        (
            re.compile(r"(.*)\b(?:think|believe)\b(.*)", re.I),
            [
                "Tell me more about that thought.",
                "Do you doubt that?",
                "What makes you think so?",
            ],
        ),
        (
            re.compile(r"(.*)\?$", re.I),
            [
                "Why do you ask that?",
                "What do you think the answer is?",
                "Perhaps the answer lies within yourself.",
            ],
        ),
    ]

    _FALLBACKS = [
        "Tell me more.",
        "That's interesting. Can you elaborate?",
        "I see. Please go on.",
        "How does that make you feel?",
        "Why do you say that?",
        "Can you tell me more about that?",
    ]

    def _reflect(self, text: str) -> str:
        words = text.lower().split()
        return " ".join(self._REFLECTIONS.get(w, w) for w in words)

    def _eliza_respond(self, text: str) -> str:
        for pattern, responses in self._PATTERNS:
            match = pattern.search(text)
            if match:
                groups = [self._reflect(g.rstrip("?.!")) for g in match.groups()]
                response = responses[hash(text) % len(responses)]
                return response.format(*groups) if groups else response

        return self._FALLBACKS[hash(text) % len(self._FALLBACKS)]

    def _handle_continue(
        self, context: ChatContext, session_id=None
    ) -> AssistantMessage | SystemAction:
        """Respond after an approval grant or rejection."""
        last_system_action = None
        for msg in reversed(context.messages):
            if isinstance(msg, SystemAction) and msg.approvals:
                last_system_action = msg
                break

        if last_system_action is None:
            return AssistantMessage(content="Nothing to continue.")

        # Re-check open approvals against current grants
        open_approvals = [
            a for a in last_system_action.approvals if a.granted is not True
        ]
        if open_approvals:
            _, still_missing = (
                self.approval_service.get_satisfied_and_missing_approvals(
                    required_approvals=open_approvals, session_id=session_id
                )
            )
            # Only truly rejected (user explicitly rejected, not just missing grant)
            rejected = [a for a in last_system_action.approvals if a.granted is False]
            if rejected and not still_missing:
                # User rejected some but granted the rest
                pass
            elif still_missing:
                rejected_by_user = [a for a in still_missing if a.granted is False]
                if rejected_by_user:
                    return AssistantMessage(
                        content=(
                            "I don't have access to current information "
                            "without web search. "
                            "I can only answer based on my existing knowledge."
                        )
                    )
                # Still waiting for grants
                return SystemAction(approvals=still_missing)

        # All approved — produce a canned search result
        search_query = ""
        for approval in last_system_action.approvals:
            search_query = str(approval.allowed_parameters.get("query", ""))
            break

        return AssistantMessage(
            content=f"Here are the search results for '{search_query}': "
            "Nothing notable found in recent news."
        )


# ---------------------------------------------------------------------------
# App factory
# ---------------------------------------------------------------------------


def create_demo_app() -> FastAPI:
    """Build a FastAPI app wired with DemoAgentExecution."""
    persistence = MemoryPersistence()
    approval_service = ApprovalService(persistence_repository=persistence)
    chat_service = ChatService(
        persistence_repository=persistence,
        agent_execution=DemoAgentExecution(approval_service=approval_service),
        approval_service=approval_service,
    )

    demo_app = FastAPI(version=VERSION, title="Relagent Demo")
    demo_app.include_router(api_router, prefix="/api/v1")
    demo_app.dependency_overrides[dependency_chat_service] = lambda: chat_service
    demo_app.dependency_overrides[dependency_approval_service] = lambda: (
        approval_service
    )

    @demo_app.get("/health")
    async def health():
        return "ok"

    logger.info("Demo server ready")
    return demo_app


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn

    from engine.settings import get_setting, get_setting_int

    init_logging()

    app = create_demo_app()

    print(f"\n  Relagent Demo Server v{VERSION}")
    print('  "search <query>" triggers approval flow')
    print("  Everything else gets an ELIZA-style response\n")

    uvicorn.run(
        app,
        host=get_setting("server", "address", default="127.0.0.1"),
        port=get_setting_int("server", "port", default=8000),
    )
