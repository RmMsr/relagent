from uuid import UUID, uuid4

import pytest

from engine.domain.models import (
    Approval,
    ChatContext,
    Grant,
    PermissionKey,
    SystemAction,
    UserMessage,
)
from engine.domain.ports.persistence import Persistence
from engine.domain.services import ApprovalService
from engine.domain.types import ApprovalType, SensitivityLevel


def _approval(**kwargs) -> Approval:
    defaults = dict(
        type=ApprovalType.OutgoingData,
        component="web_search",
        purpose="Searching the web",
        max_sensitivity=SensitivityLevel.OpenInformation,
    )
    return Approval(**{**defaults, **kwargs})


def _grant(**kwargs) -> Grant:
    defaults = dict(
        approval_type=ApprovalType.OutgoingData,
        component="web_search",
        max_sensitivity=SensitivityLevel.OpenInformation,
    )
    return Grant(**{**defaults, **kwargs})


def _key(**kwargs) -> PermissionKey:
    defaults = dict(
        approval_type=ApprovalType.OutgoingData,
        component="web_search",
        allowed_parameters=(),
        wildcard_parameter=None,
        sensitivity=SensitivityLevel.OpenInformation,
    )
    return PermissionKey(**{**defaults, **kwargs})


def _load_approval(
    persistence: Persistence, session_id: UUID, approval_id: UUID
) -> Approval:
    context = persistence.load_context(session_id)
    for msg in context.messages:
        if isinstance(msg, SystemAction):
            for approval in msg.approvals:
                if approval.id == approval_id:
                    return approval
    raise KeyError(approval_id)


def _context_with_approval(*approvals: Approval) -> ChatContext:
    """ChatContext with a user message followed by a SystemAction requesting the given approvals."""
    return ChatContext(
        messages=[
            UserMessage(content="Do a web search"),
            SystemAction(approvals=list(approvals)),
        ]
    )


class TestGetSatisfiedAndMissingApprovals:
    def test_no_approvals_returns_empty(self, approval_service: ApprovalService):
        satisfied, missing = approval_service.get_satisfied_and_missing_approvals([])
        assert satisfied == []
        assert missing == []

    def test_no_grants_all_approvals_missing(self, approval_service: ApprovalService):
        approvals = [_approval(), _approval(component="email_send")]
        satisfied, missing = approval_service.get_satisfied_and_missing_approvals(
            approvals
        )
        assert satisfied == []
        assert len(missing) == 2

    def test_exact_grant_match_satisfies_approval(
        self, approval_service: ApprovalService
    ):
        approval_service.register_global_grant(_grant())
        satisfied, missing = approval_service.get_satisfied_and_missing_approvals(
            [_approval()]
        )
        assert len(satisfied) == 1
        assert missing == []

    def test_mixed_approvals_split_correctly(self, approval_service: ApprovalService):
        approval_service.register_global_grant(_grant(component="web_search"))
        approvals = [
            _approval(component="web_search"),
            _approval(component="email_send"),
        ]

        satisfied, missing = approval_service.get_satisfied_and_missing_approvals(
            approvals
        )

        assert len(satisfied) == 1
        assert satisfied[0][0].component == "web_search"
        assert len(missing) == 1
        assert missing[0].component == "email_send"

    def test_global_grant_satisfies_any_session(
        self, approval_service: ApprovalService
    ):
        approval_service.register_global_grant(_grant())
        session_id = uuid4()

        satisfied, missing = approval_service.get_satisfied_and_missing_approvals(
            [_approval()], session_id=session_id
        )

        assert len(satisfied) == 1
        assert missing == []

    def test_session_grant_satisfies_own_session(
        self, approval_service: ApprovalService
    ):
        session_id = uuid4()
        approval_service.register_session_grant(session_id, _grant())

        satisfied, missing = approval_service.get_satisfied_and_missing_approvals(
            [_approval()], session_id=session_id
        )

        assert len(satisfied) == 1
        assert missing == []

    def test_session_grant_does_not_satisfy_other_session(
        self, approval_service: ApprovalService
    ):
        session_a = uuid4()
        session_b = uuid4()
        approval_service.register_session_grant(session_a, _grant())

        satisfied, missing = approval_service.get_satisfied_and_missing_approvals(
            [_approval()], session_id=session_b
        )

        assert satisfied == []
        assert len(missing) == 1

    def test_session_grant_not_used_without_session_id(
        self, approval_service: ApprovalService
    ):
        session_id = uuid4()
        approval_service.register_session_grant(session_id, _grant())

        satisfied, missing = approval_service.get_satisfied_and_missing_approvals(
            [_approval()]
        )

        assert satisfied == []
        assert len(missing) == 1

    def test_higher_sensitivity_grant_satisfies_lower_sensitivity_approval(
        self, approval_service: ApprovalService
    ):
        approval_service.register_global_grant(
            _grant(max_sensitivity=SensitivityLevel.Confidential)
        )

        satisfied, missing = approval_service.get_satisfied_and_missing_approvals(
            [_approval(max_sensitivity=SensitivityLevel.OpenInformation)]
        )

        assert len(satisfied) == 1
        assert missing == []

    def test_lower_sensitivity_grant_does_not_satisfy_higher_sensitivity_approval(
        self, approval_service: ApprovalService
    ):
        approval_service.register_global_grant(
            _grant(max_sensitivity=SensitivityLevel.OpenInformation)
        )

        satisfied, missing = approval_service.get_satisfied_and_missing_approvals(
            [_approval(sensitivity=SensitivityLevel.Confidential)]
        )

        assert satisfied == []
        assert len(missing) == 1


