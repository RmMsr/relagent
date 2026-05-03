from typing import Sequence

from engine.domain.exceptions import MessageImmutabilityError
from engine.domain.models import ChatMessage


def check_final_immutability(
    prior: Sequence[ChatMessage], next_: Sequence[ChatMessage]
) -> None:
    """Universal-final guard: a final=True record must round-trip unchanged."""
    next_by_seq = {
        msg.sequence_id: msg for msg in next_ if msg.sequence_id is not None
    }
    for prev in prior:
        if not prev.final or prev.sequence_id is None:
            continue
        new = next_by_seq.get(prev.sequence_id)
        if new is None:
            raise MessageImmutabilityError(
                prev.sequence_id, "message with final=True was removed"
            )
        if new.model_dump(mode="json") != prev.model_dump(mode="json"):
            raise MessageImmutabilityError(
                prev.sequence_id,
                "in-memory copy differs from the stored final=True record",
            )
