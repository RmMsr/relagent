from typing import Sequence

from engine.domain.exceptions import MessageImmutabilityError
from engine.domain.models import ChatMessage


def check_final_immutability(
    prior: Sequence[ChatMessage], next_: Sequence[ChatMessage]
) -> None:
    """Universal-final guard: a final=True record must round-trip unchanged."""
    next_by_id = {msg.message_id: msg for msg in next_}
    for prev in prior:
        if not prev.final:
            continue
        new = next_by_id.get(prev.message_id)
        if new is None:
            raise MessageImmutabilityError(
                prev.message_id, "message with final=True was removed"
            )
        if new.model_dump(mode="json") != prev.model_dump(mode="json"):
            raise MessageImmutabilityError(
                prev.message_id,
                "in-memory copy differs from the stored final=True record",
            )