class TestRegisterGlobalGrant:
    def test_is_retrievable(self, approval_service: ApprovalService):
        grant = _grant()
        approval_service.register_global_grant(grant)
        assert grant in approval_service.active_global_grants()

    def test_replaces_same_key(self, approval_service: ApprovalService):
        grant_a = _grant()
        grant_b = _grant()  # same permission_key
        approval_service.register_global_grant(grant_a)
        approval_service.register_global_grant(grant_b)
        assert len(approval_service.active_global_grants()) == 1


class TestRegisterSessionGrant:
    def test_is_retrievable(self, approval_service: ApprovalService):
        session_id = uuid4()
        grant = _grant()
        approval_service.register_session_grant(session_id, grant)
        assert grant in approval_service.active_session_grants(session_id)

    def test_not_visible_in_other_session(self, approval_service: ApprovalService):
        session_a, session_b = uuid4(), uuid4()
        approval_service.register_session_grant(session_a, _grant())
        assert approval_service.active_session_grants(session_b) == []

    def test_not_visible_as_global(self, approval_service: ApprovalService):
        approval_service.register_session_grant(uuid4(), _grant())
        assert approval_service.active_global_grants() == []

    def test_replaces_same_key(self, approval_service: ApprovalService):
        grant_a = _grant()
        grant_b = _grant()  # same permission_key
        session_id = uuid4()
        approval_service.register_session_grant(session_id, grant_a)
        approval_service.register_session_grant(session_id, grant_b)
        assert len(approval_service.active_session_grants(session_id)) == 1


class TestRejectSessionApprovals:
    def test_reject_single_approval(
        self,
        approval_service: ApprovalService,
        persistence: Persistence,
    ):
        session_id = uuid4()
        approval = _approval()
        persistence.save_context(session_id, _context_with_approval(approval))

        approval_service.reject_session_approvals(
            session_id=session_id, approvals=[approval.id]
        )

        assert _load_approval(persistence, session_id, approval.id).granted is False

    def test_reject_multiple_approvals_at_once(
        self,
        approval_service: ApprovalService,
        persistence: Persistence,
    ):
        session_id = uuid4()
        approval_a = _approval(component="web_search")
        approval_b = _approval(component="email_send")
        persistence.save_context(
            session_id, _context_with_approval(approval_a, approval_b)
        )

        approval_service.reject_session_approvals(
            session_id=session_id, approvals=[approval_a.id, approval_b.id]
        )

        assert _load_approval(persistence, session_id, approval_a.id).granted is False
        assert _load_approval(persistence, session_id, approval_b.id).granted is False

    def test_reject_partial_approvals(
        self,
        approval_service: ApprovalService,
        persistence: Persistence,
    ):
        session_id = uuid4()
        approval_a = _approval(component="web_search")
        approval_b = _approval(component="email_send")
        persistence.save_context(
            session_id, _context_with_approval(approval_a, approval_b)
        )

        approval_service.reject_session_approvals(
            session_id=session_id, approvals=[approval_a.id]
        )

        assert _load_approval(persistence, session_id, approval_a.id).granted is False
        assert _load_approval(persistence, session_id, approval_b.id).granted is None

    def test_reject_unknown_approval_raises_error(
        self,
        approval_service: ApprovalService,
        persistence: Persistence,
    ):
        session_id = uuid4()
        approval = _approval()
        persistence.save_context(session_id, _context_with_approval(approval))

        with pytest.raises(ValueError):
            approval_service.reject_session_approvals(
                session_id=session_id,
                approvals=[uuid4()],  # unknown ID
            )

    def test_reject_idempotent(
        self,
        approval_service: ApprovalService,
        persistence: Persistence,
    ):
        session_id = uuid4()
        approval = _approval()
        persistence.save_context(session_id, _context_with_approval(approval))

        approval_service.reject_session_approvals(
            session_id=session_id, approvals=[approval.id]
        )
        # Second call with same ID must not raise
        approval_service.reject_session_approvals(
            session_id=session_id, approvals=[approval.id]
        )

        assert _load_approval(persistence, session_id, approval.id).granted is False

    def test_rejections_isolated_per_session(
        self,
        approval_service: ApprovalService,
        persistence: Persistence,
    ):
        session_a, session_b = uuid4(), uuid4()
        approval_a = _approval()
        approval_b = _approval()
        persistence.save_context(session_a, _context_with_approval(approval_a))
        persistence.save_context(session_b, _context_with_approval(approval_b))

        approval_service.reject_session_approvals(
            session_id=session_a, approvals=[approval_a.id]
        )

        assert _load_approval(persistence, session_b, approval_b.id).granted is None


