"""The parse worker spends model budget only on fresh, text-decodable messages."""

import datetime as dt
from dataclasses import FrozenInstanceError

import pytest

from copytrading_engine.execution.adapters.alpaca.models import decode_account
from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.domain.sizing import (
    DestinationSignal,
    DestinationTerms,
    RouteConnection,
)
from copytrading_engine.parsing.contracts import RawMessage, RequestReservation
from copytrading_engine.parsing.extraction import DecodeError, Route
from copytrading_engine.parsing.worker import ParseWorker
from copytrading_engine.shared.correlation import current_workflow_attempt

from ..readings import buy, commentary, trade
from .fakes import InMemoryExtractionStore

NOW = dt.datetime(2026, 1, 5, 15, tzinfo=dt.UTC)


def raw_message(
    text="Commentary only", *, id="1", channel_id="demo", author_id=None, timestamp=NOW
):
    return RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id=channel_id,
        author_id=author_id,
        id=id,
        timestamp=timestamp,
        text=text,
    )


class FakeDecoder:
    def __init__(self, fail=False):
        self.calls = 0
        self.fail = fail

    async def decode(self, text, route):
        self.calls += 1
        if self.fail:
            raise DecodeError("provider_timeout", retryable=True)
        return commentary("Commentary")


def box_and_worker(*, fail=False, age=0, daily_limit=200, text="Commentary only"):
    box = InMemoryExtractionStore()
    raw = raw_message(text, timestamp=NOW - dt.timedelta(seconds=age))
    box.add(raw)
    decoder = FakeDecoder(fail)
    worker = ParseWorker(box, decoder, {"discord:demo:*": Route()}, "test", daily_limit=daily_limit)
    return box, decoder, worker


async def test_worker_builds_retry_reservations_from_attempts_and_utc_day():
    now = dt.datetime(2026, 1, 5, 23, 59, tzinfo=dt.timezone(dt.timedelta(hours=-8)))
    box = InMemoryExtractionStore()
    box.add(raw_message(timestamp=now))
    decoder = FakeDecoder(fail=True)
    worker = ParseWorker(box, decoder, {"discord:demo:*": Route()}, "test", daily_limit=3)
    reservation = RequestReservation(
        key="discord:demo:1",
        expected_attempts=0,
        day=dt.date(2026, 1, 6),
        daily_limit=3,
        retry_at=now + dt.timedelta(seconds=10),
    )
    field = "expected_attempts"
    with pytest.raises(FrozenInstanceError):
        setattr(reservation, field, 3)

    await worker.process_next(now)
    assert box.reservations == (reservation,)

    second = RequestReservation(
        key="discord:demo:1",
        expected_attempts=1,
        day=dt.date(2026, 1, 6),
        daily_limit=3,
        retry_at=now + dt.timedelta(seconds=31),
    )
    await worker.process_next(now + dt.timedelta(seconds=11))
    assert box.reservations == (reservation, second)


async def test_parser_retry_attempts_bind_the_same_persisted_workflow_lineage():
    box = InMemoryExtractionStore()
    event = raw_message()
    box.add(event)

    class CorrelatedDecoder:
        def __init__(self):
            self.seen = []

        async def decode(self, text, route):
            self.seen.append(current_workflow_attempt())
            raise DecodeError("provider_timeout", retryable=True)

    decoder = CorrelatedDecoder()
    worker = ParseWorker(box, decoder, {"discord:demo:*": Route()}, "test")

    await worker.process_next(NOW)
    await worker.process_next(NOW + dt.timedelta(seconds=11))

    first, second = decoder.seen
    assert first is not None
    assert second is not None
    assert first.workflow_id == second.workflow_id
    assert first.trace_id == second.trace_id
    assert first.destination_id is None
    assert second.destination_id is None
    assert [first.attempt, second.attempt] == [1, 2]


async def test_stale_message_never_spends_model_budget():
    box, decoder, worker = box_and_worker(age=121)
    await worker.process_next(NOW)
    assert decoder.calls == 0
    assert box.pending()[0].signal.reason == "stale_signal"
    assert box.reservations == ()


@pytest.mark.parametrize(
    ("age", "reason"),
    [(120, None), (120.001, "stale_signal"), (-5, None), (-5.001, "future_signal")],
)
async def test_timing_boundaries_have_distinct_reasons_and_no_model_spend(age, reason):
    box, decoder, worker = box_and_worker(age=age)
    await worker.process_next(NOW)
    result = box.pending()[0].signal
    if reason:
        assert result.reason == reason
        assert result.decision == "review"
        assert result.instructions == ()
        assert decoder.calls == 0
        assert box.reservations == ()
    else:
        assert decoder.calls == 1


