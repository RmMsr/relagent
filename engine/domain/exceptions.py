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
