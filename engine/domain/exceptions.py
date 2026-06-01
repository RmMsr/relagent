from uuid import UUID


class ProviderUnavailable(Exception):
    """The inference provider could not be reached or is not ready yet.

    Covers both a provider that is not running/unreachable and one that is up
    but still warming up (e.g. bundled llama.cpp loading model weights).
    """

    def __init__(self, reason: str):
        self.reason = reason
        super().__init__(reason)


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
    def __init__(self, session_id: UUID, trailing_message_id: UUID | None):
        self.session_id = session_id
        self.trailing_message_id = trailing_message_id
        super().__init__(
            f"Session '{session_id}' still in-flight at trailing message "
            f"{trailing_message_id}"
        )


class NoInFlightCycleToStop(Exception):
    def __init__(self, session_id: UUID):
        self.session_id = session_id
        super().__init__(f"Session '{session_id}' has no in-flight cycle to stop")


class MessageImmutabilityError(PersistenceError):
    """Raised when a write would mutate or remove a message that is final=True
    on the persistence boundary. Mirrors the universal-final invariant."""

    def __init__(self, message_id: UUID | None, reason: str):
        self.message_id = message_id
        super().__init__(
            f"Refusing to mutate final message (message_id={message_id}): {reason}"
        )