@pytest.mark.parametrize(("jump", "reason"), [(-60, "future_signal"), (121, "stale_signal")])
async def test_clock_change_between_enqueue_and_processing_is_reported(jump, reason):
    box, decoder, worker = box_and_worker()
    await worker.process_next(NOW + dt.timedelta(seconds=jump))
    result = box.pending()[0].signal
    assert result.reason == reason
    assert result.instructions == ()
    assert decoder.calls == 0


async def test_model_budget_is_a_hard_gate():
    box, decoder, worker = box_and_worker(daily_limit=0)
    await worker.process_next(NOW)
    assert decoder.calls == 0
    assert box.pending()[0].signal.reason == "daily_model_request_budget_exhausted"
    assert box.reservations == ()


async def test_image_dependent_message_is_review_only_without_vision_call():
    box = InMemoryExtractionStore()
    message = raw_message().model_copy(update={"image_count": 1})
    box.add(message)
    decoder = FakeDecoder()
    worker = ParseWorker(box, decoder, {"discord:demo:*": Route()}, "test")

    await worker.process_next(NOW)

    result = box.pending()[0].signal
    assert result.decision == "review"
    assert result.reason == "attachments_require_human_review"
    assert decoder.calls == 0


async def test_published_or_pending_result_never_redecodes():
    box, decoder, worker = box_and_worker()
    await worker.process_next(NOW)
    await worker.process_next(NOW + dt.timedelta(seconds=11))
    assert decoder.calls == 1
    assert len(box.pending()) == 1
    assert box.pending()[0].signal.decision == "ignore"


async def test_permanent_provider_rejection_is_not_retried():
    box, _decoder, worker = box_and_worker()

    class Rejected:
        async def decode(self, text, route):
            raise DecodeError("provider_rejected", retryable=False)

    worker.decoder = Rejected()
    await worker.process_next(NOW)
    assert not await worker.process_next(NOW + dt.timedelta(seconds=60))
    assert box.pending()[0].signal.reason == "provider_rejected"
    assert worker.model_ready is False


async def test_retry_blocks_overtaking_within_source_but_not_other_channels():
    box, _decoder, worker = box_and_worker(fail=True)
    await worker.process_next(NOW)
    raw = raw_message("Later exit", id="2")
    box.add(raw)
    assert await box.next(NOW + dt.timedelta(seconds=2)) is None
    other_channel = raw_message("Later exit", id="2", channel_id="another")
    box.add(other_channel)
    next_job = await box.next(NOW + dt.timedelta(seconds=2))
    assert next_job is not None
    assert next_job.key == "discord:another:2"


async def test_unknown_route_is_reviewed_without_model_or_request_budget_spend():
    box, decoder, worker = box_and_worker()
    worker.routes = {}
    await worker.process_next(NOW)

    assert box.pending()[0].signal.reason == "source_profile_not_configured"
    assert box.pending()[0].signal.decision == "review"
    assert decoder.calls == 0
    assert box.reservations == ()


async def test_channel_profile_routes_resolve_by_author_and_keep_source_identity_separate():
    raw = raw_message("SIGNAL: Commentary only", author_id="200")
    box = InMemoryExtractionStore()
    box.add(raw)
    observed = []

    class Decoder:
        async def decode(self, text, route):
            observed.append((route.guru_id, route.profile_revision))
            return commentary("Commentary")

    first_revision, second_revision = "a" * 64, "b" * 64
    worker = ParseWorker(
        box,
        Decoder(),
        {
            "discord:demo:100": Route(
                guru_id="guru-a",
                profile_revision=first_revision,
                exit_basis="original_position",
            ),
            "discord:demo:200": Route(
                guru_id="guru-b",
                profile_revision=second_revision,
                exit_basis="remaining_position",
            ),
        },
        "test",
    )

    await worker.process_next(NOW)
    result = box.pending()[0].signal
    assert observed == [("guru-b", second_revision)]
    assert result.guru_id == "guru-b"
    assert result.profile_revision == second_revision
    assert result.author_id == "200"
    assert (result.source, result.channel_id, result.id) == ("discord", "demo", "1")


