from uuid import UUID


class PersistenceError(Exception):
    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


class SessionNotFound(PersistenceError):
    def __init__(self, session_id: UUID):
        self.session_id = session_id
        super().__init__(f"No usable session with id '{session_id}' found")


class ChatContextNotFound(PersistenceError):
    def __init__(self, session_id: UUID):
        self.session_id = session_id
        super().__init__(f"Chat context for session '{session_id}' not found")


class SessionInFlightTimeout(Exception):
    def __init__(self, session_id: UUID, trailing_sequence_id: int | None):
        self.session_id = session_id
        self.trailing_sequence_id = trailing_sequence_id
        super().__init__(
            f"Session '{session_id}' still in-flight at trailing sequence "
            f"{trailing_sequence_id}"
        )


class NoInFlightCycleToStop(Exception):
    def __init__(self, session_id: UUID):
        self.session_id = session_id
        super().__init__(f"Session '{session_id}' has no in-flight cycle to stop")


class MessageImmutabilityError(PersistenceError):
    """Raised when a write would mutate or remove a message that is final=True
    on the persistence boundary. Mirrors the universal-final invariant."""

    def __init__(self, sequence_id: int | None, reason: str):
        self.sequence_id = sequence_id
        super().__init__(
            f"Refusing to mutate final message (sequence_id={sequence_id}): {reason}"
        )
