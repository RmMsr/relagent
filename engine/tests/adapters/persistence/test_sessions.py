import uuid

import pytest

from engine.domain.exceptions import SessionNotFound
from engine.domain.models import SessionInfo
from engine.domain.ports.persistence import Persistence


class TestSessionPersistence:
    def test_save_and_load_session_round_trip(self, persistence: Persistence):
        session = SessionInfo(title="Test Session")

        persistence.save_session(session)
        loaded = persistence.load_session(session_id=session.session_id)

        assert loaded.session_id == session.session_id
        assert loaded.title == session.title

    def test_load_session_not_found(self, persistence: Persistence):
        non_existent_id = uuid.uuid4()

        with pytest.raises(SessionNotFound) as exc_info:
            persistence.load_session(session_id=non_existent_id)

        assert exc_info.value.session_id == non_existent_id