async def test_runtime_route_map_collision_is_reviewed_without_model_selection():
    raw = raw_message(author_id="200")
    box = InMemoryExtractionStore()
    box.add(raw)
    decoder = FakeDecoder()
    worker = ParseWorker(
        box,
        decoder,
        {
            "discord:demo:*": Route(
                guru_id="guru-a",
                profile_revision="a" * 64,
                exit_basis="original_position",
            ),
            "discord:demo:200": Route(
                guru_id="guru-b",
                profile_revision="b" * 64,
                exit_basis="remaining_position",
            ),
        },
        "test",
    )

    await worker.process_next(NOW)
    assert box.pending()[0].signal.reason == "ambiguous_source_profile"
    assert decoder.calls == 0


@pytest.mark.parametrize("text", ["   ", "\n"])
async def test_local_decision_cannot_exhaust_budget_for_next_real_request(text):
    box, decoder, worker = box_and_worker(daily_limit=1, text=text)
    worker.routes = {"discord:demo:*": Route()}
    message = box.inputs[0]
    await worker.process_next(NOW)
    assert decoder.calls == 0
    assert not worker.model_ready
    box.add(message.model_copy(update={"id": "next", "text": "ALERT: Commentary"}))
    await worker.process_next(NOW)
    assert decoder.calls == 1
    assert worker.model_ready
    assert len(box.reservations) == 1


async def test_schema_failure_records_typed_diagnostic_and_never_becomes_commentary():
    from copytrading_engine.parsing.diagnostics import ValidationIssue

    box, _, worker = box_and_worker()

    class Invalid:
        async def decode(self, text, route):
            raise DecodeError(
                "invalid_model_output",
                retryable=False,
                issues=(ValidationIssue(path="instructions.0", code="entry_has_lot_reference"),),
            )

    worker.decoder = Invalid()
    decisions = []
    worker.on_decision = decisions.append
    await worker.process_next(NOW)
    [diagnostic] = box.diagnostics
    assert diagnostic.attempt == 1
    assert diagnostic.reason == "invalid_model_output"
    assert diagnostic.issues == (
        ValidationIssue(path="instructions.0", code="entry_has_lot_reference"),
    )
    assert box.pending()[0].signal.decision == "review"
    assert decisions == ["review"]


@pytest.mark.parametrize(
    ("text", "action", "symbol"),
    [
        ("25加了1/6常规仓abc", "加了", "abc"),
        ("25加了25%常规仓abc", "加了", "abc"),
        ("25加了half仓abc", "加了", "abc"),
        ("25加了full仓abc", "加了", "abc"),
        ("Bought ABC at 25, half position", "Bought", "ABC"),
        ("Bought ABC at 25, full position", "Bought", "ABC"),
    ],
)
async def test_omitted_allocation_never_reaches_default_sized_destination_order(
    text, action, symbol
):
    class OmittedFractionDecoder:
        async def decode(self, text, route):
            return trade(buy("ABC", "25", said=action, ticker_said=symbol))

    class ReviewRepository:
        def __init__(self):
            self.state = LedgerSnapshot()

        def load(self):
            return self.state

        def save(self, snapshot, event):
            self.state = snapshot

    class NoOrderBroker:
        calls = 0

        def account(self):
            return decode_account(
                {
                    "id": "paper-demo",
                    "status": "ACTIVE",
                    "cash": "3000",
                    "equity": "3000",
                    "last_equity": "3000",
                    "buying_power": "3000",
                    "currency": "USD",
                    "trading_blocked": False,
                    "account_blocked": False,
                    "trade_suspended_by_user": False,
                }
            )

        def positions(self):
            return ()

        def open_orders(self):
            return ()

        def submit(self, order):
            self.calls += 1
            raise AssertionError("Review was submitted as an order")

    box = InMemoryExtractionStore()
    box.add(raw_message(text))
    worker = ParseWorker(box, OmittedFractionDecoder(), {"discord:demo:*": Route()}, "test")
    await worker.process_next(NOW)
    [delivery] = box.pending()
    assert delivery.signal.decision == "review"
    assert delivery.signal.reason == "evidence_validation_failed"
    assert delivery.signal.text == text
    assert box.diagnostics[0].issues[0].code == "source_fraction_omitted"

    broker = NoOrderBroker()
    engine = CopyEngine(ReviewRepository(), broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    engine.receive(
        DestinationSignal(
            signal=delivery.signal,
            terms=DestinationTerms(
                connection=RouteConnection(
                    account_id="paper-demo",
                    full_position_usd="3000",
                    default_fraction="1",
                ),
                environment="paper",
                configuration_revision="a" * 64,
            ),
        ),
        NOW,
    )
    engine.process(NOW)
    assert broker.calls == 0
    assert engine.ledger.message("discord:demo:1").status == "review_required"