class TestGenerateMatchingPermissionKeys:
    def test_base_key_always_included(self, approval_service: ApprovalService):
        key = _key()
        result = approval_service.generate_matching_permission_keys(key)
        assert key in result

    def test_higher_sensitivity_keys_included(self, approval_service: ApprovalService):
        key = _key(sensitivity=SensitivityLevel.OpenInformation)
        result = approval_service.generate_matching_permission_keys(key)
        sensitivities = {k.sensitivity for k in result}
        assert sensitivities == set(SensitivityLevel)

    def test_lower_sensitivity_keys_not_included(
        self, approval_service: ApprovalService
    ):
        key = _key(sensitivity=SensitivityLevel.Internal)
        result = approval_service.generate_matching_permission_keys(key)
        sensitivities = {k.sensitivity for k in result}
        assert sensitivities == {SensitivityLevel.Internal}

    def test_personal_sensitivity_expands_upward_only(
        self, approval_service: ApprovalService
    ):
        key = _key(sensitivity=SensitivityLevel.Personal)
        result = approval_service.generate_matching_permission_keys(key)
        sensitivities = {k.sensitivity for k in result}
        assert sensitivities == {
            SensitivityLevel.Personal,
            SensitivityLevel.Confidential,
            SensitivityLevel.Internal,
        }

    def test_no_parameters_produces_no_wildcard_variants(
        self, approval_service: ApprovalService
    ):
        key = _key(allowed_parameters=())
        result = approval_service.generate_matching_permission_keys(key)
        assert all(k.wildcard_parameter is None for k in result)

    def test_single_parameter_produces_wildcard_variant(
        self, approval_service: ApprovalService
    ):
        key = _key(
            allowed_parameters=(("query", "news"),),
            sensitivity=SensitivityLevel.Specific,
        )
        result = approval_service.generate_matching_permission_keys(key)
        wildcard_keys = {
            k.wildcard_parameter for k in result if k.wildcard_parameter is not None
        }
        assert wildcard_keys == {"query"}

    def test_wildcard_variant_removes_wildcarded_field_from_parameters(
        self, approval_service: ApprovalService
    ):
        key = _key(
            allowed_parameters=(("query", "news"),),
            sensitivity=SensitivityLevel.Specific,
        )
        result = approval_service.generate_matching_permission_keys(key)
        wildcard_key = next(k for k in result if k.wildcard_parameter == "query")
        assert wildcard_key.allowed_parameters == ()

    def test_wildcard_variant_keeps_other_parameters(
        self, approval_service: ApprovalService
    ):
        key = _key(
            allowed_parameters=(("provider", "ddg"), ("query", "news")),
            sensitivity=SensitivityLevel.Specific,
        )
        result = approval_service.generate_matching_permission_keys(key)
        wildcard_on_query = next(k for k in result if k.wildcard_parameter == "query")
        assert wildcard_on_query.allowed_parameters == (("provider", "ddg"),)

    def test_two_parameters_produce_two_wildcard_variants(
        self, approval_service: ApprovalService
    ):
        key = _key(
            allowed_parameters=(("provider", "ddg"), ("query", "news")),
            sensitivity=SensitivityLevel.Specific,
        )
        result = approval_service.generate_matching_permission_keys(key)
        wildcard_fields = {k.wildcard_parameter for k in result if k.wildcard_parameter}
        assert wildcard_fields == {"query", "provider"}

    def test_exact_key_present_at_all_accepted_sensitivity_levels(
        self, approval_service: ApprovalService
    ):
        key = _key(
            allowed_parameters=(("query", "news"),),
            sensitivity=SensitivityLevel.Personal,
        )
        result = approval_service.generate_matching_permission_keys(key)
        exact_keys = {k for k in result if k.wildcard_parameter is None}
        exact_sensitivities = {k.sensitivity for k in exact_keys}
        assert exact_sensitivities == {
            SensitivityLevel.Personal,
            SensitivityLevel.Confidential,
            SensitivityLevel.Internal,
        }

    def test_wildcard_variant_present_at_all_accepted_sensitivity_levels(
        self, approval_service: ApprovalService
    ):
        key = _key(
            allowed_parameters=(("query", "news"),),
            sensitivity=SensitivityLevel.Personal,
        )
        result = approval_service.generate_matching_permission_keys(key)
        wildcard_sensitivities = {
            k.sensitivity for k in result if k.wildcard_parameter == "query"
        }
        assert wildcard_sensitivities == {
            SensitivityLevel.Personal,
            SensitivityLevel.Confidential,
            SensitivityLevel.Internal,
        }


