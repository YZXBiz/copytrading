"""Proposals run once, only with the owner's approval of the content they saw."""

import datetime as dt
from dataclasses import replace
from decimal import Decimal

import pytest
from hypothesis import strategies as st
from hypothesis.stateful import RuleBasedStateMachine, invariant, precondition, rule

from copytrading_engine.control.proposals import (
    Caller,
    ConfirmManualOrder,
    Pending,
    ProposalBook,
    ProposalRefused,
    ResumeAccount,
    Running,
    SetRecovery,
    digest,
)

from .fakes import Clock

CALLER = Caller(4242, "/usr/bin/agent")


def test_digest_changes_with_any_approved_detail():
    order = ConfirmManualOrder(
        account_id="paper",
        preview_id="preview-1",
        environment="paper",
        symbol="ABC",
        side="buy",
        order_type="limit",
        quantity=Decimal(12),
        limit_price=Decimal("25.00"),
    )
    changed = replace(order, quantity=Decimal(13))
    assert digest(order) != digest(changed)
    assert digest(ResumeAccount("paper")) != digest(SetRecovery("paper", "manual"))


def test_approval_needs_the_shown_digest_and_is_accepted_once():
    clock = Clock()
    book = ProposalBook(clock)
    proposal = book.propose(ResumeAccount("paper"), CALLER)

    with pytest.raises(ProposalRefused) as wrong:
        book.begin(proposal.proposal_id, "0" * 64)
    assert wrong.value.code == "conflict"

    assert isinstance(book.begin(proposal.proposal_id, proposal.digest).state, Running)
    with pytest.raises(ProposalRefused) as again:
        book.begin(proposal.proposal_id, proposal.digest)
    assert again.value.code == "conflict"


def test_proposals_expire_and_cannot_then_be_approved():
    clock = Clock()
    book = ProposalBook(clock)
    proposal = book.propose(ResumeAccount("paper"), CALLER)
    clock.advance(minutes=5)
    with pytest.raises(ProposalRefused) as expired:
        book.begin(proposal.proposal_id, proposal.digest)
    assert expired.value.code == "expired"


def test_preview_expiry_shortens_a_proposal():
    clock = Clock()
    book = ProposalBook(clock)
    proposal = book.propose(
        ResumeAccount("paper"), CALLER, expires_by=clock.now + dt.timedelta(seconds=20)
    )
    assert proposal.expires_at == clock.now + dt.timedelta(seconds=20)
    with pytest.raises(ProposalRefused) as stale:
        book.propose(SetRecovery("paper", "manual"), CALLER, expires_by=clock.now)
    assert stale.value.code == "expired"


def test_one_pending_proposal_per_kind():
    book = ProposalBook(Clock())
    book.propose(ResumeAccount("paper"), CALLER)
    with pytest.raises(ProposalRefused) as limited:
        book.propose(ResumeAccount("other"), CALLER)
    assert limited.value.code == "proposal_limit"
    book.propose(SetRecovery("paper", "automatic"), CALLER)


def test_repeated_rejections_pause_new_proposals():
    clock = Clock()
    book = ProposalBook(clock)
    for _ in range(3):
        book.reject(book.propose(ResumeAccount("paper"), CALLER).proposal_id)
    with pytest.raises(ProposalRefused) as cooling:
        book.propose(ResumeAccount("paper"), CALLER)
    assert cooling.value.code == "cooling_down"
    clock.advance(minutes=10)
    assert isinstance(book.propose(ResumeAccount("paper"), CALLER).state, Pending)


def test_discarding_closes_only_waiting_proposals():
    book = ProposalBook(Clock())
    running = book.propose(ResumeAccount("paper"), CALLER)
    book.begin(running.proposal_id, running.digest)
    book.propose(SetRecovery("paper", "manual"), CALLER)
    assert book.discard_pending() == 1
    assert [item.state.__class__.__name__ for item in book.all()] == ["Running", "Closed"]


class ProposalMachine(RuleBasedStateMachine):
    """Any interleaving of agent and owner actions starts each action at most once, and only
    after an approval with the right digest before expiry."""

    def __init__(self) -> None:
        super().__init__()
        self.clock = Clock()
        self.book = ProposalBook(self.clock)
        self.started: dict[str, int] = {}
        self.ids: list[str] = []

    @rule(kind=st.sampled_from(("resume", "recovery")), account=st.sampled_from(("a", "b")))
    def propose(self, kind: str, account: str) -> None:
        subject = ResumeAccount(account) if kind == "resume" else SetRecovery(account, "manual")
        try:
            self.ids.append(self.book.propose(subject, CALLER).proposal_id)
        except ProposalRefused as refused:
            assert refused.code in ("proposal_limit", "cooling_down")

    @precondition(lambda self: self.ids)
    @rule(index=st.integers(min_value=0), honest=st.booleans())
    def approve(self, index: int, honest: bool) -> None:
        try:
            proposal = self.book.get(self.ids[index % len(self.ids)])
        except ProposalRefused as refused:
            assert refused.code == "not_found"  # pruned an hour after it closed
            return
        was_pending = isinstance(proposal.state, Pending)
        try:
            self.book.begin(proposal.proposal_id, proposal.digest if honest else "f" * 64)
        except ProposalRefused:
            return
        assert honest
        assert was_pending
        assert self.clock.now < proposal.expires_at
        self.started[proposal.proposal_id] = self.started.get(proposal.proposal_id, 0) + 1

    @precondition(lambda self: self.ids)
    @rule(index=st.integers(min_value=0))
    def reject(self, index: int) -> None:
        try:
            self.book.reject(self.ids[index % len(self.ids)])
        except ProposalRefused as refused:
            assert refused.code in ("conflict", "not_found")

    @rule(seconds=st.integers(min_value=0, max_value=400))
    def wait(self, seconds: int) -> None:
        self.clock.advance(seconds=seconds)

    @rule()
    def lock(self) -> None:
        self.book.discard_pending()

    @invariant()
    def each_action_starts_at_most_once(self) -> None:
        assert all(count == 1 for count in self.started.values())


TestProposalMachine = ProposalMachine.TestCase
