from uuid import UUID


class SessionNotFound(Exception):
    def __init__(self, session_id: UUID):
        self.session_id = session_id
        super().__init__(f"Session '{session_id}' not found")


class SessionCorrupted(Exception):
    def __init__(self, session_id: UUID):
        self.session_id = session_id
        super().__init__(f"Session '{session_id}' is corrupted or not compatible")