class TestWildcardGrants:
    def test_wildcard_grant_satisfies_approval_with_any_query(
        self, approval_service: ApprovalService
    ):
        approval_service.register_global_grant(_grant(wildcard_parameter="query"))
        satisfied, missing = approval_service.get_satisfied_and_missing_approvals(
            [_approval(allowed_parameters={"query": "breaking news"})]
        )
        assert len(satisfied) == 1
        assert missing == []

    def test_wildcard_grant_satisfies_different_query_values(
        self, approval_service: ApprovalService
    ):
        approval_service.register_global_grant(_grant(wildcard_parameter="query"))
        approvals = [
            _approval(allowed_parameters={"query": "first query"}),
            _approval(allowed_parameters={"query": "second query"}),
        ]
        satisfied, missing = approval_service.get_satisfied_and_missing_approvals(
            approvals
        )
        assert len(satisfied) == 2
        assert missing == []

    def test_wildcard_grant_respects_other_constrained_parameters(
        self, approval_service: ApprovalService
    ):
        # Grant allows any query but only for provider=ddg
        approval_service.register_global_grant(
            _grant(
                allowed_parameters={"provider": "ddg"},
                wildcard_parameter="query",
            )
        )
        satisfied, missing = approval_service.get_satisfied_and_missing_approvals(
            [_approval(allowed_parameters={"query": "news", "provider": "bing"})]
        )
        assert satisfied == []
        assert len(missing) == 1

    def test_wildcard_grant_does_not_satisfy_different_component(
        self, approval_service: ApprovalService
    ):
        approval_service.register_global_grant(
            _grant(component="web_search", wildcard_parameter="query")
        )
        satisfied, missing = approval_service.get_satisfied_and_missing_approvals(
            [_approval(component="email_send", allowed_parameters={"query": "news"})]
        )
        assert satisfied == []
        assert len(missing) == 1

    def test_exact_parameter_grant_still_satisfies_matching_approval(
        self, approval_service: ApprovalService
    ):
        approval_service.register_global_grant(
            _grant(allowed_parameters={"query": "specific query"})
        )
        satisfied, missing = approval_service.get_satisfied_and_missing_approvals(
            [_approval(allowed_parameters={"query": "specific query"})]
        )
        assert len(satisfied) == 1
        assert missing == []

    def test_exact_parameter_grant_does_not_satisfy_different_query(
        self, approval_service: ApprovalService
    ):
        approval_service.register_global_grant(
            _grant(allowed_parameters={"query": "specific query"})
        )
        satisfied, missing = approval_service.get_satisfied_and_missing_approvals(
            [_approval(allowed_parameters={"query": "different query"})]
        )
        assert satisfied == []
        assert len(missing) == 1
