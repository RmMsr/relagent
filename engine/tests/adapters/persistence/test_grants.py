from datetime import datetime, timezone
from uuid import uuid4

import time_machine

from engine.domain.models import Grant
from engine.domain.ports.persistence import Persistence
from engine.domain.types import ApprovalType, SensitivityLevel


def _grant(**kwargs) -> Grant:
    defaults: dict = dict(
        approval_type=ApprovalType.OutgoingData,
        max_sensitivity=SensitivityLevel.OpenInformation,
    )
    return Grant(**{**defaults, **kwargs})


class TestGlobalGrants:
    def test_round_trip(self, persistence: Persistence):
        grant = _grant()
        persistence.add_global_grant(grant)
        assert persistence.load_active_global_grants() == [grant]

    def test_empty_when_no_grants(self, persistence: Persistence):
        assert persistence.load_active_global_grants() == []

    def test_multiple_grants_all_returned(self, persistence: Persistence):
        g1 = _grant(component="web_search")
        g2 = _grant(component="email_send")
        persistence.add_global_grant(g1)
        persistence.add_global_grant(g2)
        loaded = persistence.load_active_global_grants()
        assert len(loaded) == 2 and g1 in loaded and g2 in loaded

    @time_machine.travel("2026-06-01 12:00:00+00:00")
    def test_non_expiring_grant_returned(self, persistence: Persistence):
        grant = _grant(expires_at=None)
        persistence.add_global_grant(grant)
        assert persistence.load_active_global_grants() == [grant]

    @time_machine.travel("2026-06-01 12:00:00+00:00")
    def test_future_expiry_grant_returned(self, persistence: Persistence):
        grant = _grant(expires_at=datetime(2026, 6, 1, 13, 0, 0, tzinfo=timezone.utc))
        persistence.add_global_grant(grant)
        assert persistence.load_active_global_grants() == [grant]

    @time_machine.travel("2026-06-01 12:00:00+00:00")
    def test_past_expiry_grant_excluded(self, persistence: Persistence):
        grant = _grant(expires_at=datetime(2026, 6, 1, 11, 0, 0, tzinfo=timezone.utc))
        persistence.add_global_grant(grant)
        assert persistence.load_active_global_grants() == []

    def test_duplicate_scope_replaces_existing(self, persistence: Persistence):
        original = _grant(
            expires_at=datetime(2026, 6, 1, 12, 0, 0, tzinfo=timezone.utc)
        )
        updated = _grant(expires_at=None)
        persistence.add_global_grant(original)
        persistence.add_global_grant(updated)
        loaded = persistence.load_active_global_grants()
        assert loaded == [updated]

    def test_different_scope_not_deduplicated(self, persistence: Persistence):
        g1 = _grant(component="web_search")
        g2 = _grant(component="email_send")
        persistence.add_global_grant(g1)
        persistence.add_global_grant(g2)
        assert len(persistence.load_active_global_grants()) == 2


class TestSessionGrants:
    def test_round_trip(self, persistence: Persistence):
        session_id = uuid4()
        grant = _grant()
        persistence.add_session_grant(session_id, grant)
        assert persistence.load_active_session_grants(session_id) == [grant]

    def test_empty_when_no_grants(self, persistence: Persistence):
        assert persistence.load_active_session_grants(uuid4()) == []

    def test_isolated_from_other_sessions(self, persistence: Persistence):
        session_a = uuid4()
        session_b = uuid4()
        persistence.add_session_grant(session_a, _grant())
        assert persistence.load_active_session_grants(session_b) == []

    def test_not_visible_as_global(self, persistence: Persistence):
        persistence.add_session_grant(uuid4(), _grant())
        assert persistence.load_active_global_grants() == []

    @time_machine.travel("2026-06-01 12:00:00+00:00")
    def test_future_expiry_grant_returned(self, persistence: Persistence):
        session_id = uuid4()
        grant = _grant(expires_at=datetime(2026, 6, 1, 13, 0, 0, tzinfo=timezone.utc))
        persistence.add_session_grant(session_id, grant)
        assert persistence.load_active_session_grants(session_id) == [grant]

    @time_machine.travel("2026-06-01 12:00:00+00:00")
    def test_past_expiry_grant_excluded(self, persistence: Persistence):
        session_id = uuid4()
        grant = _grant(expires_at=datetime(2026, 6, 1, 11, 0, 0, tzinfo=timezone.utc))
        persistence.add_session_grant(session_id, grant)
        assert persistence.load_active_session_grants(session_id) == []

    def test_duplicate_scope_replaces_existing(self, persistence: Persistence):
        session_id = uuid4()
        original = _grant(
            expires_at=datetime(2026, 6, 1, 12, 0, 0, tzinfo=timezone.utc)
        )
        updated = _grant(expires_at=None)
        persistence.add_session_grant(session_id, original)
        persistence.add_session_grant(session_id, updated)
        loaded = persistence.load_active_session_grants(session_id)
        assert loaded == [updated]

    def test_deduplication_is_session_scoped(self, persistence: Persistence):
        session_a = uuid4()
        session_b = uuid4()
        grant = _grant()
        persistence.add_session_grant(session_a, grant)
        persistence.add_session_grant(session_b, grant)
        assert len(persistence.load_active_session_grants(session_a)) == 1
        assert len(persistence.load_active_session_grants(session_b)) == 1
